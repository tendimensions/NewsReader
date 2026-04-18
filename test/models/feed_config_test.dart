import 'package:flutter_test/flutter_test.dart';
import 'package:news_reader/models/feed_config.dart';

void main() {
  group('FeedConfig constructor', () {
    test('defaults enabled to true', () {
      final feed = FeedConfig(url: 'https://example.com/feed', name: 'Example');
      expect(feed.enabled, isTrue);
    });

    test('defaults isBuiltIn to false', () {
      final feed = FeedConfig(url: 'https://example.com/feed', name: 'Example');
      expect(feed.isBuiltIn, isFalse);
    });

    test('defaults articleLimit to 5', () {
      final feed = FeedConfig(url: 'https://example.com/feed', name: 'Example');
      expect(feed.articleLimit, 5);
    });

    test('accepts explicit values', () {
      final feed = FeedConfig(
        url: 'https://example.com/feed',
        name: 'My Feed',
        enabled: false,
        isBuiltIn: true,
        articleLimit: 10,
      );
      expect(feed.enabled, isFalse);
      expect(feed.isBuiltIn, isTrue);
      expect(feed.articleLimit, 10);
    });
  });

  group('FeedConfig equality', () {
    test('same URL means equal', () {
      final a = FeedConfig(url: 'https://example.com/feed', name: 'Feed A');
      final b = FeedConfig(url: 'https://example.com/feed', name: 'Feed B');
      expect(a, equals(b));
    });

    test('different URL means not equal', () {
      final a = FeedConfig(url: 'https://a.com/feed', name: 'Feed');
      final b = FeedConfig(url: 'https://b.com/feed', name: 'Feed');
      expect(a, isNot(equals(b)));
    });

    test('hashCode is consistent with equality', () {
      final a = FeedConfig(url: 'https://example.com/feed', name: 'A');
      final b = FeedConfig(url: 'https://example.com/feed', name: 'B');
      expect(a.hashCode, b.hashCode);
    });
  });

  group('FeedConfig.defaultFeeds', () {
    test('returns 15 entries', () {
      expect(FeedConfig.defaultFeeds.length, 15);
    });

    test('all built-in feeds have isBuiltIn == true', () {
      expect(FeedConfig.defaultFeeds.every((f) => f.isBuiltIn), isTrue);
    });

    test('all built-in feeds are enabled by default', () {
      expect(FeedConfig.defaultFeeds.every((f) => f.enabled), isTrue);
    });

    test('all built-in feeds have valid https URLs', () {
      for (final feed in FeedConfig.defaultFeeds) {
        final uri = Uri.parse(feed.url);
        expect(uri.isAbsolute, isTrue,
            reason: '${feed.name} URL is not absolute');
        expect(feed.url, startsWith('https://'),
            reason: '${feed.name} URL does not use https');
      }
    });

    test('feed URLs are unique', () {
      final urls = FeedConfig.defaultFeeds.map((f) => f.url).toList();
      expect(urls.toSet().length, urls.length);
    });

    test('contains expected sources', () {
      final names = FeedConfig.defaultFeeds.map((f) => f.name).toSet();
      expect(names, containsAll(['Ars Technica', 'The Verge', 'Hacker News', 'Wired', 'CNET']));
    });
  });
}
