import 'package:hive/hive.dart';
import '../models/article.dart';

/// Caches article headlines + summaries for offline browsing
class ArticleCacheRepository {
  static const String _boxName = 'article_cache';
  static const int _maxCacheSize = 200;
  late Box<Article> _box;

  Future<void> init() async {
    _box = await Hive.openBox<Article>(_boxName);
  }

  List<Article> getAll() {
    final articles = _box.values.toList();
    articles.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return articles;
  }

  Future<void> cacheArticles(List<Article> articles) async {
    // Store without full content to save space
    for (final article in articles) {
      final cached = Article(
        id: article.id,
        title: article.title,
        description: article.description,
        content: null, // Don't cache full content
        url: article.url,
        imageUrl: article.imageUrl,
        publishedAt: article.publishedAt,
        sourceName: article.sourceName,
        author: article.author,
        categories: article.categories,
        sourceCount: article.sourceCount,
        sourceNames: article.sourceNames,
      );
      await _box.put(article.id, cached);
    }
    await _trimCache();
  }

  Future<void> _trimCache() async {
    if (_box.length <= _maxCacheSize) return;
    final articles = getAll();
    // Remove oldest entries beyond max
    final toRemove = articles.sublist(_maxCacheSize);
    for (final article in toRemove) {
      await _box.delete(article.id);
    }
  }

  Future<void> clear() async {
    await _box.clear();
  }
}
