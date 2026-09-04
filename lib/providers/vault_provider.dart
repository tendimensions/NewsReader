import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/article.dart';
import '../models/vault_sync_entry.dart';
import '../repositories/vault_outbox_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/vault_token_store.dart';
import '../services/vault_client.dart';
import 'repositories_provider.dart';

/// Snapshot of the outbox, for the settings screen.
class VaultSyncState {
  final int pending;
  final bool isSyncing;
  final String? lastError;

  const VaultSyncState({this.pending = 0, this.isSyncing = false, this.lastError});

  VaultSyncState copyWith({int? pending, bool? isSyncing, String? lastError, bool clearError = false}) {
    return VaultSyncState(
      pending: pending ?? this.pending,
      isSyncing: isSyncing ?? this.isSyncing,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

final vaultTokenStoreProvider = Provider<VaultTokenStore>((ref) => VaultTokenStore());

final vaultSyncProvider =
    StateNotifierProvider<VaultSyncNotifier, VaultSyncState>((ref) {
  return VaultSyncNotifier(
    outbox: ref.watch(vaultOutboxRepositoryProvider),
    tokenStore: ref.watch(vaultTokenStoreProvider),
    settings: ref.watch(settingsRepositoryProvider),
  );
});

/// Pushes bookmarked articles to the mcp-vault server, queueing them first so a
/// save survives being offline.
///
/// Bookmarking is never blocked on this. The local Hive bookmark is the source
/// of truth for the reading list; the vault copy is long-term memory, and the
/// two have different lifetimes. In particular **un-bookmarking does not delete
/// the vault document** - the article leaves the reading queue, the curated
/// document stays.
class VaultSyncNotifier extends StateNotifier<VaultSyncState> {
  final VaultOutboxRepository _outbox;
  final VaultTokenStore _tokenStore;
  final SettingsRepository _settings;

  /// Injectable so tests can supply a client backed by a mock transport.
  final VaultClient Function({required String serverUrl, required String token})? _clientFactory;

  bool _draining = false;

  VaultSyncNotifier({
    required VaultOutboxRepository outbox,
    required VaultTokenStore tokenStore,
    required SettingsRepository settings,
    VaultClient Function({required String serverUrl, required String token})? clientFactory,
  })  : _outbox = outbox,
        _tokenStore = tokenStore,
        _settings = settings,
        _clientFactory = clientFactory,
        super(const VaultSyncState()) {
    state = state.copyWith(pending: _outbox.pendingCount);
  }

  /// Queue a newly bookmarked article, then try to send straight away.
  ///
  /// The article's own text and categories go in the queue so the server can
  /// skip its fetch - better input than scraping, and it works on pages that
  /// would paywall or 404 a server-side request.
  Future<void> enqueue(Article article) async {
    if (!_settings.settings.vaultSyncEnabled) return;

    await _outbox.add(VaultSyncEntry(
      articleId: article.id,
      url: article.url,
      title: article.title,
      text: _articleText(article),
      tags: article.categories,
    ));
    state = state.copyWith(pending: _outbox.pendingCount);

    await drain();
  }

  /// Send everything queued. Safe to call repeatedly; overlapping calls no-op.
  Future<void> drain() async {
    if (_draining) return;
    if (!_settings.settings.vaultSyncEnabled) return;

    final token = await _tokenStore.read();
    if (token == null) {
      state = state.copyWith(lastError: 'No vault token configured');
      return;
    }

    final entries = _outbox.getAll();
    if (entries.isEmpty) return;

    _draining = true;
    state = state.copyWith(isSyncing: true, clearError: true);

    final client = _clientFactory != null
        ? _clientFactory(serverUrl: _settings.settings.vaultServerUrl, token: token)
        : VaultClient(serverUrl: _settings.settings.vaultServerUrl, token: token);

    String? lastError;
    try {
      for (final entry in entries) {
        try {
          await client.saveBookmark(
            url: entry.url,
            title: entry.title,
            text: entry.text,
            tags: entry.tags,
          );
          await _outbox.remove(entry.articleId);
        } on VaultException catch (e) {
          lastError = e.message;
          final dropped = await _outbox.recordFailure(entry.articleId, e.message);
          debugPrint('[vault] ${entry.title}: ${e.message}${dropped ? ' (giving up)' : ''}');
          // Stop on the first failure: these are nearly always shared causes -
          // no network, a dead token - and hammering the rest just burns
          // attempts on entries that would have succeeded later.
          break;
        }
      }
    } finally {
      client.close();
      _draining = false;
      state = state.copyWith(
        pending: _outbox.pendingCount,
        isSyncing: false,
        lastError: lastError,
        clearError: lastError == null,
      );
    }
  }

  Future<void> clearQueue() async {
    await _outbox.clear();
    state = state.copyWith(pending: 0, clearError: true);
  }

  /// Best available body text for the server to enrich.
  static String _articleText(Article article) {
    final content = article.content?.trim() ?? '';
    if (content.isNotEmpty) return content;
    return article.description?.trim() ?? '';
  }
}
