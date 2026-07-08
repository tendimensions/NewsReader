# Feature Design: RSS Feed Discovery

**Status**: MVP implemented (paste + clipboard). iOS Share Sheet still pending.
**Date**: 2026-07-08
**Tracking**: BrainDepo task #35 — "Add NewsReader feature for discovering RSS feeds and newsletters"
**Branch**: implemented on `main` (per owner request)

> Scope note: task #35 mentions "newsletters" but that was loose wording. This
> feature is **RSS/Atom feed discovery only**. Email newsletters are out of scope.

---

## Summary

Let a user discover the RSS/Atom feed for a site without knowing its exact feed
URL. The user pastes anything site-shaped — a homepage (`theverge.com`), a full
URL (`https://arstechnica.com`), or even a specific article URL — and the app
finds the feed(s) for that site, previews them, and adds the chosen one with one
tap through the existing add-feed path.

This solves the real pain: users know the **site** they like, not its feed URL.

---

## Core user story

> I'm reading a site I like. I copy the URL from my browser, open NewsReader,
> and it tells me whether there's a feed I can subscribe to — without me hunting
> for a feed icon or guessing `/rss`.

---

## Entry points

### 1. Paste field + clipboard auto-fill (MVP, cross-platform)

A **"Discover Feeds"** action in `settings_screen.dart`, next to the existing
"Add Feed" button. It opens a screen/sheet with a single URL field.

- On open, read the clipboard (`Clipboard.getData`). If it holds a URL-shaped
  string, either pre-fill the field or surface a tappable chip
  (`Paste "theverge.com"?`). This is the fast path for the copy/paste flow.
- Manual typing still works. The old "type an exact feed URL" dialog becomes a
  fallback / advanced path — discovery is the default.

### 2. iOS Share Sheet (fast-follow, iOS-specific)

"Share → NewsReader" from Safari or any app that shares a URL. This is the most
frictionless version of the core user story, but it is **not** pure Dart:

- Requires a native iOS **Share Extension** target.
- Requires passing the shared URL into the Flutter app (app group + deep link,
  or a package such as `receive_sharing_intent`).
- On launch/resume with a shared URL, route straight into the discovery flow
  pre-filled with that URL.

Deferred from MVP because of the native setup cost. Tracked as a follow-up.

---

## Detection pipeline

All client-side (`http` for fetch, HTML parsing for `<head>`, and the existing
`RssNewsSource` parser for validation). Run in order; stop when hits are found.

1. **Normalize input.** Trim; prepend `https://` if no scheme. Fetch the page
   (follow redirects, 15s timeout to match `RssNewsSource._fetchFromFeed`).
2. **Is it already a feed?** Try `RssFeed.parse` / `AtomFeed.parse` on the body
   first (reuse the exact RSS→Atom fallback in `RssNewsSource._fetchFromFeed`).
   If it parses, the user pasted a feed URL directly — done.
3. **`<link>` autodiscovery.** Scan `<head>` for
   `<link rel="alternate" type="application/rss+xml">` and
   `type="application/atom+xml">`. This is the RSS spec's official mechanism and
   most real sites expose it. Resolve relative hrefs against the base URL. Use
   the `title` attribute as a candidate feed name.
4. **`<a>` href heuristics.** Scan anchors whose href contains `feed`, `rss`,
   `atom`, or `.xml`. Catches sites that link a feed in the footer without a
   `<link>` declaration.
5. **Common-path probing.** If still nothing, probe a short list against the
   **origin** (not the pasted path): `/feed`, `/rss`, `/feed.xml`, `/rss.xml`,
   `/atom.xml`, `/index.xml`, `/feed/`. Fire in parallel (`Future.wait`, like the
   existing multi-feed fetch), keep the ones that parse.

