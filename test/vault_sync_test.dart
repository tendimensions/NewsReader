import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:news_reader/models/app_settings.dart';
import 'package:news_reader/models/article.dart';
import 'package:news_reader/models/vault_sync_entry.dart';
import 'package:news_reader/repositories/bookmarks_repository.dart';
import 'package:news_reader/repositories/settings_repository.dart';
import 'package:news_reader/repositories/vault_outbox_repository.dart';
import 'package:news_reader/repositories/vault_token_store.dart';
import 'package:news_reader/providers/bookmarks_provider.dart';
import 'package:news_reader/providers/vault_provider.dart';
import 'package:news_reader/services/vault_client.dart';

/// Token store that never touches the platform keystore.
class _FakeTokenStore implements VaultTokenStore {
  String? token;
  _FakeTokenStore(this.token);

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> delete() async => token = null;
}

/// Records the saves it is asked to make, and can be told to fail.
class _RecordingClient implements VaultClient {
  final List<String> saved = [];
  final String? failWith;
  _RecordingClient({this.failWith});

  @override
  Future<VaultSaveResult> saveBookmark({
    required String url,
    required String title,
    String note = '',
    String text = '',
    List<String> tags = const [],
  }) async {
    if (failWith != null) throw VaultException(failWith!);
    saved.add(url);
    return const VaultSaveResult(slug: 's', status: 'processed');
  }

  @override
  void close() {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Article _article(String id, {String? content, List<String> categories = const []}) => Article(
      id: id,
      title: 'Article $id',
      url: 'https://example.com/$id',
      publishedAt: DateTime(2026, 9, 4),
      sourceName: 'Example',
      content: content,
      description: 'description of $id',
      categories: categories,
    );

void main() {
  late Directory tempDir;
  late VaultOutboxRepository outbox;
  late SettingsRepository settingsRepo;
  late BookmarksRepository bookmarksRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('newsreader_vault_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ArticleAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ThemePreferenceAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(AppSettingsAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(VaultSyncEntryAdapter());

    outbox = VaultOutboxRepository();
    settingsRepo = SettingsRepository();
    bookmarksRepo = BookmarksRepository();
    await outbox.init();
    await settingsRepo.init();
    await bookmarksRepo.init();
    await settingsRepo.setVaultSyncEnabled(true);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true).catchError((_) => tempDir);
  });

  VaultSyncNotifier notifierWith(VaultClient client, {String? token = 'tok'}) {
    return VaultSyncNotifier(
      outbox: outbox,
      tokenStore: _FakeTokenStore(token),
      settings: settingsRepo,
      clientFactory: ({required String serverUrl, required String token}) => client,
    );
  }

  group('outbox', () {
    test('re-queuing the same article replaces rather than duplicates', () async {
      await outbox.add(VaultSyncEntry(articleId: 'a', url: 'u', title: 't'));
      await outbox.add(VaultSyncEntry(articleId: 'a', url: 'u2', title: 't2'));
      expect(outbox.pendingCount, 1);
      expect(outbox.getAll().single.url, 'u2');
    });

    test('drops an entry after maxAttempts failures', () async {
      await outbox.add(VaultSyncEntry(articleId: 'a', url: 'u', title: 't'));
      for (var i = 1; i < VaultOutboxRepository.maxAttempts; i++) {
        expect(await outbox.recordFailure('a', 'boom'), isFalse);
      }
      expect(await outbox.recordFailure('a', 'boom'), isTrue);
      expect(outbox.pendingCount, 0);
    });

    test('returns entries oldest first', () async {
      await outbox.add(VaultSyncEntry(
          articleId: 'new', url: 'u', title: 't', queuedAt: DateTime(2026, 9, 4)));
      await outbox.add(VaultSyncEntry(
          articleId: 'old', url: 'u', title: 't', queuedAt: DateTime(2026, 1, 1)));
      expect(outbox.getAll().map((e) => e.articleId), ['old', 'new']);
    });
  });

  group('enqueue', () {
    test('sends the article and clears the queue', () async {
      final client = _RecordingClient();
      await notifierWith(client).enqueue(_article('a1'));

      expect(client.saved, ['https://example.com/a1']);
      expect(outbox.pendingCount, 0);
    });

    test('prefers article content over description as the text sent', () async {
      final notifier = notifierWith(_RecordingClient(failWith: 'offline'));
      await notifier.enqueue(_article('a1', content: 'the full body'));

      expect(outbox.getAll().single.text, 'the full body');
    });

    test('falls back to the description when there is no content', () async {
      final notifier = notifierWith(_RecordingClient(failWith: 'offline'));
      await notifier.enqueue(_article('a1'));

      expect(outbox.getAll().single.text, 'description of a1');
    });

    test('carries feed categories as tags', () async {
      final notifier = notifierWith(_RecordingClient(failWith: 'offline'));
      await notifier.enqueue(_article('a1', categories: ['tech', 'ai']));

      expect(outbox.getAll().single.tags, ['tech', 'ai']);
    });

    test('does nothing when sync is disabled', () async {
      await settingsRepo.setVaultSyncEnabled(false);
      final client = _RecordingClient();
      await notifierWith(client).enqueue(_article('a1'));

      expect(client.saved, isEmpty);
      expect(outbox.pendingCount, 0);
    });

    test('keeps the entry queued when the send fails', () async {
      final notifier = notifierWith(_RecordingClient(failWith: 'no network'));
      await notifier.enqueue(_article('a1'));

      expect(outbox.pendingCount, 1);
      expect(outbox.getAll().single.attempts, 1);
      expect(notifier.state.pending, 1);
      expect(notifier.state.lastError, 'no network');
    });

    test('a queued entry is sent by a later drain', () async {
      final failing = notifierWith(_RecordingClient(failWith: 'no network'));
      await failing.enqueue(_article('a1'));
      expect(outbox.pendingCount, 1);

      final client = _RecordingClient();
      await notifierWith(client).drain();

      expect(client.saved, ['https://example.com/a1']);
      expect(outbox.pendingCount, 0);
    });

    test('reports a missing token instead of sending', () async {
      final client = _RecordingClient();
      final notifier = notifierWith(client, token: null);
      await notifier.enqueue(_article('a1'));

      expect(client.saved, isEmpty);
      expect(outbox.pendingCount, 1, reason: 'kept for when a token is set');
      expect(notifier.state.lastError, contains('No vault token'));
    });
  });

  group('bookmark lifecycle', () {
    test('bookmarking notifies, un-bookmarking does not', () async {
      final added = <String>[];
      final notifier = BookmarksNotifier(bookmarksRepo, onAdded: (a) => added.add(a.id));
      final article = _article('a1');

      await notifier.toggle(article);
      expect(added, ['a1'], reason: 'newly bookmarked');

      await notifier.toggle(article);
      expect(added, ['a1'],
          reason: 'removing a bookmark must not touch the vault document');

      await notifier.toggle(article);
      expect(added, ['a1', 'a1'], reason: 're-bookmarking notifies again');
    });
  });
}
