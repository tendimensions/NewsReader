import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../models/article.dart';
import 'news_sources/rss_news_source.dart';

/// Fetches and parses [url] as a feed, returning its articles (empty if it
/// doesn't parse). Injectable so discovery can be unit-tested offline.
typedef FeedFetcher = Future<List<Article>> Function(String url, {int limit});

/// A feed found by [FeedDiscoveryService] for a given site.
class DiscoveredFeed {
  /// Resolved, absolute feed URL.
  final String url;

  /// Best available display name: the `<link title>` if present, otherwise the
  /// feed's own `<title>`.
  final String name;

  /// Up to two recent article titles, used as a recognition preview.
  final List<String> sampleTitles;

  /// True when this feed is already in the user's feed configuration.
  final bool alreadyAdded;

  const DiscoveredFeed({
    required this.url,
    required this.name,
    this.sampleTitles = const [],
    this.alreadyAdded = false,
  });
}

/// Raised when discovery cannot start or complete for a user-facing reason
/// (bad input, unreachable host). The [message] is safe to show directly.
class FeedDiscoveryException implements Exception {
  final String message;
  const FeedDiscoveryException(this.message);

  @override
  String toString() => message;
}

/// Finds the RSS/Atom feed(s) for a site from any site-shaped input: a
/// homepage, a full URL, an article URL, or a feed URL itself.
///
/// The pipeline (stops early when candidates are found):
///   1. Normalize the input and fetch the page.
///   2. If the input is itself a feed, use it directly.
///   3. Scan `<head>` for `<link rel="alternate">` autodiscovery tags.
///   4. Scan `<a>` hrefs that look like feed links.
///   5. If still nothing, probe common feed paths against the origin.
///
/// Every candidate is validated by actually parsing it as a feed (via
/// [RssNewsSource]), so 404s and HTML pages are discarded.
class FeedDiscoveryService {
  final http.Client _client;
  final FeedFetcher _fetchFeed;

  FeedDiscoveryService({http.Client? client, FeedFetcher? feedFetcher})
      : _client = client ?? http.Client(),
        _fetchFeed = feedFetcher ?? _defaultFetchFeed;

  /// Default validator: fetch + parse the URL through [RssNewsSource], which
  /// applies the same RSS→Atom fallback the rest of the app uses.
  static Future<List<Article>> _defaultFetchFeed(String url, {int limit = 2}) {
    return RssNewsSource(feedUrls: [url]).fetchArticles(limit: limit);
  }

  static const Duration _timeout = Duration(seconds: 15);

  static const List<String> _commonPaths = [
    '/feed',
    '/rss',
    '/feed.xml',
    '/rss.xml',
    '/atom.xml',
    '/index.xml',
    '/feed/',
  ];

  /// Discovers feeds for [rawInput]. [existingUrls] are the URLs already in the
  /// user's configuration, used to flag [DiscoveredFeed.alreadyAdded].
  ///
  /// Throws [FeedDiscoveryException] on bad input or an unreachable host.
  /// Returns an empty list when the site is reachable but exposes no feed.
  Future<List<DiscoveredFeed>> discover(
    String rawInput, {
    Set<String> existingUrls = const {},
  }) async {
    final base = _normalize(rawInput);
    if (base == null) {
      throw const FeedDiscoveryException('Enter a website or feed URL.');
    }

    http.Response response;
    try {
      response = await _client.get(base).timeout(_timeout);
    } catch (e) {
      debugPrint('[FeedDiscovery] fetch failed for $base: $e');
      throw FeedDiscoveryException("Couldn't reach ${base.host}.");
    }

    final body = response.statusCode == 200
        ? utf8.decode(response.bodyBytes, allowMalformed: true)
        : '';

    // Phase A: candidates from the page itself — the input as a feed, then
    // <link> autodiscovery, then <a> href heuristics. Candidate feed URL ->
    // optional display-name hint. Insertion-ordered so <link> hits rank first.
    final pageCandidates = <String, String?>{};
    var inputIsFeed = false;

    if (body.isNotEmpty && _looksLikeFeed(response, body)) {
      pageCandidates[base.toString()] = null;
      inputIsFeed = true;
    } else if (body.isNotEmpty) {
      final doc = html_parser.parse(body);
      _collectLinkFeeds(doc, base, pageCandidates);
      _collectAnchorFeeds(doc, base, pageCandidates);
    }

    final validated = await Future.wait(
      pageCandidates.entries.map(
        (e) => _validate(e.key, nameHint: e.value, existingUrls: existingUrls),
      ),
    );
    final results = [for (final f in validated) if (f != null) f];

    // Phase B: if the page yielded no real feed, fall back to probing
    // conventional paths against the origin. These are aliases of one feed, so
    // keep only the first that validates (in priority order). A bogus anchor
    // (e.g. an HTML "/rss-feeds/" index) must not suppress this fallback.
    if (results.isEmpty && !inputIsFeed) {
      final probed = await Future.wait(
        _commonPaths.map(
          (p) => _validate(base.resolve(p).toString(), existingUrls: existingUrls),
        ),
      );
      for (final f in probed) {
        if (f != null) return [f];
      }
    }

    return results;
  }

