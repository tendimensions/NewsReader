import 'models/article.dart';
import 'services/news_aggregator_service.dart';
import 'services/news_sources/i_news_source.dart';
import 'services/news_sources/news_api_source.dart';
import 'services/news_sources/rss_news_source.dart';

/// Example usage of the news aggregator service
void main() async {
  // Configure your news sources
  final sources = <INewsSource>[
    // NewsAPI.org source (requires API key)
    NewsApiSource(
      apiKey: 'YOUR_NEWSAPI_KEY_HERE',
    ),

    // RSS feeds source
    RssNewsSource(
      displayName: 'Tech News',
      feedUrls: [
        'https://feeds.arstechnica.com/arstechnica/index',
        'https://www.theverge.com/rss/index.xml',
        'https://techcrunch.com/feed/',
      ],
    ),

    // You can add more RSS sources with different configurations
    RssNewsSource(
      displayName: 'General News',
      feedUrls: [
        'https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml',
        'https://feeds.bbci.co.uk/news/rss.xml',
      ],
    ),
  ];

  // Create the aggregator with deduplication strategy
  final aggregator = NewsAggregatorService(
    sources: sources,
    deduplicationStrategy: DeduplicationStrategy.combined,
  );

  print('Checking news sources health...');
  final health = await aggregator.checkSourcesHealth();
  health.forEach((source, isHealthy) {
    print('$source: ${isHealthy ? "✓" : "✗"}');
  });

  print('\nFetching latest articles...');
  try {
    final articles = await aggregator.fetchArticles(limit: 10);
    print('Found ${articles.length} articles (after deduplication)\n');

    for (final article in articles) {
      print('${article.title}');
      print('  Source: ${article.sourceName}');
      print('  Reported by ${article.sourceCount} source(s): ${article.sourceNames.join(", ")}');
      print('  URL: ${article.url}');
      print('  Published: ${article.publishedAt}');
      print('');
    }

    // Show most repeated articles
    print('\n=== MOST REPEATED ARTICLES (2+ sources) ===');
    final mostRepeated = aggregator.getMostRepeated(articles, minSources: 2);
    if (mostRepeated.isEmpty) {
      print('No articles found in multiple sources');
    } else {
      for (final article in mostRepeated) {
        print('${article.title}');
        print('  ${article.sourceCount} sources: ${article.sourceNames.join(", ")}');
        print('');
      }
    }

    // Show unique articles
    print('\n=== UNIQUE ARTICLES (1 source only) ===');
    final uniqueArticles = aggregator.getUniqueArticles(articles);
    print('Found ${uniqueArticles.length} unique articles');
    for (final article in uniqueArticles.take(3)) {
      print('${article.title}');
      print('  From: ${article.sourceName}');
      print('');
    }
  } catch (e) {
    print('Error fetching articles: $e');
  }

  print('\nSearching for "Flutter"...');
  try {
    final searchResults = await aggregator.searchArticles(
      query: 'Flutter',
      limit: 5,
    );
    print('Found ${searchResults.length} articles\n');

    for (final article in searchResults) {
      print('${article.title}');
      print('  Source: ${article.sourceName}');
      print('');
    }
  } catch (e) {
    print('Error searching articles: $e');
  }

  print('\nAvailable categories:');
  final categories = await aggregator.getCategories();
  print(categories.join(', '));
}
