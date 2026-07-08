import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/feed_provider.dart';
import '../services/feed_discovery_service.dart';

/// Discover the RSS/Atom feed(s) for a site by pasting any site-shaped URL.
class FeedDiscoveryScreen extends ConsumerStatefulWidget {
  const FeedDiscoveryScreen({super.key});

  @override
  ConsumerState<FeedDiscoveryScreen> createState() =>
      _FeedDiscoveryScreenState();
}

class _FeedDiscoveryScreenState extends ConsumerState<FeedDiscoveryScreen> {
  final _urlController = TextEditingController();
  final _service = FeedDiscoveryService();

  bool _isSearching = false;
  bool _hasSearched = false;
  String? _error;
  List<DiscoveredFeed> _results = const [];
  final Set<String> _addedUrls = {};

  @override
  void initState() {
    super.initState();
    _prefillFromClipboard();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// Pre-fill the field when the clipboard holds something URL-shaped, so the
  /// common "I just copied a site URL" flow needs no typing.
  Future<void> _prefillFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!mounted || text == null || text.isEmpty) return;
    if (_urlController.text.isNotEmpty) return;
    final looksUrl = text.contains('.') && !text.contains(RegExp(r'\s'));
    if (looksUrl) {
      _urlController.text = text;
      _urlController.selection =
          TextSelection(baseOffset: 0, extentOffset: text.length);
    }
  }

  Future<void> _discover() async {
    final input = _urlController.text.trim();
    if (input.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _error = null;
      _results = const [];
    });

    final existingUrls =
        ref.read(feedConfigsProvider).map((f) => f.url).toSet();

    try {
      final results =
          await _service.discover(input, existingUrls: existingUrls);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } on FeedDiscoveryException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong while searching.';
        _isSearching = false;
      });
    }
  }

  void _addFeed(DiscoveredFeed feed) {
    ref.read(feedConfigsProvider.notifier).addFeed(feed.url, feed.name);
    setState(() => _addedUrls.add(feed.url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added ${feed.name}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover Feeds')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _discover(),
                  decoration: InputDecoration(
                    labelText: 'Website or feed URL',
                    hintText: 'e.g. theverge.com',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: 'Find feeds',
                      onPressed: _isSearching ? null : _discover,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Paste a site you like and we\'ll look for its RSS feed.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);

    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildMessage(Icons.error_outline, _error!, theme.colorScheme.error);
    }

    if (!_hasSearched) {
      return const SizedBox.shrink();
    }

    if (_results.isEmpty) {
      return _buildMessage(
        Icons.search_off,
        "No feed found at that address.",
        theme.colorScheme.onSurfaceVariant,
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _buildResultTile(_results[i], theme),
    );
  }

  Widget _buildMessage(IconData icon, String text, Color color) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildResultTile(DiscoveredFeed feed, ThemeData theme) {
    final added = feed.alreadyAdded || _addedUrls.contains(feed.url);

    return ListTile(
      isThreeLine: feed.sampleTitles.isNotEmpty,
      title: Text(feed.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(feed.url, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (feed.sampleTitles.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              feed.sampleTitles.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
      trailing: added
          ? Chip(
              label: const Text('Added'),
              visualDensity: VisualDensity.compact,
            )
          : FilledButton(
              onPressed: () => _addFeed(feed),
              child: const Text('Add'),
            ),
    );
  }
}
