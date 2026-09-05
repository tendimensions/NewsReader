# Changelog

## 0.2.1

- Fixed the Android build, which had never succeeded on CI. Flutter's current stable requires Gradle 8.14.0 or newer and the wrapper was pinned to 8.12, so `flutter build apk` failed before compiling anything. Bumped to 8.14.5. iOS was unaffected.
- A toast now confirms when a bookmark reaches the vault. The bookmark icon flipped immediately but the vault save takes several seconds, so there was no way to tell whether it landed. Success, "saved without enrichment", a queued retry, and a missing token each say so. The message shows over whichever screen you are on, since the save usually finishes after you have moved on from the article.

---

## 0.2.0

- Bookmarks now also save to the MCP vault. Bookmarking an article files it via the server's `save_bookmark` tool, which summarises it, extracts key facts, and tags it. Off by default — enable it and set a bearer token under Settings → Vault Sync.
- The article's own body text and feed categories are sent with the save, so the server skips its own page fetch. That works on articles behind paywalls or dead links, which would otherwise fail to enrich.
- Saves are queued, so bookmarking works with no signal. The queue drains automatically when a send succeeds, and Settings shows how many are waiting.
- Removing a bookmark leaves the vault document in place. The bookmark list is a reading queue; the vault copy is long-term memory.
- The vault token is held in the device keystore (iOS Keychain / Android EncryptedSharedPreferences), never in plain storage.
- RSS feed discovery by URL: paste a site address in Settings and the app finds its feeds.
- Clickable topic tags in the article reader: category chips on the article detail screen are now tappable when the category maps to a known topic bucket. Tapping a chip sets a topic filter on the feed, pops back to the feed list, and shows a dismissible filter chip so the user can clear it. Categories with no known bucket mapping render as non-interactive chips.

---

## 0.1.1

- Clickable section headers in grouped views (By Topic / By Source): tapping a header now instantly collapses or expands that section. A chevron icon (right when collapsed, down when expanded) shows the current state. The scroll-collapse behavior from pinned headers is unchanged.

## 0.0.10

- Article grouping & sorting: new Sort/Group button in the feed toolbar lets you switch between three modes:
  - **Chronological** — default newest-first flat list (unchanged)
  - **By Source** — sticky section headers, publications sorted alphabetically
  - **By Topic** — sticky section headers grouped by topic category (AI & ML, Security, Mobile, Hardware, Software & Dev, Policy & Law, Science & Space, Business); topics sorted by article count so the most active appear first
- Topic classification uses a two-layer strategy: RSS feed categories first (normalized), keyword taxonomy fallback for uncategorized articles
- Sort/Group button tints to the primary color when a non-default mode is active
- Search always shows a flat chronological list regardless of active grouping
- `trigger-build.ps1` now reads `ApiKey` and `AppId` from a local `app.info` file when not passed on the command line

---

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
