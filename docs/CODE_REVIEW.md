# NewsReader — Code Review

**Reviewer:** Donovan (AI Technical Assistant)  
**Date:** 2026-04-22  
**Revision:** `ea79ef6` (Add selectable text and HTML rendering to article view)  
**Scope:** Full codebase (`lib/`, `test/`, `pubspec.yaml`, `analysis_options.yaml`)

---

## Executive Summary

The codebase is well-structured and shows solid engineering instincts. The architecture is clean: a proper interface (`INewsSource`), a repository pattern backed by Hive, Riverpod for state management, and a clear separation between data sources, providers, and UI. For an app of this scope, that's legitimately good. The issues below are real, ranked honestly, and solvable — none of them are "burn it down" problems.

---

## Issues: Ranked by Severity

### 🔴 CRITICAL

---

#### 1. API key in NewsAPI source will leak in builds if ever activated

**File:** `lib/services/news_sources/news_api_source.dart`  
**Severity:** Critical (security)

The `NewsApiSource` constructor takes `apiKey` as a plain string parameter. When this source is wired up, the API key will almost certainly get hardcoded somewhere — either in `feed_provider.dart` or `main.dart`. There is no enforcement of secure injection at compile time. The `CLAUDE.md` says "API keys must be configured as secure environment variables in CodeMagic, never committed" — but nothing in the code enforces or guides this.

**Recommendation:**
- Add a dedicated `SecretsService` or environment config abstraction.
- Read keys from `dart-define` or environment at build time (not at runtime from a hardcoded string).
- Add a lint comment on `NewsApiSource` that documents the expected injection path before this source goes live.
- Consider adding a `dart_define` example in `CLAUDE.md`.

---

#### 2. Article ID generation is collision-prone

**File:** `lib/services/news_sources/rss_news_source.dart`, lines where `id` is generated  
**Severity:** Critical (data integrity)

```dart
final id = Uri.parse(url).host + url.hashCode.toString();
```

`url.hashCode` in Dart is a 32-bit integer with high collision probability across large article sets. Two different URLs on the same host could produce the same ID. Same pattern is in `news_api_source.dart`. This silently corrupts both the Hive article cache and the read/deleted state tracking — a wrong "deleted" state on a legitimate article is a silent data bug.

**Recommendation:**
Use the full URL as the ID (after normalization), or use a proper hash function:
```dart
// Simple, zero-dependency approach:
final id = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
// Or simply use the normalized URL directly — it's already unique.
final id = _normalizeUrl(url);
```

---

### 🟠 HIGH

---

#### 3. `ArticlesNotifier.build()` fetches on every `newsAggregatorProvider` rebuild

**File:** `lib/providers/feed_provider.dart`  
**Severity:** High (performance / UX)

`articlesProvider` is an `AsyncNotifierProvider` and its `build()` method calls `ref.watch(newsAggregatorProvider)`. Every time `feedConfigsProvider` changes (e.g., toggling a feed on/off), a new `NewsAggregatorService` is constructed and `build()` re-fires — meaning a full network fetch of all RSS feeds triggers on any settings change. This is expensive and will produce jarring loading states mid-session.

```dart
final aggregator = ref.watch(newsAggregatorProvider); // <-- triggers re-fetch on every config change
```

**Recommendation:**
- Use `ref.read` inside `build()` to read the aggregator without subscribing to changes, OR
- Separate the "fetch" trigger from the "config watcher" — only re-fetch when the user explicitly refreshes or after a configurable staleness window.
- Consider using `keepAlive: true` or a `FamilyAsyncNotifier` to preserve cache across rebuilds.

---

#### 4. Search fetches up to 1,000 articles from every feed — no network guard

**File:** `lib/services/news_sources/rss_news_source.dart`  
**Severity:** High (performance / reliability)

```dart
Future<List<Article>> searchArticles({...}) async {
    final articles = await fetchArticles(limit: 1000); // ← fetches ALL articles on every keypress
```

This is called every time `_performSearch` is invoked from the UI. Even with `onSubmitted` it's a full re-fetch of all feeds, each over the network, each time. On slow connections this will hang or timeout. On mobile data this burns bandwidth.

