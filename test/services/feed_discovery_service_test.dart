import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:news_reader/models/article.dart';
import 'package:news_reader/services/feed_discovery_service.dart';

Article _article(String title, String sourceName) => Article(
      id: '$sourceName/$title',
      title: title,
      url: 'https://feed.example/$title',
      publishedAt: DateTime(2026, 1, 1),
      sourceName: sourceName,
    );

/// Builds a service whose page fetch returns [pageBody]/[contentType] for any
/// request, and whose feed validator returns canned articles for the URLs in
/// [validFeeds] (empty for everything else).
FeedDiscoveryService _service({
  required String pageBody,
  String contentType = 'text/html; charset=utf-8',
  int pageStatus = 200,
  Map<String, List<Article>> validFeeds = const {},
}) {
  final client = MockClient((req) async {
    return http.Response(
      pageBody,
      pageStatus,
      headers: {'content-type': contentType},
    );
  });
  return FeedDiscoveryService(
    client: client,
    feedFetcher: (url, {int limit = 2}) async => validFeeds[url] ?? const [],
  );
}

void main() {
  group('FeedDiscoveryService.discover', () {
    test('throws on blank input', () {
      final service = _service(pageBody: '');
      expect(
        () => service.discover('   '),
        throwsA(isA<FeedDiscoveryException>()),
      );
    });

    test('throws when the host is unreachable', () {
      final client = MockClient((_) => Future.error(Exception('no route')));
      final service = FeedDiscoveryService(
        client: client,
        feedFetcher: (url, {int limit = 2}) async => const [],
      );
      expect(
        () => service.discover('down.example'),
        throwsA(isA<FeedDiscoveryException>()),
      );
    });

    test('finds a feed via <link rel="alternate"> and uses its title', () async {
      const feedUrl = 'https://blog.example/feed.xml';
      final service = _service(
        pageBody: '''
          <html><head>
            <link rel="alternate" type="application/rss+xml"
                  title="My Blog" href="/feed.xml">
          </head><body>hi</body></html>
        ''',
        validFeeds: {
          feedUrl: [_article('First post', 'blog title ignored')],
        },
      );

      final results = await service.discover('blog.example');

      expect(results, hasLength(1));
      expect(results.single.url, feedUrl);
      expect(results.single.name, 'My Blog'); // <link title> wins
      expect(results.single.sampleTitles, ['First post']);
      expect(results.single.alreadyAdded, isFalse);
    });

    test('falls back to the feed title when <link> has no title', () async {
      const feedUrl = 'https://blog.example/atom';
      final service = _service(
        pageBody: '''
          <html><head>
            <link rel="alternate" type="application/atom+xml" href="/atom">
          </head></html>
        ''',
        validFeeds: {
          feedUrl: [_article('Post', 'The Feed Title')],
        },
      );

      final results = await service.discover('https://blog.example');
      expect(results.single.name, 'The Feed Title');
    });

    test('discovers multiple distinct feeds on one page', () async {
      final service = _service(
        pageBody: '''
          <html><head>
            <link rel="alternate" type="application/rss+xml" title="Main" href="/main.xml">
            <link rel="alternate" type="application/rss+xml" title="Comments" href="/comments.xml">
          </head></html>
        ''',
        validFeeds: {
          'https://blog.example/main.xml': [_article('m', 'Main')],
          'https://blog.example/comments.xml': [_article('c', 'Comments')],
        },
      );

      final results = await service.discover('blog.example');
      expect(results.map((f) => f.name), containsAll(['Main', 'Comments']));
    });

    test('treats the input itself as a feed when it is one', () async {
      const url = 'https://feeds.example/frontpage';
      final service = _service(
        pageBody: '<?xml version="1.0"?><rss version="2.0"><channel></channel></rss>',
        contentType: 'application/rss+xml',
        validFeeds: {
          url: [_article('Item', 'Front Page')],
        },
      );

      final results = await service.discover(url);
      expect(results.single.url, url);
    });

    test('probes common paths when no <link> is present', () async {
      // Homepage exposes no autodiscovery link (Ars-Technica-style). Only the
      // conventional /feed path validates.
      const feedUrl = 'https://news.example/feed';
      final service = _service(
        pageBody: '<html><head></head><body>no link here</body></html>',
        validFeeds: {
          feedUrl: [_article('Headline', 'News')],
        },
      );

      final results = await service.discover('news.example');
      expect(results.single.url, feedUrl);
    });

    test('a bogus anchor does not suppress common-path probing', () async {
      // The page links an HTML "/rss-feeds/" index (not a real feed); the real
      // feed is only at /feed. Probing must still run.
      const feedUrl = 'https://news.example/feed';
      final service = _service(
        pageBody: '''
          <html><body>
            <a href="/rss-feeds/">Our RSS feeds</a>
          </body></html>
        ''',
        validFeeds: {
          feedUrl: [_article('Headline', 'News')],
          // "/rss-feeds/" intentionally absent -> validates as empty.
        },
      );

      final results = await service.discover('news.example');
      expect(results.single.url, feedUrl);
    });

    test('returns empty when the site exposes no feed', () async {
      final service = _service(
        pageBody: '<html><head></head><body>nothing</body></html>',
      );
      final results = await service.discover('example.com');
      expect(results, isEmpty);
    });

    test('flags feeds already in the configuration', () async {
      const feedUrl = 'https://blog.example/feed.xml';
      final service = _service(
        pageBody:
            '<html><head><link rel="alternate" type="application/rss+xml" href="/feed.xml"></head></html>',
        validFeeds: {
          feedUrl: [_article('Post', 'Blog')],
        },
      );

      final results =
          await service.discover('blog.example', existingUrls: {feedUrl});
      expect(results.single.alreadyAdded, isTrue);
    });
  });
}
