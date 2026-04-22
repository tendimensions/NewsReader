import 'package:hive/hive.dart';
import '../models/feed_config.dart';

/// Manages RSS feed configurations in Hive storage
class FeedConfigRepository {
  static const String _boxName = 'feed_configs';
  late Box<FeedConfig> _box;

  Future<void> init() async {
    _box = await Hive.openBox<FeedConfig>(_boxName);
    // Insert any built-in feed whose URL is not already in the box.
    // Runs on every init so newly added built-ins appear for existing users.
    // Feeds the user deleted stay gone; brand-new built-ins (new URL key) are
    // added because their key was never present before.
    for (final feed in FeedConfig.defaultFeeds) {
      if (!_box.containsKey(feed.url)) {
        await _box.put(feed.url, feed);
      }
    }
  }

  List<FeedConfig> getAll() => _box.values.toList();

  List<FeedConfig> getEnabled() =>
      _box.values.where((f) => f.enabled).toList();

  Future<void> addFeed(FeedConfig feed) async {
    await _box.put(feed.url, feed);
  }

  Future<void> removeFeed(String url) async {
    await _box.delete(url);
  }

  Future<void> updateFeed(
      String oldUrl, String newUrl, String newName, int articleLimit) async {
    final feed = _box.get(oldUrl);
    if (feed == null) return;
    final enabled = feed.enabled;
    final isBuiltIn = feed.isBuiltIn;
    // If the URL changed, remove the old entry and add a new one
    if (oldUrl != newUrl) {
      await _box.delete(oldUrl);
    }
    await _box.put(
      newUrl,
      FeedConfig(
        url: newUrl,
        name: newName,
        enabled: enabled,
        isBuiltIn: isBuiltIn,
        articleLimit: articleLimit,
      ),
    );
  }

  Future<void> toggleFeed(String url, bool enabled) async {
    final feed = _box.get(url);
    if (feed != null) {
      feed.enabled = enabled;
      await feed.save();
    }
  }

  Future<void> resetToDefaults() async {
    // Remove custom feeds
    final customUrls = _box.values
        .where((f) => !f.isBuiltIn)
        .map((f) => f.url)
        .toList();
    for (final url in customUrls) {
      await _box.delete(url);
    }
    // Re-enable all built-in feeds
    for (final feed in _box.values) {
      feed.enabled = true;
      await feed.save();
    }
  }
}