**Recommendation:**
- Cache the full article list after the initial fetch and search in-memory against the cache.
- Or debounce search calls aggressively (e.g., 500ms).
- Remove the `limit: 1000` magic number — add a constant `_searchFetchLimit` and document the reasoning.

---

#### 5. `_deduplicateByTitleSimilarity` is O(n²) with Levenshtein — will choke on large feeds

**File:** `lib/services/news_aggregator_service.dart`  
**Severity:** High (performance)

The combined deduplication strategy (which is the default) runs Levenshtein distance against every pair of articles. At 50 articles it's fine. At 200+ articles (plausible with 5 feeds at 50 each), the O(n²) × O(m) Levenshtein becomes a perceptible freeze on the UI thread.

**Recommendation:**
- Run deduplication off the main isolate using `compute()`.
- Or replace Levenshtein with a faster approach: shingling (word trigrams) with a set-similarity check is O(n × m_words) and far faster in practice.
- Alternatively, only apply title similarity when URL dedup catches fewer than N duplicates (i.e., skip the expensive pass when URLs already cover it).

---

#### 6. No HTTP timeout on RSS fetches

**File:** `lib/services/news_sources/rss_news_source.dart`  
**Severity:** High (reliability)

```dart
final response = await http.get(Uri.parse(feedUrl));
```

No timeout is set. If a feed server hangs (which they do), this will block indefinitely. The `isAvailable()` check has a 5-second timeout, but the actual `_fetchFromFeed` that runs on every refresh does not.

**Recommendation:**
```dart
final response = await http.get(Uri.parse(feedUrl))
    .timeout(const Duration(seconds: 15));
```
Add a consistent timeout constant at the top of the file.

---

### 🟡 MEDIUM

---

#### 7. `StateNotifierProvider` is deprecated in Riverpod 2.x

**File:** `lib/providers/feed_provider.dart`, `lib/providers/bookmarks_provider.dart`, `lib/providers/article_state_provider.dart`, `lib/providers/theme_provider.dart`  
**Severity:** Medium (maintainability)

All state management is implemented with `StateNotifier` + `StateNotifierProvider`, which was the Riverpod 1.x way. Riverpod 2.x (which this project uses — `flutter_riverpod: ^2.6.1`) introduced `Notifier` + `NotifierProvider` as the replacement. `StateNotifier` is not removed yet, but Riverpod's own docs and changelog flag it as deprecated and subject to removal in a future major version.

**Recommendation:**
Migrate to `Notifier`/`AsyncNotifier` pattern:
```dart
// Before (Riverpod 1.x style)
class BookmarksNotifier extends StateNotifier<List<Article>> { ... }

// After (Riverpod 2.x style)
class BookmarksNotifier extends Notifier<List<Article>> {
  @override
  List<Article> build() => ref.read(bookmarksRepositoryProvider).getAll();
  ...
}
```
This is a mechanical migration but worth scheduling before it becomes a breaking change.

---

#### 8. Bookmarks are stored as full `Article` objects — duplicates feed cache

**File:** `lib/repositories/bookmarks_repository.dart`  
**Severity:** Medium (architecture / storage)

Bookmarks store the complete `Article` object in a Hive box, including description and content. The same articles may be in `article_cache`. If an article is updated (e.g., a correction), the bookmarked copy will be stale forever. This is a classic denormalization problem.

**Recommendation:**
Store only article IDs in the bookmarks box and look up articles from the cache. Fall back to a "snapshot" store only for offline reading when the cache is evicted. This requires a small architectural change but eliminates the duplication.

---

#### 9. `SettingsRepository.setThemePreference` has a subtle mutation bug

**File:** `lib/repositories/settings_repository.dart`  
**Severity:** Medium (correctness)

```dart
Future<void> setThemePreference(ThemePreference pref) async {
    final s = settings;
    s.themePreference = pref;
    await _box.put(_settingsKey, s);  // <-- re-puts the same object it just got
}
```

`settings` returns `_box.get(_settingsKey) ?? AppSettings()`. If the box returns `null` (e.g., first run before init completes), a fresh `AppSettings()` is mutated and stored. This is a race condition that can silently discard prior settings if `setThemePreference` is called before `init()` completes. In practice this is unlikely to trigger, but it's fragile.

