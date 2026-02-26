# Skill: Flutter Development

Reference for common Flutter tasks in this project.

## Common Commands

```bash
flutter pub get                    # Install / update dependencies
flutter run                        # Run in debug mode (connected device/emulator)
flutter analyze                    # Static analysis (run before every push)
flutter test                       # Run all tests
flutter test test/widget_test.dart # Run a single test file
```

## Building

```bash
flutter build apk        # Android APK (used for Firebase distribution)
flutter build ios        # iOS (requires Xcode on macOS)
flutter build linux      # Linux desktop
flutter build windows    # Windows desktop
```

> Only `.apk` is built for Android — `.aab` requires a linked Google Play account and cannot be distributed via Firebase App Distribution alone.

## Code Generation

After editing any Hive model (`lib/models/*.dart`), regenerate the type adapters:

```bash
dart run build_runner build --delete-conflicting-outputs
```

See [HIVE.md](HIVE.md) for full details on model changes.

## Linting

Lint rules are configured in [`analysis_options.yaml`](../../analysis_options.yaml) using `flutter_lints`. Always resolve analyzer warnings before committing.

## CI/CD (CodeMagic)

Three workflows are defined in [`codemagic.yaml`](../../codemagic.yaml):

| Workflow | Trigger | Steps |
|----------|---------|-------|
| `ios-workflow` | push to `main`/`develop` | adapters → analyze → test → release notes → sign → build IPA → Firebase |
| `android-workflow` | push to `main`/`develop` | adapters → analyze → test → release notes → build APK → Firebase |
| `dev-workflow` | push/PR on any branch | adapters → analyze → test → release notes → build iOS + Android → Firebase |

Build numbers are injected by CodeMagic via `--build-number=$BUILD_NUMBER` (auto-increment).

Release notes are extracted from [`CHANGELOG.md`](../../CHANGELOG.md) — content above the first `---` line (after the title) becomes `release_notes.txt`.

See [`CODEMAGIC_SETUP.md`](../../CODEMAGIC_SETUP.md) for full CI/CD configuration instructions.

## State Management Patterns

This project uses **Riverpod**. Key rules:

- **Do not** use `ref.watch` inside `AsyncNotifier.build()` for providers that change at interaction time (e.g. `articleStateProvider`). This causes `build()` to re-run, triggers `AsyncLoading`, unmounts `ListView`, and resets scroll position.
- Filtering by read/deleted state happens in `FeedScreen`'s data callback, not in `ArticlesNotifier.build()`.
- `FeedScreen` uses a `ScrollController`; keep the `ListView` mounted to preserve scroll position.

## Adding a New News Source

1. Implement `INewsSource` from [`lib/services/news_sources/i_news_source.dart`](../../lib/services/news_sources/i_news_source.dart)
2. Register the source with `NewsAggregatorService` in [`lib/services/news_aggregator_service.dart`](../../lib/services/news_aggregator_service.dart)
3. Expose any required configuration via a new Hive-backed repository if persistence is needed

## Environment & Secrets

- `NEWS_API_KEY` must be a secure env var in CodeMagic — never hardcode or commit it
- Firebase config files (`google-services.json`, `GoogleService-Info.plist`) are gitignored
- See [GIT.md](GIT.md) for commit hygiene rules around secrets
