import 'package:hive/hive.dart';
import '../models/feed_config.dart';

/// Manages RSS feed configurations in Hive storage
class FeedConfigRepository {
  static const String _boxName = 'feed_configs';
  late Box<FeedConfig> _box;

  Future<void> init() async {
    _box = await Hive.openBox<FeedConfig>(_boxName);
    if (_box.isEmpty) {
      await _seedDefaults();
    }
  }

  Future<void> _seedDefaults() async {
    for (final feed in FeedConfig.defaultFeeds) {
      await _box.put(feed.url, feed);
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

  Future<void> updateFeed(String oldUrl, String newUrl, String newName) async {
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
