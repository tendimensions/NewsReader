# NewsReader

A cross-platform news reader built with Flutter. Aggregates articles from multiple RSS/Atom feeds with deduplication, offline caching, bookmarking, and a clean Material 3 UI.

**Package**: `com.tendimensions.newsreader`
**Platforms**: Android, iOS, Linux, Windows

## Features

- Reverse-chronological feed with search
- Built-in tech feeds (Ars Technica, The Verge, TechCrunch, Hacker News, and more)
- Add/remove custom RSS feed URLs; toggle built-in feeds on/off
- Article reader mode with HTML rendering, selectable text, open-in-browser, and bookmarking
- Offline cache (up to 200 articles)
- Material 3 design with system-aware dark mode and manual override
- Deduplication via URL + title-similarity matching

## Tech Stack

| Concern | Library |
|---------|---------|
| UI framework | Flutter / Dart |
| State management | Riverpod |
| Local storage | Hive |
| RSS parsing | webfeed |
| HTML rendering | flutter_html |
| HTTP | http |
| URL launch | url_launcher |
| CI/CD | CodeMagic |
| Distribution | Firebase App Distribution |

## Getting Started

```bash
# Install dependencies
flutter pub get

# Run in debug mode
flutter run

# Run tests
flutter test

# Static analysis
flutter analyze
```

## Building

```bash
flutter build apk        # Android
flutter build ios        # iOS
flutter build linux      # Linux
flutter build windows    # Windows
```

## Project Structure

```
lib/
├── main.dart            # Entry point (Hive init, ProviderScope, theme)
├── models/              # Hive-annotated data models + generated adapters
├── providers/           # Riverpod providers
├── repositories/        # Hive-backed storage layer
├── screens/             # Feed, Article reader, Settings
├── services/            # NewsAggregatorService + RSS/NewsAPI sources
└── widgets/             # Shared UI components (ArticleCard)
```

## Documentation

| Document | Purpose |
|----------|---------|
| [.claude/CLAUDE.md](.claude/CLAUDE.md) | Full project guidance for Claude Code |
| [.claude/skills/GIT.md](.claude/skills/GIT.md) | Git workflow, branching, session wrap-up |
| [.claude/skills/FLUTTER.md](.claude/skills/FLUTTER.md) | Flutter commands, CI/CD, state patterns |
| [.claude/skills/HIVE.md](.claude/skills/HIVE.md) | Hive models, adapters, migrations |
| [AGENTS.md](AGENTS.md) | Agent workflow instructions |
| [CHANGELOG.md](CHANGELOG.md) | Release history |
| [CODEMAGIC_SETUP.md](CODEMAGIC_SETUP.md) | CI/CD setup guide |
| [SUGGESTED_FEEDS.md](SUGGESTED_FEEDS.md) | Curated RSS feed list |

## CI/CD

Builds run on CodeMagic. Three workflows are configured in [`codemagic.yaml`](codemagic.yaml):

- **`ios-workflow`** / **`android-workflow`** — triggered on push to `main`/`develop`
- **`dev-workflow`** — triggered on push/PR to any branch

Each workflow generates Hive adapters, runs analysis and tests, then builds and distributes via Firebase App Distribution.

## Contributing

1. Branch from `main` using `git checkout -b your-branch`
2. Follow the git workflow in [`.claude/skills/GIT.md`](.claude/skills/GIT.md)
3. Run `flutter analyze` and `flutter test` before pushing

## License

To be determined.
