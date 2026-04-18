import 'package:flutter_test/flutter_test.dart';
import 'package:news_reader/models/article.dart';
import 'package:news_reader/services/news_aggregator_service.dart';
import 'package:news_reader/services/news_sources/i_news_source.dart';

// Simple in-memory source for testing
class _StubSource implements INewsSource {
  final List<Article> articles;

  @override
  final String sourceName;

  _StubSource(this.sourceName, this.articles);

  @override
  Future<List<Article>> fetchArticles({String? category, int limit = 20, int offset = 0}) async =>
      articles;

  @override
  Future<List<Article>> searchArticles({required String query, int limit = 20, int offset = 0}) async =>
      articles;

  @override
  Future<List<String>> getCategories() async => [];

  @override
  Future<bool> isAvailable() async => true;
}

Article _article({
  required String id,
  required String title,
  required String url,
  required String sourceName,
  DateTime? publishedAt,
  int sourceCount = 1,
  List<String>? sourceNames,
}) {
  return Article(
    id: id,
    title: title,
    url: url,
    sourceName: sourceName,
    publishedAt: publishedAt ?? DateTime(2024, 1, 1),
    sourceCount: sourceCount,
    sourceNames: sourceNames,
  );
}

void main() {
  group('URL deduplication', () {
    test('merges articles with identical URLs', () async {
      final a1 = _article(id: '1', title: 'Article', url: 'https://example.com/article', sourceName: 'Source A');
      final a2 = _article(id: '2', title: 'Article', url: 'https://example.com/article', sourceName: 'Source B');

      final aggregator = NewsAggregatorService(
        sources: [_StubSource('Source A', [a1]), _StubSource('Source B', [a2])],
        deduplicationStrategy: DeduplicationStrategy.url,
      );

      final results = await aggregator.fetchArticles(limit: 100);
      expect(results.length, 1);
      expect(results.first.sourceNames, containsAll(['Source A', 'Source B']));
      expect(results.first.sourceCount, 2);
    });

    test('strips query params and fragments when comparing URLs', () async {
      final a1 = _article(id: '1', title: 'A', url: 'https://example.com/article?utm_source=rss', sourceName: 'S1');
      final a2 = _article(id: '2', title: 'A', url: 'https://example.com/article#section', sourceName: 'S2');

      final aggregator = NewsAggregatorService(
        sources: [_StubSource('S1', [a1]), _StubSource('S2', [a2])],
        deduplicationStrategy: DeduplicationStrategy.url,
      );

      final results = await aggregator.fetchArticles(limit: 100);
      expect(results.length, 1);
    });

    test('keeps articles with different URLs distinct', () async {
      final a1 = _article(id: '1', title: 'Article 1', url: 'https://example.com/article-1', sourceName: 'S');
      final a2 = _article(id: '2', title: 'Article 2', url: 'https://example.com/article-2', sourceName: 'S');

      final aggregator = NewsAggregatorService(
        sources: [_StubSource('S', [a1, a2])],
        deduplicationStrategy: DeduplicationStrategy.url,
      );

      final results = await aggregator.fetchArticles(limit: 100);
      expect(results.length, 2);
    });
  });

  group('Title deduplication', () {
    test('merges articles with the same title (case-insensitive)', () async {
      final a1 = _article(id: '1', title: 'Flutter 4 Released', url: 'https://source-a.com/1', sourceName: 'Source A');
      final a2 = _article(id: '2', title: 'flutter 4 released', url: 'https://source-b.com/2', sourceName: 'Source B');

      final aggregator = NewsAggregatorService(
        sources: [_StubSource('Source A', [a1]), _StubSource('Source B', [a2])],
        deduplicationStrategy: DeduplicationStrategy.title,
      );

      final results = await aggregator.fetchArticles(limit: 100);
      expect(results.length, 1);
      expect(results.first.sourceCount, 2);
    });

    test('keeps articles with different titles distinct', () async {
      final a1 = _article(id: '1', title: 'Flutter 4 Released', url: 'https://a.com/1', sourceName: 'S');
      final a2 = _article(id: '2', title: 'Dart 4 Released', url: 'https://b.com/2', sourceName: 'S');

      final aggregator = NewsAggregatorService(
        sources: [_StubSource('S', [a1, a2])],
        deduplicationStrategy: DeduplicationStrategy.title,
      );

      final results = await aggregator.fetchArticles(limit: 100);
      expect(results.length, 2);
    });
  });

  group('Title similarity deduplication', () {
    test('merges articles with >85% title similarity', () async {
      // Differ by one character ('model' vs 'models') → similarity ≈ 97%
      const base = 'Tesla unveils new electric vehicle model';
      const similar = 'Tesla unveils new electric vehicle models';

      final a1 = _article(id: '1', title: base, url: 'https://a.com/1', sourceName: 'S1');
      final a2 = _article(id: '2', title: similar, url: 'https://b.com/2', sourceName: 'S2');

      final aggregator = NewsAggregatorService(
        sources: [_StubSource('S1', [a1]), _StubSource('S2', [a2])],
        deduplicationStrategy: DeduplicationStrategy.titleSimilarity,
      );

      final results = await aggregator.fetchArticles(limit: 100);
      expect(results.length, 1);
    });

    test('keeps articles with clearly different titles distinct', () async {
      final a1 = _article(id: '1', title: 'Google acquires DeepMind spinoff', url: 'https://a.com/1', sourceName: 'S');
      final a2 = _article(id: '2', title: 'Apple announces M4 chip lineup', url: 'https://b.com/2', sourceName: 'S');

      final aggregator = NewsAggregatorService(
        sources: [_StubSource('S', [a1, a2])],
        deduplicationStrategy: DeduplicationStrategy.titleSimilarity,
      );

      final results = await aggregator.fetchArticles(limit: 100);
      expect(results.length, 2);
    });
  });

  group('Combined deduplication', () {
    test('deduplicates by URL then by title similarity', () async {
      final a1 = _article(id: '1', title: 'Big Tech Layoffs Continue', url: 'https://a.com/layoffs', sourceName: 'S1');
      // Same URL as a1 — caught by URL pass
      final a2 = _article(id: '2', title: 'Big Tech Layoffs Continue', url: 'https://a.com/layoffs?ref=rss', sourceName: 'S2');
      // Different URL but very similar title ('Continues' vs 'Continue') — caught by similarity pass
      final a3 = _article(id: '3', title: 'Big Tech Layoffs Continues', url: 'https://b.com/layoffs', sourceName: 'S3');
      // Completely different
      final a4 = _article(id: '4', title: 'Mars Mission Launches Successfully', url: 'https://c.com/mars', sourceName: 'S4');

      final aggregator = NewsAggregatorService(
        sources: [
          _StubSource('S1', [a1]),
          _StubSource('S2', [a2]),
          _StubSource('S3', [a3]),
          _StubSource('S4', [a4]),
        ],
        deduplicationStrategy: DeduplicationStrategy.combined,
      );

      final results = await aggregator.fetchArticles(limit: 100);
      expect(results.length, 2);
    });
  });

  group('Sorting', () {
    test('returns articles sorted newest first', () async {
      final older = _article(id: '1', title: 'Old', url: 'https://a.com/1', sourceName: 'S',
          publishedAt: DateTime(2024, 1, 1));
      final newer = _article(id: '2', title: 'New', url: 'https://b.com/2', sourceName: 'S',
          publishedAt: DateTime(2024, 6, 1));

      final aggregator = NewsAggregatorService(
        sources: [_StubSource('S', [older, newer])],
        deduplicationStrategy: DeduplicationStrategy.url,
      );

      final results = await aggregator.fetchArticles(limit: 100);
      expect(results.first.id, '2');
      expect(results.last.id, '1');
    });
  });

  group('getMostRepeated', () {
    test('returns articles with sourceCount >= minSources', () {
      final aggregator = NewsAggregatorService(sources: [], deduplicationStrategy: DeduplicationStrategy.url);

      final articles = [
        _article(id: '1', title: 'A', url: 'https://a.com', sourceName: 'S', sourceCount: 3),
        _article(id: '2', title: 'B', url: 'https://b.com', sourceName: 'S', sourceCount: 1),
        _article(id: '3', title: 'C', url: 'https://c.com', sourceName: 'S', sourceCount: 2),
      ];

      final result = aggregator.getMostRepeated(articles);
      expect(result.map((a) => a.id), containsAll(['1', '3']));
      expect(result.map((a) => a.id), isNot(contains('2')));
    });

    test('sorts by sourceCount descending', () {
      final aggregator = NewsAggregatorService(sources: [], deduplicationStrategy: DeduplicationStrategy.url);

      final articles = [
        _article(id: '1', title: 'A', url: 'https://a.com', sourceName: 'S', sourceCount: 2),
        _article(id: '2', title: 'B', url: 'https://b.com', sourceName: 'S', sourceCount: 5),
        _article(id: '3', title: 'C', url: 'https://c.com', sourceName: 'S', sourceCount: 3),
      ];

      final result = aggregator.getMostRepeated(articles);
      expect(result.first.sourceCount, 5);
      expect(result.last.sourceCount, 2);
    });

    test('respects custom minSources', () {
      final aggregator = NewsAggregatorService(sources: [], deduplicationStrategy: DeduplicationStrategy.url);

      final articles = [
        _article(id: '1', title: 'A', url: 'https://a.com', sourceName: 'S', sourceCount: 4),
        _article(id: '2', title: 'B', url: 'https://b.com', sourceName: 'S', sourceCount: 2),
      ];

      final result = aggregator.getMostRepeated(articles, minSources: 3);
      expect(result.length, 1);
      expect(result.first.id, '1');
    });
  });

  group('getUniqueArticles', () {
    test('returns only articles with sourceCount == 1', () {
      final aggregator = NewsAggregatorService(sources: [], deduplicationStrategy: DeduplicationStrategy.url);

      final articles = [
        _article(id: '1', title: 'A', url: 'https://a.com', sourceName: 'S', sourceCount: 1),
        _article(id: '2', title: 'B', url: 'https://b.com', sourceName: 'S', sourceCount: 2),
        _article(id: '3', title: 'C', url: 'https://c.com', sourceName: 'S', sourceCount: 1),
      ];

      final result = aggregator.getUniqueArticles(articles);
      expect(result.map((a) => a.id), containsAll(['1', '3']));
      expect(result.map((a) => a.id), isNot(contains('2')));
    });
  });

  group('getArticlesBySourceCount', () {
    test('filters by minSources only', () {
      final aggregator = NewsAggregatorService(sources: [], deduplicationStrategy: DeduplicationStrategy.url);

      final articles = [
        _article(id: '1', title: 'A', url: 'https://a.com', sourceName: 'S', sourceCount: 1),
        _article(id: '2', title: 'B', url: 'https://b.com', sourceName: 'S', sourceCount: 3),
        _article(id: '3', title: 'C', url: 'https://c.com', sourceName: 'S', sourceCount: 5),
      ];

      final result = aggregator.getArticlesBySourceCount(articles, minSources: 3);
      expect(result.map((a) => a.id), containsAll(['2', '3']));
      expect(result.map((a) => a.id), isNot(contains('1')));
    });

    test('filters by minSources and maxSources range', () {
      final aggregator = NewsAggregatorService(sources: [], deduplicationStrategy: DeduplicationStrategy.url);

      final articles = [
        _article(id: '1', title: 'A', url: 'https://a.com', sourceName: 'S', sourceCount: 1),
        _article(id: '2', title: 'B', url: 'https://b.com', sourceName: 'S', sourceCount: 3),
        _article(id: '3', title: 'C', url: 'https://c.com', sourceName: 'S', sourceCount: 5),
      ];

      final result = aggregator.getArticlesBySourceCount(articles, minSources: 2, maxSources: 4);
      expect(result.map((a) => a.id), [contains('2')]);
      expect(result.length, 1);
      expect(result.first.id, '2');
    });
  });

  group('getArticlesFromSource', () {
    test('returns articles that include the specified source', () {
      final aggregator = NewsAggregatorService(sources: [], deduplicationStrategy: DeduplicationStrategy.url);

      final articles = [
        _article(id: '1', title: 'A', url: 'https://a.com', sourceName: 'BBC', sourceNames: ['BBC', 'CNN']),
        _article(id: '2', title: 'B', url: 'https://b.com', sourceName: 'Reuters', sourceNames: ['Reuters']),
        _article(id: '3', title: 'C', url: 'https://c.com', sourceName: 'CNN', sourceNames: ['CNN']),
      ];

      final result = aggregator.getArticlesFromSource(articles, 'CNN');
      expect(result.map((a) => a.id), containsAll(['1', '3']));
      expect(result.map((a) => a.id), isNot(contains('2')));
    });
  });

  group('source error handling', () {
    test('continues fetching when one source throws', () async {
      final good = _article(id: '1', title: 'Good', url: 'https://good.com/1', sourceName: 'Good');

      final aggregator = NewsAggregatorService(
        sources: [
          _StubSource('Good', [good]),
          // Source that always fails
          _FailingSource(),
        ],
        deduplicationStrategy: DeduplicationStrategy.url,
      );

      final results = await aggregator.fetchArticles(limit: 100);
      expect(results.length, 1);
      expect(results.first.id, '1');
    });
  });
}

class _FailingSource implements INewsSource {
  @override
  String get sourceName => 'Failing Source';

  @override
  Future<List<Article>> fetchArticles({String? category, int limit = 20, int offset = 0}) async {
    throw Exception('Network error');
  }

  @override
  Future<List<Article>> searchArticles({required String query, int limit = 20, int offset = 0}) async {
    throw Exception('Network error');
  }

  @override
  Future<List<String>> getCategories() async => [];

  @override
  Future<bool> isAvailable() async => false;
}
