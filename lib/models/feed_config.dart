import 'package:hive/hive.dart';

part 'feed_config.g.dart';

/// Represents an RSS feed configuration
@HiveType(typeId: 1)
class FeedConfig extends HiveObject {
  @HiveField(0)
  final String url;

  @HiveField(1)
  final String name;

  @HiveField(2)
  bool enabled;

  @HiveField(3)
  final bool isBuiltIn;

  @HiveField(4)
  int articleLimit;

  FeedConfig({
    required this.url,
    required this.name,
    this.enabled = true,
    this.isBuiltIn = false,
    this.articleLimit = 5,
  });

  static List<FeedConfig> get defaultFeeds => [
        FeedConfig(
          url: 'https://feeds.arstechnica.com/arstechnica/index',
          name: 'Ars Technica',
          isBuiltIn: true,
        ),
        FeedConfig(
          url: 'https://www.theverge.com/rss/index.xml',
          name: 'The Verge',
          isBuiltIn: true,
        ),
        FeedConfig(
          url: 'https://techcrunch.com/feed/',
          name: 'TechCrunch',
          isBuiltIn: true,
        ),
        FeedConfig(
          url: 'https://hnrss.org/frontpage',
          name: 'Hacker News',
          isBuiltIn: true,
        ),
        FeedConfig(
          url: 'https://www.wired.com/feed/rss',
          name: 'Wired',
          isBuiltIn: true,
        ),
      ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FeedConfig && other.url == url;
  }

  @override
  int get hashCode => url.hashCode;
}
