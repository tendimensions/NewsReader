import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/article.dart';
import 'i_news_source.dart';

/// NewsAPI.org implementation
/// API Docs: https://newsapi.org/docs
class NewsApiSource implements INewsSource {
  final String apiKey;
  final String baseUrl = 'https://newsapi.org/v2';
  
  NewsApiSource({required this.apiKey});

  @override
  String get sourceName => 'NewsAPI.org';

  @override
  Future<List<Article>> fetchArticles({
    String? category,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final endpoint = category != null ? 'top-headlines' : 'everything';
      final queryParams = {
        'apiKey': apiKey,
        'pageSize': limit.toString(),
        'page': ((offset ~/ limit) + 1).toString(),
        if (category != null) 'category': category,
        if (category == null) 'q': 'news', // Required for 'everything' endpoint
      };

      final uri = Uri.parse('$baseUrl/$endpoint').replace(
        queryParameters: queryParams,
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final articles = (data['articles'] as List)
            .map((articleJson) => _parseArticle(articleJson))
            .where((article) => article != null)
            .cast<Article>()
            .toList();
        return articles;
      } else {
        throw Exception(
          'Failed to fetch articles from NewsAPI: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('NewsAPI error: $e');
    }
  }

  @override
  Future<List<Article>> searchArticles({
    required String query,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final queryParams = {
        'apiKey': apiKey,
        'q': query,
        'pageSize': limit.toString(),
        'page': ((offset ~/ limit) + 1).toString(),
        'sortBy': 'publishedAt',
      };

      final uri = Uri.parse('$baseUrl/everything').replace(
        queryParameters: queryParams,
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final articles = (data['articles'] as List)
            .map((articleJson) => _parseArticle(articleJson))
            .where((article) => article != null)
            .cast<Article>()
            .toList();
        return articles;
      } else {
        throw Exception(
          'Failed to search articles in NewsAPI: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('NewsAPI search error: $e');
    }
  }

  @override
  Future<List<String>> getCategories() async {
    // NewsAPI supports these categories for top-headlines
    return [
      'business',
      'entertainment',
      'general',
      'health',
      'science',
      'sports',
      'technology',
    ];
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final uri = Uri.parse('$baseUrl/top-headlines').replace(
        queryParameters: {
          'apiKey': apiKey,
          'pageSize': '1',
          'category': 'general',
        },
      );

      final response = await http.get(uri).timeout(
            const Duration(seconds: 5),
          );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Parse NewsAPI article JSON to Article model
  Article? _parseArticle(Map<String, dynamic> json) {
    try {
      final url = json['url'] as String?;
      final title = json['title'] as String?;
      final publishedAt = json['publishedAt'] as String?;

      // Skip articles with missing required fields
      if (url == null || title == null || publishedAt == null) {
        return null;
      }

      // Generate a unique ID from URL
      final id = Uri.parse(url).host + url.hashCode.toString();

      return Article(
        id: id,
        title: title,
        description: json['description'] as String?,
        content: json['content'] as String?,
        url: url,
        imageUrl: json['urlToImage'] as String?,
        publishedAt: DateTime.parse(publishedAt),
        sourceName: json['source']?['name'] as String? ?? sourceName,
        author: json['author'] as String?,
        categories: [],
      );
    } catch (e) {
      // Skip malformed articles
      return null;
    }
  }
}
