<!-- /autoplan restore point: "/Users/hasan/Developer/FamilyTreeV2/.claude/worktrees/agent-ab51b54c94dd599d0/.gstack/tmp/autoplan/worktree-agent-ab51b54c94dd599d0-autoplan-restore-20261126-025709.md" -->
## Implementation plan
# Admin Panel Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the whole admin panel of the iOS app («الإدارة» tab) in one new design language. Every existing command, number and navigation rule is kept.

**Architecture:**
- Restyle the shared admin kit first (tokens, Hub/Page/Tile kits, a new Filter kit, new Census rings), so every page changes at once.
- Then rebuild «اليوم» and each area root and its key sub-pages, one unit at a time.
- Business logic, view-model calls, the role table and navigation mechanics stay as they are.

**Tech Stack:** SwiftUI (iOS 16+), the app's DS design system (`Components/Shared/*`), Supabase (unchanged; no server changes).

**Spec:**
- `/Users/hasan/Developer/reports/admin-redesign/design-spec.md` (build contract, sections A–H).
- Mocks: `/Users/hasan/Developer/reports/admin-redesign/admin-redesign.html`.
- Inventory: `/Users/hasan/Developer/reports/admin-redesign/inventory.md`.

**Worktree:** `/Users/hasan/Developer/FamilyTreeV2/.claude/worktrees/agent-ab51b54c94dd599d0` (branch `worktree-agent-ab51b54c94dd599d0`, based on `origin/ios/uiux-batch1-2026-11-10`).

## Global Constraints

- Owner rules from spec «Owner rules» 1–6. Verbatim highlights:
  - White page, navy header #172536, gold #B89A5A on navy only, gold text #725D31 on white.
  - Titles ≤ 22. Text 13–15. Numbers 15–17 semibold. Nothing bold except titles.
  - No top tabs, no segmented switches, no section bars. Chips are filters only.
  - One home per command.
  - Arabic only, short plain words. Touch ≥ 44.
- Owner choices kept:
  - stats «أ»
  - family filters «ب»
  - «التطبيق» «ب»
  - family rings stay
  - no big «يحتاج انتباهك» card
- Project rules (CLAUDE.md):
  - DS tokens only.
  - `.dsFont(.role)`.
  - `L10n.t("عربي", "English")` for every string.
  - `Text(verbatim:)` for two-variable text.
  - No `.system(size:)`.
  - No bare spinners.
  - `AdminLazyPage{AnyView(...)}` for every link destination.
  - Pushed pages get `.adminArea(…)` + `.adminBackTitle(…)`.
- Stack depth limits: «اليوم» ≤ 720 KB, admin tab ≤ 800 KB, pages ≤ 600 KB, ≤ 64 KB per check.
- Keep these navigation mechanics unchanged (inventory §4):
  - `AdminReviewDestination` cases
  - `AdminAreaRouter` (U2 only adds `landings[hop]`, see below)
  - `AdminAreaGate`
  - `AdminRoleMatrix` ids
  - `AdminToolCatalog` ids
  - push routing (`.openAdminReviewForKind`, `.openAdminRequests`, `.openWomenTree`)
  - init parameters of `AdminAllRequestsView` (`focusId`, `initialFilter`, `startsWithMessages`, `initialSearch`) and `AdminMembersPage` (`chip`, `sub`, `womenOutside`)
- No server/database changes. No new dependencies.
- Executors run in parallel in the same worktree. Each one builds with its own `-derivedDataPath /private/tmp/claude-501/dd-<unit>`. No git commits, stash or branch changes by executors; the manager commits after review.

## Review Focus

1. A store fails to load (SMS, devices, usage, accounts). Tiles and pills must say «تعذّر التحميل», never a calm word like «سليم» (spec T1). Owner: U4, U2, U7, U16, U17.
2. A number opens a list. The opened list's count must equal the number tapped, e.g. 170 registered and 50 outside (T2). Owner: U6, U7, U11, U15.
3. Roles. Monitor, supervisor and admin must see exactly their table-allowed areas and commands; read-only areas show no edit controls (U20 walk per role). Owner: every page unit.
4. Push routing into a request (`request_id`) still lands on the request box after the inbox root is rebuilt (U8, U9).
5. Large text (AX sizes) and RTL. Tiles go to 1 column, chips wrap, nothing truncates numbers (U4, U5, U6).

