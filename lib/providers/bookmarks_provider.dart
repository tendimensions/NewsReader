import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/article.dart';
import '../repositories/bookmarks_repository.dart';
import 'repositories_provider.dart';
import 'vault_provider.dart';

/// Provides bookmarked articles list
final bookmarksProvider =
    StateNotifierProvider<BookmarksNotifier, List<Article>>((ref) {
  final repo = ref.watch(bookmarksRepositoryProvider);
  return BookmarksNotifier(
    repo,
    onAdded: (article) => ref.read(vaultSyncProvider.notifier).enqueue(article),
  );
});

class BookmarksNotifier extends StateNotifier<List<Article>> {
  final BookmarksRepository _repo;

  /// Called when an article is newly bookmarked - not when one is removed.
  /// Removing a bookmark takes the article out of the reading queue; it must not
  /// touch the vault document, which is long-term memory with its own lifetime.
  final void Function(Article article)? _onAdded;

  BookmarksNotifier(BookmarksRepository repo, {void Function(Article)? onAdded})
      : _repo = repo,
        _onAdded = onAdded,
        super(repo.getAll());

  bool isBookmarked(String articleId) => _repo.isBookmarked(articleId);

  Future<void> toggle(Article article) async {
    final wasBookmarked = _repo.isBookmarked(article.id);
    await _repo.toggle(article);
    state = _repo.getAll();
    if (!wasBookmarked) _onAdded?.call(article);
  }

  Future<void> clear() async {
    await _repo.clear();
    state = [];
  }
}
