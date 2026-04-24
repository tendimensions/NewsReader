# Architecture Refactor Plan

## Goal

Improve maintainability, testability, and separation of concerns without redesigning the app from scratch.

The current structure is workable for a small Flutter app:

- `screens/` own UI
- `providers/` manage reactive state
- `repositories/` handle persistence
- `services/` contain feed and article logic
- `models/` remain mostly simple

The main issue is not the high-level layout. The issue is that some screens are starting to accumulate controller logic, direct infrastructure calls, and duplicated UI workflows.

## Current Assessment

### What is already good

- The project already has recognizable application layers.
- Core article aggregation logic is outside the UI in `lib/services/news_aggregator_service.dart`.
- Topic classification is isolated in `lib/services/topic_classifier.dart`.
- Riverpod is being used as the state boundary instead of putting everything directly in widgets.
- Repository instances are injected through `ProviderScope` overrides in `lib/main.dart`.

### Main structural problems

1. `lib/screens/feed_screen.dart` is doing too much.
   It currently mixes view rendering, search orchestration, grouping logic, bookmark/delete side effects, modal state, snackbar behavior, and list composition.

2. `lib/screens/settings_screen.dart` contains direct integration logic.
   `_testFeed()` creates `RssNewsSource` directly and performs network work from the widget, which bypasses the normal provider/service boundary.

3. Infrastructure creation is happening inside provider logic.
   `newsAggregatorProvider` in `lib/providers/feed_provider.dart` both interprets feed configuration state and constructs a concrete `RssNewsSource`.

4. Persistence is tightly coupled to Hive.
   Repositories such as `FeedConfigRepository`, `BookmarksRepository`, and `ArticleCacheRepository` directly own Hive box lifecycle and storage logic, which makes isolated testing harder.

### Duplication to clean up

1. Add/edit feed dialogs in `lib/screens/settings_screen.dart` are largely duplicated.
2. Article action flows are repeated in several UI paths in `lib/screens/feed_screen.dart`.
3. Repository box-open / read / mutate patterns are similar across repository classes.

## Refactor Priorities

### Priority 1: Split screen orchestration from widget rendering

Target files:

- `lib/screens/feed_screen.dart`
- `lib/screens/settings_screen.dart`

Actions:

- Move search, grouping, and article action orchestration out of `FeedScreen` into Riverpod notifiers or focused controller classes.
- Keep widgets responsible for rendering and dispatching user intent.
- Extract repeated modal and sheet construction into smaller private widgets or dedicated widget files.
- Move feed test execution out of `SettingsScreen` into a provider/service entry point.

Expected outcome:

- Smaller screen files
- Less widget state
- Easier widget and provider tests
- Clearer ownership of business behavior

### Priority 2: Introduce better dependency boundaries around networking

Target files:

- `lib/services/news_sources/rss_news_source.dart`
- `lib/providers/feed_provider.dart`
- `lib/screens/settings_screen.dart`

Actions:

- Inject an `http.Client` or equivalent fetch abstraction into `RssNewsSource`.
- Stop instantiating `RssNewsSource` directly inside widgets.
- Add a provider or factory layer responsible for constructing feed-source implementations.
- Reuse the same service boundary for both normal article loading and "test feed" behavior.

Expected outcome:

- Better unit-testability for RSS parsing and network failures
- Less infrastructure leakage into UI code
- A single path for feed-related behavior

### Priority 3: Decouple repositories from direct Hive ownership

Target files:

- `lib/repositories/feed_config_repository.dart`
- `lib/repositories/bookmarks_repository.dart`
- `lib/repositories/article_cache_repository.dart`
- `lib/repositories/settings_repository.dart`
- `lib/repositories/article_state_repository.dart`

Actions:

- Introduce interfaces or constructor-injected `Box<T>` dependencies where practical.
- Isolate Hive initialization from repository behavior.
- Keep repository APIs focused on domain operations rather than storage mechanics.
- Extract any repeated box lifecycle or sorted-read behavior into shared helpers only if it reduces real duplication.

Expected outcome:

- Faster and cleaner repository tests
- Less persistence coupling
- Easier future storage changes

## Concrete Work Breakdown

### Phase 1: Low-risk cleanup

- Extract add/edit feed dialog into one reusable widget or builder.
- Extract feed bookmarks sheet from `FeedScreen`.
- Extract article grouping helper logic into a separate utility/service if it continues to grow.
- Add tests for `TopicClassifier`, which is pure logic and should be cheap to cover.

### Phase 2: Testability refactor

- Inject HTTP dependency into `RssNewsSource`.
- Add unit tests for RSS parsing success, malformed feeds, non-200 responses, and timeout/error handling.
- Add provider tests around feed loading and article state transitions.

### Phase 3: State and composition cleanup

- Move `FeedScreen` behavioral logic into one or more notifiers/controllers.
- Introduce a clearer composition boundary for aggregator/source construction.
- Reduce direct widget reads of multiple repositories/notifiers where a composed provider would be cleaner.

### Phase 4: Persistence boundary cleanup

- Refactor repositories to accept dependencies instead of opening Hive boxes internally when feasible.
- Add repository tests against fake or temp-backed storage.
- Revisit whether a shared repository base/helper is useful after the interfaces stabilize.

## Suggested Order

1. Refactor duplicated dialogs and extracted widgets first.
2. Inject HTTP into `RssNewsSource`.
3. Move feed testing behavior out of `SettingsScreen`.
4. Break up `FeedScreen` orchestration.
5. Improve repository abstraction only after the UI/service boundaries are cleaner.

## Success Criteria

- `FeedScreen` and `SettingsScreen` are materially smaller and mostly presentation-focused.
- Widgets no longer instantiate integration-heavy services directly.
- RSS/network behavior can be tested without real HTTP.
- Repository behavior can be tested without depending on global Hive setup.
- New features can be added without further growing the screen files into controller classes.

## Non-Goals

- Do not replace Riverpod.
- Do not rewrite the app into a completely different architecture.
- Do not introduce abstraction layers with no testing or maintenance payoff.

## Recommended Next Steps

Start with the highest-payoff, lowest-risk slice:

1. Extract the feed add/edit dialog into one reusable component.
2. Inject HTTP into `RssNewsSource`.
3. Add tests for `TopicClassifier` and RSS parsing behavior.

That sequence improves structure and testability immediately without forcing a large rewrite.
