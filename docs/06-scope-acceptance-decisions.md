# 06 – Scope, acceptance criteria, unresolved decisions

## 1. Scope
| Area | Initial app | Needs external setup / cost / privacy decision |
|---|---|---|
| Auth, Space, invite, join/merge | Yes | Supabase project + auth provider + SMTP for production e-mail (account creation needs explicit request) |
| Plans, days, cards, reorder | Yes | – |
| Places + mini-map + Expand Map | Yes (manual name/address/coords) | **Map tile provider** (key/billing/usage policy) – U-03 |
| Place search / geocoding | No | Paid/rate-limited API – later |
| Directions | Yes: opens external app/URL with coordinates | Link format decision U-03 |
| Transport/accommodation records | Yes | – |
| PDF attach, in-app preview, original download | Yes (≤ 3 MiB) | Renderer selected: `pdfrx` (MIT; Android/Web PDFium) |
| Photos on cards | Yes (private): picker, camera, paste; on-device compression to 3 MiB | Paste on mobile web unverified; thumbnails U-08 |
| In-app calendar | Yes | – |
| German | Infrastructure only | Translation content later |
| Offline tickets / offline editing | No | Device-storage privacy decision U-09 |
| External personal-calendar access | **Proposal only** – not built | OAuth, scopes, per-person opt-in, never auto-shared; privacy decision |
| Public-holiday layer | **Proposal only** – not built | Data source, per-person country choice, possibly external API |
| Push notifications | No | FCM setup |
| Deploy / app-store / signing | No | Explicit user request |

## 2. Proposed stage order (user chooses; each stage = one request, then stop)
S1 Shell, navigation, visual system, l10n scaffold, **preview-mode** screens (clearly labelled) · S2 Supabase schema + RLS + auth (needs explicit permission to create/connect project) · S3 Space, invitation, join/merge · S4 Plans/days/cards/reorder · S5 Places/map/directions · S6 Bookings · S7 Attachments (PDF + photos) · S8 Calendar · S9 hardening, German-readiness, accessibility audit.

## 3. Acceptance criteria
Verification: **A** = automated test, **M** = manual (desktop web / Android app / Android mobile web each recorded PASS/FAIL/NOT RUN).

### Shell & visual system (S1)
* AC-S1-1 (A,M) Navigation shows exactly Plans/Calendar/Space; bottom bar < 600, rail 600–1023, sidebar ≥ 1024; no overflow at 360×640, 768×1024, 1440×900.
* AC-S1-2 (A) No hex colors, magic sizes, or widget string literals outside token/ARB files (scan test).
* AC-S1-3 (A) Contrast test over every token pair ≥ thresholds in doc 03; touch-target test ≥ 48 dp on compact.
* AC-S1-4 (A) Every data screen has loading/empty/error/populated widget tests, using shared components.
* AC-S1-5 (M) Unbuilt destinations show "Not available yet" and no fake data; preview screens show the preview banner; stage report lists each destination WORKING/PREVIEW/UNFINISHED.
* AC-S1-6 (A) Pseudo-locale and 200 % text scale render without clipped text.

### Auth & Space (S2–S3)
* AC-S3-1 (A, DB) A non-member cannot SELECT/INSERT/UPDATE/DELETE any Space-owned row, nor read any storage object, nor obtain a signed URL (tested with two users in different Spaces and an anonymous client).
* AC-S3-2 (A, DB) A third `space_members` insert is rejected via every path (direct, function, concurrent race of two transactions).
* AC-S3-3 (A, DB) Invitation: code is never stored/logged in clear (grep of logs/schema); reuse, revoked, expired, wrong code all return `INVITE_INVALID`; attempts are rate-limited.
* AC-S3-4 (M) Review screen appears before any change; Join disabled until acknowledged; Cancel leaves both Spaces byte-identical.
* AC-S3-5 (A, DB) Merge with plans+photos+PDFs on both sides: all ids preserved, counts A+B = A', zero duplicates, `storage.objects` names unchanged, no row with `space_id=B`, B tombstone exists, nothing deleted.
* AC-S3-6 (A, DB) Idempotency: `confirm_join` repeated with same `operation_id` returns success and changes nothing; forced failure mid-transaction leaves A and B unchanged and retry succeeds.
* AC-S3-7 (A, DB) Simultaneous mutual redemption and two redeemers of one code: exactly one outcome, no deadlock, no partial state.
* AC-S3-8 (A) Static check: every public table with `space_id` is covered by the merge list.
* AC-S3-9 (M) After join both users see all plans/files created before joining and can edit them.

