import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_settings.dart';
import '../models/feed_config.dart';
import '../providers/theme_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/repositories_provider.dart';
import '../providers/vault_provider.dart';
import '../services/news_sources/rss_news_source.dart';
import 'feed_discovery_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final Map<String, _FeedTestResult> _feedTestResults = {};

  /// Null while the keystore read is in flight. The token itself is never held
  /// here - only whether one exists.
  bool? _tokenPresent;

  @override
  void initState() {
    super.initState();
    _refreshTokenPresence();
  }

  Future<void> _testFeed(FeedConfig feed) async {
    setState(() {
      _feedTestResults[feed.url] = _FeedTestResult.loading();
    });

    try {
      final source = RssNewsSource(
        displayName: feed.name,
        feedUrls: [feed.url],
      );
      final articles = await source.fetchArticles(limit: 5);
      if (mounted) {
        setState(() {
          _feedTestResults[feed.url] =
              _FeedTestResult.success(articles.length);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _feedTestResults[feed.url] = _FeedTestResult.error('$e');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeNotifier = ref.read(themeProvider.notifier);
    final feeds = ref.watch(feedConfigsProvider);
    final feedsNotifier = ref.read(feedConfigsProvider.notifier);
    final currentThemePref = themeNotifier.currentPreference;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Theme section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Appearance',
                style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary)),
          ),
          RadioGroup<ThemePreference>(
            groupValue: currentThemePref,
            onChanged: (v) { if (v != null) themeNotifier.setTheme(v); },
            child: Column(
              children: [
                RadioListTile<ThemePreference>(
                  title: const Text('System default'),
                  subtitle: const Text('Match device setting'),
                  value: ThemePreference.system,
                ),
                RadioListTile<ThemePreference>(
                  title: const Text('Light'),
                  value: ThemePreference.light,
                ),
                RadioListTile<ThemePreference>(
                  title: const Text('Dark'),
                  value: ThemePreference.dark,
                ),
              ],
            ),
          ),

          const Divider(),

          // Vault sync section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Vault Sync',
                style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary)),
          ),
          ..._buildVaultSection(theme),

          const Divider(),

          // Feeds section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text('News Feeds',
                    style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary)),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.travel_explore, size: 18),
                  label: const Text('Discover'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FeedDiscoveryScreen(),
                    ),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Feed'),
                  onPressed: () => _showAddFeedDialog(context, feedsNotifier),
                ),
              ],
            ),
          ),

          // All feeds in one unified list
          ...feeds.map(
            (feed) => _buildFeedTile(feed, feedsNotifier, theme),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  List<Widget> _buildVaultSection(ThemeData theme) {
    final settingsRepo = ref.watch(settingsRepositoryProvider);
    final settings = settingsRepo.settings;
    final sync = ref.watch(vaultSyncProvider);

    return [
      SwitchListTile(
        title: const Text('Save bookmarks to vault'),
        subtitle: const Text(
            'Bookmarked articles are also filed in mcp-vault, where they are '
            'summarised and tagged. Removing a bookmark leaves the vault copy.'),
        value: settings.vaultSyncEnabled,
        onChanged: (enabled) async {
          await settingsRepo.setVaultSyncEnabled(enabled);
          if (!mounted) return;
          setState(() {});
          if (enabled) ref.read(vaultSyncProvider.notifier).drain();
        },
      ),
      if (settings.vaultSyncEnabled) ...[
        ListTile(
          title: const Text('Bearer token'),
          subtitle: Text(_tokenPresent == null
              ? 'Checking…'
              : _tokenPresent!
                  ? 'Stored securely on this device'
                  : 'Not set — bookmarks cannot be sent'),
          trailing: const Icon(Icons.edit, size: 18),
          onTap: _showTokenDialog,
        ),
        ListTile(
          title: const Text('Server URL'),
          subtitle: Text(settings.vaultServerUrl),
          trailing: const Icon(Icons.edit, size: 18),
          onTap: () => _showServerUrlDialog(settingsRepo.settings.vaultServerUrl),
        ),
        ListTile(
          title: const Text('Pending'),
          subtitle: Text(sync.lastError != null
              ? 'Last error: ${sync.lastError}'
              : sync.pending == 0
                  ? 'Everything sent'
                  : '${sync.pending} waiting to send'),
          trailing: sync.isSyncing
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  onPressed: sync.pending == 0
                      ? null
                      : () => ref.read(vaultSyncProvider.notifier).drain(),
                  child: const Text('Sync now'),
                ),
        ),
      ],
    ];
  }

  Future<void> _showTokenDialog() async {
    final controller = TextEditingController();
    final store = ref.read(vaultTokenStoreProvider);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('mcp-vault bearer token'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Paste token',
            helperText: 'Stored in the device keystore, never in plain text.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await store.delete();
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Clear'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true && controller.text.trim().isNotEmpty) {
      await store.write(controller.text.trim());
    }
    await _refreshTokenPresence();
    if (mounted) ref.read(vaultSyncProvider.notifier).drain();
  }

  Future<void> _showServerUrlDialog(String current) async {
    final controller = TextEditingController(text: current);
    final settingsRepo = ref.read(settingsRepositoryProvider);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server URL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'https://…/mcp'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );

    if (ok == true) {
      await settingsRepo.setVaultServerUrl(controller.text);
      if (mounted) setState(() {});
    }
  }

  Future<void> _refreshTokenPresence() async {
    final token = await ref.read(vaultTokenStoreProvider).read();
    if (mounted) setState(() => _tokenPresent = token != null);
  }

  Widget _buildFeedTile(
    FeedConfig feed,
    FeedConfigNotifier feedsNotifier,
    ThemeData theme,
  ) {
    final testResult = _feedTestResults[feed.url];

    return ListTile(
      onTap: () {
        ref.read(feedFilterProvider.notifier).state = feed.name;
        Navigator.of(context).pop();
      },
      title: Text(feed.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(feed.url,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (testResult != null) ...[
            const SizedBox(height: 4),
            if (testResult.isLoading)
              const SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (testResult.isSuccess)
              Text(
                '${testResult.articleCount} articles found',
                style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.green),
              )
            else
              Text(
                'Error: ${testResult.errorMessage}',
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.download, size: 20),
            tooltip: 'Test feed',
            onPressed: () => _testFeed(feed),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: 'Edit feed',
            onPressed: () =>
                _showEditFeedDialog(context, feed, feedsNotifier),
          ),
          Switch(
            value: feed.enabled,
            onChanged: (v) => feedsNotifier.toggleFeed(feed.url, v),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove feed',
            onPressed: () => feedsNotifier.removeFeed(feed.url),
          ),
        ],
      ),
    );
  }

  void _showAddFeedDialog(
      BuildContext context, FeedConfigNotifier feedsNotifier) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final limitController = TextEditingController(text: '5');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add RSS Feed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Feed name',
                hintText: 'e.g. My Tech Blog',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'RSS feed URL',
                hintText: 'https://example.com/feed.xml',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: limitController,
              decoration: const InputDecoration(
                labelText: 'Articles to fetch',
                helperText: 'Enter a number from 1 to 50',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              final url = urlController.text.trim();
              final limit =
                  (int.tryParse(limitController.text.trim()) ?? 5).clamp(1, 50);
              if (name.isNotEmpty && url.isNotEmpty) {
                feedsNotifier.addFeed(url, name, articleLimit: limit);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditFeedDialog(
      BuildContext context, FeedConfig feed, FeedConfigNotifier feedsNotifier) {
    final nameController = TextEditingController(text: feed.name);
    final urlController = TextEditingController(text: feed.url);
    final limitController =
        TextEditingController(text: feed.articleLimit.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Feed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Feed name',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'RSS feed URL',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: limitController,
              decoration: const InputDecoration(
                labelText: 'Articles to fetch',
                helperText: 'Enter a number from 1 to 50',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              final url = urlController.text.trim();
              final limit =
                  (int.tryParse(limitController.text.trim()) ?? 5).clamp(1, 50);
              if (name.isNotEmpty && url.isNotEmpty) {
                feedsNotifier.updateFeed(feed.url, url, name, limit);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _FeedTestResult {
  final bool isLoading;
  final bool isSuccess;
  final int articleCount;
  final String? errorMessage;

  _FeedTestResult._({
    this.isLoading = false,
    this.isSuccess = false,
    this.articleCount = 0,
    this.errorMessage,
  });

  factory _FeedTestResult.loading() =>
      _FeedTestResult._(isLoading: true);

  factory _FeedTestResult.success(int count) =>
      _FeedTestResult._(isSuccess: true, articleCount: count);

  factory _FeedTestResult.error(String message) =>
      _FeedTestResult._(errorMessage: message);
}
