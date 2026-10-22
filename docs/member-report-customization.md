# Member-list PDF customization

The export screen now opens **البيانات وتنسيق الملف** instead of a horizontally scrolling field-chip row. A sheet groups the available fields into basic data, dates/ages, and contact/registration, with Minimal / Standard / All-data presets. Changes apply together on **تطبيق**, preserving the existing per-user, per-report field preferences.

The member register additionally offers:

- Compact rows (default): 8.5 pt body text and 3.25 pt vertical padding, compared with the regular 9.5 pt and 4.5 pt. Wide tables can still use the existing smaller-font fallback in regular mode.
- One continuous list or groups by branch, retaining tree order.
- Optional cover, count tiles and branch-summary table. The branch summary is only included when grouping by branch is enabled.

Layout choices are saved separately per user/report. Older stored option objects retain defaults for newly introduced controls. Required fields remain included. Hidden phone numbers and birth dates remain hidden, and disabling the death-date field now removes that date from the status cell as well.

The renderer measures using the same fonts and padding used for drawing. Coverless exports number their first content page as page 1. Other report types retain their existing layout and content; they receive the grouped field editor.

## Verification

Signed iPhone Debug build passed. The real builder and UIKit PDF renderer were run in a simulator against 182 synthetic members with long names, hidden fields, all columns and subset selections. Twenty checks passed: pagination, member counts, privacy, no embedded unchecked death dates, cover removal, flat grouping/branch columns, option decoding and the other three report types. The customization sheet and first/interior/final PDF pages were rendered and inspected.

To reproduce without accessing live family data:

```sh
python3 tools/admin-report-preview/verify.py \
  --simulator <booted-arm64-simulator-UDID> \
  --products <path-to-built-FamilyTreeV2.app> \
  --output /tmp/familytree-report-qa
```

The harness imports the production builder and renderer, omitting only the live-member snapshot adapter. It generates synthetic PDFs without an authenticated app session; no Supabase requests are made. The customization UI uses the app’s shared DSComposer, DSComposerSection, DSToggleBox, chip and segmented-switch components, presented through dsTallBox. It is checked in a full app simulator build so its identity is not replaced by test-only controls.