---

## Build batches (≤ 2 executors at once; units never share files)

Each unit's files, dependencies and "done when" check are in spec §D (U1–U20) and the T1–T6 list, plus the additions below (autoplan 2026-11-26, checked against the code).
- **Order of authority:** this plan › spec A–C + «Autoplan notes» › the «لوحة الإدارة» section of CLAUDE.md, which describes the old UI. The CLAUDE.md *rules* (tokens, L10n, stack guard, roles) still apply.
- **Executors never wait for the owner.** Ignore §D's "waits for the owner's keep-or-revert". The owner sees the work only at the B7 checkpoint and at B11.

After each batch:
- the manager builds the whole app;
- the manager runs verification steps 2–3 on one simulator (see the end of this section);
- a reviewer checks each unit's diff (`git add -N <new files>; git diff -- <unit files>`) and its screenshots against the spec and the mock;
- then the manager makes **one local commit per unit**, so one unit can be reverted alone.

If an executor dies mid-edit:
1. Run `git status --porcelain -- <unit files>`.
2. `git checkout --` its tracked files and delete its new files.
3. Relaunch the unit.

### Rules that keep every batch compiling

1. **Compat rule.** A type, initializer, enum case or token that a file outside your list uses must keep compiling.
   - Add new parameters with defaults. Keep old cases and old initializers. Mark them `@available(*, deprecated, message: "U21 removes")`.
   - The deprecation message names the replacement, e.g. `"use DS.Hub.band; U21 removes"`.
   - Only U21 deletes them: it deletes the shim, then lets the build decide. `grep` also hits comments, so it is not enough.
   - U1 (committed `fecad874`) kept `DS.Hub.bandTop`/`bandBottom`/`ring*` as aliases without the attribute. U21 removes them.
2. **Frozen shared APIs.** Restyle them freely, but do not change their signatures or meaning:
   - `AdminLazyPage` (U7 file)
   - `AdminTodayText`, `AdminTodayFetch`, `AdminMemberCounts` (U7)
   - `AdminFamilyCensus` (U11; also read by `WomenTreeView`)
   - `AdminMemberReview`, `AdminMemberSub`, `AdminMembersIndex`, `AdminAccountsStore`, `AdminLivingCheck` (U11)
   - `AdminOccasionsText`, `DeceasedDateBox` (U14)
   - `AdminPageKPI` (U3; it becomes the data of `AdminHeaderLine`)
   - `AdminArea` raw values (U2)
   - `AdminMemberSheet(ids:start:)` (U13; one id = no prev/next bar)
3. **Parallel builds.** Two executors share one worktree, so each one's build also compiles the other's half-done files.
   - Outcomes:
     - **GREEN:** no `error:` anywhere.
     - **RED-OWN:** an error in your own files. Fix it.
     - **RED-OTHER:** errors only in the other unit's files. Report them and don't fix them. This counts as done.
     - **INFRA:** SPM resolve, disk or derived-data failure. `rm -rf` your dd folder, retry once, then report the log path.
   - The manager's whole-app build after the batch is the gate.
   - Executors build only. Simulator runs and screenshots are the manager's, so two lanes never fight over one simulator.
