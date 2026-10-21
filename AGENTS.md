# Project instructions

## What we are building

This is a personal planning app for two long-distance or international partners. Meeting in person may require a train or flight and an overnight stay. Instead of coordinating dates in chat and searching for booking screenshots later, the partners can plan a meeting and keep its activities, places, tickets, and accommodation details together.

The app has one Space. A person can sign in and start planning before inviting their partner. When the partner joins by invitation code, both people can see and edit every Date Plan and attachment in the Space, including content created before the invitation. A Space has at most two members.

A Date Plan represents one meeting, possibly across several days. Each day has an ordered feed of Activity Cards for activities and travel segments. A card may contain short text, photos, and a place. Places have a small map, an Expand Map action inside the app, and a separate Directions action for external navigation.

Transport and accommodation are booked elsewhere. This app stores their details and confirmation files. Partners can attach PDF tickets and booking confirmations, preview a PDF inside the app without first downloading it, and separately download or save the original PDF. The in-app calendar shows Date Plan periods and important travel times.

Use one Flutter project for the Android app, desktop web, and Android mobile web. Use Supabase for authentication, shared data, and file storage when the relevant stage is requested. The initial UI is in English. Centralize user-facing strings so German can be added later.

## Working rules

- Read `docs/product-spec.md`, inspect existing files, and review the preceding stage's results before implementing a stage. Work only on the stage explicitly requested by the user. Report its results and stop.
- Before an invited person confirms joining, clearly explain that both people's existing plans and attachments will become visible and editable to each other. Joining must preserve the records and files without loss or duplication. Enforce Space membership and the two-member limit on the server, not only in Flutter.
- Restrict plans, photos, booking records, and PDFs to Space members at the Supabase layer. Do not make storage public merely to implement PDF preview or download.
- Keep calendar dates separate from time-zone-aware travel times. Do not automatically disclose either person's external personal-calendar events to their partner.
- Never put secrets, usable invitation codes, or real booking details in source code, Git, or logs.
- For a user-requested app implementation stage, additive and non-destructive schema migrations may be applied to the Supabase project configured for the app (including its production project) when that stage requires them. Before applying one, inspect the exact migration, verify it is safe to re-run and does not drop or rewrite existing user data, and run the available local database checks first. Report the target project and migration outcome. Ask for separate explicit authorization before destructive/data-rewriting migrations, database resets, creating external accounts, enabling paid APIs or billing, deploying, committing, or pushing.
- Run available builds and tests. Distinguish automated tests from manual browser/device verification. Mark each relevant platform check PASS, FAIL, or NOT RUN; never present a placeholder or mock as a completed integration.
- At the end of each stage, report changed files; commands and tests actually run with their results; verification on desktop web, Android app, and Android mobile web where relevant; blockers and unresolved decisions. Then stop.
- Before adding feature screens, design the complete user journey, navigation, responsive desktop/mobile layouts, and shared visual system. Integrate features into that system; do not create disconnected demo pages or inconsistent screens.
- Make desktop web comfortable for planning and editing. Make the Android app and Android mobile web convenient for checking plans, tickets, and accommodation while traveling.
- For each implementation request, check the connected user journey available at that stage, including navigation and empty, loading, error, and populated states. Clearly identify working features, mockups, and unfinished screens.
