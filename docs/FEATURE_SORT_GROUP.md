# Feature Design: Article Grouping & Sorting

**Status**: Approved — implementation in progress  
**Date**: 2026-04-22  
**Branch target**: `claude/sort-group-articles`

---

## Summary

Add a fourth action button to the `FeedScreen` AppBar that lets the user choose how the article list is organized. The existing default (reverse-chronological) stays as-is; two new modes — **By Source** and **By Topic** — are added.

---

## UI Change: New AppBar Button

### Button placement

Current order:

```
[Refresh] [Bookmarks] [Settings]
```

New order:

```
[Refresh] [Sort/Group] [Bookmarks] [Settings]
```

### Icon

**Recommended: `Icons.sort`** — universally understood as "change list order/grouping". Alternatives considered:

| Icon | Material name | Notes |
|------|---------------|-------|
| `Icons.sort` | Sort | ✅ Clear, compact, standard |
| `Icons.tune` | Tune | Works, but implies broader filter controls |
| `Icons.filter_list` | Filter list | Implies filtering (hiding items), not organizing |
| `Icons.view_agenda` | View agenda | Too specific to calendar metaphor |
| `Icons.dashboard_customize` | Dashboard customize | Too wide in meaning |

`Icons.sort` wins — it reads immediately as "change how this list is ordered."

### Interaction

Tapping the button opens a **`showModalBottomSheet`** (consistent with the existing bookmarks sheet pattern in `FeedScreen`). The sheet presents three options as a `ListTile` radio group. The active selection has a filled radio indicator and is highlighted. Selecting an option dismisses the sheet and instantly reorders the list.

The button itself shows a **filled variant** (`Icons.sort` with a tinted color from `ColorScheme.primary`) when any non-default mode is active, so the user can see at a glance that the list is not in default order.

---

## Grouping / Sorting Modes

### Mode 1 — Chronological (default, current behavior)

All articles in a single flat list, newest first. No change from today's behavior.

No header rows. Scroll position is preserved via the existing `ScrollController`.

---

### Mode 2 — By Source

Articles grouped by `sourceName`, with groups sorted alphabetically. Within each group, articles are newest-first.

Each group is rendered with a **sticky section header** — a slim `SliverPersistentHeader` showing the source name and article count (e.g., `Ars Technica  ·  4`). Headers stick to the top of the viewport as the user scrolls through a group, matching the common behavior users know from contacts lists and email clients.

Implementation note: this requires switching the main `ListView` to a `CustomScrollView` with `SliverList` sections. The existing `ScrollController` carries over.

If the user also has a **feed filter** active (the existing `feedFilterProvider` that filters to one source), "By Source" effectively shows a single group — this is fine and consistent.

---

### Mode 3 — By Topic

Articles grouped into topic buckets. Within each bucket, articles are newest-first. Buckets are sorted by article count (most articles first) so the most active topics appear at the top.

Same sticky-header treatment as By Source.

**Topic methodology is discussed in the next section.**

---

## Topic Grouping: Methodology Options

This is the key design question. The options below are ordered from most practical (no external dependencies) to most powerful (requires a service).

### Option A — RSS Categories (recommended primary strategy)

**How it works**: The `Article` model already has a `categories: List<String>` field populated from `<category>` elements in RSS feeds and `<category term="">` in Atom feeds. This data is parsed today in `rss_news_source.dart` but is not yet surfaced in the UI.

**Strengths**:
- Zero extra computation — data already exists
- Source-provided labels tend to be accurate (e.g., Ars Technica uses "Technology", "Science", "Gaming")
- No internet dependency beyond the existing feed fetch

**Weaknesses**:
- Inconsistent across feeds — one source may tag "AI" while another uses "Artificial Intelligence" or leaves categories blank
- Some feeds (notably Hacker News) provide no categories at all

**Normalization needed**: A lightweight canonicalization map collapses synonyms:

```
"AI" / "Artificial Intelligence" / "Machine Learning" / "ML" → "AI & Machine Learning"
"Security" / "Cybersecurity" / "InfoSec" → "Security"
"Mobile" / "Android" / "iOS" / "Smartphones" → "Mobile"
... etc.
```

This map lives in a Dart const map in a small utility file — no dependencies, easily extended.

---

### Option B — Keyword Taxonomy Matching (recommended fallback)

**How it works**: For articles with no RSS categories (or after normalization leaves them uncategorized), scan `title` + `description` against a predefined set of topic keyword lists.

Example taxonomy for a tech news reader:

| Topic bucket | Keywords to match |
|---|---|
| AI & Machine Learning | ai, llm, gpt, neural, openai, gemini, claude, model, inference |
| Security | hack, breach, vulnerability, ransomware, exploit, malware, phishing, cve |
| Mobile | android, ios, iphone, pixel, samsung, smartphone, app store |
| Hardware | chip, cpu, gpu, processor, nvidia, amd, intel, server, memory, ssd |
| Software & Dev | open source, github, release, update, api, sdk, developer |
| Policy & Law | regulation, lawsuit, ftc, gdpr, antitrust, congress, legislation |
| Science & Space | nasa, space, research, study, physics, biology, quantum |
| Business | acquisition, funding, ipo, earnings, revenue, layoffs, startup |

