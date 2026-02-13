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

  Future<void> addFeed(String url, String name) async {
    final feed = FeedConfig(url: url, name: name);
    await _repo.addFeed(feed);
    state = _repo.getAll();
  }

  Future<void> removeFeed(String url) async {
    await _repo.removeFeed(url);
    state = _repo.getAll();
  }

  Future<void> updateFeed(String oldUrl, String newUrl, String newName) async {
    await _repo.updateFeed(oldUrl, newUrl, newName);
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
  );

  return NewsAggregatorService(
    sources: [rssSource],
    deduplicationStrategy: DeduplicationStrategy.combined,
  );
});

/// Fetches articles from the aggregator, filters deleted, caches for offline
final articlesProvider =
    AsyncNotifierProvider<ArticlesNotifier, List<Article>>(
        ArticlesNotifier.new);

class ArticlesNotifier extends AsyncNotifier<List<Article>> {
  @override
  Future<List<Article>> build() async {
    final aggregator = ref.watch(newsAggregatorProvider);
    final cacheRepo = ref.read(articleCacheRepositoryProvider);
    final articleState = ref.watch(articleStateProvider);

    try {
      debugPrint('[ArticlesNotifier] build() called, fetching articles...');
      final articles = await aggregator.fetchArticles(limit: 50);
      debugPrint('[ArticlesNotifier] Fetched ${articles.length} articles from aggregator');
      debugPrint('[ArticlesNotifier] Deleted IDs: ${articleState.deletedIds.length}');
      await cacheRepo.cacheArticles(articles);
      final filtered = articles
          .where((a) => !articleState.deletedIds.contains(a.id))
          .toList();
      debugPrint('[ArticlesNotifier] Returning ${filtered.length} articles after filtering');
      return filtered;
    } catch (e, stack) {
      debugPrint('[ArticlesNotifier] ERROR fetching articles: $e');
      debugPrint('[ArticlesNotifier] Stack: $stack');
      final cached = cacheRepo.getAll();
      if (cached.isNotEmpty) {
        debugPrint('[ArticlesNotifier] Falling back to ${cached.length} cached articles');
        return cached
            .where((a) => !articleState.deletedIds.contains(a.id))
            .toList();
      }
      rethrow;
    }
  }

  Future<void> refresh() async {
    debugPrint('[ArticlesNotifier] refresh() called');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
    debugPrint('[ArticlesNotifier] refresh() done, state: ${state.hasValue ? "${state.value!.length} articles" : state.hasError ? "error: ${state.error}" : "loading"}');
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
