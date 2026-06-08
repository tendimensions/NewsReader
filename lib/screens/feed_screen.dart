import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/article.dart';
import '../providers/feed_provider.dart';
import '../providers/bookmarks_provider.dart';
import '../providers/article_state_provider.dart';
import '../services/topic_classifier.dart';
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
  void initState() {
    super.initState();
    _scrollController.addListener(_dismissSnackBar);
  }

  void _dismissSnackBar() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_dismissSnackBar);
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
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
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

  void _bookmarkArticle(Article article, bool wasBookmarked) {
    ref.read(bookmarksProvider.notifier).toggle(article);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(wasBookmarked ? 'Bookmark removed' : 'Bookmarked'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => ref.read(bookmarksProvider.notifier).toggle(article),
        ),
      ),
    );
  }

  void _showGroupingSheet(BuildContext context) {
    final current = ref.read(articleGroupingProvider);
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text('Group & Sort', style: theme.textTheme.titleMedium),
                ],
              ),
            ),
            const Divider(height: 1),
            RadioGroup<ArticleGrouping>(
                  groupValue: current,
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(articleGroupingProvider.notifier).state = value;
                    }
                    Navigator.of(sheetContext).pop();
                  },
                  child: Column(
                    children: ArticleGrouping.values.map((mode) {
                      return ListTile(
                        leading: Radio<ArticleGrouping>(value: mode),
                        title: Text(_groupingLabel(mode)),
                        subtitle: Text(_groupingDescription(mode)),
                        onTap: () {
                          ref.read(articleGroupingProvider.notifier).state =
                              mode;
                          Navigator.of(sheetContext).pop();
                        },
                      );
                    }).toList(),
                  ),
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _groupingLabel(ArticleGrouping mode) => switch (mode) {
        ArticleGrouping.chronological => 'Chronological',
        ArticleGrouping.bySource => 'By Source',
        ArticleGrouping.byTopic => 'By Topic',
      };

  String _groupingDescription(ArticleGrouping mode) => switch (mode) {
        ArticleGrouping.chronological => 'Newest articles first',
        ArticleGrouping.bySource => 'Grouped by publication, alphabetically',
        ArticleGrouping.byTopic => 'Grouped by topic category',
      };

  @override
  Widget build(BuildContext context) {
    final articlesAsync = ref.watch(articlesProvider);
    final bookmarkedIds =
        ref.watch(bookmarksProvider).map((a) => a.id).toSet();
    final bookmarksNotifier = ref.read(bookmarksProvider.notifier);
    final articleState = ref.watch(articleStateProvider);
    final feedFilter = ref.watch(feedFilterProvider);
    final topicFilter = ref.watch(topicFilterProvider);
    final grouping = ref.watch(articleGroupingProvider);
    final theme = Theme.of(context);
    final isNonDefault = grouping != ArticleGrouping.chronological;

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
            icon: Icon(
              Icons.sort,
              color: isNonDefault ? theme.colorScheme.primary : null,
            ),
            tooltip: 'Group & sort',
            onPressed: () => _showGroupingSheet(context),
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

          // Active feed filter chip
          if (feedFilter != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  FilterChip(
                    label: Text(feedFilter),
                    selected: true,
                    onSelected: (_) =>
                        ref.read(feedFilterProvider.notifier).state = null,
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () =>
                        ref.read(feedFilterProvider.notifier).state = null,
                  ),
                ],
              ),
            ),

          // Active topic filter chip
          if (topicFilter != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  FilterChip(
                    label: Text(topicFilter),
                    selected: true,
                    onSelected: (_) =>
                        ref.read(topicFilterProvider.notifier).state = null,
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () =>
                        ref.read(topicFilterProvider.notifier).state = null,
                  ),
                ],
              ),
            ),

          // Content
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _searchResults != null
                    // Search always shows flat chronological
                    ? _buildArticleList(
                        _searchResults!, bookmarkedIds, bookmarksNotifier,
                        articleState, theme)
                    : articlesAsync.when(
                        data: (articles) {
                          var visible = articles
                              .where((a) =>
                                  !articleState.deletedIds.contains(a.id))
                              .toList();
                          if (feedFilter != null) {
                            visible = visible
                                .where((a) => a.sourceName == feedFilter)
                                .toList();
                          }
                          if (topicFilter != null) {
                            visible = visible
                                .where((a) =>
                                    TopicClassifier.classify(a) == topicFilter)
                                .toList();
                          }
                          return RefreshIndicator(
                            onRefresh: () =>
                                ref.read(articlesProvider.notifier).refresh(),
                            child: _buildArticleList(
                                visible, bookmarkedIds, bookmarksNotifier,
                                articleState, theme,
                                scrollController: _scrollController,
                                grouping: grouping),
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
    ArticleGrouping grouping = ArticleGrouping.chronological,
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

    if (grouping != ArticleGrouping.chronological &&
        scrollController != null) {
      return _buildGroupedList(articles, bookmarkedIds, bookmarksNotifier,
          articleState, theme, grouping, scrollController);
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: articles.length,
      itemBuilder: (context, index) =>
          _buildDismissibleCard(articles[index], bookmarkedIds,
              bookmarksNotifier, articleState, theme),
    );
  }

  Widget _buildGroupedList(
    List<Article> articles,
    Set<String> bookmarkedIds,
    BookmarksNotifier bookmarksNotifier,
    ArticleStateData articleState,
    ThemeData theme,
    ArticleGrouping grouping,
    ScrollController scrollController,
  ) {
    final sections = _groupArticles(articles, grouping);

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        const SliverPadding(padding: EdgeInsets.only(top: 4)),
        for (final entry in sections.entries) ...[
          SliverPersistentHeader(
            pinned: true,
            delegate: _SectionHeaderDelegate(
              title: entry.key,
              count: entry.value.length,
              theme: theme,
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildDismissibleCard(
                  entry.value[index], bookmarkedIds, bookmarksNotifier,
                  articleState, theme),
              childCount: entry.value.length,
            ),
          ),
        ],
        const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
      ],
    );
  }

  /// Groups and sorts articles into an ordered map of section → articles.
  Map<String, List<Article>> _groupArticles(
      List<Article> articles, ArticleGrouping grouping) {
    final groups = <String, List<Article>>{};

    if (grouping == ArticleGrouping.bySource) {
      for (final article in articles) {
        (groups[article.sourceName] ??= []).add(article);
      }
      final sorted = groups.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return Map.fromEntries(sorted);
    }

    // byTopic
    for (final article in articles) {
      final bucket = TopicClassifier.classify(article);
      (groups[bucket] ??= []).add(article);
    }
    final sorted = groups.entries.toList()
      ..sort((a, b) {
        if (a.key == TopicClassifier.other) return 1;
        if (b.key == TopicClassifier.other) return -1;
        return b.value.length.compareTo(a.value.length);
      });
    return Map.fromEntries(sorted);
  }

  Widget _buildDismissibleCard(
    Article article,
    Set<String> bookmarkedIds,
    BookmarksNotifier bookmarksNotifier,
    ArticleStateData articleState,
    ThemeData theme,
  ) {
    final isRead = articleState.readIds.contains(article.id);
    final isBookmarked = bookmarkedIds.contains(article.id);
    return Dismissible(
      key: ValueKey(article.id),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        color: theme.colorScheme.primaryContainer,
        child: Icon(
          isBookmarked
              ? Icons.bookmark_remove_outlined
              : Icons.bookmark_add_outlined,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: theme.colorScheme.errorContainer,
        child: Icon(Icons.delete_outline,
            color: theme.colorScheme.onErrorContainer),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          _bookmarkArticle(article, isBookmarked);
          return false;
        }
        return true;
      },
      onDismissed: (_) => _deleteArticle(article),
      child: ArticleCard(
        article: article,
        isBookmarked: isBookmarked,
        isRead: isRead,
        onTap: () => _openArticle(article),
        onBookmarkTap: () => bookmarksNotifier.toggle(article),
        onDelete: () => _deleteArticle(article),
      ),
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

class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final int count;
  final ThemeData theme;

  const _SectionHeaderDelegate({
    required this.title,
    required this.count,
    required this.theme,
  });

  @override
  double get minExtent => 40;

  @override
  double get maxExtent => 40;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_SectionHeaderDelegate old) =>
      title != old.title || count != old.count;
}
