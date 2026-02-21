import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/article.dart';
import '../models/feed_config.dart';
import '../repositories/feed_config_repository.dart';
import '../services/news_aggregator_service.dart';
import '../services/news_sources/rss_news_source.dart';
import 'article_state_provider.dart';
import 'repositories_provider.dart';

/// Provides the list of feed configurations
final feedConfigsProvider =
    StateNotifierProvider<FeedConfigNotifier, List<FeedConfig>>((ref) {
  final repo = ref.watch(feedConfigRepositoryProvider);
  return FeedConfigNotifier(repo);
});

class FeedConfigNotifier extends StateNotifier<List<FeedConfig>> {
  final FeedConfigRepository _repo;

  FeedConfigNotifier(FeedConfigRepository repo)
      : _repo = repo,
        super(repo.getAll());

  Future<void> addFeed(String url, String name, {int articleLimit = 5}) async {
    final feed = FeedConfig(url: url, name: name, articleLimit: articleLimit);
    await _repo.addFeed(feed);
    state = _repo.getAll();
  }

  Future<void> removeFeed(String url) async {
    await _repo.removeFeed(url);
    state = _repo.getAll();
  }

  Future<void> updateFeed(
      String oldUrl, String newUrl, String newName, int articleLimit) async {
    await _repo.updateFeed(oldUrl, newUrl, newName, articleLimit);
    state = _repo.getAll();
  }

  Future<void> toggleFeed(String url, bool enabled) async {
    await _repo.toggleFeed(url, enabled);
    state = _repo.getAll();
  }

  Future<void> resetToDefaults() async {
    await _repo.resetToDefaults();
    state = _repo.getAll();
  }
}

/// Builds the aggregator from enabled feed configs
final newsAggregatorProvider = Provider<NewsAggregatorService>((ref) {
  final configs = ref.watch(feedConfigsProvider);
  final enabledConfigs = configs.where((c) => c.enabled).toList();
  debugPrint('[FeedProvider] Building aggregator: ${enabledConfigs.length} enabled feeds');

  if (enabledConfigs.isEmpty) {
    debugPrint('[FeedProvider] No enabled feeds!');
    return NewsAggregatorService(
      sources: [],
      deduplicationStrategy: DeduplicationStrategy.combined,
    );
  }

  for (final c in enabledConfigs) {
    debugPrint('[FeedProvider]   Feed: ${c.name} -> ${c.url}');
  }

  final rssSource = RssNewsSource(
    displayName: 'RSS Feeds',
    feedUrls: enabledConfigs.map((c) => c.url).toList(),
    feedNames: {for (final c in enabledConfigs) c.url: c.name},
    feedLimits: enabledConfigs.map((c) => c.articleLimit).toList(),
  );

  return NewsAggregatorService(
    sources: [rssSource],
    deduplicationStrategy: DeduplicationStrategy.combined,
  );
});

/// Active feed filter — when set, FeedScreen shows only articles from this feed name
final feedFilterProvider = StateProvider<String?>((ref) => null);

/// Fetches articles from the aggregator, filters deleted, caches for offline
final articlesProvider =
    AsyncNotifierProvider<ArticlesNotifier, List<Article>>(
        ArticlesNotifier.new);

class ArticlesNotifier extends AsyncNotifier<List<Article>> {
  @override
  Future<List<Article>> build() async {
    final aggregator = ref.watch(newsAggregatorProvider);
    final cacheRepo = ref.read(articleCacheRepositoryProvider);

    // Guard against stale background fetches when the notifier is rebuilt
    var cancelled = false;
    ref.onDispose(() => cancelled = true);

    final cached = cacheRepo.getAll();
    debugPrint('[ArticlesNotifier] build() called, returning ${cached.length} cached articles immediately');

    // Fetch in the background; update state when done without blocking startup
    Future.microtask(() async {
      try {
        debugPrint('[ArticlesNotifier] Background fetch starting...');
        final articles = await aggregator.fetchArticles(limit: 50);
        if (cancelled) return;
        debugPrint('[ArticlesNotifier] Background fetch complete: ${articles.length} articles');
        await cacheRepo.cacheArticles(articles);
        if (cancelled) return;
        state = AsyncData(articles);
      } catch (e, stack) {
        if (cancelled) return;
        debugPrint('[ArticlesNotifier] Background fetch ERROR: $e');
        // Only surface the error if we have nothing to show
        final current = state;
        if (current is AsyncData<List<Article>> && current.value.isEmpty) {
          state = AsyncError(e, stack);
        }
      }
    });

    return cached;
  }

  Future<void> refresh() async {
    debugPrint('[ArticlesNotifier] refresh() called');
    final aggregator = ref.read(newsAggregatorProvider);
    final cacheRepo = ref.read(articleCacheRepositoryProvider);
    state = const AsyncLoading();
    try {
      final articles = await aggregator.fetchArticles(limit: 50);
      await cacheRepo.cacheArticles(articles);
      state = AsyncData(articles);
      debugPrint('[ArticlesNotifier] refresh() done: ${articles.length} articles');
    } catch (e, stack) {
      debugPrint('[ArticlesNotifier] refresh() ERROR: $e');
      final cached = cacheRepo.getAll();
      state = cached.isNotEmpty ? AsyncData(cached) : AsyncError(e, stack);
    }
  }

  Future<List<Article>> search(String query) async {
    final aggregator = ref.read(newsAggregatorProvider);
    final articleState = ref.read(articleStateProvider);
    final results = await aggregator.searchArticles(query: query, limit: 30);
    return results
        .where((a) => !articleState.deletedIds.contains(a.id))
        .toList();
  }
}
