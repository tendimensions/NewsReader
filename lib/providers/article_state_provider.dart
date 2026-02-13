import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/article_state_repository.dart';
import 'repositories_provider.dart';

/// Tracks read and deleted article IDs with reactive state
final articleStateProvider =
    StateNotifierProvider<ArticleStateNotifier, ArticleStateData>((ref) {
  final repo = ref.watch(articleStateRepositoryProvider);
  return ArticleStateNotifier(repo);
});

class ArticleStateData {
  final Set<String> readIds;
  final Set<String> deletedIds;

  const ArticleStateData({
    this.readIds = const {},
    this.deletedIds = const {},
  });

  ArticleStateData copyWith({
    Set<String>? readIds,
    Set<String>? deletedIds,
  }) {
    return ArticleStateData(
      readIds: readIds ?? this.readIds,
      deletedIds: deletedIds ?? this.deletedIds,
    );
  }
}

class ArticleStateNotifier extends StateNotifier<ArticleStateData> {
  final ArticleStateRepository _repo;

  ArticleStateNotifier(ArticleStateRepository repo)
      : _repo = repo,
        super(ArticleStateData(
          readIds: repo.readIds,
          deletedIds: repo.deletedIds,
        ));

  bool isRead(String articleId) => state.readIds.contains(articleId);
  bool isDeleted(String articleId) => state.deletedIds.contains(articleId);

  Future<void> markRead(String articleId) async {
    await _repo.markRead(articleId);
    state = state.copyWith(readIds: _repo.readIds);
  }

  Future<void> markUnread(String articleId) async {
    await _repo.markUnread(articleId);
    state = state.copyWith(readIds: _repo.readIds);
  }

  Future<void> deleteArticle(String articleId) async {
    await _repo.markDeleted(articleId);
    state = state.copyWith(deletedIds: _repo.deletedIds);
  }

  Future<void> undeleteArticle(String articleId) async {
    await _repo.undelete(articleId);
    state = state.copyWith(deletedIds: _repo.deletedIds);
  }

  Future<void> clearDeleted() async {
    await _repo.clearDeleted();
    state = state.copyWith(deletedIds: {});
  }

  Future<void> clearRead() async {
    await _repo.clearRead();
    state = state.copyWith(readIds: {});
  }
}