**Recommendation:**
Add a guard:
```dart
Future<void> setThemePreference(ThemePreference pref) async {
    assert(_box.isOpen, 'SettingsRepository not initialized');
    final s = _box.get(_settingsKey) ?? AppSettings();
    s.themePreference = pref;
    await _box.put(_settingsKey, s);
}
```

---

#### 10. `RadioGroup` widget used in settings screen is non-standard

**File:** `lib/screens/settings_screen.dart`  
**Severity:** Medium (correctness)

```dart
RadioGroup<ThemePreference>(
    groupValue: currentThemePref,
    onChanged: (v) { if (v != null) themeNotifier.setTheme(v); },
    child: Column(...)
)
```

`RadioGroup` is not a Flutter SDK or Material 3 widget. `RadioListTile` values are not being bound through a standard group mechanism here. Each `RadioListTile` inside the `Column` is not passed `groupValue` or `onChanged` directly, so the radio selection state is decoupled from the tiles' rendering. This likely means the radio buttons will either always appear unselected or not respond correctly to taps.

**Recommendation:**
Remove the `RadioGroup` wrapper and bind each `RadioListTile` directly:
```dart
RadioListTile<ThemePreference>(
    value: ThemePreference.system,
    groupValue: currentThemePref,
    onChanged: (v) { if (v != null) themeNotifier.setTheme(v); },
    title: const Text('System default'),
    subtitle: const Text('Match device setting'),
),
```

---

#### 11. Image loading has no caching

**File:** `lib/screens/article_screen.dart`  
**Severity:** Medium (performance / UX)

```dart
Image.network(article.imageUrl!, ...)
```

`Image.network` in Flutter uses an in-memory `PaintingBinding.imageCache` that is cleared on app restart. There is no persistent image cache, so every app launch re-fetches all article images. On slow connections this causes visible layout jank as images load in.

**Recommendation:**
Add `cached_network_image` package:
```dart
CachedNetworkImage(
    imageUrl: article.imageUrl!,
    fit: BoxFit.cover,
    errorWidget: (_, __, ___) => const SizedBox.shrink(),
)
```

---

#### 12. `_openInBrowser` imports `dart:io` at the top of `article_screen.dart`

**File:** `lib/screens/article_screen.dart`  
**Severity:** Medium (portability)

```dart
import 'dart:io';
```

`dart:io` is not available on the web platform. Since `pubspec.yaml` includes web as a build target, this will cause a compile error if someone attempts a web build. The WSL detection logic (`Platform.isLinux`) is also unnecessary complexity for a mobile/desktop app.

**Recommendation:**
- Remove the `dart:io` import and the `wslview`/`xdg-open` fallback if web support is needed.
- If Linux/WSL is a real supported platform, wrap the `dart:io` usage in a `kIsWeb` guard or use conditional imports (`import 'platform_io.dart' if (dart.library.html) 'platform_web.dart'`).

---

### 🟢 LOW / POLISH

---

#### 13. Verbose `debugPrint` logging left in production code

**File:** `lib/providers/feed_provider.dart`, `lib/services/news_sources/rss_news_source.dart`, `lib/services/news_aggregator_service.dart`  
**Severity:** Low

There are dozens of `debugPrint` calls throughout the fetch and aggregation pipeline. While `debugPrint` is a no-op in release builds, it adds noise to debug sessions and signals incomplete cleanup. Consider a proper logging abstraction (e.g., `package:logging`) or at minimum consolidate to `kDebugMode`-guarded blocks.

---

#### 14. `README.md` reflects initial scaffolding — outdated

**File:** `README.md`  
**Severity:** Low (documentation)

The README still says "🚧 In Development — Initial setup phase" with placeholder sections for "news sources to be determined" and "architecture to be decided." The app is substantially built. The README should be updated to reflect what actually exists.

---

#### 15. No real tests

**File:** `test/widget_test.dart`  
**Severity:** Low (test coverage)

```dart
testWidgets('App smoke test placeholder', (WidgetTester tester) async {
    // TODO: Add proper widget tests once app stabilizes
    expect(true, isTrue);
});
```

This test passes unconditionally and tests nothing. The CI pipeline runs `flutter test` — so it succeeds, but gives false confidence. The app is stable enough to write at least unit tests for the deduplication logic and repository layer.

