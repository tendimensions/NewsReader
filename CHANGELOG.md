# Changelog

## 0.0.6

- Fixed: iOS launch hang: app no longer silently freezes on a blank screen if initialization fails
- Hive database corruption now auto-recovers on next launch instead of leaving the app stuck
- Hive adapters guarded against double-registration on unexpected re-init
- Added NSAppTransportSecurity to iOS Info.plist to allow HTTP feed URLs
- Added global error handlers (FlutterError, PlatformDispatcher, runZonedGuarded) so any unhandled exception is logged and shown instead of silently dropped
- Initialization timeout (30 s) prevents infinite hang if Hive boxes stall

---

## 0.0.5

- Fixed: Scroll position now restored when returning from article view to the feed list

---

## 0.0.4

### Added

- RSS/Atom feed aggregation from built-in tech sources (Ars Technica, The Verge, TechCrunch, Hacker News)
- Reverse-chronological article feed with search
- Article reader mode with HTML rendering and selectable/copyable text
- Open articles in external browser
- Bookmark articles for later reading
- Custom RSS feed URLs via settings
- Toggle built-in feeds on/off
- Dark mode with system-aware default and manual override in settings
- Offline article cache (up to 200 articles)
- Material 3 design with custom seed color
