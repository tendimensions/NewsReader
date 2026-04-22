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
        FeedConfig(
          url: 'https://www.technologyreview.com/feed/',
          name: 'MIT Technology Review',
          isBuiltIn: true,
        ),
        FeedConfig(
          url: 'https://spectrum.ieee.org/feeds/feed.rss',
          name: 'IEEE Spectrum',
          isBuiltIn: true,
        ),
        FeedConfig(
          url: 'https://www.engadget.com/rss.xml',
          name: 'Engadget',
          isBuiltIn: true,
        ),
        FeedConfig(
          url: 'https://9to5mac.com/feed/',
          name: '9to5Mac',
          isBuiltIn: true,
        ),
        FeedConfig(
          url: 'https://www.androidauthority.com/feed/',
          name: 'Android Authority',
          isBuiltIn: true,
        ),
        FeedConfig(
          url: 'https://www.tomshardware.com/feeds/all',
          name: "Tom's Hardware",
          isBuiltIn: true,
        ),
        FeedConfig(
          url: 'https://rss.slashdot.org/Slashdot/slashdotMain',
          name: 'Slashdot',
          isBuiltIn: true,
        ),
        FeedConfig(
          url: 'https://www.theregister.com/headlines.atom',
          name: 'The Register',
          isBuiltIn: true,
        ),
        FeedConfig(
          url: 'https://lobste.rs/rss',
          name: 'Lobsters',
          isBuiltIn: true,
        ),
        FeedConfig(
          url: 'https://www.cnet.com/rss/news/',
          name: 'CNET',
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