**Priority tests to write:**
1. `NewsAggregatorService._deduplicateCombined` — logic is complex, no tests
2. `ArticleCacheRepository._trimCache` — off-by-one errors are easy here
3. `Article.fromJson` / `toJson` roundtrip
4. `_calculateTitleSimilarity` edge cases (empty strings, identical, completely different)

---

#### 16. `FeedConfig.defaultFeeds` is a static getter on the model

**File:** `lib/models/feed_config.dart`  
**Severity:** Low (architecture smell)

The default feed list is embedded as a static getter on the model class. Model classes should be pure data. This logic belongs in `FeedConfigRepository._seedDefaults()` or a separate config file.

---

#### 17. `ArticleCard` has inconsistent layout when `author` is null

**File:** `lib/widgets/article_card.dart`  
**Severity:** Low (UI)

When `article.author != null`, the bottom row uses `Expanded` to constrain the author text. When it's null, it uses `const Spacer()`. These have different layout behaviors — `Expanded` in a `Row` behaves differently than `Spacer` when sibling widgets vary in width. This can cause inconsistent card heights across the list. Standardize on one or the other.

---

## Summary Table

| # | Issue | Severity | File |
|---|-------|----------|------|
| 1 | API key leak risk when NewsAPI activated | 🔴 Critical | `news_api_source.dart` |
| 2 | Collision-prone article ID generation | 🔴 Critical | `rss_news_source.dart`, `news_api_source.dart` |
| 3 | Full re-fetch on every feed config change | 🟠 High | `feed_provider.dart` |
| 4 | Search fetches 1000 articles from network each call | 🟠 High | `rss_news_source.dart` |
| 5 | O(n²) Levenshtein dedup blocks main thread | 🟠 High | `news_aggregator_service.dart` |
| 6 | No HTTP timeout on RSS fetches | 🟠 High | `rss_news_source.dart` |
| 7 | `StateNotifierProvider` deprecated in Riverpod 2.x | 🟡 Medium | All providers |
| 8 | Full article objects stored in bookmarks (denormalization) | 🟡 Medium | `bookmarks_repository.dart` |
| 9 | Subtle mutation bug in `setThemePreference` | 🟡 Medium | `settings_repository.dart` |
| 10 | `RadioGroup` widget non-standard, likely broken | 🟡 Medium | `settings_screen.dart` |
| 11 | No persistent image caching | 🟡 Medium | `article_screen.dart` |
| 12 | `dart:io` import breaks web builds | 🟡 Medium | `article_screen.dart` |
| 13 | Verbose `debugPrint` left in production code | 🟢 Low | Multiple |
| 14 | README still says "in development" | 🟢 Low | `README.md` |
| 15 | No real tests (placeholder only) | 🟢 Low | `test/widget_test.dart` |
| 16 | Default feeds as static getter on model class | 🟢 Low | `feed_config.dart` |
| 17 | `ArticleCard` inconsistent layout with/without author | 🟢 Low | `article_card.dart` |

---

## What's Done Well

- **Architecture is solid.** The `INewsSource` interface, repository pattern, and clean provider layer are above average for a Flutter project at this stage.
- **Deduplication is thoughtful.** Offering multiple strategies with a `combined` default shows good product thinking. Levenshtein similarity for title matching is the right approach — just needs to move off the main thread.
- **Offline fallback works.** The `articlesProvider` gracefully falls back to cached articles on network failure. That's easy to forget and was remembered here.
- **Material 3 done correctly.** The app uses `ColorScheme.fromSeed` properly and respects both light/dark theming without any hardcoded colors.
- **Error states are handled in the UI.** The feed screen shows a proper error widget with a retry button rather than crashing or showing nothing.
- **Hive adapters are generated, not hand-written.** Using `build_runner` for Hive adapters is the right call — avoids a whole class of serialization bugs.
- **WSL browser fallback is a nice touch.** Remembering that this app may be developed on WSL and adding `wslview` fallback is practical and shows awareness of the dev environment (even if the `dart:io` import needs fixing for web).

---

*Review generated from source at commit `ea79ef6`. Re-run against future commits as issues are addressed.*
