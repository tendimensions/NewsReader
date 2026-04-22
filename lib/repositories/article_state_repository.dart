import 'package:hive/hive.dart';

/// Tracks read/unread status and deleted (suppressed) article IDs
class ArticleStateRepository {
  static const String _readBoxName = 'read_articles';
  static const String _deletedBoxName = 'deleted_articles';
  late Box<bool> _readBox;
  late Box<bool> _deletedBox;

  Future<void> init() async {
    _readBox = await Hive.openBox<bool>(_readBoxName);
    _deletedBox = await Hive.openBox<bool>(_deletedBoxName);
  }

  // --- Read/Unread ---

  bool isRead(String articleId) => _readBox.containsKey(articleId);

  Set<String> get readIds => _readBox.keys.cast<String>().toSet();

  Future<void> markRead(String articleId) async {
    await _readBox.put(articleId, true);
  }

  Future<void> markUnread(String articleId) async {
    await _readBox.delete(articleId);
  }

  // --- Deleted/Suppressed ---

  bool isDeleted(String articleId) => _deletedBox.containsKey(articleId);

  Set<String> get deletedIds => _deletedBox.keys.cast<String>().toSet();

  Future<void> markDeleted(String articleId) async {
    await _deletedBox.put(articleId, true);
  }

  Future<void> undelete(String articleId) async {
    await _deletedBox.delete(articleId);
  }

  Future<void> clearDeleted() async {
    await _deletedBox.clear();
  }

  Future<void> clearRead() async {
    await _readBox.clear();
  }

  /// Removes read/deleted IDs that are no longer in the live article set
  /// (i.e. not in the cache and not bookmarked). Call after cache is trimmed.
  Future<void> pruneOrphans(Set<String> liveIds) async {
    final staleRead = _readBox.keys.cast<String>().where((id) => !liveIds.contains(id)).toList();
    for (final id in staleRead) {
      await _readBox.delete(id);
    }
    final staleDeleted = _deletedBox.keys.cast<String>().where((id) => !liveIds.contains(id)).toList();
    for (final id in staleDeleted) {
      await _deletedBox.delete(id);
    }
  }
}
