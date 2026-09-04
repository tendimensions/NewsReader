import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/feed_config_repository.dart';
import '../repositories/bookmarks_repository.dart';
import '../repositories/article_cache_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/article_state_repository.dart';
import '../repositories/vault_outbox_repository.dart';

/// Singleton repository providers — initialized at app startup

final feedConfigRepositoryProvider = Provider<FeedConfigRepository>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});

final bookmarksRepositoryProvider = Provider<BookmarksRepository>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});

final articleCacheRepositoryProvider = Provider<ArticleCacheRepository>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});

final articleStateRepositoryProvider = Provider<ArticleStateRepository>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});

final vaultOutboxRepositoryProvider = Provider<VaultOutboxRepository>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});
