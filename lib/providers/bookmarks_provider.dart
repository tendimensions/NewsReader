import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/article.dart';
import '../repositories/bookmarks_repository.dart';
import 'repositories_provider.dart';

/// Provides bookmarked articles list
final bookmarksProvider =
    StateNotifierProvider<BookmarksNotifier, List<Article>>((ref) {
  final repo = ref.watch(bookmarksRepositoryProvider);
  return BookmarksNotifier(repo);
});

class BookmarksNotifier extends StateNotifier<List<Article>> {
  final BookmarksRepository _repo;

  BookmarksNotifier(BookmarksRepository repo)
      : _repo = repo,
        super(repo.getAll());

  bool isBookmarked(String articleId) => _repo.isBookmarked(articleId);

  Future<void> toggle(Article article) async {
    await _repo.toggle(article);
    state = _repo.getAll();
  }

  Future<void> clear() async {
    await _repo.clear();
    state = [];
  }
}
