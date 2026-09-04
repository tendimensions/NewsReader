import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown when the vault rejects a call or the transport fails.
class VaultException implements Exception {
  final String message;
  VaultException(this.message);

  @override
  String toString() => 'VaultException: $message';
}

/// Minimal MCP Streamable HTTP client for the mcp-vault server.
///
/// A direct port of the CustomAddBookmark extension's `shared/mcp.js`, so the
/// two clients stay recognisably the same. The transport requires a handshake
/// before any tool call:
///
///   POST initialize                 -> Mcp-Session-Id header + protocol version
///   POST notifications/initialized
///   POST tools/call
///
/// Responses come back as either `application/json` or a `text/event-stream`
/// body depending on the request, so both are handled.
///
/// No `Origin` header is sent from `dart:io`, which is what lets this past the
/// server's DNS-rebinding protection without the header-stripping the browser
/// extension needs. A web build would send one and be refused.
class VaultClient {
  static const String protocolVersion = '2025-06-18';
  static const Map<String, String> clientInfo = {
    'name': 'NewsReader',
    'version': '0.2.0',
  };

  /// `save_bookmark` fetches nothing when we supply `text`, but still makes an
  /// LLM call, so this is well above a normal request budget.
  static const Duration defaultTimeout = Duration(seconds: 90);

  final String serverUrl;
  final String token;
  final Duration timeout;
  final http.Client _http;

  String? _sessionId;
  String _negotiatedVersion = protocolVersion;
  int _nextId = 1;

  VaultClient({
    required this.serverUrl,
    required this.token,
    this.timeout = defaultTimeout,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  void close() => _http.close();

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        'MCP-Protocol-Version': _negotiatedVersion,
        'Authorization': 'Bearer $token',
        if (_sessionId != null) 'Mcp-Session-Id': _sessionId!,
      };

  Future<Map<String, dynamic>?> _post(Map<String, dynamic> payload) async {
    final http.Response response;
    try {
      response = await _http
          .post(Uri.parse(serverUrl), headers: _headers(), body: jsonEncode(payload))
          .timeout(timeout);
    } on TimeoutException {
      throw VaultException('timed out after ${timeout.inSeconds}s');
    } catch (e) {
      throw VaultException('$e');
    }

    final sid = response.headers['mcp-session-id'];
    if (sid != null && sid.isNotEmpty) _sessionId = sid;

    if (response.statusCode >= 400) {
      throw VaultException('HTTP ${response.statusCode}: ${_truncate(response.body)}');
    }

    // Notifications carry no id and get an empty 202.
    if (response.statusCode == 202 || payload['id'] == null) return null;

    return _parseRpc(response, payload['id'] as int);
  }

  /// Extract the JSON-RPC result for [id] from a JSON or SSE response body.
  Map<String, dynamic>? _parseRpc(http.Response response, int id) {
    final contentType = response.headers['content-type'] ?? '';
    final message = contentType.contains('text/event-stream')
        ? parseSseMessage(response.body, id)
        : _decodeJsonObject(response.body);

    if (message == null) throw VaultException('no response received');
    if (message['error'] != null) {
      final error = message['error'] as Map<String, dynamic>;
      throw VaultException('${error['code']}: ${error['message']}');
    }
    return message['result'] as Map<String, dynamic>?;
  }

  Future<void> _initialize() async {
    final result = await _post({
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': 'initialize',
      'params': {
        'protocolVersion': protocolVersion,
        'capabilities': <String, dynamic>{},
        'clientInfo': clientInfo,
      },
    });

    final negotiated = result?['protocolVersion'];
    if (negotiated is String && negotiated.isNotEmpty) _negotiatedVersion = negotiated;

    await _post({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
  }

  Future<Map<String, dynamic>?> _callTool(String name, Map<String, dynamic> arguments) async {
    final result = await _post({
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': 'tools/call',
      'params': {'name': name, 'arguments': arguments},
    });

    if (result?['isError'] == true) {
      throw VaultException(_resultText(result) ?? 'tool call failed');
    }
    return result;
  }

  /// Save one bookmark via the server's `save_bookmark` tool.
  ///
  /// [text] is the article body we already hold from the feed. Supplying it
  /// makes the server skip its own fetch, which is both faster and immune to
  /// the paywalls and dead links that produce `fetch_failed` bookmarks.
  ///
  /// Returns the tool's `{slug, tags, status}`. A [status] other than
  /// "processed" means the document was written but enrichment failed; the
  /// server retries those itself via `reprocess_bookmarks`.
  Future<VaultSaveResult> saveBookmark({
    required String url,
    required String title,
    String note = '',
    String text = '',
    List<String> tags = const [],
  }) async {
    await _initialize();
    final result = await _callTool('save_bookmark', {
      'url': url,
      'title': title,
      'note': note,
      'text': text,
      'tags': tags,
    });

    final decoded = _decodeJsonObject(_resultText(result) ?? '');
    return VaultSaveResult(
      slug: decoded?['slug'] as String?,
      status: decoded?['status'] as String? ?? 'unknown',
      tags: (decoded?['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }

  /// Concatenated text content blocks of a tool result.
  static String? _resultText(Map<String, dynamic>? result) {
    final content = result?['content'];
    if (content is! List) return null;
    final parts = content
        .whereType<Map<String, dynamic>>()
        .map((block) => block['text'])
        .whereType<String>();
    return parts.isEmpty ? null : parts.join();
  }

  static Map<String, dynamic>? _decodeJsonObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String _truncate(String s) => s.length <= 200 ? s : '${s.substring(0, 200)}…';

  /// First JSON-RPC message in an SSE body whose id matches [id], or any error.
  ///
  /// Frames are separated by a blank line and may use LF or CRLF - sse-starlette
  /// emits CRLF. Visible for testing.
  static Map<String, dynamic>? parseSseMessage(String body, int id) {
    for (final frame in body.split(RegExp(r'\r?\n\r?\n'))) {
      final data = frame
          .split(RegExp(r'\r?\n'))
          .where((line) => line.startsWith('data:'))
          .map((line) => line.substring(5).trim())
          .join();
      if (data.isEmpty) continue;

      final message = _decodeJsonObject(data);
      if (message == null) continue;
      if (message['id'] == id || message['error'] != null) return message;
    }
    return null;
  }
}

/// Outcome of one `save_bookmark` call.
class VaultSaveResult {
  final String? slug;
  final String status;
  final List<String> tags;

  const VaultSaveResult({this.slug, required this.status, this.tags = const []});

  /// True when the server fetched/enriched and wrote a complete document.
  bool get isProcessed => status == 'processed';
}
