# Skill: Riverpod State Management

Reference for Riverpod patterns used in this project.

## Provider Types in Use

| Provider | Used for | Examples |
|----------|----------|---------|
| `Provider` | Derived/computed values, services | `newsAggregatorProvider`, repository providers |
| `StateProvider` | Simple mutable values | `feedFilterProvider` |
| `StateNotifierProvider` | Mutable state with methods | `feedConfigsProvider`, `bookmarksProvider`, `articleStateProvider`, `themeProvider` |
| `AsyncNotifierProvider` | Async state with background work | `articlesProvider` |

## Repository Injection Pattern

Repository providers are declared with `throw UnimplementedError` as their body — they **must** be overridden at startup:

```dart
// repositories_provider.dart — declaration only, no implementation
final feedConfigRepositoryProvider = Provider<FeedConfigRepository>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});
```

In `main.dart`, after Hive initialises, each is injected via `overrideWithValue`:

```dart
ProviderScope(
  overrides: [
    feedConfigRepositoryProvider.overrideWithValue(feedConfigRepo),
    bookmarksRepositoryProvider.overrideWithValue(bookmarksRepo),
    // ... all five repos
  ],
  child: const NewsReaderApp(),
)
```

When adding a new repository: declare it in [lib/providers/repositories_provider.dart](../../lib/providers/repositories_provider.dart), initialise and inject it in [lib/main.dart](../../lib/main.dart).

## StateNotifier Pattern

Used for Hive-backed state. Constructor loads initial state synchronously from the repo; mutations call repo methods then reassign `state`:

```dart
class BookmarksNotifier extends StateNotifier<List<Article>> {
  final BookmarksRepository _repo;

  BookmarksNotifier(BookmarksRepository repo)
      : _repo = repo,
        super(repo.getAll());       // synchronous Hive read

  Future<void> toggle(Article article) async {
    await _repo.toggle(article);
    state = _repo.getAll();         // reassign triggers rebuild
  }
}
```

## ref.watch vs ref.read

| Use | When |
|-----|------|
| `ref.watch` | Inside `build()` / `Provider` body — rebuilds when dependency changes |
| `ref.read` | Inside event handlers / async methods — one-time read, no subscription |

Inside `AsyncNotifier` methods like `refresh()` and `search()`, always use `ref.read` — never `ref.watch`.

## Critical Anti-Pattern: ref.watch in AsyncNotifier.build()

**Do not** watch providers that change at interaction time (e.g. `articleStateProvider`) inside `AsyncNotifier.build()`.

When a watched dependency changes, Riverpod **disposes and re-runs `build()` entirely**, which:
1. Triggers `AsyncLoading`
2. Unmounts the `ListView`
3. Resets scroll position

**Wrong:**
```dart
@override
Future<List<Article>> build() async {
  final aggregator = ref.watch(newsAggregatorProvider);
  final articleState = ref.watch(articleStateProvider); // WRONG — causes scroll reset
  // ...
}
```

**Correct** — watch only providers whose changes should trigger a full re-fetch; filter in the UI:
```dart
@override
Future<List<Article>> build() async {
  final aggregator = ref.watch(newsAggregatorProvider); // intentional — feed changes need re-fetch

  // articleStateProvider is NOT watched here
  // read/deleted filtering happens in FeedScreen's data callback instead
}
```

Currently intentional watches in `ArticlesNotifier.build()`:
- `newsAggregatorProvider` — feed config changes should trigger a network re-fetch

## Background Fetch Pattern (ArticlesNotifier)

`build()` returns cached data immediately, then fetches in the background without blocking startup. A `cancelled` guard prevents stale futures from writing state after the notifier is disposed:

```dart
@override
Future<List<Article>> build() async {
  final aggregator = ref.watch(newsAggregatorProvider);
  final cacheRepo = ref.read(articleCacheRepositoryProvider);

  var cancelled = false;
  ref.onDispose(() => cancelled = true);

  final cached = cacheRepo.getAll();

  Future.microtask(() async {
    final articles = await aggregator.fetchArticles(limit: 50);
    if (cancelled) return;          // guard before every state write
    await cacheRepo.cacheArticles(articles);
    if (cancelled) return;
    state = AsyncData(articles);
  });

  return cached;                    // immediate return — no AsyncLoading flash
}
```

## Filtering in the UI, Not in the Notifier

Read/deleted filtering is applied in `FeedScreen`'s `when(data:)` callback, not inside `ArticlesNotifier`. This keeps the `ListView` mounted and scroll position stable:

```dart
// FeedScreen — data callback
ref.watch(articlesProvider).when(
  data: (articles) {
    final articleState = ref.read(articleStateProvider);
    final visible = articles
        .where((a) => !articleState.deletedIds.contains(a.id))
        .toList();
    // build ListView from visible
  },
  // ...
)
```

## Provider Directory

| Provider | File | Type | Provides |
|----------|------|------|---------|
| `feedConfigsProvider` | [lib/providers/feed_provider.dart](../../lib/providers/feed_provider.dart) | `StateNotifierProvider` | `List<FeedConfig>` |
| `newsAggregatorProvider` | [lib/providers/feed_provider.dart](../../lib/providers/feed_provider.dart) | `Provider` | `NewsAggregatorService` |
| `feedFilterProvider` | [lib/providers/feed_provider.dart](../../lib/providers/feed_provider.dart) | `StateProvider` | `String?` (active feed filter) |
| `articlesProvider` | [lib/providers/feed_provider.dart](../../lib/providers/feed_provider.dart) | `AsyncNotifierProvider` | `List<Article>` |
| `bookmarksProvider` | [lib/providers/bookmarks_provider.dart](../../lib/providers/bookmarks_provider.dart) | `StateNotifierProvider` | `List<Article>` |
| `articleStateProvider` | [lib/providers/article_state_provider.dart](../../lib/providers/article_state_provider.dart) | `StateNotifierProvider` | `ArticleStateData` (read/deleted IDs) |
| `themeProvider` | [lib/providers/theme_provider.dart](../../lib/providers/theme_provider.dart) | `StateNotifierProvider` | `ThemeMode` |
| `*RepositoryProvider` | [lib/providers/repositories_provider.dart](../../lib/providers/repositories_provider.dart) | `Provider` | Repository singletons (overridden in main) |
