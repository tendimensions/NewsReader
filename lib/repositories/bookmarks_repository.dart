import 'package:hive/hive.dart';
import '../models/article.dart';

/// Manages bookmarked articles in Hive storage
class BookmarksRepository {
  static const String _boxName = 'bookmarks';
  late Box<Article> _box;

  Future<void> init() async {
    _box = await Hive.openBox<Article>(_boxName);
  }

  List<Article> getAll() {
    final articles = _box.values.toList();
    articles.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return articles;
  }

  bool isBookmarked(String articleId) => _box.containsKey(articleId);

  Future<void> add(Article article) async {
    await _box.put(article.id, article);
  }

  Future<void> remove(String articleId) async {
    await _box.delete(articleId);
  }

  Future<void> toggle(Article article) async {
    if (isBookmarked(article.id)) {
      await remove(article.id);
    } else {
      await add(article);
    }
  }

  Future<void> clear() async {
    await _box.clear();
  }
}
