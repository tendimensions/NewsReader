import '../models/article.dart';

/// Common interface for all news sources
/// Implement this interface to add a new news source to the aggregator
abstract class INewsSource {
  /// Unique identifier for this news source
  String get sourceName;

  /// Fetch latest articles from this source
  /// 
  /// Parameters:
  /// - [category]: Optional category filter (e.g., 'technology', 'sports')
  /// - [limit]: Maximum number of articles to return
  /// - [offset]: Number of articles to skip (for pagination)
  /// 
  /// Returns a list of articles or throws an exception on error
  Future<List<Article>> fetchArticles({
    String? category,
    int limit = 20,
    int offset = 0,
  });

  /// Search for articles matching a query
  /// 
  /// Parameters:
  /// - [query]: Search term
  /// - [limit]: Maximum number of articles to return
  /// - [offset]: Number of articles to skip (for pagination)
  /// 
  /// Returns a list of articles matching the query
  Future<List<Article>> searchArticles({
    required String query,
    int limit = 20,
    int offset = 0,
  });

  /// Get available categories/topics from this source
  /// Returns empty list if categories are not supported
  Future<List<String>> getCategories();

  /// Check if this source is currently available/healthy
  /// Used for health checks and graceful fallback
  Future<bool> isAvailable();
}
