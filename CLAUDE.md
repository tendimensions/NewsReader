# NewsReader - Claude Code Instructions

## Project Overview

Cross-platform news reader app built with Flutter (Dart SDK ^3.9.2). Aggregates articles from multiple RSS/Atom feed sources with deduplication. Targets **Android, iOS, Linux, and Windows** platforms.

**Package name**: `com.tendimensions.newsreader`

## Agent Instructions

See [AGENTS.md](AGENTS.md) for issue tracking workflows using **beads** (`bd`).

## Requirements

### State Management & Architecture
- **State management**: Riverpod
- **Local storage**: Hive (NoSQL box storage)
- **Architecture**: Provider/repository pattern with Riverpod

### UI/UX
- **Feed layout**: Single vertical scroll, reverse-chronological (newest first)
- **Search**: Search bar at top of feed
- **Article view**: Reader mode — extract and render article content in a clean, distraction-free layout
- **Design system**: Material 3 with custom seed color
- **Dark mode**: System-aware by default with manual override toggle in settings
- **Platforms**: Android, iOS, Linux, Windows

### Data & Sources
- **Initial launch**: RSS feeds only (no NewsAPI key required)
- **Built-in feeds** (tech-focused): Ars Technica, The Verge, TechCrunch, Hacker News, etc.
- **Feed customization**: Users can add/remove custom RSS feed URLs and toggle built-in feeds on/off via settings
- **Deduplication**: Combined strategy (URL + title similarity) via existing `NewsAggregatorService`

### Persistence (Hive)
- **Bookmarks**: Save articles for later reading
- **Offline cache**: Headlines + summaries cached for offline browsing
- **Settings**: Theme preference, feed configuration (enabled/disabled feeds, custom feed URLs)

### Not in Initial Release
- Push notifications
- NewsAPI.org integration (code exists in [lib/services/news_sources/news_api_source.dart](lib/services/news_sources/news_api_source.dart), just not active)
- Full offline article content + image caching

## Tech Stack

- **Framework**: Flutter (uses-material-design)
- **Language**: Dart
- **State management**: Riverpod (`flutter_riverpod`)
- **Local storage**: Hive (`hive`, `hive_flutter`)
- **HTTP**: `http` package
- **RSS parsing**: `webfeed` package
- **CI/CD**: CodeMagic ([codemagic.yaml](codemagic.yaml), setup guide in [CODEMAGIC_SETUP.md](CODEMAGIC_SETUP.md))
- **Distribution**: Firebase App Distribution
- **Linting**: `flutter_lints` via [analysis_options.yaml](analysis_options.yaml)

## Project Structure

```
lib/
├── main.dart                              # App entry point (Hive init, ProviderScope, theme)
├── models/
│   ├── article.dart                       # Article data model (Hive typeId: 0)
│   ├── article.g.dart                     # Generated Hive adapter
│   ├── feed_config.dart                   # RSS feed config model (Hive typeId: 1)
│   ├── feed_config.g.dart                 # Generated Hive adapter
│   ├── app_settings.dart                  # ThemePreference enum + AppSettings (Hive typeId: 2,3)
│   └── app_settings.g.dart               # Generated Hive adapter
├── providers/
│   ├── repositories_provider.dart         # Singleton repo providers (overridden in main)
│   ├── theme_provider.dart                # ThemeMode StateNotifier
│   ├── feed_provider.dart                 # Feed configs, aggregator, articles AsyncNotifier
│   ├── bookmarks_provider.dart            # Bookmarks StateNotifier
│   └── article_state_provider.dart        # Read/unread + deleted article tracking
├── repositories/
│   ├── feed_config_repository.dart        # Hive-backed feed config CRUD + defaults
│   ├── bookmarks_repository.dart          # Hive-backed bookmark storage
│   ├── article_cache_repository.dart      # Hive-backed offline cache (max 200 articles)
│   ├── settings_repository.dart           # Hive-backed app settings
│   └── article_state_repository.dart      # Hive-backed read/deleted article IDs
├── screens/
│   ├── feed_screen.dart                   # Main reverse-chron feed + search + bookmarks sheet
│   ├── article_screen.dart                # Reader mode article view
│   └── settings_screen.dart               # Theme toggle, feed management, add custom feeds
├── services/
│   ├── news_aggregator_service.dart       # Aggregator with deduplication strategies
│   └── news_sources/
│       ├── i_news_source.dart             # INewsSource interface
│       ├── news_api_source.dart           # NewsAPI.org implementation (future)
│       └── rss_news_source.dart           # RSS/Atom feed implementation
└── widgets/
    └── article_card.dart                  # Article list item card widget
```

## Architecture

- **News source interface**: `INewsSource` in [lib/services/news_sources/i_news_source.dart](lib/services/news_sources/i_news_source.dart) — implement this to add new sources
- **Aggregator**: `NewsAggregatorService` fetches from all sources in parallel, deduplicates, and provides filtering (by source count, source name, categories)
- **Deduplication strategies**: `url`, `title`, `titleSimilarity` (Levenshtein, >85% threshold), `combined` (recommended)
- **Providers**: Riverpod providers expose aggregator, bookmarks, feed config, theme, and article cache state
- **Repositories**: Hive-backed repositories for bookmarks, feed configuration, cached articles, and settings

## Common Commands

```bash
flutter pub get          # Install dependencies
flutter run              # Run in debug mode
flutter test             # Run tests
flutter analyze          # Run static analysis
flutter build apk        # Build Android APK
flutter build ios        # Build iOS
flutter build linux      # Build Linux
flutter build windows    # Build Windows
```

## CI/CD Workflows (CodeMagic)

- **ios-workflow**: push to `main`/`develop` → analyze → test → build IPA → Firebase distribution
- **android-workflow**: push to `main`/`develop` → analyze → test → build APK+AAB → Firebase distribution
- **dev-workflow**: PRs on any branch → analyze → test → debug APK (no distribution)

## Important Notes

- API keys (NEWS_API_KEY) must be configured as secure environment variables in CodeMagic, never committed
- Firebase config files (`google-services.json`, `GoogleService-Info.plist`) are gitignored
- Tests are minimal (only default `widget_test.dart`) — expand as features are built
