# Product specification: shared date planning

## 1. Product overview

A private planning app for two long-distance or international partners who need to coordinate an in-person meeting. A meeting may span several days and involve travel, activities, places, tickets, and accommodation. Plans and related files live together in one shared Space so partners can plan together and retrieve booking information later.

Transport and accommodation are booked through external providers. The app records booking details and stores confirmation files; it is not a booking marketplace or payment processor.

## 2. Platforms and localization

- Build one Flutter project that supports the Android app, desktop web, and Android mobile web.
- The initial user interface is English.
- Centralize all user-facing text so German can be added later without rewriting screens.
- Keep responsive layouts usable on desktop and Android-sized screens.

## 3. Accounts, Space, and collaboration

- A person can sign in and create or use the app's single Space, then begin planning before inviting their partner.
- The Space has a maximum of two members.
- The owner invites the partner with an invitation code. Do not expose usable invitation codes in source, Git, or logs.
- Before the invitee confirms joining, show a clear explanation that joining grants both people visibility and edit access to all existing and future Date Plans and attachments in the Space.
- On confirmation, add the invitee to the same Space. Preserve existing records and files without loss or duplication; pre-invitation content must become visible to the new member.
- Both Space members can view and edit every Date Plan and attachment in the Space.
- Enforce membership and the two-member limit on the server. Client-side checks alone are insufficient.
- A non-member must not be able to read or modify Space plans, activity data, photos, booking records, or PDFs.

## 4. Date Plans

- A Date Plan represents one in-person meeting and can cover one or more calendar days.
- Store the meeting's start and end calendar dates as date values, separately from time-zone-aware travel times.
- Each day contains an ordered feed of Activity Cards.
- Members can create, view, edit, reorder, and remove plans and their cards, subject to the shared Space access rules.
- Plans and their related records are visible to both members, including plans created before the partner joined.

## 5. Activity Cards

- Each card represents an activity or travel segment in a day's itinerary.
- A card may contain short text, photos, and a place. These parts are optional so a card can represent, for example, a simple note or a train segment.
- Cards appear in a deliberate, editable order within their day.
- Travel entries can record important travel times with the applicable time-zone context; calendar-day boundaries must not silently shift due to time-zone conversion.
- Photos are private Space attachments and follow the same member-only access rules as other files.

## 6. Places and directions

- A place on a card includes enough location information to identify and display it on a small in-app map.
- Provide an **Expand Map** action that expands the map within the app.
- Provide a separate **Directions** action that opens an external navigation experience. Expanding the map and opening directions are distinct actions.
- Do not represent an unimplemented map or directions integration as complete; disclose placeholders as such during implementation reporting.

## 7. Transport and accommodation records

- Partners book trains, flights, and accommodation elsewhere; the app stores their details and supporting confirmation files.
- Booking records belong to the Space and can be viewed and edited by both members.
- Allow PDF tickets and booking confirmations to be attached to relevant plans or booking records.
- Keep PDFs as original files. Provide a distinct action to download or save the original PDF.
- Provide an in-app PDF preview that can open and render the PDF without requiring the user to download the file first. Previewing must not silently replace, transform, or discard the original.
- Both preview and original-file download/save must be authenticated and restricted to current Space members. Do not make a storage bucket public to implement either capability. Use private storage and an access-controlled delivery mechanism (for example, a short-lived signed URL issued only after authorization, or an authenticated streaming endpoint).
- Preserve attachment associations when the invited partner joins. Joining must not copy files or create duplicate attachment records.

## 8. Calendar

- Provide an in-app calendar showing Date Plan periods and important travel times.
- Calendar dates and time-zone-aware travel times are separate concepts and must be stored/displayed accordingly.
- Do not automatically import or disclose either partner's external personal-calendar events to the other person.

## 9. Data and security requirements

- Use Supabase for authentication, shared data, and file storage when the relevant implementation stage is requested.
- Apply authorization at the Supabase/server layer for Space membership, the two-member limit, and all plan and attachment access.
- Keep photos, booking records, and PDFs private to Space members. Storage must not be public merely to make preview or download convenient.
- Joining a Space must update membership without duplicating or relocating existing plans, records, or files.
- Never place secrets, usable invitation codes, or real booking details in source code, Git, or logs.
- Do not modify a production database, create external accounts, enable paid APIs or billing, deploy, commit, or push without a separate explicit user request.

