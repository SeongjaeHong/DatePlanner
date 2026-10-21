# 03 – Visual system

Material 3 foundation (Flutter `ThemeData` with `useMaterial3: true`) customized through one `AppTheme` and design tokens. **No screen may hard-code colors, sizes, or text styles**; all come from tokens (`AppColors`, `AppSpacing`, `AppTextStyles`, `AppRadius`) so dark mode and German text expansion work everywhere.

## 1. Typography
* Family: **Inter** (SIL OFL) bundled as an asset, fallback Roboto/system. Bundled, not fetched at runtime (privacy, offline, no third-party request). Latin Extended covers German.
* Scale (sp) — scales with OS font size up to 200%; layouts must reflow, never clip.

| Token | Size/Line | Weight | Use |
|---|---|---|---|
| display | 28/36 | 700 | Plan title on plan header |
| titleLarge | 22/28 | 600 | Screen titles, day header |
| titleMedium | 18/24 | 600 | Card titles, section headers |
| bodyLarge | 16/24 | 400 | Card text, booking details |
| bodyMedium | 14/20 | 400 | Secondary text |
| label | 12/16 | 600 | Chips, captions (minimum size) |

## 2. Color tokens (hex; contrast measured, WCAG 2.x)
Text/icon pairs target ≥ 4.5:1 (body) and UI boundaries ≥ 3:1. Meaning is **never color-only** (icon + text always accompany status color).

| Token | Light | Dark | Measured contrast |
|---|---|---|---|
| background | #FBF7F5 | #161213 | – |
| surface | #FFFFFF | #201B1C | – |
| surfaceAlt | #F4EDEA | #2B2425 | – |
| onSurface | #1E1A1B | #EDE0E2 | L 16.18 (bg) · D 14.48 |
| onSurfaceVariant | #5A5155 | #C9BCBF | L 7.19 (bg) · D 9.25 (surface) |
| primary (actions, links) | #A8174A | #FFB1C8 | L 6.83 on bg · D 10.95 on bg |
| onPrimary | #FFFFFF | #5E0A2E | L 7.28 · D 7.94 |
| primaryContainer / on | #FFD9E3 / #3F0020 | #7D1E44 / #FFD9E3 | L 13.22 · D 7.61 |
| travel (transport) | #00626A | #7FD3DB | L 6.67 · D 9.91 |
| travelContainer / on | #CDEDF0 / #00363A | (derive) | L 10.68 |
| stay (accommodation) | #7A5200 | #F2BE62 | L 6.50 · D 9.97 |
| stayContainer / on | #FFE7B8 / #3E2A00 | (derive) | L 11.31 |
| outline (inputs, UI boundary) | #857A7F | #988C90 | L 3.88 (bg), 4.13 (surface) · D 5.25 |
| divider (decorative only) | #E0D6D2 | #3A3234 | exempt |
| success / container | #1E6B3A / #D7F0DD | #8FD7A3 | L 5.40 · D 10.05 |
| warning / container | #7A4B00 / #FFEBC2 | #F2BE62 | L 6.32 · D 9.97 |
| error / container | #B3261E / #FCDAD6 | #FFB4AB | L 5.02 (6.14 on bg) · D 10.02 |
| info / container | #1D58A6 / #D8E6FA | #A9C8F5 | L 5.54 · D 9.93 |

Ratios computed with the WCAG relative-luminance formula for the listed pairs. Dark-theme container variants marked "derive" must be measured when implemented. Focus ring: 2 px primary + 2 px surface offset (≥ 3:1 against adjacent colors).

## 3. Spacing, shape, elevation
* 4 dp base: `4, 8, 12, 16, 24, 32, 48`. Screen padding 16 (compact) / 24 (medium) / 32 (expanded). Card inner padding 16. Gap between feed cards 12.
* Radius: 8 (inputs, chips-small), 12 (cards, dialogs), 999 (chips, pills).
* Elevation: flat — 1 dp `outline`-tinted border instead of shadows on cards; only dialogs/sheets use elevation.
* Max content width 720 dp for reading/editing columns; feed never stretches full-width on desktop.
* Motion: 150–250 ms standard easing; honor "reduce motion"; no motion carries meaning alone.

## 4. Touch and pointer targets
* Touch layouts (compact, medium): **≥ 48 × 48 dp** for every interactive element; ≥ 8 dp between adjacent targets.
* Pointer layouts (expanded): ≥ 40 × 40 dp visual, 48 dp hit area for icon buttons; never below 24 px (WCAG 2.2 AA 2.5.8).
* Form inputs height 56 dp; labels always visible (no placeholder-as-label); error text beneath field with icon.
* Every control has a semantic label (screen readers: TalkBack, browser a11y tree). Reorder handles expose *Move up/down* semantic actions.

## 5. Status indicators (icon + text + color)
| Status | Icon | Text (l10n key) | Color |
|---|---|---|---|
| Plan: in progress / upcoming / past | ▶ / ◷ / ✓ | `plan_status_*` | primary / info / onSurfaceVariant |
| Saving / Saved / Not saved | ⟳ / ✓ / ⚠ | `save_state_*` | onSurfaceVariant / success / error |
| Attachment: ready / uploading / failed | 📄 / ⬆ / ⚠ | `attachment_state_*` | success / info / error |
| Booking record: no file attached / file attached | ○ / 📎 | `booking_file_*` | warning / success |
| Invite: pending / revoked / used | ⏳ / ⊘ / ✓ | `invite_state_*` | info / onSurfaceVariant / success |
| Feature: not available yet / preview | ⏻ / ◐ | `feature_status_*` | onSurfaceVariant / warning |

"Booking record" statuses describe stored files only; the app never claims a booking is confirmed/paid (it is not a booking system).

## 6. Reusable components (shared widget library; each documented with states & a11y)
`AdaptiveShell`, `PaneLayout`, `AppTopBar`, `SectionHeader`, `PlanCard`, `NextUpCard`, `DayChip`/`DayRail`, `ActivityCard` (variants: note, activity, travel), `PlaceBlock` (mini-map + **Expand Map** + **Directions**), `BookingCard` (transport, stay), `AttachmentTile`, `PdfViewerPanel`, `PhotoStrip`, `StatusChip`, `SaveIndicator`, `EmptyState`, `ErrorState` (with Retry), `LoadingSkeleton`, `Banner` (info/warning/preview), `DisclosurePanel`, `ConfirmDialog`, `ConflictDialog`, `UnfinishedDestination`, form controls (`AppTextField`, `AppDateField`, `AppDateRangeField`, `AppTimeZoneDateTimeField`, `AppDropdown`, `AppSwitch`), buttons (`PrimaryButton`, `TonalButton`, `OutlinedButton`, `TextButton`, `DestructiveButton`, `IconButton48`).

Buttons: one primary action per screen region; **Expand Map** = tonal, **Directions** = outlined with external-link icon (visibly different, never merged); **Download original** = outlined with download icon, adjacent to but distinct from the preview. Destructive actions need a confirmation naming the object and what happens to attached files.