4. **Not in any unit, so nobody edits them:** `MainTabView.swift`, `FamilyTreeV2App.swift` (except T0's one DEBUG line), `MainHeaderView.swift`, `AuthViewModel.swift` (except T0), `NotificationsCenterView.swift`, `MemberPendingRequestsCard.swift`, `Core/AdminRoleMatrix.swift`, all server files.
5. New files need no project edit: the Xcode project uses synchronized folders.

### Units whose file lists changed (spec §D plus these)

- **U2** + NEW `Admin/AdminContracts.swift`, the shared contracts every page unit codes against:
  - **Landing** (the deep-link contract design review found missing): `AdminStatsAnchor`, `AdminMembersLanding` (account · life · branch), `AdminWomenLanding` (status · branch), `AdminInboxLanding` (status · group · kind · source), `AdminOccasionsAnchor`.
    - Stored in `AdminAreaRouter.landings[hop]`, keyed by the unique hop that `.area(_, hop)` already carries.
    - Read with a typed `take`, e.g. `AdminAreaRouter.take(.inbox, hop:)`.
    - Cleared on every `navigate`, on `didReselectTab`, when leaving the tab, and in `AdminAreaGate`'s refused branch.
    - Explicit init parameters win over a landing.
    - `kind` is mapped through a whitelist and clamped to `tabsForRole`. An unknown kind opens the inbox unfiltered.
    - No new `AdminReviewDestination` cases. Adding `landings` is the only change to `AdminAreaRouter`.
  - **`AdminStoreHealth`**: `idle · loading · loaded(at:) · failed(lastGood:) · denied`, plus how each state draws:
    - idle or loading → skeleton;
    - loaded → the word;
    - failed with no older data → «تعذّر التحميل» + retry;
    - failed after a good load → keep the word and add «آخر تحديث 9:12»;
    - denied → hidden or read-only, never a retry.
    - Every store a word, pill, chip count or header number reads gets an adapter in its owner's file.
  - **`AuthViewModel.adminCanEdit(_ area:)`** (an extension = `adminAccess(area).canEdit`). Every page unit ANDs it with the existing role check (`canApprove`, `canEditMembers`…). This enforces "read" areas, which the server table allows today but the UI ignores.
  - **`AdminHeaderItem`** (number, `AdminStoreHealth`, tap): the data of `AdminHeaderLine`. A zero, loading or failed number never shows as a plain string.
- **U3** runs after U2. It uses U2's `AdminHeaderLine`, so they cannot run in parallel.
  - Adds the `AdminPageKPI` → `AdminHeaderItem` adapter (`AdminPageKPI` stays frozen).
- **U5** + `Components/Shared/DSAdminPage.swift` (`DSFilterChips`, `DSSearchField`; spec A.9).
  - The new look comes through an explicit `style:` argument that defaults to today's look. No environment value: pushed pages don't inherit it.
  - Member screens use these and must not change: `FamilyArchiveView` (chips), `DaughterSons` and `TreeSearchOverlay` (search field).
- **U7** deletes `AdminTodayPager.swift` only after moving its shared types, under the same names, into `AdminTodayModel.swift`:
  - `AdminHeaderIcon` (used by U2 and `AdminAnnounceComposer`)
  - `AdminFamilyStats`
  - `AdminFamilyStatsPage.aliveText`/`deceasedText` (used by U11)
  - The manager does this pure move **at the end of B6** and commits it. U11 works in parallel with U7 in B7 and must not see errors in its own file.
  - Keep `AdminMemberCountsCard` until U21 if anything still uses it.
  - Keep `AdminReviewDestination.status` routing (move `AdminSystemStatusLine.page`).
  - The smart line is drawn under `MainHeaderView` inside `AdminDashboardView`; `MainHeaderView` is not edited.
  - Push routing:
    - A push with no `request_id` goes to `.area(.inbox, hop)` with `landings[hop] = .inbox(kind:)`.
    - `.allRequests`, `.inboxItem` and `.treeEditRequests` are wrapped in `AdminAreaGate(area: .inbox)`.
  - Tile tap: when a tile's state word names something a filter can show, the tap lands with that filter on, as a removable chip. «4 مشكلات في الشجرة» opens the family root and pushes the «مشكلات» review list on top, so back returns to the root.
  - Load order: the census and inbox numbers load first. Tile stores load after them without blocking, and each store keeps a refetch time limit.
- **U8** + `Admin/AdminTrailPreview.swift`: **keep it and port it** to the new inbox; do not delete it. It is the app's only fake-data mode (`-uiPreviewRequestTrail`), and `ContentView` uses it. U20 runs its approve/advance checks on it.
  - `startsWithMessages` pushes the messages page only when `adminAccess(.inboxMessages)` allows it.
  - Consumes `AdminInboxLanding`.
  - `focusMissing` («هذا الطلب عولج من قبل») shows only when the store that owns the item loaded. If it failed, show «تعذّر التحميل» + retry. Search all pending items, ignoring the user's filters.
- **U9** + `Admin/AdminAllRequestsView.swift`, the detail-box region (`requestDetailSheet` … `hardDeleteDetail`). The box is assembled there, not in the U9 kit files. So U9 runs in a later batch than U8, never beside it.
  - A box opened by `focusId` (push or notice) closes after the decision.
  - Auto-advance:
    - only when the box was opened from the list;
    - the next request is picked by id among those still pending;
    - the bar stays disabled until the next request has loaded, and for at least 0.8 s;
    - VoiceOver announces «الطلب التالي: <name>».
  - Close or advance only after a **confirmed success**.
    - On an error: stay on the request and show the message for the `decide_admin_request` hint (`not_allowed`, `own_request`, `phone_in_use`, `family_links_protected`…).
    - On a timeout: fetch the request again before turning the buttons back on.
    - On `already_handled`: show who handled it, then advance.
  - The member sheet pushed inside the box goes behind `AdminLazyPage { AnyView(...) }`. This is a stack hot spot: the inbox body used to overflow at 128 KB.
- **U10** keeps `embedded:`/`sharedSearch:` compiling, marked deprecated. U8 drops the call, and U21 deletes the parameters.
- **U11** runs after U12. It pushes U12's `AdminReviewHubPage` and women page.
  - Old `chip:`/`sub:` values (`problems`, `verifyLiving`, `registered`, `treeOnly`, `deceased`, `notSignedIn`, `noPush`) keep compiling. Each maps to a filter or pushes the matching review list. Callers include `AdminUsageDevicesKit`, which no unit owns.
  - Gives `AdminAccountsStore` an `AdminStoreHealth` adapter. A failed load logs `Log.error("[AdminAccountsStore] load failed: …")`; today it fails silently.
- **U12** keeps `AdminWomenPanel`'s current init, `AdminWomenChip` and `AdminWomenChipRequest` compiling until U11 lands. It also keeps `AdminMemberReview.death` working (redirect to `DeathDatesCampaignPage`).
  - Removes `DSSegmentedSwitch` from `AdminReviewListPage.swift:222`.
  - The «فرع خارج العائلة» list uses the same rule as `AdminFamilyCensus.make` (named people only), so the list count equals the number (T2).
- **U13:** the ban row passes `prefillPhone` normalised with `KuwaitPhone.normalizedForStorage`. It never passes a masked number and never auto-submits.
- **U14** + `Admin/AdminAnnounceComposer.swift`: `AdminChoiceChip` lives there (spec A.9). Restyle only.
- **U15** gates inside the root:
  - family sections by `metrics.family`;
  - «الموافقات» by `metrics.approvals` plus the workflow flag;
  - a role with family `none` and approvals `read` sees only «الموافقات»;
  - both `none` → an empty state, not a blank page.
  - Reads `AdminStatsAnchor`.
- **U16** adds `AdminRegistrationBansView(prefillPhone:)` (default nil) for U13.
- **U18** gives `AdminNoticeStore` an `AdminStoreHealth` adapter, with a logged failure cause.
- **U19** + `Core/RoleGuides.swift`. Role texts still say «المؤشرات» and «سطر حالة النظام»; rename and reword them per the AdminRoleItem table below.
  - `AdminAreaGate` says «هذا القسم للمالك فقط» only for owner-capped areas. Any other hidden area says «هذا القسم ليس ضمن صلاحياتك».
- **NEW U21 Admin leftovers + cleanup** (runs alone).
  - Removes `DSSegmentedSwitch` from `AdminErrorsPage`, `AdminUsageCards`, `AdminSmsAttempts`, `AdminUpdateWhatsNewView` and `AdminReportsView`. Use filter chips or a `Menu`; no other layout work.
  - Tokens and wording in `AdminUsageDevicesKit` and `ApprovalsReportView` («المؤشرات»).
  - Then deletes every deprecated shim from rule 1 (delete, then build).
  - Rewrites the «لوحة الإدارة» section of CLAUDE.md to describe the new panel. It adds the standing rule that new admin requests follow spec §A, and records the deliberate admin exceptions: `lineZero` white 55%, cards without shadow, `hubKPI` gone.
- **T0 (manager, not an executor, before B1):** restore the DEBUG-only tools. Today the stack probe exists only as a comment in `AdminPageKit.swift:30`.
  - **Files:**
    - NEW `Core/DebugAdminProbe.swift`.
    - One `#if DEBUG` line in `FamilyTreeV2App.swift` (no change to `routePushTap`).
    - The role hook in `AuthViewModel`.
    - Failure hooks in the three store files no unit owns: `AdminSmsData.swift`, `AdminPushHealthView.swift`, `AdminUsageData.swift`.
    - NEW `scripts/admin-verify-unit.sh`.
  - **One `DebugArgs` helper** built on `ProcessInfo.arguments`. An unknown value logs an error. One launch line lists the active overrides, and a small DEBUG badge is shown. Flags are never saved to UserDefaults.
  - **`-tmpStackDepth -tmpStackCheck`:** samples the main thread's stack depth during admin rendering. Prints one line per page: `STACK page=<Type> peakKB=<n> limitKB=<n> PASS|FAIL`. A FAIL names the deepest type and the fix (`AdminLazyPage{AnyView}` / split into `AnyView` cards). Done when it prints PASS for today's «اليوم» before B1 work is measured.
  - **`-tmpAdminRole owner|admin|monitor|supervisor`** and **`-tmpRoleMatrix <json>`:** applied where the role is read, so the next refresh doesn't drift back to owner.
    - The walk checks what each role **sees**. The server still answers as the real login (the owner), so the data scope is not tested.
    - While any `-tmp*` role or matrix override is on, DEBUG writes are dry-run: approve, advance, send, member edits and settings writes log `DRY-RUN` and fake success.
  - **`-tmpFailStores sms,devices,accounts,usage,notices,inbox,census[@seconds]`:** `@seconds` fails a store only after it has loaded once, which tests the "keep the word + time" case. Owner units add the check for their stores (U11 accounts, U18 notices, U8 inbox, U7 census).
  - **`scripts/admin-verify-unit.sh <unit> <screen>`:** simulator build → install → light / dark / AX3 (+ landscape for roots) screenshots, plus `.apns` payloads for `xcrun simctl push`.

### AdminRoleItem → new home (server keys unchanged)

| Key | After the redesign |
|---|---|
| `today.census` | census card on «اليوم» |
| `today.attention` + `attention_fourth` | order of the inbox tile's state words; the fourth fact per role (رسائل · مشكلات الشجرة · بلاغات) |
| `today.system_status` | state words on the «الفريق والأمان»/«التطبيق» tiles; «مجدول اليوم N» for the admin |
| `today.megaphone` | megaphone, unchanged |
| `inbox.*`, `occasions.*`, `team.*`, `app.settings` | same screens; `inbox.messages` also gates the messages page and `startsWithMessages` |
| `metrics.family` / `metrics.approvals` | sections inside the «الإحصاءات» root (U15) |

### Batches

- [x] **B0:** U1 Tokens (committed `fecad874`)
- [ ] **T0:** debug tools by the manager, before B1 measures anything
- [ ] **B1:** U2 Hub kit + `AdminContracts.swift` ‖ U5 Filter kit + `DSAdminPage.swift`
- [ ] **B2:** U3 Page kit ‖ U4 Tile kit
- [ ] **B3:** U6 Census rings ‖ U10 Messages page
- [ ] **B4:** U8 «الوارد» root + done page ‖ U16 «الفريق والأمان»
- [ ] **B5:** U9 Request box (after U8; shares `AdminAllRequestsView.swift`) ‖ U12 Family sub-pages
- [ ] **B6:** U15 «الإحصاءات» ‖ U13 Member sheet (needs U16)
- [ ] **B7:** U7 «اليوم» (needs U6, U12, U15) ‖ U11 «العائلة» root (needs U12)
  - **Checkpoint, no question:** install on the owner's iPhone if the cable is connected, else take simulator shots. Keep going unless he says stop.
- [ ] **B8:** U14 «المناسبات» ‖ U18 «إشعارات الإدارة»
- [ ] **B9:** U17 «التطبيق» ‖ U19 Catalog, search and role texts
- [ ] **B10:** U21 Admin leftovers + cleanup (alone)
- [ ] **B11:** U20 Whole-flow QA:
  - full build
  - code review (code-review skill)
  - design review (design-review skill)
  - every role through `-tmpAdminRole`
  - every failed store through `-tmpFailStores`
  - every push route: `request_id`, `sms_*`, `tree_edit` with and without id, `startsWithMessages` as monitor
  - member screens that read admin kit or tokens: `NotificationsCenterView`, `WomenTreeView`, `DaughterSons`, `PrivacyRequestsViews`, `TreeSearchOverlay`, `FamilyArchiveView`
  - install on the owner's iPhone by cable
  - ios-design-review on device

Per-unit verification (spec §D):

**Step 1, executor.** A simulator compile with no signing and no keychain prompt, and with the full log kept:
```
cd /Users/hasan/Developer/FamilyTreeV2/.claude/worktrees/agent-ab51b54c94dd599d0 && set -o pipefail; L=/private/tmp/claude-501/dd-<unit>/build.log; mkdir -p "${L%/*}"; xcodebuild -project FamilyTreeV2.xcodeproj -scheme FamilyTreeV2 -destination 'generic/platform=iOS Simulator' -configuration Debug -derivedDataPath /private/tmp/claude-501/dd-<unit> -clonedSourcePackagesDirPath /private/tmp/claude-501/spm CODE_SIGNING_ALLOWED=NO build >"$L" 2>&1; rc=$?; grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$L"; echo "exit=$rc log=$L"
```
Classify the result by rule 3.

**Step 2, manager, after the batch build.** Run `-tmpStackDepth -tmpStackCheck` on the unit's screens. Every line must say PASS. Limits:
- «اليوم» ≤ 720 KB
- tab ≤ 800 KB
- pages ≤ 600 KB
- ≤ 64 KB per check

**Step 3, manager.** Run `scripts/admin-verify-unit.sh`.
- Screenshots light, dark and AX3 (+ landscape for area roots) go to `/Users/hasan/Developer/reports/admin-redesign/units/<unit>/`.
- The batch reviewer compares them with the unit's mock phone.
- Never open «طلبات رمز الدخول» or full phone numbers with real data. Use `-tmpFailStores` states for SMS pages. Delete screenshots of team/SMS pages after review.

**Step 4, executor.** Apply `AdminStoreHealth` (U2) to every store that a word, pill, chip count or header number reads.
- Write the unit's pure logic as plain Foundation code:
  - landing mapping;
  - old-chip mapping;
  - smart-line priority;
  - store-health → word;
  - U15 gating;
  - number ↔ list ids.
- Test it with a `swiftc` script under `tests/admin-redesign/<unit>/`, following the pattern of `tests/otp-wait-text/main.swift` (no project edit). The manager runs all of these at each batch gate.

**Device builds** (`generic/platform=iOS`, signed, `-allowProvisioningUpdates`) are only for the manager's installs at B7 and B11. If the phone isn't connected, take simulator shots and keep going.

## Progress log
- 2026-11-26: inventory, spec and mocks done. Owner said: no questions, execute to the end, use all skills. Nothing gets pushed until the owner says «ثبّته» after trying it on his phone.
## Autoplan decisions (2026-11-26, no questions; each decided by the reviewer)

1. **Pipeline was lean.** CEO, design, DX and eng each ran as one independent Claude reviewer. Codex is not installed. The eng review also checked every unit's files against the code.
2. **Skipped two prompts.** The telemetry prompt and the /office-hours offer were not shown, because the owner forbade questions. Telemetry stays unset; that consent is not ours to give.
3. **Moved the inbox earlier** (U10 in B3, U8 in B4, U9 in B5). The CEO and design reviewers both asked for it: it is the daily screen and the push target.
4. **U3 runs after U2.** It needs U2's `AdminHeaderLine`; spec §D wrongly showed them as parallel.
5. **U8 and U9 run one after the other.** The request box is assembled in `AdminAllRequestsView.swift`, so U9 gets that region.
6. **Destinations come before sources.** U12 lands before U11 and U7, U15 before U7, and U6 before U7 and U15.
7. **Added U21** (admin leftovers + cleanup) **and T0** (the manager's DEBUG tools). Today the stack probe is only a comment in the code.
8. **Added files to units:**
   - U2: `AdminContracts.swift`
   - U5: `DSAdminPage.swift`
   - U8: keeps and ports `AdminTrailPreview.swift`
   - U9: the box region of `AdminAllRequestsView.swift`
   - U14: `AdminAnnounceComposer.swift`
   - U19: `RoleGuides.swift`
   - T0: three store files no unit owns
9. **Compat rule and frozen shared APIs.** Each kit change otherwise breaks callers in later units: `AdminRowTile`, `AdminPageKPI`, `AdminInboxView(embedded:)`, `AdminWomenChip`, `AdminFamilyStatsPage`, `AdminMemberCountsCard`, old chips.
10. **`AdminTodayPager.swift` is deleted only after its shared types move to `AdminTodayModel.swift`.** The manager does the move at the end of B6.
11. **The deep-link landing is keyed by the area hop.** A push with no `request_id` goes to `.area(.inbox, hop)`, push destinations pass through `AdminAreaGate`, and there are no new destination cases.
12. **One `AdminStoreHealth`** with five states, including `denied` (no retry). A failed load never shows a calm word or «عولج من قبل».
13. **`adminCanEdit(area)` is ANDed with the role checks.** "Read" areas in the server table are now enforced in the UI.
14. **Per-unit check:**
    - a simulator build without signing, with `pipefail` and the log kept;
    - the manager runs the stack probe and screenshots after the batch;
    - `swiftc` logic tests in `tests/admin-redesign/`.
15. **One commit per unit.** Executors never wait for the owner. A no-question install checkpoint follows B7.
16. **Role walks check what each role sees, never what it can write.** DEBUG writes are dry-run while a role override is on. A pass with real monitor and supervisor accounts is left to the owner.
17. **Request-box safety:** close or advance only after a confirmed success; a box opened from a push closes; auto-advance waits until the next request has loaded.
18. **Accepted U1's change of shared tokens** (card radius 12, no overlap). Member screens that read them are in the U20 walk: notifications, women tree, daughters' sons, privacy, tree search.
19. **Taste call:** the inbox tile may show two facts («2 عاجل · 5 بانتظارك»). The smart line stays one line.
20. **Taste call:** kept the owner's full redesign. The CEO voice's "kit only first" was raised by one voice only, and the owner's direction stands.
21. **Deferred:**
    - Android/web parity for the «الإحصاءات» rename;
    - the owner's verdict on the unpushed `0fcaac1c`. The redesign builds on it, and its «المسجّلون» is the T2 reference.
22. **The admin folder stays frozen to this branch until B11.** New admin requests join this plan.
23. **U20 gives the owner two notes:** "what will feel different" (E.4, E.20, E.21, messages one tap away) with revert paths, and a before/after sheet per area.

## Review record

Phase coverage (run `worktree-agent-ab51b54c94dd599d0-autoplan-20261126-025709`): every phase = 1 native Claude reviewer, Codex `not_installed` (consensus N/A, single-model). CEO + design reviewed the source plan (sha 6e3038…); DX + eng reviewed the amended plan (sha cb0134…). Restore point: `.gstack/tmp/autoplan/worktree-agent-ab51b54c94dd599d0-autoplan-restore-20261126-025709.md`.

<!-- autoplan-accepted:ceo -->
- B7 install checkpoint with no question; per-unit commits for per-unit revert; «what will feel different» note at B11.
- Role texts (`RoleGuides.swift`) and the AdminRoleItem → screen table are owned (U19, U7, U15).
- Member screens reading admin kit/tokens are walked in U20.
<!-- /autoplan-accepted:ceo -->
<!-- autoplan-accepted:design -->
- Per-unit screenshots (light/dark/AX3, landscape for roots) compared with the mock; stack probe per unit.
- `AdminStoreHealth` states; landing contract; tiles land with their filter; request-box auto-advance safety; team tile counts failing push devices.
<!-- /autoplan-accepted:design -->
<!-- autoplan-accepted:dx -->
- Simulator build without signing, pipefail, kept log, outcome classes, shared SPM dir; T0 `DebugArgs` with loud unknown values, `STACK … PASS|FAIL` line, `admin-verify-unit.sh`, `@seconds` failure syntax, DRY-RUN writes; executor crash recipe; order of authority.
<!-- /autoplan-accepted:dx -->
<!-- autoplan-accepted:eng -->
- Batch order B0–B11 and the file lists above; compat rule; frozen APIs; U8→U9 serial; `AdminTrailPreview` kept; landings keyed by hop and cleared; inbox push destinations gated; `adminCanEdit`; `focusMissing` only after a good load; manager moves `AdminFamilyStatsPage` helpers at end of B6; explicit `style:` on `DSFilterChips`/`DSSearchField`; swiftc logic tests per unit.
<!-- /autoplan-accepted:eng -->