## 10. Quality and delivery expectations

- Read this specification, inspect existing project files, and review the preceding stage's results before implementing any stage.
- Implement only the stage explicitly requested by the user and stop after reporting that stage.
- Run available builds and tests. Report commands actually run and their results. Distinguish automated tests from manual browser or device verification.
- For each relevant platform—desktop web, Android app, and Android mobile web—mark verification **PASS**, **FAIL**, or **NOT RUN**. Never claim a mock or placeholder is a completed integration.
- At the end of each stage, report changed files, commands and tests with results, relevant platform verification, blockers, and unresolved decisions.

## 10.1 Coherent app experience

- Before adding feature screens, design the complete user journey, navigation, responsive desktop/mobile layouts, and a shared visual system.
- Integrate each feature into the same navigation and visual system. Do not build disconnected demo pages or inconsistent screen designs.
- Make desktop web comfortable for planning and editing. Make the Android app and Android mobile web convenient for checking plans, tickets, and accommodation while traveling.
- For each implementation request, check the connected journey available at that stage, including navigation and empty, loading, error, and populated states.
- Clearly distinguish working features from mockups and unfinished screens.

## 11. Open implementation decisions

The agreed requirements do not prescribe the detailed UI design, navigation deep-link format, exact booking fields, PDF rendering package, file type limits (size limits are fixed in section 12), or account recovery flow. Resolve these as implementation decisions when the relevant stage is requested, without weakening the privacy, membership, file-preservation, or two-member requirements.

## 12. Agreed decisions (design review, 2026-10-10)

12.1 **Space merge.** When an invitee who already has a one-member Space joins, their existing records may be re-pointed to the surviving Space (same record ids, no copies, no file moves). This clarifies "without duplicating or relocating" in sections 3 and 9. No second approval by the inviter is required.

12.2 **Leaving a Space.** A person may leave. The person who leaves loses access to all Space data. The remaining member keeps everything. When both people have left, nobody owns the data and it is deleted permanently.

12.3 **Account deletion.** Deleting an account removes the profile. Space data is deleted only if the Space then has no member.

12.4 **Photos.** Photos can be added by picker, camera, or copy & paste. Maximum stored size is 3 MB. A larger photo is compressed on the device; a photo that cannot be reduced to the limit is rejected.

12.5 **PDFs.** A PDF must not exceed 3 MB; a larger file cannot be uploaded and is never compressed or altered.

12.6 "3 MB" means 3 MiB (3,145,728 bytes), for photos and PDFs.

12.7 Accepted photo formats: JPEG, PNG, WebP, HEIC, BMP. The app may convert photos to another format before upload. GPS location is not needed and is removed.

12.8 There is no data export before leaving. Permanent deletion happens at once, without a grace period. After a leave, the remaining member becomes owner.

12.9 Join disclosure text must state sections 12.2, 12.3 and 12.8 accurately. Other details remain open decisions (see docs/design/06).

12.10 **PDF viewer.** Use the MIT-licensed `pdfrx` Flutter package to render PDFs in the Android app and both web layouts. The package uses PDFium on native platforms and PDFium WASM on web. This selection does not guarantee the absence of vulnerabilities; dependency updates and security advisories must be reviewed.

12.11 **Private-file preview links.** Each signed URL expires after 300 seconds; this is the lifetime of that particular delivery link, not the member's permission. While a user remains a Space member and the file remains in the Space, the app can issue a fresh URL after checking current membership, so their file access continues. On expiry, the app may issue one fresh URL and retry the preview. Signed URLs are temporary bearer links and must not appear in routes, logs, or persistent storage. The Storage bucket remains private. After membership is removed, no new URL may be issued, though a previously issued URL may remain usable until it expires.

12.12 **Map behavior.** Keep the current OpenStreetMap raster map and separate Google Maps Directions action. Do not add map search or geocoding in this stage.

12.13 **Invitation expiry.** Invitation codes are single-use and revocable and expire seven days after creation. Expired invitations cannot be redeemed; a new code may be created.

12.14 **Active-Space retention.** Soft-deleted records and failed-upload data are not automatically purged while their Space is active.
