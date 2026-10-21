# 01 – User journey and navigation

## 1. Journey overview

```
Launch ─► Sign in (U-01 method) ─► ensure one-member Space ─► PLANS (home)
                                                                  │
                        partner invitation code ► JOIN ──────────┤
                                                                ▼
PLANS ─► New plan ─► PLAN (Itinerary tab) ─► Day ─► Activity Card (view/edit)
  │                       │                                  └─ Place: mini-map · Expand Map · Directions
  │                       └► Travel & Stay tab ─► Booking ─► PDF preview (in app) ─ Download/Save original
  ├► CALENDAR ─► plan period / travel time ─► back into the PLAN
  └► SPACE ─► Invite partner ─► (partner) JOIN ─► Review disclosure ─► Confirm ─► merged Space
```

### 1.1 Steps in detail
| # | Journey | Key behavior |
|---|---|---|
| J1 | Sign-in → Space | After authentication, the server idempotently ensures the user has a one-member Space and the app opens Plans. A person joining by code already has their own Space; after the disclosure review, confirmation merges that Space into the inviter's Space while preserving rows and storage objects. |
| J2 | Plans list | Lists every Date Plan in the Space (including content created before the partner joined). "Next up" card pins the nearest upcoming/in-progress plan with quick links *Tickets & stay* and *Itinerary*. |
| J3 | Create plan | Title, start date, end date (calendar dates, no time zone). On save the server creates one Day per date. Lands on the new plan's Itinerary with the empty-day state. |
| J4 | Itinerary | Day selector; per-day ordered feed of Activity Cards (Note / Activity / Travel). Add, edit, reorder, remove. |
| J5 | Card | Optional short text, photos, place. Place block shows a small map with **Expand Map** (in-app) and, separately, **Directions** (external navigation). |
| J6 | Travel & Stay | Transport bookings (with segments and time-zone-aware times) and accommodation (check-in/out dates). Each booking lists attached PDFs. |
| J7 | PDF | Tapping a PDF opens an in-app preview immediately (no prior Download). **Download/Save original** is a separate action. |
| J8 | Calendar | Month + agenda. Date Plan periods (all-day spans) and important travel times (timed, labelled with their own zone). |
| J9 | Invitation | See 1.2. Never blocks planning. |
| J10 | Leave / delete account | Space → Settings → *Leave Space* or *Delete account*. Shows exactly what is lost (doc 04 §5); the last-member case lists counts and requires typing a confirmation word. |

### 1.2 Where invitation fits
* **Optional and non-blocking.** Planning works alone. Entry points: (a) dismissible "Invite your partner" banner on Plans, (b) **Space** destination → *Invite partner*.
* **Inviter flow:** Space → Invite partner → read *inviter disclosure* (everything in this Space, now and later, becomes visible/editable by the partner, and the partner's own pre-existing plans, if any, will be added) → confirm → code generated server-side and **shown once**; status "Pending", with *Revoke*.
* **Invitee flow:** signed in → Join with a code → server returns counts only (no titles) → **Review screen with full disclosure** → explicit confirm (checkbox + button, button disabled until checked) → progress → result. Details in doc 05.
* After join: both users see one Space containing all plans; Space screen shows two members.

## 2. Navigation model
Three top-level destinations, identical on every platform: **Plans**, **Calendar**, **Space**.
Account/language/sign-out live under Space → *Settings*.

```
App
├─ (signed out)   /sign-in
├─ /join          code entry → /join/review → /join/result      (full-screen flow, outside the shell)
└─ SHELL (bottom bar on compact · rail/sidebar on medium+)
   ├─ PLANS        /plans
   │   ├─ /plans/new
   │   └─ /plans/:planId                      (plan home = Itinerary tab)
   │       ├─ /plans/:planId/day/:dayId       (day feed; on compact this is a route, on desktop a pane)
   │       │   └─ /plans/:planId/day/:dayId/card/:cardId        (view/edit; place; Expand Map)
   │       ├─ /plans/:planId/travel           (Travel & Stay tab)
   │       │   ├─ /plans/:planId/travel/transport/:bookingId
   │       │   └─ /plans/:planId/travel/stay/:bookingId
   │       ├─ /plans/:planId/file/:attachmentId                 (PDF preview; photo viewer)
   │       └─ /plans/:planId/edit             (title/dates/notes)
   ├─ CALENDAR     /calendar                  (+ ?month=YYYY-MM)
   └─ SPACE        /space
       ├─ /space/invite
       ├─ /space/settings                      (profile, language, sign-out)
       │   ├─ /space/leave
       │   └─ /space/delete-account
       └─ /space/coming-soon/:feature          (UnfinishedDestination, see doc 02 §5)
```

* Deep links use ids only. Invitation codes are **never** placed in a path or query string (they reach server logs and history). If a link form is later wanted, the code goes in the URL fragment and is stripped immediately (U-05).
* Unknown/forbidden plan id → "Plan not found or you don't have access" error state with *Go to Plans* (does not reveal existence).

## 3. Returning to a plan
1. Plans tab is always one tap away; re-tapping it pops to the list root.
2. Desktop: breadcrumb `Plans › <plan title>` in the header; the plan list stays visible as the left pane.
3. Compact: back arrow in the top bar; system Back (Android) and browser Back (mobile web) follow the same route stack.
4. Calendar items and the "Next up" card open `/plans/:planId` (travel items open the booking).
5. Last opened plan id is remembered locally (non-sensitive) to offer "Continue: <title>" on the Plans list; if it is no longer accessible the offer silently disappears.

## 4. Where later features appear (reserved slots, not built)
| Later feature | Slot |
|---|---|
| Checklist / packing / budget / ideas | Extra tab in the plan tab bar after *Travel & Stay* |
| External personal calendar (proposal) | Space → Settings → *Connected calendars* (off by default, per-person, never shared automatically) |
| Public holidays layer (proposal) | Calendar → *Layers* toggle |
| Notifications | Space → Settings |
| Offline tickets (proposal U-09) | Attachment tile menu → *Make available offline* |
| German | Settings → Language (infrastructure exists from day one) |

Unbuilt slots appear only as `UnfinishedDestination` entries (doc 02 §5), never as working-looking UI.
