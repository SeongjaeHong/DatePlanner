# 05 – Safe, retryable connection of two one-member Spaces

## 1. Scenario
Each person may have signed in and started planning, so **two one-member Spaces (A = inviter's, B = invitee's) may both hold plans, photos, bookings, and PDFs.** When the invitee joins with A's code, the result must be one Space with two members where *all* of both people's records and files are visible/editable by both — with no loss, no duplication, and no silent deletion.

Cases: (1) invitee has no Space → simply added to A. (2) B empty → merge is trivial. (3) B and/or A have content → full merge below. (4) B already has two members, or A already has two members → rejected (§5).

## 2. Design decision: re-parent, never copy or move files
* The surviving Space is **A** (the Space that issued the code). B's rows keep their **same ids**; only `space_id` changes (UPDATE, not INSERT/DELETE). This is a *membership/ownership reassignment of existing records*; no plan, booking, or attachment record is recreated.
* Storage objects are **not touched**: their paths contain no `space_id` and access is resolved through the `attachments` row (doc 04 §2.2). So no file is copied, moved, renamed, or re-uploaded.
* B is kept as a tombstone (`status='merged'`, `merged_into=A`, zero members) — **not deleted.**
* **Confirmed (U-02A, project owner: yes):** re-pointing `space_id` on the same rows is acceptable under the spec's "no relocation" wording.

## 3. Disclosure (pre-confirmation) — requirement
### 3.1 Inviter, at code creation
Must acknowledge: *"Everything in this Space — every Date Plan, activity, place, photo, booking detail and PDF, existing and future — will be visible and editable by the person who joins. If they already have their own plans or files, those will be added to this Space and become visible to you too."* Confirmation required before a code is generated. **No second approval step** is required when the partner later joins with existing plans (U-02B, decided).

### 3.2 Invitee, review screen (before any change)
Fetched via `preview_invitation(code)` — returns **only**: inviter display name and **counts** (plans, files) for A and for the invitee's own Space B. Titles/contents of A are not revealed before confirmation.
Text (l10n keys `join_review_*`, versioned as `disclosure_version`):
> **Before you join** — Joining connects your Space with *{inviterName}'s*. **Both of you will be able to see and edit everything in both Spaces:** all Date Plans, days, activities, places, photos, booking details and PDF files — the ones that exist now (your {myPlanCount} plans, {myFileCount} files and their {theirPlanCount} plans, {theirFileCount} files) and everything added later.
> Joining deletes and copies nothing. **If either of you later leaves the Space, the person who leaves loses access to all plans and files — including ones they created — and the other person keeps everything. If both of you leave, everything is permanently deleted.**
> ☐ I understand that both of us will see and be able to edit all plans and files. **[Join]**  [Cancel]

Join button is disabled until the checkbox is ticked. Cancel changes nothing.

## 4. Two-phase, idempotent protocol
All steps are server functions (`SECURITY DEFINER`, fixed `search_path`, `authenticated` only). The client generates `operation_id` (uuid) once per attempt series and reuses it on every retry.

**Phase 1 – `prepare_join(code, operation_id)`** (committed, no data moved)
1. Verify code (constant-time compare of hash), status `pending`, not expired/revoked; rate-limit failed attempts per user/IP; never log the code.
2. Validate preconditions (§5) *without* locks needed for decision-making; record `space_merge_operations` row `prepared` with `counts_before`, `disclosure_version`.
3. Return counts + current `disclosure_version` to render §3.2. Repeat calls with the same `operation_id` return the same operation.

