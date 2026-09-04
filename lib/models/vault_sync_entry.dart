import 'package:hive/hive.dart';

part 'vault_sync_entry.g.dart';

/// One bookmark waiting to be pushed to the mcp-vault server.
///
/// The article's fields are copied in at queue time rather than looked up when
/// the entry is drained: a news reader is routinely offline, and the article may
/// have been evicted from the 200-item cache by the time the queue runs.
@HiveType(typeId: 4)
class VaultSyncEntry extends HiveObject {
  @HiveField(0)
  final String articleId;

  @HiveField(1)
  final String url;

  @HiveField(2)
  final String title;

  /// Article body from the feed, handed to the server so it skips its own fetch.
  @HiveField(3)
  final String text;

  /// Feed categories, merged server-side with the LLM's tags.
  @HiveField(4)
  final List<String> tags;

  @HiveField(5)
  final DateTime queuedAt;

  @HiveField(6)
  int attempts;

  @HiveField(7)
  String? lastError;

  VaultSyncEntry({
    required this.articleId,
    required this.url,
    required this.title,
    this.text = '',
    this.tags = const [],
    DateTime? queuedAt,
    this.attempts = 0,
    this.lastError,
  }) : queuedAt = queuedAt ?? DateTime.now();
}
