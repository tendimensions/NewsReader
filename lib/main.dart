import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'models/article.dart';
import 'models/feed_config.dart';
import 'models/app_settings.dart';
import 'models/vault_sync_entry.dart';
import 'providers/repositories_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/vault_provider.dart';
import 'repositories/feed_config_repository.dart';
import 'repositories/bookmarks_repository.dart';
import 'repositories/article_cache_repository.dart';
import 'repositories/settings_repository.dart';
import 'repositories/article_state_repository.dart';
import 'repositories/vault_outbox_repository.dart';
import 'screens/feed_screen.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Catch Flutter framework errors (widget build exceptions, etc.)
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('[FlutterError] ${details.exception}');
        debugPrint('[FlutterError] ${details.stack}');
      };

      // Catch unhandled async errors on the root isolate
      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('[PlatformError] $error\n$stack');
        return true;
      };

      try {
        await _initializeAndRun();
      } catch (e, stack) {
        debugPrint('[main] Fatal initialization error: $e\n$stack');
        runApp(_InitErrorApp(error: '$e'));
      }
    },
    (error, stack) {
      debugPrint('[Zone] Unhandled error: $error\n$stack');
    },
  );
}

Future<void> _initializeAndRun() async {
  await Hive.initFlutter();

  // Guard against double-registration (hot reload, unexpected re-init)
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ArticleAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(FeedConfigAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ThemePreferenceAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(AppSettingsAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(VaultSyncEntryAdapter());

  final feedConfigRepo = FeedConfigRepository();
  final bookmarksRepo = BookmarksRepository();
  final articleCacheRepo = ArticleCacheRepository();
  final settingsRepo = SettingsRepository();
  final articleStateRepo = ArticleStateRepository();
  final vaultOutboxRepo = VaultOutboxRepository();

  // Open each Hive box individually. If a specific box is corrupted (e.g.
  // after a schema change), only that box is wiped and recreated — user data
  // in other boxes (custom feeds, bookmarks, settings) is preserved.
  await _tryInit(feedConfigRepo.init, ['feed_configs']);
  await _tryInit(bookmarksRepo.init, ['bookmarks']);
  await _tryInit(articleCacheRepo.init, ['article_cache']);
  await _tryInit(settingsRepo.init, ['settings']);
  await _tryInit(articleStateRepo.init, ['read_articles', 'deleted_articles']);
  await _tryInit(vaultOutboxRepo.init, ['vault_outbox']);

  runApp(
    ProviderScope(
      overrides: [
        feedConfigRepositoryProvider.overrideWithValue(feedConfigRepo),
        bookmarksRepositoryProvider.overrideWithValue(bookmarksRepo),
        articleCacheRepositoryProvider.overrideWithValue(articleCacheRepo),
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        articleStateRepositoryProvider.overrideWithValue(articleStateRepo),
        vaultOutboxRepositoryProvider.overrideWithValue(vaultOutboxRepo),
      ],
      child: const NewsReaderApp(),
    ),
  );
}

/// Opens one repository. On failure, deletes only its box(es) and retries once.
/// Other repositories are untouched, so unaffected user data is preserved.
Future<void> _tryInit(
  Future<void> Function() init,
  List<String> boxNames,
) async {
  try {
    await init().timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('[main] Box(es) $boxNames failed ($e) — clearing and retrying...');
    for (final name in boxNames) {
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (deleteErr) {
        debugPrint('[main] Could not delete box "$name": $deleteErr');
      }
    }
    // If this also fails the exception propagates to main() → error screen.
    await init().timeout(const Duration(seconds: 10));
  }
}

// ---------------------------------------------------------------------------
// Error screen shown when initialization fails before the app can start
// ---------------------------------------------------------------------------

class _InitErrorApp extends StatelessWidget {
  final String error;
  const _InitErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'App failed to start',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'An error occurred during initialization.\n'
                  'Try force-quitting and reopening the app, '
                  'or clearing app data if the problem persists.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    error,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main application widget
// ---------------------------------------------------------------------------

/// Lets the vault-sync toast be shown from outside any particular screen's
/// context. A save takes seconds and finishes long after the user has moved on,
/// so the confirmation has to survive navigating from the article back to the
/// feed - a per-screen ScaffoldMessenger would not.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class NewsReaderApp extends ConsumerWidget {
  const NewsReaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    // Bookmarking flips the icon immediately, but the vault save is a network
    // round trip plus an LLM call. Without this the user has no idea whether it
    // landed, or whether it is sitting in the outbox waiting for signal.
    ref.listen<VaultSyncState>(vaultSyncProvider, (previous, next) {
      final event = next.lastEvent;
      if (event == null || identical(event, previous?.lastEvent)) return;

      scaffoldMessengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              event.title.isEmpty ? event.message : '${event.message}: ${event.title}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            duration: Duration(seconds: event.isError ? 5 : 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
    });

    return MaterialApp(
      title: 'Ten Dimensional News Reader',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const FeedScreen(),
    );
  }
}
