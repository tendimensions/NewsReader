import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/article.dart';
import '../providers/feed_provider.dart';
import '../providers/bookmarks_provider.dart';
import '../providers/article_state_provider.dart';
import '../widgets/article_card.dart';
import 'article_screen.dart';
import 'settings_screen.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSearching = false;
  List<Article>? _searchResults;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = null;
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    try {
      final results =
          await ref.read(articlesProvider.notifier).search(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    }
  }

  void _openArticle(Article article) {
    ref.read(articleStateProvider.notifier).markRead(article.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArticleScreen(article: article),
      ),
    );
  }

  void _deleteArticle(Article article) {
    ref.read(articleStateProvider.notifier).deleteArticle(article.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed: ${article.title}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            ref.read(articleStateProvider.notifier).undeleteArticle(article.id);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final articlesAsync = ref.watch(articlesProvider);
    final bookmarkedIds =
        ref.watch(bookmarksProvider).map((a) => a.id).toSet();
    final bookmarksNotifier = ref.read(bookmarksProvider.notifier);
    final articleState = ref.watch(articleStateProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ten Dimensional'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Fetch articles',
            onPressed: () => ref.read(articlesProvider.notifier).refresh(),
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_outline),
            tooltip: 'Bookmarks',
            onPressed: () => _showBookmarks(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search articles...',
              leading: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.search),
              ),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchResults = null);
                    },
                  ),
              ],
              onSubmitted: _performSearch,
              onChanged: (value) {
                if (value.isEmpty) {
                  setState(() => _searchResults = null);
                }
              },
            ),
          ),

          // Content
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _searchResults != null
                    ? _buildArticleList(
                        _searchResults!, bookmarkedIds, bookmarksNotifier, articleState, theme)
                    : articlesAsync.when(
                        data: (articles) {
                          final visible = articles
                              .where((a) =>
                                  !articleState.deletedIds.contains(a.id))
                              .toList();
                          return RefreshIndicator(
                            onRefresh: () =>
                                ref.read(articlesProvider.notifier).refresh(),
                            child: _buildArticleList(
                                visible, bookmarkedIds, bookmarksNotifier,
                                articleState, theme,
                                scrollController: _scrollController),
                          );
                        },
                        loading: () => const Center(
                            child: CircularProgressIndicator()),
                        error: (err, _) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cloud_off,
                                    size: 48,
                                    color: theme.colorScheme.error),
                                const SizedBox(height: 16),
                                Text(
                                  'Could not load articles',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '$err',
                                  style: theme.textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: () => ref
                                      .read(articlesProvider.notifier)
                                      .refresh(),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Fetch Articles'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildArticleList(
    List<Article> articles,
    Set<String> bookmarkedIds,
    BookmarksNotifier bookmarksNotifier,
    ArticleStateData articleState,
    ThemeData theme, {
    ScrollController? scrollController,
  }) {
    if (articles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('No articles found', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Tap the refresh button to fetch articles',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(articlesProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Fetch Articles'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: articles.length,
      itemBuilder: (context, index) {
        final article = articles[index];
        final isRead = articleState.readIds.contains(article.id);
        return Dismissible(
          key: ValueKey(article.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: theme.colorScheme.errorContainer,
            child: Icon(Icons.delete_outline,
                color: theme.colorScheme.onErrorContainer),
          ),
          onDismissed: (_) => _deleteArticle(article),
          child: ArticleCard(
            article: article,
            isBookmarked: bookmarkedIds.contains(article.id),
            isRead: isRead,
            onTap: () => _openArticle(article),
            onBookmarkTap: () => bookmarksNotifier.toggle(article),
            onDelete: () => _deleteArticle(article),
          ),
        );
      },
    );
  }

  void _showBookmarks(BuildContext context) {
    final bookmarks = ref.read(bookmarksProvider);
    final bookmarksNotifier = ref.read(bookmarksProvider.notifier);
    final articleState = ref.read(articleStateProvider);
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text('Bookmarks',
                      style: theme.textTheme.titleLarge),
                  const Spacer(),
                  Text('${bookmarks.length} saved',
                      style: theme.textTheme.labelMedium),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: bookmarks.isEmpty
                  ? Center(
                      child: Text('No bookmarks yet',
                          style: theme.textTheme.bodyMedium),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: bookmarks.length,
                      itemBuilder: (context, index) {
                        final article = bookmarks[index];
                        final isRead =
                            articleState.readIds.contains(article.id);
                        return ArticleCard(
                          article: article,
                          isBookmarked: true,
                          isRead: isRead,
                          onTap: () {
                            Navigator.of(context).pop();
                            _openArticle(article);
                          },
                          onBookmarkTap: () =>
                              bookmarksNotifier.toggle(article),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
