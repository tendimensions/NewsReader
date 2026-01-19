import 'package:http/http.dart' as http;
import 'package:webfeed/webfeed.dart';
import '../../models/article.dart';
import 'i_news_source.dart';

/// RSS Feed implementation
/// Supports both RSS 2.0 and Atom feeds
class RssNewsSource implements INewsSource {
  final List<String> feedUrls;
  final String displayName;

  RssNewsSource({
    required this.feedUrls,
    this.displayName = 'RSS Feed',
  });

  @override
  String get sourceName => displayName;

  @override
  Future<List<Article>> fetchArticles({
    String? category,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final allArticles = <Article>[];

      // Fetch from all configured RSS feeds
      for (final feedUrl in feedUrls) {
        try {
          final articles = await _fetchFromFeed(feedUrl);
          allArticles.addAll(articles);
        } catch (e) {
          // Continue with other feeds if one fails
          print('Failed to fetch from $feedUrl: $e');
        }
      }

      // Sort by date (newest first)
      allArticles.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

      // Apply pagination
      final start = offset;
      final end = (offset + limit).clamp(0, allArticles.length);

      return allArticles.sublist(start, end);
    } catch (e) {
      throw Exception('RSS feed error: $e');
    }
  }

  @override
  Future<List<Article>> searchArticles({
    required String query,
    int limit = 20,
    int offset = 0,
  }) async {
    // Fetch all articles and filter by query
    final articles = await fetchArticles(limit: 1000);
    final lowerQuery = query.toLowerCase();

    final filtered = articles.where((article) {
      return article.title.toLowerCase().contains(lowerQuery) ||
          (article.description?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();

    // Apply pagination
    final start = offset;
    final end = (offset + limit).clamp(0, filtered.length);

    return filtered.sublist(start, end);
  }

  @override
  Future<List<String>> getCategories() async {
    // RSS feeds typically don't have standard categories
    return [];
  }

  @override
  Future<bool> isAvailable() async {
    if (feedUrls.isEmpty) return false;

    try {
      // Check if at least one feed is accessible
      final response = await http.get(Uri.parse(feedUrls.first)).timeout(
            const Duration(seconds: 5),
          );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Fetch and parse articles from a single RSS feed
  Future<List<Article>> _fetchFromFeed(String feedUrl) async {
    final response = await http.get(Uri.parse(feedUrl));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch RSS feed: ${response.statusCode}');
    }

    final contentType = response.headers['content-type'] ?? '';

    // Try parsing as RSS first
    try {
      final rssFeed = RssFeed.parse(response.body);
      return _parseRssFeed(rssFeed, feedUrl);
    } catch (e) {
      // If RSS parsing fails, try Atom
      try {
        final atomFeed = AtomFeed.parse(response.body);
        return _parseAtomFeed(atomFeed, feedUrl);
      } catch (e) {
        throw Exception('Failed to parse feed as RSS or Atom: $e');
      }
    }
  }

  /// Parse RSS feed to Article models
  List<Article> _parseRssFeed(RssFeed feed, String feedUrl) {
    final articles = <Article>[];
    final feedTitle = feed.title ?? 'RSS Feed';

    for (final item in feed.items ?? []) {
      try {
        final url = item.link;
        final title = item.title;

        if (url == null || title == null) continue;

        final id = Uri.parse(url).host + url.hashCode.toString();
        final publishedAt = item.pubDate ?? DateTime.now();

        articles.add(Article(
          id: id,
          title: title,
          description: item.description,
          content: item.content?.value ?? item.description,
          url: url,
          imageUrl: _extractImageUrl(item),
          publishedAt: publishedAt,
          sourceName: feedTitle,
          author: item.author ?? item.dc?.creator,
          categories: item.categories?.map((c) => c.value ?? '').toList() ?? [],
        ));
      } catch (e) {
        // Skip malformed items
        continue;
      }
    }

    return articles;
  }

  /// Parse Atom feed to Article models
  List<Article> _parseAtomFeed(AtomFeed feed, String feedUrl) {
    final articles = <Article>[];
    final feedTitle = feed.title ?? 'Atom Feed';

    for (final entry in feed.items ?? []) {
      try {
        final url = entry.links?.firstOrNull?.href;
        final title = entry.title;

        if (url == null || title == null) continue;

        final id = Uri.parse(url).host + url.hashCode.toString();
        final publishedAt = entry.published ?? entry.updated ?? DateTime.now();

        articles.add(Article(
          id: id,
          title: title,
          description: entry.summary,
          content: entry.content ?? entry.summary,
          url: url,
          imageUrl: _extractAtomImageUrl(entry),
          publishedAt: publishedAt,
          sourceName: feedTitle,
          author: entry.authors?.firstOrNull?.name,
          categories: entry.categories?.map((c) => c.term ?? '').toList() ?? [],
        ));
      } catch (e) {
        // Skip malformed items
        continue;
      }
    }

    return articles;
  }

  /// Extract image URL from RSS item
  String? _extractImageUrl(RssItem item) {
    // Try media:content first
    if (item.media?.contents?.isNotEmpty ?? false) {
      return item.media!.contents!.first.url;
    }

    // Try media:thumbnail
    if (item.media?.thumbnails?.isNotEmpty ?? false) {
      return item.media!.thumbnails!.first.url;
    }

    // Try enclosure
    if (item.enclosure?.url != null) {
      final url = item.enclosure!.url!;
      if (url.contains(RegExp(r'\.(jpg|jpeg|png|gif|webp)', caseSensitive: false))) {
        return url;
      }
    }

    return null;
  }

  /// Extract image URL from Atom entry
  String? _extractAtomImageUrl(AtomItem entry) {
    // Atom feeds don't have a standard image field
    // Could try to parse from content/summary HTML if needed
    return null;
  }
}
