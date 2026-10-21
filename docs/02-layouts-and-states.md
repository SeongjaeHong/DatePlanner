# 02 – Responsive layouts and states

One Flutter codebase, one adaptive shell. Layout is chosen by **window width**, not platform, so Android phones and mobile web share the same compact layout.

| Class | Width (dp/CSS px) | Used by | Navigation | Panes |
|---|---|---|---|---|
| Compact | < 600 | Android app, Android mobile web | Bottom navigation bar (3 items) | 1 (push routes) |
| Medium | 600–1023 | Android tablets/landscape, narrow desktop window | Navigation rail | 1–2 |
| Expanded | ≥ 1024 | Desktop web | Left sidebar with labels | 2–3 |

Platform adapters (not layout forks) handle: file save/share (Android Storage Access/share sheet vs browser download), photo add (camera/gallery/file picker/paste — decided, doc 04 §6), opening Directions (Android intent/URL vs new browser tab), back behavior.

## 1. Desktop web (planning/editing) — Expanded

```
┌────────┬─────────────────────┬────────────────────────────────────┬───────────────────┐
│ Sidebar│ Plans list (pane 1) │ Plan (pane 2)                       │ Inspector (pane 3)│
│ Plans  │ [+ New plan]        │ Breadcrumb  Plans › Berlin weekend  │ Context-sensitive:│
│ Calendar│ ▸ Next up card     │ Title · dates · status chip · ⋯     │ • card editor     │
│ Space  │ ▸ Berlin weekend ●  │ Tabs: Itinerary | Travel & Stay     │ • expanded map    │
│        │ ▸ Seoul visit       │ ┌ Days ─┐ ┌ Day feed ─────────────┐ │ • PDF preview     │
│ ─────  │ ▸ …                 │ │Fri 12 │ │ [+ Add card]           │ │ • booking details │
│ ⓘ sync │                     │ │Sat 13●│ │ ⠿ Card  Card  Card …   │ │ Close ✕ returns to│
│ user ▾ │                     │ │Sun 14 │ │ drag handle + Move ▲▼  │ │ the plan view     │
└────────┴─────────────────────┴────────────────────────────────────┴───────────────────┘
```
* Pane 1 collapses to an icon list at < 1200 px; pane 3 becomes a modal side sheet at < 1200 px.
* Editing is in place in the inspector so the feed stays visible; keyboard: Tab order follows reading order, `Esc` closes inspector, visible focus ring, drag-reorder has a keyboard/menu alternative (*Move up / Move down / Move to day…*).
* Expand Map opens in pane 3 (or large dialog) — it never navigates away. Directions is a separate button that opens a new tab/external app.
* PDF preview opens in pane 3 with page navigation and zoom; header holds **Download original** (separate from preview).

## 2. Android app (use while traveling) — Compact
```
┌──────────────────────────┐   Plans home                    Plan                           Card / PDF (full screen)
│ Plans              ⚙     │   ┌─────────────┐                 ┌─────────────┐                 ┌─────────────┐
│ ┌ Next up ────────────┐  │   │ ← Berlin  ⋯ │                 │ ← Day 2     │                 │ ← Ticket.pdf│
│ │ Berlin · in 3 days   │  │   │ Dec 20–22   │                 │ Place map   │                 │ [preview]   │
│ │ [Tickets & stay]     │  │   │ Itinerary ▏Travel & Stay│    │ [Expand Map]│                 │ ‹ 1/2 ›  ＋－│
│ └──────────────────────┘  │   │ Fri│Sat│Sun  (chips)    │    │ [Directions]│                 │ ⬇ Download  │
│ ▸ Seoul visit            │   │ Card · Card · Card       │    └─────────────┘                 │   original  │
│                  [＋ New]│   │                    [＋]  │                                    └─────────────┘
│ Plans │ Calendar │ Space │   │ Plans │ Calendar │ Space │
└──────────────────────────┘
```
* Priority on **read speed**: "Next up" card, large touch targets (≥ 48 dp), booking references/times at body-large size, *Tickets & stay* reachable in ≤ 2 taps from app launch.
* Editing works but uses full-screen routes/bottom sheets; drag-reorder via long-press handle plus *Move up/down* menu.
* System Back pops the route stack; Android-only extras (share sheet, SAF save) are adapters.

## 3. Android mobile web — Compact
Same layout and routes as the Android app. Differences, handled by adapters/CSS only: browser Back/Forward/reload must restore the same route (URL-addressable, doc 01 §2); no hover-only controls; respect safe-area/virtual-keyboard insets; download uses the browser; no assumption of app-install features. Installability (PWA) is **not decided** (U-10).

## 4. State model (applies to every list/detail screen)
Every data screen implements all four states with shared components (doc 03 §6). "Populated" is the only state that shows user data.

| Screen | Loading | Empty | Error | Populated |
|---|---|---|---|---|
| Plans | 3 skeleton plan cards | "No plans yet" + **New plan**; invite banner shown | Retry-able banner + **Retry**; cached list not assumed | Plan cards sorted: in progress, upcoming (soonest first), past |
| Plan / Itinerary | Header + day chips skeleton | Per day: "Nothing planned for this day" + **Add card** | "Couldn't load this plan" + **Retry**, **Back to Plans**; 404/403 → not-found-or-no-access | Ordered feed |
| Card editor | Field skeleton | Optional parts shown as "+ Add text / photo / place" | Save failure keeps edits in the form, inline error + **Retry**; conflict dialog (doc 04 §7) | Filled form |
| Place block | Map placeholder with spinner | No place → "+ Add place" | Map failed → static place name/address + **Retry map**; **Directions** still works if coordinates exist | Mini-map, Expand Map, Directions |
| Travel & Stay | Skeleton rows | "No transport or stay saved" + **Add transport** / **Add stay** | Retry | Booking cards with attachment count |
| Attachments on booking | Tile skeleton | "No files attached" + **Attach PDF** | Upload failure per file, retry/remove, original untouched | PDF tiles (name, size, uploaded by) |
| PDF preview | Page skeleton with progress | – | "Couldn't open preview" + **Retry** + **Download original** (if authorized) ; "Access expired – reloading" auto-refetch once; 403 → no-access | Rendered pages |
| Calendar | Month skeleton | "Nothing scheduled" + **New plan** | Retry | Spans + timed travel markers |
| Space | Skeleton | One member: "Invite your partner" | Retry | Two members, invite status |
| Leave / delete account | Spinner while counts load | – | Failure keeps state, shows code + **Retry** (same operation id) | Consequence text, counts, typed confirmation when last member |
| Join review | Spinner while fetching counts | – | Invalid/expired/used/full → specific localized message, no hint about which Space | Disclosure + counts |

Cross-cutting: offline/connection loss shows a persistent "Not connected" banner; edits are **not** queued silently in the initial scope (offline editing is U-09/later). Save indicator (`Saving…`/`Saved`/`Not saved – retry`) is visible on every editor.

## 5. Unfinished destinations (not presented as working)
* Registry `FeatureStatus { working, preview, unfinished }` drives every navigation entry.
* `unfinished`: entry is visible only where a slot is reserved, carries a **"Not available yet"** chip, is not a primary action, and opens a standard `UnfinishedDestination` screen: icon, name, one-sentence description of the future feature, status chip, **Back** button. No fake data, no disabled-looking forms.
* `preview` (screen with sample data, used only during early stages): persistent top banner **"Preview – sample data, not saved"**; sample data is never written to Supabase and never mixed with real records.
* Each stage report lists every destination as WORKING / PREVIEW / UNFINISHED.
