import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:webfeed/webfeed.dart';
import '../../models/article.dart';
import '../../utils/html_utils.dart';
import 'i_news_source.dart';

/// RSS Feed implementation
/// Supports both RSS 2.0 and Atom feeds
class RssNewsSource implements INewsSource {
  final List<String> feedUrls;
  final String displayName;

  /// Optional per-feed display name overrides (url → name).
  /// When provided, the feed's own title is ignored in favour of this name,
  /// so article.sourceName will match the user-visible FeedConfig.name.
  final Map<String, String>? feedNames;

  /// Optional per-feed article limits, parallel to [feedUrls].
  /// When provided, at most feedLimits[i] articles are taken from feedUrls[i].
  final List<int>? feedLimits;

  RssNewsSource({
    required this.feedUrls,
    this.displayName = 'RSS Feed',
    this.feedNames,
    this.feedLimits,
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

      debugPrint('[RssNewsSource] Fetching from ${feedUrls.length} feeds in parallel...');
      // Fetch all feeds in parallel; errors are caught per-feed
      final results = await Future.wait(
        List.generate(feedUrls.length, (i) async {
          final feedUrl = feedUrls[i];
          final perFeedLimit =
              (feedLimits != null && i < feedLimits!.length) ? feedLimits![i] : limit;
          final sourceName = feedNames?[feedUrl];
          try {
            debugPrint('[RssNewsSource] Fetching: $feedUrl');
            final articles =
                await _fetchFromFeed(feedUrl, sourceName: sourceName);
            debugPrint('[RssNewsSource] Got ${articles.length} articles from $feedUrl');
            return articles.take(perFeedLimit).toList();
          } catch (e) {
            debugPrint('[RssNewsSource] FAILED $feedUrl: $e');
            log('Failed to fetch from $feedUrl: $e');
            return <Article>[];
          }
        }),
      );
      for (final batch in results) {
        allArticles.addAll(batch);
      }
      debugPrint('[RssNewsSource] Total articles before pagination: ${allArticles.length}');

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
  Future<List<Article>> _fetchFromFeed(String feedUrl,
      {String? sourceName}) async {
    final response = await http
        .get(Uri.parse(feedUrl))
        .timeout(const Duration(seconds: 15));
    debugPrint('[RssNewsSource] HTTP ${response.statusCode} from $feedUrl (${response.body.length} bytes)');

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch RSS feed: ${response.statusCode}');
    }

    // Decode as UTF-8 explicitly so curly quotes and other multi-byte
    // characters aren't mangled by the default Latin-1 fallback.
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);

    // Try parsing as RSS first
    try {
      final rssFeed = RssFeed.parse(body);
      final articles = _parseRssFeed(rssFeed, feedUrl, sourceName: sourceName);
      debugPrint('[RssNewsSource] Parsed ${articles.length} RSS items from $feedUrl');
      return articles;
    } catch (e) {
      debugPrint('[RssNewsSource] RSS parse failed for $feedUrl: $e, trying Atom...');
      // If RSS parsing fails, try Atom
      try {
        final atomFeed = AtomFeed.parse(body);
        final articles =
            _parseAtomFeed(atomFeed, feedUrl, sourceName: sourceName);
        debugPrint('[RssNewsSource] Parsed ${articles.length} Atom items from $feedUrl');
        return articles;
      } catch (e2) {
        throw Exception('Failed to parse feed as RSS or Atom: $e2');
      }
    }
  }

  /// Parse RSS feed to Article models
  List<Article> _parseRssFeed(RssFeed feed, String feedUrl,
      {String? sourceName}) {
    final articles = <Article>[];
    final feedTitle = sourceName ?? feed.title ?? 'RSS Feed';
    debugPrint('[RssNewsSource] _parseRssFeed: feed.items count = ${feed.items?.length ?? "null"}');

    for (final item in feed.items ?? []) {
      try {
        final url = item.link;
        final title = item.title;

        if (url == null || title == null) {
          debugPrint('[RssNewsSource] Skipping item: url=$url, title=$title');
          continue;
        }

        final id = Uri.parse(url).host + url.hashCode.toString();
        final publishedAt = item.pubDate ?? DateTime.now();

        final rawDescription = item.description;
        articles.add(Article(
          id: id,
          title: decodeHtmlEntities(title),
          description: rawDescription != null ? stripHtml(rawDescription) : null,
          content: item.content?.value ?? item.description,
          url: url,
          imageUrl: _extractImageUrl(item),
          publishedAt: publishedAt,
          sourceName: feedTitle,
          author: item.author ?? item.dc?.creator,
          categories: item.categories?.map((c) => c.value ?? '').toList().cast<String>() ?? <String>[],
        ));
      } catch (e) {
        debugPrint('[RssNewsSource] Error parsing item: $e');
        continue;
      }
    }

    return articles;
  }

  /// Parse Atom feed to Article models
  List<Article> _parseAtomFeed(AtomFeed feed, String feedUrl,
      {String? sourceName}) {
    final articles = <Article>[];
    final feedTitle = sourceName ?? feed.title ?? 'Atom Feed';
    debugPrint('[RssNewsSource] _parseAtomFeed: feed.items count = ${feed.items?.length ?? "null"}');

    for (final entry in feed.items ?? []) {
      try {
        final url = entry.links?.firstOrNull?.href;
        final title = entry.title;

        if (url == null || title == null) {
          debugPrint('[RssNewsSource] Skipping Atom entry: url=$url, title=$title');
          continue;
        }

        final id = Uri.parse(url).host + url.hashCode.toString();
        final publishedAt = entry.published ?? entry.updated ?? DateTime.now();

        final rawSummary = entry.summary;
        articles.add(Article(
          id: id,
          title: decodeHtmlEntities(title),
          description: rawSummary != null ? stripHtml(rawSummary) : null,
          content: entry.content ?? entry.summary,
          url: url,
          imageUrl: _extractAtomImageUrl(entry),
          publishedAt: publishedAt,
          sourceName: feedTitle,
          author: entry.authors?.firstOrNull?.name,
          categories: entry.categories?.map((c) => c.term ?? '').toList().cast<String>() ?? <String>[],
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
