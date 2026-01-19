import '../models/article.dart';
import 'news_sources/i_news_source.dart';

/// Aggregates articles from multiple news sources and handles deduplication
class NewsAggregatorService {
  final List<INewsSource> sources;
  final DeduplicationStrategy deduplicationStrategy;

  NewsAggregatorService({
    required this.sources,
    this.deduplicationStrategy = DeduplicationStrategy.url,
  });

  /// Fetch articles from all sources and deduplicate
  Future<List<Article>> fetchArticles({
    String? category,
    int limit = 20,
    int offset = 0,
  }) async {
    final allArticles = <Article>[];

    // Fetch from all sources in parallel
    final results = await Future.wait(
      sources.map((source) async {
        try {
          return await source.fetchArticles(
            category: category,
            limit: limit,
          );
        } catch (e) {
          print('Error fetching from ${source.sourceName}: $e');
          return <Article>[];
        }
      }),
    );

    // Flatten results
    for (final articles in results) {
      allArticles.addAll(articles);
    }

    // Deduplicate
    final deduplicated = _deduplicate(allArticles);

    // Sort by date (newest first)
    deduplicated.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    // Apply pagination
    final start = offset;
    final end = (offset + limit).clamp(0, deduplicated.length);

    return deduplicated.sublist(start, end);
  }

  /// Search articles across all sources
  Future<List<Article>> searchArticles({
    required String query,
    int limit = 20,
    int offset = 0,
  }) async {
    final allArticles = <Article>[];

    // Search all sources in parallel
    final results = await Future.wait(
      sources.map((source) async {
        try {
          return await source.searchArticles(
            query: query,
            limit: limit,
          );
        } catch (e) {
          print('Error searching ${source.sourceName}: $e');
          return <Article>[];
        }
      }),
    );

    // Flatten results
    for (final articles in results) {
      allArticles.addAll(articles);
    }

    // Deduplicate
    final deduplicated = _deduplicate(allArticles);

    // Sort by date (newest first)
    deduplicated.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    // Apply pagination
    final start = offset;
    final end = (offset + limit).clamp(0, deduplicated.length);

    return deduplicated.sublist(start, end);
  }

  /// Get all available categories from all sources
  Future<List<String>> getCategories() async {
    final allCategories = <String>{};

    for (final source in sources) {
      try {
        final categories = await source.getCategories();
        allCategories.addAll(categories);
      } catch (e) {
        print('Error getting categories from ${source.sourceName}: $e');
      }
    }

    return allCategories.toList()..sort();
  }

  /// Check which sources are currently available
  Future<Map<String, bool>> checkSourcesHealth() async {
    final health = <String, bool>{};

    await Future.wait(
      sources.map((source) async {
        try {
          health[source.sourceName] = await source.isAvailable();
        } catch (e) {
          health[source.sourceName] = false;
        }
      }),
    );

    return health;
  }

  /// Get most repeated articles (reported by multiple sources)
  /// 
  /// [articles] - List of articles to filter
  /// [minSources] - Minimum number of sources required (default: 2)
  /// 
  /// Returns articles sorted by source count (highest first)
  List<Article> getMostRepeated(List<Article> articles, {int minSources = 2}) {
    return articles
        .where((article) => article.sourceCount >= minSources)
        .toList()
      ..sort((a, b) => b.sourceCount.compareTo(a.sourceCount));
  }

  /// Get unique articles (reported by only one source)
  /// 
  /// Returns articles that appear in only one source
  List<Article> getUniqueArticles(List<Article> articles) {
    return articles.where((article) => article.sourceCount == 1).toList();
  }

  /// Get articles by source count range
  /// 
  /// [articles] - List of articles to filter
  /// [minSources] - Minimum source count (inclusive)
  /// [maxSources] - Maximum source count (inclusive, optional)
  /// 
  /// Returns filtered articles
  List<Article> getArticlesBySourceCount(
    List<Article> articles, {
    int minSources = 1,
    int? maxSources,
  }) {
    return articles.where((article) {
      if (article.sourceCount < minSources) return false;
      if (maxSources != null && article.sourceCount > maxSources) return false;
      return true;
    }).toList();
  }

  /// Get articles from a specific source
  /// 
  /// [articles] - List of articles to filter
  /// [sourceName] - Name of the source to filter by
  /// 
  /// Returns articles that include the specified source
  List<Article> getArticlesFromSource(
    List<Article> articles,
    String sourceName,
  ) {
    return articles
        .where((article) => article.sourceNames.contains(sourceName))
        .toList();
  }

  /// Deduplicate articles based on the selected strategy
  List<Article> _deduplicate(List<Article> articles) {
    switch (deduplicationStrategy) {
      case DeduplicationStrategy.url:
        return _deduplicateByUrl(articles);
      case DeduplicationStrategy.title:
        return _deduplicateByTitle(articles);
      case DeduplicationStrategy.titleSimilarity:
        return _deduplicateByTitleSimilarity(articles);
      case DeduplicationStrategy.combined:
        return _deduplicateCombined(articles);
    }
  }