### Plans, cards, ordering (S4)
* AC-S4-1 (A,M) Creating a plan with dates D1–D2 creates exactly one day per date; stored as `date` values; changing device time zone never changes displayed dates.
* AC-S4-2 (A) Shortening dates with cards on dropped days is blocked with a message.
* AC-S4-3 (A, DB) Two clients reorder/insert concurrently: no card lost, order deterministic, identical on both after refresh.
* AC-S4-4 (A) Concurrent edit of the same card shows ConflictDialog; no silent overwrite. Edit-vs-remove offers Restore.
* AC-S4-5 (M) Reorder possible by drag **and** by Move up/down menu on all three platforms.
* AC-S4-6 (A) Card with only text, only photo, only place, and with none of the parts (e.g. travel) all save and render.

### Places & directions (S5)
* AC-S5-1 (M) Place shows a small map; **Expand Map** enlarges in-app with no external navigation; **Directions** opens external navigation; the two are separate controls.
* AC-S5-2 (M) If the map provider is not configured, the UI states "Map not available" – no fake map; stage report marks integration NOT RUN/FAIL honestly.

### Bookings (S6)
* AC-S6-1 (A) Transport segment stores instant + IANA zone for both ends; displayed wall times match the stored zones under viewer zones UTC−10 and UTC+14.
* AC-S6-2 (A) DST-gap and DST-overlap entries prompt instead of silently shifting.
* AC-S6-3 (A) Accommodation check-in/out are dates; a Seoul→Berlin overnight itinerary keeps the card on its chosen day.

### Attachments (S7)
* AC-S7-1 (A, DB) Bucket is private; unauthenticated URL access to an object path fails; member signed URL works; non-member gets 403.
* AC-S7-2 (M) Tapping a PDF renders it in-app **without** a download/save step first (verify no file written, no browser download event), on all three platforms.
* AC-S7-3 (M) **Download/Save original** is a separate control; saved file's SHA-256 equals the uploaded file's.
* AC-S7-4 (A) Non-PDF or renamed non-PDF upload rejected; a PDF over 3 MiB is blocked before upload with a size message, creates no record, and a direct API upload over 3 MiB is rejected by Storage; failed upload is retryable and doesn't create a "ready" record.
* AC-S7-5 (A) Signed URLs/tokens never appear in logs or error reports (log-capture test).
* AC-S7-6 (A) Expired URL triggers one transparent re-fetch then a retryable error.

### Calendar (S8)
* AC-S8-1 (A,M) Plan periods render as all-day spans from dates; travel times as timed markers in their own zone with zone label.
* AC-S8-2 (A) No external-calendar API call, token, or UI exists in the build.
* AC-S8-3 (M) Tapping a span/marker opens the correct plan/booking; Back returns to Calendar.

### Photos (S7)
* AC-P-1 (A) A JPEG ≤ 3 MiB without GPS metadata is stored unchanged (hash equal). Other accepted image formats are converted to JPEG and GPS metadata is removed. Photo > 3 MiB is compressed to ≤ 3 MiB with orientation preserved and a "compressed" notice shown; an image that cannot reach 3 MiB is rejected; a direct upload > 3 MiB is rejected server-side.
* AC-P-2 (M) Multi-select pick and camera work on Android app; each platform's **copy & paste** is verified separately and recorded PASS/FAIL/NOT RUN (desktop web, Android app, Android mobile web); no platform is claimed without a test.
* AC-P-3 (A) Undecodable or unsupported files give a localized error and create no record.

### Leaving and deletion (S3)
* AC-L-1 (A, DB) Leave with 2 members: leaver's membership removed, leaver fails every read/write/signed-URL check immediately; partner sees all rows and files with unchanged ids; leaver's items show "Former member"; leaver's pending invitations revoked.
* AC-L-2 (A, DB) Last member leaves: zero rows with that `space_id` in every Space-owned table (incl. soft-deleted, tombstones, invitations), `file_deletion_queue` drained and **no** storage object remains; queue survives a forced failure and retries.
* AC-L-3 (A) `expected_member_count` mismatch (simultaneous leave) changes nothing and demands re-confirmation; the second leaver is then shown the last-member confirmation.
* AC-L-4 (A, DB) Repeating `leave_space` with the same `operation_id` is a no-op success; no partial state on forced failure.
* AC-L-5 (A, DB) Account deletion: profile and auth user gone; shared data survives if a partner remains, is deleted if not; failure between steps is retryable.
* AC-L-6 (M) Leave and last-member screens state the real consequences; typing the confirmation word is required for last-member/account deletion. The disclosure text (version 2) is tested to contain the leave/delete statements.