**Validation.** Every candidate is fetched + parsed via `RssNewsSource` so a URL
that 404s or returns HTML is discarded. Dedupe by URL against other candidates
**and** against feeds already in `FeedConfigRepository` (mark those "already
added").

---

## Return model

```dart
class DiscoveredFeed {
  final String url;          // resolved, absolute feed URL
  final String name;         // <link title>, else feed's own <title>
  final List<String> sampleTitles; // top 1–2 article titles from validation
  final bool alreadyAdded;   // already in FeedConfigRepository
}
```

The discovery service takes a raw string and returns `List<DiscoveredFeed>`.

---

## UI / UX

- Results list: each row shows the resolved **feed name**, the URL, and a **live
  preview** (top 1–2 article titles from the validating fetch) so the user
  recognizes the feed before committing.
- One tap adds via the existing `addFeed(url, name)` path with the current
  enabled-by-default behavior.
- Rows for feeds already present are marked and disabled.
- Explicit states for **"no feed found at that address"** and **network error**
  (both are normal outcomes, not failures to hide).

---

## Code layout

- `lib/services/feed_discovery_service.dart` — new. Raw string in,
  `List<DiscoveredFeed>` out. Composes `http` for HTML fetch and reuses
  `RssNewsSource` for validation, so no parsing logic is duplicated.
- HTML `<head>` scanning — use the `html` package (`querySelectorAll`). Already
  in the tree transitively via `flutter_html`; promote to a direct dependency.
  Pin to the **exact** resolved version (`html: 2.0.1`, no caret range) to match
  the repo's dependency-pinning policy (commit `eec2289`) — pinned for security /
  reproducible builds. See resolved decision 1.
- UI — new discovery screen/sheet wired into `settings_screen.dart` alongside
  `_showAddFeedDialog`.
- Provider — reuse `feedConfigProvider` / its notifier for the actual add.
  Discovery itself can be local screen state (one-shot action) or a
  `FutureProvider.family` keyed on the input string.

---

## Edge cases

- **Article URL, not homepage.** Autodiscovery `<link>` tags usually still live
  in an article page's `<head>`, so it works. Common-path probing must use the
  **origin**, not the full article path.
- **Multiple feeds on one site** (per-category, comments feeds). Show all and let
  the user pick (resolved decision 2).
- **JS-only / paywalled sites** that inject `<link>` client-side. Autodiscovery
  finds nothing; common-path probe is the safety net, then a graceful
  "couldn't find a feed."
- **Name collisions** with the user's existing custom feed names.

---

## Resolved decisions

1. **HTML parsing → use the `html` package** (proper DOM parse via
   `querySelectorAll`), not a regex. The package is **already in the dependency
   tree** (transitive via `flutter_html`, v2.0.1), so this adds no bundle weight —
   it only promotes it to a direct dependency in `pubspec.yaml`. Regex-on-HTML is
   fragile against real-world markup (attribute order, unquoted values, multiline
   tags, commented-out `<link>`s) and scales badly once we also scan `<a>` tags,
   which the DOM query handles cleanly.
2. **Surface all discovered feeds**, not just the primary one. A site may expose
   per-category or comments feeds; show them all and let the user pick. Dedupe by
   URL and mark any already in `FeedConfigRepository` as "already added".
3. **Sit beside the existing add-feed dialog, don't replace it.** Add a separate
   **"Discover"** action next to "Add Feed" in `settings_screen.dart`. Manual
   exact-URL entry stays as-is for power users.

---

## Out of scope

- Email newsletters.
- Keyword / topic search ("feeds about home espresso") — no free public RSS
  search API; would need a backend. Possible future work, separate from this.
- Bundled interest catalog (see `SUGGESTED_FEEDS.md`) — complementary but
  separate.

---

## Implementation notes (2026-07-08)

- `lib/services/feed_discovery_service.dart` — `FeedDiscoveryService.discover()`
  and the `DiscoveredFeed` / `FeedDiscoveryException` types. Page fetch (`http`)
  and feed validation (`FeedFetcher`, default = `RssNewsSource`) are both
  injectable for offline unit tests.
- `lib/screens/feed_discovery_screen.dart` — paste field with clipboard
  pre-fill, results list, add/added/empty/error states.
- `settings_screen.dart` — "Discover" action added beside "Add Feed".
- `pubspec.yaml` — `html: 0.15.6` (pinned exact).
- Tests: `test/services/feed_discovery_service_test.dart` — 10 offline cases
  (link autodiscovery, title fallback, multiple feeds, feed-as-input, common
  path probe, bogus-anchor-doesn't-suppress-probe, empty, already-added, bad
  input, unreachable host). All mocked; no network in CI.

### Pipeline detail worth remembering

Common-path probing is gated on "no feed found via the page" (validated `<link>`
or feed-as-input), **not** on "no candidates". A low-confidence `<a>` anchor
(e.g. an HTML `/rss-feeds/` index) must not suppress probing. Probe paths are
aliases of one feed, so only the first that validates is kept.

### Known limitation surfaced during testing

Validation requires the feed to yield ≥1 article, which also means discovery
depends on the app's own Atom parser. That parser has a **pre-existing bug**:
`RssNewsSource._parseAtomFeed` reads `entry.links?.firstOrNull?.href`, which is
null for some real Atom feeds (e.g. The Verge — a *built-in* feed), so every
entry is skipped and the feed yields 0 articles. Such feeds currently can't be
discovered (and don't render in the app either). Tracked separately.

## Future follow-ups

- Fix the pre-existing Atom `entry.links` parsing bug in `RssNewsSource`
  (affects the built-in The Verge feed).
- iOS Share Sheet entry point (native Share Extension) — entry point #2 above.
- Android equivalent (`ACTION_SEND` intent filter) for parity.
