import 'dart:developer' as developer;
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

  if (enabledConfigs.isEmpty) {
    return NewsAggregatorService(
      sources: [],
      deduplicationStrategy: DeduplicationStrategy.combined,
    );
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
      final articles = await aggregator.fetchArticles(limit: 50);
      developer.log('Fetched ${articles.length} articles from aggregator');
      await cacheRepo.cacheArticles(articles);
      return articles
          .where((a) => !articleState.deletedIds.contains(a.id))
          .toList();
    } catch (e) {
      developer.log('Error fetching articles: $e');
      final cached = cacheRepo.getAll();
      if (cached.isNotEmpty) {
        return cached
            .where((a) => !articleState.deletedIds.contains(a.id))
            .toList();
      }
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
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