### Cross-cutting
* AC-X-1 No secret, usable invitation code, or real booking data in repo (secret-scan + fixtures review).
* AC-X-2 Every stage report lists changed files, commands run with results, platform PASS/FAIL/NOT RUN, blockers, unresolved decisions — then stops.

## 4. Decisions made by the project owner (2026-10-10)
| ID | Decision |
|---|---|
| U-02A | Re-pointing `space_id` on the same rows during a Space merge is acceptable (no copies, same ids, no file moves) |
| U-02B | No extra approval step for the inviter when the invitee joins with existing plans |
| U-13 | Leaving: the leaver loses the data; when both have left nobody owns it; ownerless data is permanently deleted. Account deletion removes the profile only; Space data is deleted only if it has no owner |
| U-12 | Photo defaults (pick, camera, multi-select); max 3 MB; larger photos are compressed; copy & paste supported |
| U-16 | 3 MB = 3 MiB (3,145,728 bytes) for photos and PDFs |
| U-17 | No export of data before leaving a Space |
| U-18 | Permanent deletion happens at once; no grace period (backups note shown) |
| U-19 | Photo input: JPEG, PNG, WebP, HEIC, BMP; converted to JPEG before upload; GPS not needed (removed) |
| U-20 | Remaining member becomes owner after a leave |
| U-06 (part) | PDFs ≤ 3 MB, otherwise the upload is refused (no compression). The 300-second URL lifetime and continuing member access are specified in §6. |
| Space provisioning | On the first authenticated app launch, call the idempotent server RPC to ensure the user has a one-member Space. An invitee's existing Space is merged into the inviter's Space only after the invitee reviews the sharing disclosure and confirms joining. |

## 5. Unresolved decisions
| ID | Decision | Notes / proposed default (not adopted) |
|---|---|---|
| U-01 | Auth method & account recovery | E-mail magic link vs password vs Google |
| U-03 | Map provider; directions link format | Cost/licence/key handling; PDF renderer is selected in §4 |
| U-04 | Invitation expiry, revocation, regeneration | Proposed: single use, revocable; expiry length open |
| U-05 | Code entry: manual only vs fragment link | Never path/query |
| U-07 | Retention/purge of soft-deleted items in a live Space and files of failed uploads | Nothing auto-deleted until decided |
| U-08 | Photo thumbnails (paid image transforms vs on-device) | Compression itself is decided |
| U-09 | Offline access to tickets / device caching | Opt-in per file proposed |
| U-10 | PWA/installable mobile web | Not assumed |
| U-11 | Which date is "today" for plan status | Proposed: viewer's device date |
| U-14 | Exact booking fields beyond those proposed | Spec leaves open |
| U-15 | Dark theme in initial scope? | Tokens defined |

Note: maximum photos per card is not set (proposed: no limit); HEIC support per platform is verified at S7.

## 6. Additional implementation decisions (2026-10-11)
| ID | Decision |
|---|---|
| U-03 (PDF part) | Use `pdfrx` (MIT) for Android app, desktop web, and Android mobile web. It uses PDFium natively and PDFium WASM on web; it does not require loading the viewer from a third-party CDN. This is a risk-based selection, not a guarantee that the dependency has no vulnerabilities. Keep it updated and review dependency/security advisories. |
| U-06 | Supabase private-storage signed URLs expire 300 seconds (5 minutes) after each issuance. This limits one delivery link only: while a user remains a member and the file remains in the Space, the app can issue a fresh link after checking membership, so the user's access does not expire. On link expiry, request a fresh URL once and retry; if that retry fails, show a retryable error. A URL is a temporary bearer link, so never put it in routes, logs, or persistent storage. When membership is removed, no new link may be issued; an already-issued link may remain usable until its own expiry. |