  /// Trims [raw], adds an `https://` scheme when missing, and returns a valid
  /// absolute [Uri], or null if it can't be parsed into one with a host.
  Uri? _normalize(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(s)) {
      s = 'https://$s';
    }
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return null;
    return uri;
  }

  /// Sniffs whether a fetched document is itself a feed, via content-type and a
  /// look at the opening bytes of the body.
  bool _looksLikeFeed(http.Response response, String body) {
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final head =
        (body.length > 512 ? body.substring(0, 512) : body).toLowerCase();
    final looksXml = contentType.contains('rss') ||
        contentType.contains('atom') ||
        head.contains('<rss') ||
        head.contains('<feed') ||
        head.contains('<rdf:rdf');
    return looksXml;
  }

  /// Collects feeds declared via `<link rel="alternate" type="...rss/atom...">`.
  void _collectLinkFeeds(
    dom.Document doc,
    Uri base,
    Map<String, String?> out,
  ) {
    for (final link in doc.querySelectorAll('link')) {
      final rel = (link.attributes['rel'] ?? '').toLowerCase();
      final type = (link.attributes['type'] ?? '').toLowerCase();
      final isAlternate = rel.split(RegExp(r'\s+')).contains('alternate');
      final isFeedType = type.contains('rss') ||
          type.contains('atom') ||
          (type.contains('xml') && isAlternate);
      if (!isFeedType) continue;

      final href = link.attributes['href']?.trim();
      if (href == null || href.isEmpty) continue;

      final resolved = base.resolve(href).toString();
      final title = link.attributes['title']?.trim();
      out.putIfAbsent(resolved, () => (title?.isNotEmpty ?? false) ? title : null);
    }
  }

  /// Collects feeds linked via `<a>` hrefs that look feed-shaped. Noise here is
  /// harmless: validation discards anything that doesn't parse as a feed.
  void _collectAnchorFeeds(
    dom.Document doc,
    Uri base,
    Map<String, String?> out,
  ) {
    for (final anchor in doc.querySelectorAll('a')) {
      final href = anchor.attributes['href']?.trim();
      if (href == null || href.isEmpty) continue;

      final lower = href.toLowerCase();
      final looksFeed = lower.contains('rss') ||
          lower.contains('atom') ||
          lower.contains('/feed') ||
          lower.endsWith('.xml');
      if (!looksFeed) continue;

      final resolved = base.resolve(href).toString();
      final text = anchor.text.trim();
      out.putIfAbsent(resolved, () => text.isNotEmpty ? text : null);
    }
  }

  /// Fetches and parses [url] as a feed. Returns a [DiscoveredFeed] on success,
  /// or null if it doesn't parse or yields no articles.
  Future<DiscoveredFeed?> _validate(
    String url, {
    String? nameHint,
    Set<String> existingUrls = const {},
  }) async {
    try {
      // No displayName override, so article.sourceName carries the feed's own
      // <title>, which we fall back to when there's no <link title> hint.
      final articles = await _fetchFeed(url, limit: 2);
      if (articles.isEmpty) return null;

      final hint = nameHint?.trim();
      final name = (hint != null && hint.isNotEmpty)
          ? hint
          : articles.first.sourceName;

      return DiscoveredFeed(
        url: url,
        name: name,
        sampleTitles: articles.take(2).map((a) => a.title).toList(),
        alreadyAdded: existingUrls.contains(url),
      );
    } catch (e) {
      debugPrint('[FeedDiscovery] validation failed for $url: $e');
      return null;
    }
  }
}
