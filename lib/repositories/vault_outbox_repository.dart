import 'package:hive/hive.dart';
import '../models/vault_sync_entry.dart';

/// Queue of bookmarks waiting to reach the mcp-vault server.
///
/// Keyed by article id, so bookmarking the same article twice replaces the
/// pending entry rather than queuing a duplicate save.
class VaultOutboxRepository {
  static const String _boxName = 'vault_outbox';

  /// Entries are dropped after this many failed attempts. Past this point the
  /// failure is not transient - a revoked token, a URL the server can never
  /// resolve - and retrying it forever only delays everything queued behind it.
  static const int maxAttempts = 5;

  late Box<VaultSyncEntry> _box;

  Future<void> init() async {
    _box = await Hive.openBox<VaultSyncEntry>(_boxName);
  }

  int get pendingCount => _box.length;

  List<VaultSyncEntry> getAll() {
    final entries = _box.values.toList();
    entries.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return entries;
  }

  Future<void> add(VaultSyncEntry entry) async {
    await _box.put(entry.articleId, entry);
  }

  Future<void> remove(String articleId) async {
    await _box.delete(articleId);
  }

  /// Record a failed attempt. Returns true if the entry was dropped for
  /// exceeding [maxAttempts].
  Future<bool> recordFailure(String articleId, String error) async {
    final entry = _box.get(articleId);
    if (entry == null) return false;

    entry.attempts += 1;
    entry.lastError = error;

    if (entry.attempts >= maxAttempts) {
      await _box.delete(articleId);
      return true;
    }
    await _box.put(articleId, entry);
    return false;
  }

  Future<void> clear() async {
    await _box.clear();
  }
}