Matching is case-insensitive substring search — no ML required. An article matching multiple buckets gets assigned to the first (highest-priority) match, or the bucket with the most keyword hits.

**Strengths**:
- Works for all articles regardless of feed quality
- Fully offline, zero latency
- Easily tunable by editing the keyword list

**Weaknesses**:
- Keyword matching is brittle — "Apple earnings" hits "Hardware" if "Apple" is listed there, not "Business"
- Requires ongoing maintenance as news topics evolve

---

### Option C — Combined (A + B together) ✅ Selected

1. Use RSS `categories` as the primary label after normalization.
2. For articles with no usable categories after normalization, fall back to keyword taxonomy (Option B).
3. Articles that match nothing get an **"Other"** bucket, always sorted last.

This gives the best coverage with no external dependencies and no latency cost. The taxonomy will be iterated on over time based on real-world usage.

---

### Option D — Dynamic / Emerging Topics (future enhancement)

**How it works**: After static classification runs (Option C), scan the remaining title corpus for high-frequency named entities — company names, product names, proper nouns — that appear in a significant number of articles (e.g., ≥4 articles mentioning "Apple" or "Tariffs"). Promote these as additional dynamic buckets above the static taxonomy groups.

This addresses a real use case: during a major news cycle (an Apple event, a policy ruling, a specific incident), the most newsworthy entity may not appear in the static taxonomy at all. Dynamic buckets surface it automatically.

**Implementation sketch**:
- After Option C classification, collect all articles still assigned to "Other" plus a scan of all titles
- Count occurrences of capitalized tokens (rough named-entity heuristic) and multi-word phrases after stop-word removal
- Any entity appearing in ≥ N articles (threshold TBD, e.g. 4) becomes a dynamic bucket
- Dynamic buckets sort above "Other" but below static taxonomy buckets (or can be interleaved by count)

**Strengths**:
- Surfaces timely topics that no static list could anticipate
- Fully offline — pure string processing

**Weaknesses**:
- Named-entity detection without an NLP library is imprecise (capitalization heuristic catches "Apple" but also "The")
- Bucket names are raw tokens, not user-friendly labels
- Threshold tuning needed to avoid noise

**Verdict**: Out of scope for v1. Design it as an additive layer on top of Option C so it can be switched on independently later without rearchitecting the classifier.

---

### Options not selected

| Option | Why excluded |
|---|---|
| D — TF-IDF clustering | Group names are unstable across refreshes, confusing for users |
| E — On-device LLM | App size, latency, platform complexity — overkill |
| F — External API | Requires API key, breaks offline use, cost management |

---

## Recommended Approach Summary

| Layer | Strategy |
|---|---|
| Primary | RSS `categories` field, normalized via a const synonym map |
| Fallback | Keyword taxonomy matching on `title` + `description` |
| Catch-all | "Other" bucket for unmatched articles |

This is fully offline, adds no dependencies, uses data already in the model, and produces reasonably stable, readable group names.

---

## State Management

A new lightweight provider holds the active sort/group mode:

```dart
enum ArticleGrouping { chronological, bySource, byTopic }

final articleGroupingProvider = StateProvider<ArticleGrouping>(
  (_) => ArticleGrouping.chronological,
);
```

The grouping logic lives in `FeedScreen` as a derived computation from the existing `articles` list (same pattern as the current feed filter). **No changes to `ArticlesNotifier` or the aggregator** — grouping is a pure presentation concern.

---

## Scope / Out of Scope

| In scope | Out of scope |
|---|---|
| Three grouping modes | Persisting grouping preference across restarts |
| Sticky section headers | Collapsible/expandable groups |
| Normalized RSS category labels | Editing the taxonomy in settings UI |
| Keyword taxonomy fallback | ML-based or API-based classification |
| Button state indicator when non-default active | Per-source grouping customization |
| Search reverts to flat chronological | Grouped search results |
| | Dynamic/emerging topic buckets (future, see Option D above) |

---

## Files Affected

| File | Change |
|---|---|
| `lib/screens/feed_screen.dart` | Add AppBar button, bottom sheet, grouping logic, section headers |
| `lib/providers/feed_provider.dart` | Add `articleGroupingProvider` |
| `lib/services/topic_classifier.dart` *(new)* | Normalization map + keyword taxonomy |

No Hive model changes. No adapter regeneration required.

---

## Decisions

| Question | Decision |
|---|---|
| Bottom sheet vs. popup menu | **Bottom sheet** — consistent with the existing bookmarks sheet |
| Topic methodology | **Option C** (RSS categories + keyword taxonomy fallback). Taxonomy iterated over time based on feedback. |
| Dynamic emerging topics | **Future enhancement** — designed as an additive layer on top of Option C (see Option D above) |
| Persist grouping across restarts | **No** — resets to Chronological each launch (v1) |
| Search + grouping interaction | **Search always reverts to flat chronological** — grouping is suspended while a query is active |