  /// Remove exact URL duplicates and track source counts
  List<Article> _deduplicateByUrl(List<Article> articles) {
    final map = <String, Article>{};

    for (final article in articles) {
      final normalizedUrl = _normalizeUrl(article.url);
      
      if (map.containsKey(normalizedUrl)) {
        // Merge with existing article
        final existing = map[normalizedUrl]!;
        final mergedSourceNames = <String>{
          ...existing.sourceNames,
          ...article.sourceNames,
        }.toList();
        
        map[normalizedUrl] = existing.copyWith(
          sourceCount: mergedSourceNames.length,
          sourceNames: mergedSourceNames,
        );
      } else {
        map[normalizedUrl] = article;
      }
    }

    return map.values.toList();
  }

  /// Remove exact title duplicates (case-insensitive) and track source counts
  List<Article> _deduplicateByTitle(List<Article> articles) {
    final map = <String, Article>{};

    for (final article in articles) {
      final normalizedTitle = article.title.toLowerCase().trim();
      
      if (map.containsKey(normalizedTitle)) {
        // Merge with existing article
        final existing = map[normalizedTitle]!;
        final mergedSourceNames = <String>{
          ...existing.sourceNames,
          ...article.sourceNames,
        }.toList();
        
        map[normalizedTitle] = existing.copyWith(
          sourceCount: mergedSourceNames.length,
          sourceNames: mergedSourceNames,
        );
      } else {
        map[normalizedTitle] = article;
      }
    }

    return map.values.toList();
  }

  /// Remove articles with similar titles and track source counts
  List<Article> _deduplicateByTitleSimilarity(List<Article> articles) {
    final deduplicated = <Article>[];

    for (final article in articles) {
      Article? matchingArticle;
      int matchIndex = -1;

      for (var i = 0; i < deduplicated.length; i++) {
        final existing = deduplicated[i];
        final similarity = _calculateTitleSimilarity(
          article.title,
          existing.title,
        );

        // Consider articles duplicates if similarity > 85%
        if (similarity > 0.85) {
          matchingArticle = existing;
          matchIndex = i;
          break;
        }
      }

      if (matchingArticle != null) {
        // Merge with existing article
        final mergedSourceNames = <String>{
          ...matchingArticle.sourceNames,
          ...article.sourceNames,
        }.toList();
        
        deduplicated[matchIndex] = matchingArticle.copyWith(
          sourceCount: mergedSourceNames.length,
          sourceNames: mergedSourceNames,
        );
      } else {
        deduplicated.add(article);
      }
    }

    return deduplicated;
  }

  /// Combined strategy: URL first, then title similarity, tracking sources
  List<Article> _deduplicateCombined(List<Article> articles) {
    // First pass: remove exact URL duplicates and merge sources
    final urlDeduplicated = _deduplicateByUrl(articles);

    // Second pass: remove similar titles and merge sources
    return _deduplicateByTitleSimilarity(urlDeduplicated);
  }

  /// Normalize URL for comparison (remove query params, fragments, etc.)
  String _normalizeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.host}${uri.path}'.toLowerCase();
    } catch (e) {
      return url.toLowerCase();
    }
  }

  /// Calculate similarity between two titles (0.0 to 1.0)
  double _calculateTitleSimilarity(String title1, String title2) {
    final s1 = title1.toLowerCase().trim();
    final s2 = title2.toLowerCase().trim();

    if (s1 == s2) return 1.0;

    final distance = _levenshteinDistance(s1, s2);
    final maxLength = s1.length > s2.length ? s1.length : s2.length;

    if (maxLength == 0) return 1.0;

    return 1.0 - (distance / maxLength);
  }

  /// Calculate Levenshtein distance between two strings
  int _levenshteinDistance(String s1, String s2) {
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    final matrix = List.generate(
      s1.length + 1,
      (i) => List.filled(s2.length + 1, 0),
    );

    for (var i = 0; i <= s1.length; i++) {
      matrix[i][0] = i;
    }

    for (var j = 0; j <= s2.length; j++) {
      matrix[0][j] = j;
    }

    for (var i = 1; i <= s1.length; i++) {
      for (var j = 1; j <= s2.length; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;

        matrix[i][j] = [
          matrix[i - 1][j] + 1, // deletion
          matrix[i][j - 1] + 1, // insertion
          matrix[i - 1][j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    return matrix[s1.length][s2.length];
  }
}

/// Strategies for deduplicating articles
enum DeduplicationStrategy {
  /// Remove exact URL duplicates only
  url,

  /// Remove exact title duplicates only (case-insensitive)
  title,

  /// Remove articles with similar titles using fuzzy matching
  titleSimilarity,

  /// Combined: URL + title similarity (recommended)
  combined,
}
