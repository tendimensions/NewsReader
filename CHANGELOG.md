# Changelog

## 0.0.9

- Fixed: Share button now works on iOS — passes the button's screen position as required by the iOS share sheet

---

## 0.0.8

- Swipe right on an article to bookmark/unbookmark it; swipe left continues to remove it from the feed
- Article state (read/deleted IDs) is now pruned automatically on each fetch, preventing unbounded local database growth

---

## 0.0.7

- Added 10 new built-in feeds: MIT Technology Review, IEEE Spectrum, Engadget, 9to5Mac, Android Authority, Tom's Hardware, Slashdot, The Register, Lobsters, CNET
- New built-in feeds are added automatically for existing users on next launch (no reinstall required)

---

## 0.0.6

- Fixed: iOS launch hang: app no longer silently freezes on a blank screen if initialization fails
- Hive database corruption now auto-recovers on next launch: only the corrupted box is wiped, preserving custom feeds, bookmarks, and settings in unaffected boxes
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