**Phase 2 – `confirm_join(operation_id, disclosure_version)`** (one transaction)
1. Authorize: `auth.uid()` = operation `actor_user_id`; `disclosure_version` equals the one displayed (otherwise `DISCLOSURE_CHANGED`, nothing happens).
2. If operation already `completed` → return the stored result (idempotent success).
3. Lock `spaces` rows **A and B in ascending id order** (`FOR UPDATE`) to avoid deadlocks and serialize concurrent merges/joins.
4. Re-check under lock: invitation still `pending` and valid; A has exactly 1 member (the inviter) and is `active`; B (if any) is `active`, has exactly 1 member = the invitee; A ≠ B; invitee not already in A. Business-rule failures return an error code and record `rejected` (no data change); unexpected errors raise → whole transaction rolls back.
5. For every table in the **Space-owned table list** run `UPDATE … SET space_id = A WHERE space_id = B` (same ids). Deferred constraints allow parent/child updates in any order.
6. Membership: delete invitee's `space_members` row for B; insert invitee into A as `member` (trigger re-checks ≤ 2 under the lock; `user_id` UNIQUE guarantees no double membership).
7. Mark B `merged`, `merged_into = A`; revoke B's pending invitations; mark invitation `accepted` (`accepted_by`, time).
8. **Invariant checks inside the transaction** (any mismatch ⇒ raise ⇒ rollback): per table, `count(A after) = count(A before) + count(B before)`; no id appears twice; count of `attachments` rows unchanged overall; no row left with `space_id = B`. Store `counts_moved`.
9. Mark operation `completed`; commit.

The Space-owned table list is read from the catalog (every public table with a `space_id` column, excluding `spaces`, `space_members`, `space_invitations`, `space_merge_operations`); a test fails if a new Space-owned table is not handled, preventing a forgotten table from being stranded in B.

## 5. Server-side two-member limit and rejection cases
Defense in depth: (a) `space_members.user_id` UNIQUE; (b) `BEFORE INSERT` trigger locks the `spaces` row and rejects a third member; (c) both functions re-check under the lock; (d) no client-writable membership path. Error codes (localized client-side): `INVITE_INVALID` (covers wrong/used/revoked/expired — one code to avoid probing), `SPACE_FULL`, `ALREADY_IN_TWO_PERSON_SPACE`, `SAME_SPACE`, `DISCLOSURE_CHANGED`, `NOT_AUTHORIZED`, `RATE_LIMITED`.

## 6. Recovery and retry
| Failure point | Result | Recovery |
|---|---|---|
| Network drops before/while Phase 2 | Transaction either committed or rolled back — never partial | Client retries `confirm_join` with the **same** `operation_id`; returns success if already completed |
| App killed after pressing Join | Same | On launch, `get_my_join_operation()` shows "Finishing…" / result; user is never left in limbo |
| Unexpected DB error / invariant mismatch | Full rollback; A and B unchanged; operation stays `prepared` | Retry is safe; error is shown with code; no cleanup needed |
| Both people redeem each other's codes simultaneously | Ordered locks ⇒ one wins; the loser gets `INVITE_INVALID`/`ALREADY_IN_TWO_PERSON_SPACE` | No data change for the loser |
| Third person uses the code | `SPACE_FULL`/`INVITE_INVALID` | – |
| Upload in flight during merge | `attachments` row (pending) is re-parented like any row; object path unaffected | Upload finalizes normally |
| Stale client still holding space B ids | RLS denies (no membership in B) | Client refetches Space and routes to Plans |

## 7. Related files
* Same `attachments` ids, same storage objects, same paths; zero copies, zero duplicate records (tested by comparing id sets and `storage.objects` names before/after).
* PDF preview/download keeps working through the same access function; no URLs issued before the merge are relied upon.

## 8. Deletion policy (decided) and what remains open
Joining itself deletes nothing. Invitation codes expire seven days after creation and can be revoked; expired codes cannot be redeemed. Leaving, last-member deletion and account deletion follow the rules in doc 04 §5 (decided by the project owner). The disclosure text above is `disclosure_version` 2 and must match doc 04 §5 exactly; any policy change bumps the version. Decided: no export before leaving, deletion at once with a backups note. Soft-deleted items and failed-upload data are not automatically purged inside an active Space (U-07).
