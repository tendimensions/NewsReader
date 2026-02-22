import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'models/article.dart';
import 'models/feed_config.dart';
import 'models/app_settings.dart';
import 'providers/repositories_provider.dart';
import 'providers/theme_provider.dart';
import 'repositories/feed_config_repository.dart';
import 'repositories/bookmarks_repository.dart';
import 'repositories/article_cache_repository.dart';
import 'repositories/settings_repository.dart';
import 'repositories/article_state_repository.dart';
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

  final feedConfigRepo = FeedConfigRepository();
  final bookmarksRepo = BookmarksRepository();
  final articleCacheRepo = ArticleCacheRepository();
  final settingsRepo = SettingsRepository();
  final articleStateRepo = ArticleStateRepository();

  // Open all Hive boxes. If any box is corrupted or incompatible (e.g. after
  // an update that changed the schema), wipe all boxes and retry once so the
  // app can still launch instead of hanging on a blank screen.
  try {
    await _openRepositories(
        feedConfigRepo, bookmarksRepo, articleCacheRepo, settingsRepo, articleStateRepo);
  } catch (e) {
    debugPrint('[main] Hive open failed ($e) — clearing all boxes and retrying...');
    await _clearAllBoxes();
    // If this second attempt also fails, the exception propagates to main()
    // and the user sees the error screen instead of a blank screen.
    await _openRepositories(
        feedConfigRepo, bookmarksRepo, articleCacheRepo, settingsRepo, articleStateRepo);
  }

  runApp(
    ProviderScope(
      overrides: [
        feedConfigRepositoryProvider.overrideWithValue(feedConfigRepo),
        bookmarksRepositoryProvider.overrideWithValue(bookmarksRepo),
        articleCacheRepositoryProvider.overrideWithValue(articleCacheRepo),
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        articleStateRepositoryProvider.overrideWithValue(articleStateRepo),
      ],
      child: const NewsReaderApp(),
    ),
  );
}

Future<void> _openRepositories(
  FeedConfigRepository feedConfigRepo,
  BookmarksRepository bookmarksRepo,
  ArticleCacheRepository articleCacheRepo,
  SettingsRepository settingsRepo,
  ArticleStateRepository articleStateRepo,
) {
  return Future.wait([
    feedConfigRepo.init(),
    bookmarksRepo.init(),
    articleCacheRepo.init(),
    settingsRepo.init(),
    articleStateRepo.init(),
  ]).timeout(const Duration(seconds: 30));
}

Future<void> _clearAllBoxes() async {
  const boxNames = [
    'feed_configs',
    'bookmarks',
    'article_cache',
    'settings',
    'read_articles',
    'deleted_articles',
  ];
  for (final name in boxNames) {
    try {
      await Hive.deleteBoxFromDisk(name);
    } catch (e) {
      debugPrint('[main] Could not delete box "$name": $e');
    }
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

class NewsReaderApp extends ConsumerWidget {
  const NewsReaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Ten Dimensional News Reader',
      debugShowCheckedModeBanner: false,
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
