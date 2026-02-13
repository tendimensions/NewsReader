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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  Hive.registerAdapter(ArticleAdapter());
  Hive.registerAdapter(FeedConfigAdapter());
  Hive.registerAdapter(ThemePreferenceAdapter());
  Hive.registerAdapter(AppSettingsAdapter());

  // Initialize repositories
  final feedConfigRepo = FeedConfigRepository();
  final bookmarksRepo = BookmarksRepository();
  final articleCacheRepo = ArticleCacheRepository();
  final settingsRepo = SettingsRepository();
  final articleStateRepo = ArticleStateRepository();

  await Future.wait([
    feedConfigRepo.init(),
    bookmarksRepo.init(),
    articleCacheRepo.init(),
    settingsRepo.init(),
    articleStateRepo.init(),
  ]);

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
