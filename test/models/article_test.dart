import 'package:flutter_test/flutter_test.dart';
import 'package:news_reader/models/article.dart';

Article _makeArticle({
  String id = 'a1',
  String title = 'Test Article',
  String url = 'https://example.com/article',
  String sourceName = 'Test Source',
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
  group('Article constructor', () {
    test('defaults sourceNames to [sourceName]', () {
      final article = _makeArticle(sourceName: 'BBC');
      expect(article.sourceNames, ['BBC']);
    });

    test('defaults sourceCount to 1', () {
      final article = _makeArticle();
      expect(article.sourceCount, 1);
    });

    test('defaults categories to empty list', () {
      final article = _makeArticle();
      expect(article.categories, isEmpty);
    });

    test('accepts explicit sourceNames', () {
      final article = _makeArticle(sourceNames: ['BBC', 'CNN']);
      expect(article.sourceNames, ['BBC', 'CNN']);
    });
  });

  group('Article.fromJson / toJson', () {
    test('roundtrips required fields', () {
      final original = _makeArticle(
        id: 'xyz',
        title: 'Hello',
        url: 'https://example.com',
        sourceName: 'Source A',
        publishedAt: DateTime.utc(2024, 6, 15, 12, 0),
        sourceCount: 2,
        sourceNames: ['Source A', 'Source B'],
      );

      final json = original.toJson();
      final restored = Article.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.url, original.url);
      expect(restored.sourceName, original.sourceName);
      expect(restored.publishedAt, original.publishedAt);
      expect(restored.sourceCount, original.sourceCount);
      expect(restored.sourceNames, original.sourceNames);
    });

    test('roundtrips optional fields when present', () {
      final original = Article(
        id: 'id1',
        title: 'Title',
        url: 'https://example.com',
        sourceName: 'S',
        publishedAt: DateTime.utc(2024, 1, 1),
        description: 'A description',
        content: '<p>Content</p>',
        imageUrl: 'https://example.com/img.jpg',
        author: 'Jane Doe',
        categories: ['tech', 'flutter'],
      );

      final restored = Article.fromJson(original.toJson());

      expect(restored.description, 'A description');
      expect(restored.content, '<p>Content</p>');
      expect(restored.imageUrl, 'https://example.com/img.jpg');
      expect(restored.author, 'Jane Doe');
      expect(restored.categories, ['tech', 'flutter']);
    });

    test('fromJson handles missing optional fields gracefully', () {
      final json = {
        'id': 'id2',
        'title': 'Minimal',
        'url': 'https://example.com',
        'sourceName': 'S',
        'publishedAt': '2024-01-01T00:00:00.000Z',
      };

      final article = Article.fromJson(json);

      expect(article.description, isNull);
      expect(article.content, isNull);
      expect(article.imageUrl, isNull);
      expect(article.author, isNull);
      expect(article.categories, isEmpty);
      expect(article.sourceCount, 1);
    });
  });

  group('Article.copyWith', () {
    test('replaces specified fields', () {
      final original = _makeArticle(title: 'Old Title', sourceCount: 1);
      final copy = original.copyWith(title: 'New Title', sourceCount: 3);

      expect(copy.title, 'New Title');
      expect(copy.sourceCount, 3);
    });

    test('preserves unspecified fields', () {
      final original = _makeArticle(id: 'keep-me', url: 'https://keep.me');
      final copy = original.copyWith(title: 'Changed');

      expect(copy.id, 'keep-me');
      expect(copy.url, 'https://keep.me');
    });
  });

  group('Article equality', () {
    test('same id means equal', () {
      final a = _makeArticle(id: 'same', title: 'Article A');
      final b = _makeArticle(id: 'same', title: 'Article B');
      expect(a, equals(b));
    });

    test('different id means not equal', () {
      final a = _makeArticle(id: 'id-a');
      final b = _makeArticle(id: 'id-b');
      expect(a, isNot(equals(b)));
    });

    test('hashCode is consistent with equality', () {
      final a = _makeArticle(id: 'same');
      final b = _makeArticle(id: 'same');
      expect(a.hashCode, b.hashCode);
    });
  });
}
