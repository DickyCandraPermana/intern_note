# Intern Noter Design Direction

## Identity & Surface Mode

- **Product**: Intern Noter (daily work journal & DataSea consulting timesheet generator for Android & desktop).
- **Mode**: **Operate** (the user comes in flow to capture daily work notes quickly, inspect monthly progress, and export compliant DataSea `.xlsx` and `.pdf` timesheets).
- **Aesthetic**: **Work Journal** (warm paper surfaces for calm, glare-free daily writing paired with crisp DataSea Cobalt accents and tabular figures for hours and dates).

## Explicit Dials (antislop Part 3)

| Dial | Value | Rationale |
|---|---|---|
| **ENERGY** | `1` (Calm) | Note capture and timesheet auditing prioritize speed and zero visual noise over spectacle. |
| **RHYTHM** | `2` (Balanced) | Today's summary card anchors the top, followed by structured lists/timelines and compact preset chips. |
| **MOTION** | `1` (Functional) | Fast 150-200ms state transitions for sheet opens, snackbars, theme switches, and chip toggles only; zero decorative loops. |

## Color Palette (Light & Dark Modes)

Core palette stays within 2 core neutral layers + 1 corporate accent + semantic feedback colors. Both Light and Dark modes are first-class and toggleable (Light / Dark / System).

### Light Mode

| Token | Hex | Contrast & Purpose (One-Line Reason) |
|---|---|---|
| `canvas` | `#F7F6F2` | Warm paper canvas reduces eye fatigue during daily logging and separates card edges cleanly. |
| `surface` | `#FFFFFF` | Pure white cards elevate today's log, calendar, and form sheets without needing heavy shadows. |
| `surfaceAlt` | `#EFECE5` | Muted stone layer distinguishes input fields, preset bars, and secondary toolbars. |
| `inkPrimary` | `#1A1D21` | High-contrast charcoal (>14:1 on white) ensures crisp legibility for multi-line activity text. |
| `inkMuted` | `#555D6B` | Subdued slate (>6.1:1 on canvas) visually separates timestamps, captions, and secondary labels. |
| `border` | `#E2DFD7` | Subtle warm hairline defines card and input boundaries cleanly without shadow clutter. |
| `accent` | `#1E5AA8` | DataSea Cobalt (>6.7:1 with white text) ties the journal directly to the DataSea corporate timesheet brand. |
| `accentTint` | `#E8F0FA` | Soft cobalt wash marks selected dates, active preset chips, and summary KPIs cleanly. |
| `success` | `#1F7A4C` | Deep green (>5.3:1 on white) confirms export completion, backups, and saved quick notes. |
| `destructive` | `#B83232` | Crimson (>5.8:1 on white) clearly signals delete confirmations and validation errors. |
| `warning` | `#9A5B13` | Amber (>5.2:1 on white) highlights missing workday entries or uncategorized quick notes. |

### Dark Mode

| Token | Hex | Contrast & Purpose (One-Line Reason) |
|---|---|---|
| `canvas` | `#121417` | Low-glare charcoal base makes night logging and homescreen widget overlays comfortable. |
| `surface` | `#1B1F24` | Elevated graphite cards establish depth against the dark canvas without harsh contrast jumps. |
| `surfaceAlt` | `#232830` | Secondary slate distinguishes form inputs, chips, and search bars inside dark surfaces. |
| `inkPrimary` | `#F1F3F5` | Soft off-white (>14:1 on card) keeps long activity lists crisp without halation. |
| `inkMuted` | `#9BA4B0` | Cool grey (>6.8:1 on card) keeps metadata, hints, and dividers legible yet secondary. |
| `border` | `#2C323B` | Subtle slate hairline preserves clear structural boundaries in dark mode. |
| `accent` | `#60A5FA` | Sky Cobalt (>7.2:1 on card; pairs with `#0E1A2B` button text) preserves DataSea brand recognition at WCAG AA contrast. |
| `accentTint` | `#1E2E44` | Deep navy wash highlights active tags, selected calendar days, and cycle pills without neon glare. |
| `success` | `#4ADE80` | Bright mint (>10:1 on card) gives immediate confirmation feedback on dark surfaces. |
| `destructive` | `#F87171` | Coral red (>6.2:1 on card) signals destructive actions and error states clearly on dark backgrounds. |
| `warning` | `#FBBF24` | Warm gold (>10:1 on card) flags uncategorized quick notes needing module/project tags. |

## Typography

- **Family**: Single platform sans-serif family (Roboto on Android, system sans on desktop) to preserve native Operate-mode familiarity and avoid decorative font noise.
- **Tabular Figures**: Enable `FontFeature.tabularFigures()` on all numeric displays (hours, days, cycle totals, dates, KPI counters) so numbers align cleanly across rows.
- **Scale (Fixed)**:
  - `24sp` Bold (`w700`): KPI figures & hero metric values.
  - `20sp` SemiBold (`w600`): AppBar / modal sheet titles.
  - `16sp` SemiBold (`w600`): Card headings, date headers, primary button labels.
  - `14sp` Regular/Medium (`w400`/`w500`): Activity text, form inputs, timeline descriptions.
  - `12sp` Medium (`w500`): Project/module tags, metadata, table subtitles, chip labels.

## Shape, Borders & Elevation

- **Border Radius Hierarchy**: `12dp` for cards & bottom sheets, `10dp` for buttons & form fields, `8dp` for chips & status tags. Avoid pill-shaping every control.
- **Elevation**: `0dp` default with `1dp` `border` hairline on cards; reserve soft modal elevation strictly for bottom sheets, dialogs, and the floating `QuickNoteActivity` card.
- **Spacing**: `16dp` outer screen padding, `12dp` card internal padding, `12dp` vertical gap between stacked activity cards.

## Component, State & Interaction Standards

- **Tap Targets & Keyboard**: Minimum `48dp` interactive height on buttons, list tiles, and widget controls; explicit focus borders on desktop/keyboard navigation (`Tab`, `Enter`, `Escape` on dialogs).
- **UI States (Required on All Data Views)**:
  - **Loading**: Inline shimmer/skeleton placeholder rows instead of full-screen blocking spinners where possible.
  - **Empty**: Contextual prompt with direct action (e.g., `"Belum ada catatan hari ini"` with `"Tambah Catatan"` CTA or `"Daily Scrum 7E"` quick preset).
  - **Error**: Actionable inline banner or retry button with plain diagnostic message.
- **Assets**: Keep existing `ic_launcher.png` app icon untouched; embed only real extracted corporate assets (`assets/datasea_logo.jpg` and `assets/signature_dicky.png`) for timesheet export/preview.

## Home-Screen Widget Surface (`TodayNoteWidget` & `QuickNoteActivity`)

- **Widget Card**: Sticky-note layout mirroring `surface` (`#FFFFFF` light / `#1B1F24` dark via `values/` and `values-night/`), `16dp` outer corner radius, `1dp` `border`, compact header showing today's Indonesian date + `hours` badge, up to 5 bullet lines of today's notes, and a full-width bottom tap bar (`"+ Tulis catatan hari ini..."`, min `44dp` height) with a DataSea Cobalt `+` affordance.
- **Quick Note Overlay**: Translucent dimmed backdrop (`#66000000`) with a centered floating `surface` card (`16dp` radius), auto-focused multiline text input, horizontal row of compact `8dp` tag/preset chips (defaulting to last-used or uncategorized `"Catatan Cepat"`), and aligned `Batal` / `Simpan` actions (`48dp` target height).
