import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_reader/services/vault_client.dart';

/// A server that completes the MCP handshake and then answers one tool call.
///
/// [toolResponse] builds the JSON-RPC reply for the tools/call, given its id.
/// Every request is recorded in [requests] so tests can assert on what was sent.
MockClient _server({
  required Map<String, dynamic> Function(int id) toolResponse,
  String contentType = 'application/json',
  String? sessionId = 'sess-1',
}) {
  return MockClient((request) async {
    final payload = jsonDecode(request.body) as Map<String, dynamic>;
    _sent.add(payload);

    final headers = <String, String>{
      'content-type': contentType,
      if (sessionId != null) 'mcp-session-id': sessionId,
    };

    if (payload['method'] == 'notifications/initialized') {
      return http.Response('', 202, headers: headers);
    }

    final id = payload['id'] as int;
    final Map<String, dynamic> body;
    if (payload['method'] == 'initialize') {
      body = {
        'jsonrpc': '2.0',
        'id': id,
        'result': {'protocolVersion': '2025-06-18', 'capabilities': {}},
      };
    } else {
      body = toolResponse(id);
    }

    final encoded = jsonEncode(body);
    return http.Response(
      contentType.contains('event-stream') ? 'event: message\r\ndata: $encoded\r\n\r\n' : encoded,
      200,
      headers: headers,
    );
  });
}

late List<Map<String, dynamic>> _sent;

Map<String, dynamic> _toolOk(int id, Map<String, dynamic> payload) => {
      'jsonrpc': '2.0',
      'id': id,
      'result': {
        'content': [
          {'type': 'text', 'text': jsonEncode(payload)}
        ]
      },
    };

void main() {
  setUp(() => _sent = []);

  VaultClient clientWith(http.Client http_) => VaultClient(
        serverUrl: 'https://vault.example.com/mcp',
        token: 'tok',
        httpClient: http_,
      );

  group('saveBookmark', () {
    test('handshakes, then calls save_bookmark with the supplied fields', () async {
      final client = clientWith(_server(
        toolResponse: (id) => _toolOk(id, {
          'slug': 'bookmarks/example.com/a-story',
          'tags': ['tech', 'ai'],
          'status': 'processed',
        }),
      ));

      final result = await client.saveBookmark(
        url: 'https://example.com/a-story',
        title: 'A Story',
        text: 'the article body',
        tags: const ['rss'],
      );

      expect(_sent.map((m) => m['method']),
          ['initialize', 'notifications/initialized', 'tools/call']);

      final call = _sent.last;
      expect(call['params']['name'], 'save_bookmark');
      final args = call['params']['arguments'] as Map<String, dynamic>;
      expect(args['url'], 'https://example.com/a-story');
      expect(args['title'], 'A Story');
      expect(args['text'], 'the article body');
      expect(args['tags'], ['rss']);

      expect(result.slug, 'bookmarks/example.com/a-story');
      expect(result.status, 'processed');
      expect(result.isProcessed, isTrue);
      expect(result.tags, ['tech', 'ai']);
    });

    test('reads a result delivered as an SSE stream', () async {
      final client = clientWith(_server(
        contentType: 'text/event-stream',
        toolResponse: (id) => _toolOk(id, {'slug': 's', 'tags': [], 'status': 'processed'}),
      ));

      final result = await client.saveBookmark(url: 'https://x.test/a', title: 'A');
      expect(result.status, 'processed');
    });

    test('carries the session id returned by initialize on later requests', () async {
      final seenSessions = <String?>[];
      final client = clientWith(MockClient((request) async {
        seenSessions.add(request.headers['Mcp-Session-Id']);
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final headers = {'content-type': 'application/json', 'mcp-session-id': 'sess-9'};
        if (payload['method'] == 'notifications/initialized') {
          return http.Response('', 202, headers: headers);
        }
        final id = payload['id'] as int;
        if (payload['method'] == 'initialize') {
          return http.Response(
              jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': {}}), 200,
              headers: headers);
        }
        return http.Response(
            jsonEncode(_toolOk(id, {'slug': 's', 'tags': [], 'status': 'processed'})), 200,
            headers: headers);
      }));

      await client.saveBookmark(url: 'https://x.test/a', title: 'A');
      expect(seenSessions.first, isNull, reason: 'no session before initialize');
      expect(seenSessions.last, 'sess-9');
    });

    test('reports a non-processed status rather than throwing', () async {
      final client = clientWith(_server(
        toolResponse: (id) => _toolOk(id, {
          'slug': 'bookmarks/example.com/x',
          'tags': [],
          'status': 'fetch_failed: HTTP 404',
        }),
      ));

      final result = await client.saveBookmark(url: 'https://example.com/x', title: 'X');
      expect(result.status, 'fetch_failed: HTTP 404');
      expect(result.isProcessed, isFalse);
    });

    test('throws VaultException on an HTTP error', () async {
      final client = clientWith(MockClient((_) async =>
          http.Response('{"error":"Forbidden"}', 403, headers: {'content-type': 'application/json'})));

      expect(
        () => client.saveBookmark(url: 'https://x.test/a', title: 'A'),
        throwsA(isA<VaultException>().having((e) => e.message, 'message', contains('403'))),
      );
    });

    test('throws VaultException on a JSON-RPC error', () async {
      final client = clientWith(_server(
        toolResponse: (id) => {
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': -32602, 'message': 'Invalid params'},
        },
      ));

      expect(
        () => client.saveBookmark(url: 'https://x.test/a', title: 'A'),
        throwsA(isA<VaultException>().having((e) => e.message, 'message', contains('Invalid params'))),
      );
    });

    test('throws VaultException when the tool itself reports an error', () async {
      final client = clientWith(_server(
        toolResponse: (id) => {
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'isError': true,
            'content': [
              {'type': 'text', 'text': 'save_bookmark exploded'}
            ]
          },
        },
      ));

      expect(
        () => client.saveBookmark(url: 'https://x.test/a', title: 'A'),
        throwsA(isA<VaultException>()
            .having((e) => e.message, 'message', contains('save_bookmark exploded'))),
      );
    });
  });

  group('parseSseMessage', () {
    test('returns the frame matching the request id', () {
      final body = 'event: message\r\n'
          'data: {"jsonrpc":"2.0","id":7,"result":{"ok":true}}\r\n\r\n';
      expect(VaultClient.parseSseMessage(body, 7)?['id'], 7);
    });

    test('handles LF-only line endings', () {
      final body = 'data: {"jsonrpc":"2.0","id":3,"result":{}}\n\n';
      expect(VaultClient.parseSseMessage(body, 3), isNotNull);
    });

    test('skips frames for other ids', () {
      final body = 'data: {"jsonrpc":"2.0","id":1,"result":{"n":1}}\n\n'
          'data: {"jsonrpc":"2.0","id":2,"result":{"n":2}}\n\n';
      expect(VaultClient.parseSseMessage(body, 2)?['result']['n'], 2);
    });

    test('returns an error frame regardless of id', () {
      final body = 'data: {"jsonrpc":"2.0","id":99,"error":{"code":-1,"message":"nope"}}\n\n';
      expect(VaultClient.parseSseMessage(body, 5)?['error'], isNotNull);
    });

    test('returns null when nothing matches', () {
      expect(VaultClient.parseSseMessage('data: {"id":1}\n\n', 4), isNull);
    });

    test('ignores non-data lines and unparseable frames', () {
      final body = ': keepalive\n\n'
          'data: not json\n\n'
          'data: {"jsonrpc":"2.0","id":8,"result":{}}\n\n';
      expect(VaultClient.parseSseMessage(body, 8), isNotNull);
    });
  });
}
