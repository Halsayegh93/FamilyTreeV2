# FamilyTreeV2 - Project Rules

## Project Overview

FamilyTreeV2 is a SwiftUI family tree app for the Al-Mohammad Ali family. It uses MVVM architecture with Supabase backend. The app supports Arabic/English bilingual UI with full RTL layout support. Created by HASAN, February 2026.

## Architecture

- **Pattern:** MVVM (Model-View-ViewModel)
- **UI Framework:** SwiftUI (iOS 16+)
- **Backend:** Supabase (auth, database, storage, edge functions)
- **State Management:** `@StateObject` at root, `@EnvironmentObject` for injection, `@Published` for reactivity
- **Concurrency:** async/await with `@MainActor` on ViewModels
- **Navigation:** `NavigationStack` at root, tab-based via `MainTabView`

### Directory Structure

```
FamilyTreeV2/                         ← Xcode project root
├── FamilyTreeV2/                     ← App target source
│   ├── FamilyTreeV2App.swift         ← @main entry point
│   ├── ContentView.swift             ← NavigationStack → RootView
│   ├── Assets.xcassets/              ← Color sets, app icon
│   ├── Info.plist                    ← App configuration
│   └── PrivacyInfo.xcprivacy         ← Privacy manifest
├── Components/
│   ├── Shared/                       ← Reusable DS components
│   │   ├── DesignSystem.swift        ← DS enum (colors, fonts, spacing, shadows, components)
│   │   ├── AppL10n.swift             ← L10n localization helper
│   │   ├── DirectionalOffset.swift   ← RTL-aware horizontal positioning
│   │   └── ImageCropperView.swift    ← Image crop utility (circle/square)
│   ├── Home/                         ← Home feature components
│   │   ├── HomeHeaderView.swift
│   │   └── NewsCardView.swift
│   └── Tree/
│       └── MemberNodeView.swift      ← Family tree node visualization
├── Models/
│   ├── Tree/
│   │   ├── FamilyMember.swift        ← Core member model + UserRole + MemberStatus + KuwaitPhone
│   │   └── MemberGalleryPhoto.swift  ← Photo gallery entries
│   ├── News/
│   │   └── NewsPost.swift            ← News posts + NewsPollVote + NewsLikeRecord + NewsCommentRecord
│   ├── Diwaniyas/
│   │   └── Diwaniya.swift            ← Diwaniya gathering model
│   ├── AI/
│   │   └── AIModels.swift            ← AIChatMessage + API response models
│   └── Admin/
│       ├── AdminRequest.swift        ← Admin action requests
│       ├── PhoneChangeRequest.swift  ← Phone change requests
│       └── AppNotification.swift     ← In-app notifications
├── ViewModels/
│   ├── Auth/
│   │   └── AuthViewModel.swift       ← Central ViewModel (~2800 lines, manages auth + data)
│   ├── AI/
│   │   └── AIViewModel.swift         ← AI chat & admin summary
│   └── DiwaniyasViewModel.swift      ← Diwaniya CRUD operations
├── Views/
│   ├── App/                          ← App-level views
│   │   ├── RootView.swift            ← Auth state router
│   │   ├── SplashScreenView.swift    ← Animated launch screen
│   │   └── AppIconPreview.swift      ← Dev utility
│   ├── Main/                         ← Main navigation
│   │   ├── MainTabView.swift         ← 5-tab navigation
│   │   └── MainContentView.swift     ← Auth state router (alternative)
│   └── Features/
│       ├── Auth/                     ← LoginView, RegistrationView, WaitingForApprovalView, TrialExpiredView
│       ├── Home/                     ← HomeNewsView, ContactCenterView, NotificationsCenterView
│       ├── Tree/                     ← TreeView, TreeViewPrototype, MemberDetailsView
│       │   └── AdminView/            ← AdminMemberControlView, AdminMemberDetailSheet
│       ├── Profile/                  ← ProfileView, EditProfileView, SettingsView, AddChildSheet, EditChildSheet, AddChildRequestView
│       ├── Diwaniyas/                ← DiwaniyasView
│       ├── Admin/                    ← AdminDashboardView + 15 admin management views
│       └── AI/                       ← AIChatView, AIAdminSummaryView
├── Core/
│   ├── SupabaseConfig.swift          ← Supabase client setup + OTP fallback config
│   ├── AppLogger.swift               ← Log enum (info, error, warning) via os.Logger
│   └── PushNotificationDelegate.swift ← APNs registration & notification handling
└── supabase/
    ├── config.toml                   ← Supabase CLI config
    ├── functions/                    ← Edge functions (TypeScript)
    │   ├── claude-ai/               ← AI assistant backend
    │   ├── contact-email/            ← Contact form email
    │   ├── delete-account/           ← Account deletion
    │   ├── otp-fallback/             ← WhatsApp/Voice OTP delivery
    │   ├── push-admins/              ← Admin push notifications
    │   └── push-notify/              ← General push notifications
    ├── migrations/                   ← 15 SQL migration files (2026-02-09 to 2026-02-28)
    └── seed/
        └── seed_dummy.sql            ← Development seed data
```

## App Lifecycle & Entry Point

The app starts from `FamilyTreeV2App.swift`:
1. `@main FamilyTreeV2App` creates `AuthViewModel` as `@StateObject`
2. Injects `authVM` via `.environmentObject()` and sets locale/layout direction from `LanguageManager`
3. Wraps `ContentView` which contains `NavigationStack { RootView() }`
4. `RootView` switches on `authVM.status` to show the appropriate screen
5. `PushNotificationDelegate` handles APNs via `@UIApplicationDelegateAdaptor`

## Auth Flow

Auth is managed by `AuthViewModel` with these states:

```
unauthenticated → (OTP login) → checking → authenticatedNoProfile → (register)
                                         → pendingApproval → (admin approves)
                                         → trialExpired
                                         → fullyAuthenticated → MainTabView
```

- **OTP delivery:** SMS (default), WhatsApp, Voice call via `OTPDeliveryChannel`
- **Roles:** `admin`, `supervisor`, `member`, `pending` (defined in `FamilyMember.UserRole`)
- **Member statuses:** `pending`, `active`, `frozen`
- **Trial system:** 7-day trial period tracked via `trialStartedAt`/`trialEndsAt`
- **Moderation:** `canModerate` = admin OR supervisor (controls Admin tab visibility)

## Navigation

Tab-based via `MainTabView` with 5 tabs:

| Tab | View | Icon | Arabic | English |
|-----|------|------|--------|---------|
| 0 | `HomeNewsView` | house | الرئيسية | Home |
| 1 | `TreeView` | person.3 | الشجرة | Tree |
| 2 | `DiwaniyasView` | map | الديوانيات | Diwaniyas |
| 3 | `ProfileView` | person | حسابي | Profile |
| 4 | `AdminDashboardView` | shield | الإدارة | Admin (if canModerate) |

## Design System (DS)

IMPORTANT: All UI must use the centralized `DS` enum from `Components/Shared/DesignSystem.swift`. Never hardcode colors, fonts, spacing, or radii.

### Colors — `DS.Color`

- **Brand:** `primary` (#2B7A9F Ocean Blue), `primaryDark` (#1E5474), `primaryLight` (#78ACC3), `accent` (#516F80 Slate Blue), `accentDark` (#344B59), `accentLight` (#8A9EA9)
- **Neon Accents:** `neonBlue` (#5D8AA8), `neonPurple` (#89A6B1), `neonCyan` (#A3C4D3), `neonPink` (#D3AEB1)
- **Semantic:** `success` (#2F5C3E), `warning` (#B88E33), `error` (#8C2A2A), `info` (#496885)
- **Surfaces:** `background`, `surface`, `surfaceElevated` (auto light/dark mode via system colors)
- **Text:** `textPrimary`, `textSecondary`, `textTertiary`, `textOnPrimary`
- **Grid:** `gridTree` (#344B59), `gridAlerts` (#8C2A2A), `gridDiwaniya` (#2B7A9F), `gridContact` (#516F80)
- **Gradients:** `gradientPrimary`, `gradientAccent`, `gradientWarm`, `gradientCool`, `gradientDark`, `gradientAuth`, `gradientFire`, `gradientOcean`, `gradientNeon`
- Hex colors via `Color(hex: "#XXXXXX")` extension

### Typography — `DS.Font`

- Uses SF Rounded (`.system(.style, design: .rounded)`)
- Scale: `hero`, `largeTitle`, `title1`-`title3`, `headline`, `body`, `bodyBold`, `callout`, `calloutBold`, `subheadline`, `footnote`, `caption1`, `caption2`
- Dynamic Type: use `DS.Font.scaled(size, weight:)` instead of `.system(size:)` — maps sizes to appropriate text styles

### Spacing — `DS.Spacing`

- `xs: 4` | `sm: 8` | `md: 12` | `lg: 16` | `xl: 20` | `xxl: 24` | `xxxl: 32` | `xxxxl: 40`

### Corner Radius — `DS.Radius`

- `sm: 6` | `md: 10` | `lg: 14` | `xl: 18` | `xxl: 22` | `xxxl: 26` | `full: 999`

### Icons — `DS.Icon`

- SF Symbols only. Sizes: `size: 46`, `sizeSm: 38`, `sizeLg: 58`, `opacity: 0.15`

### Shadows — `DS.Shadow`

- `card` (black 0.06, r:10, y:3), `subtle` (black 0.03, r:5, y:2), `glow` (gold 0.15, r:12, y:4), `glowAccent` (green 0.12, r:10, y:4), `neon` (gold 0.15, r:12, y:3), `none`

### Animations — `DS.Anim`

- Spring-based: `bouncy` (0.35/0.6), `snappy` (0.3/0.7), `smooth` (0.5/0.8), `elastic` (0.45/0.55)
- Timed: `quick` (0.2s easeOut), `medium` (0.35s easeInOut)

## DS Components

IMPORTANT: Always use existing DS components before creating custom views.

| Component | Use For |
|---|---|
| `DSCard` | Standard solid card container with border stroke + shadow |
| `DSGradientCard` | Gradient background card with glass overlay |
| `DSGlowCard` | Card with colored border accent |
| `DSPrimaryButton` | Full-width gradient CTA (height: 58), supports `useGradient` and custom `color` |
| `DSSecondaryButton` | Outlined secondary action (height: 52) |
| `DSTextField` | Text input with icon, label, focus glow, and secure mode |
| `DSIcon` | Icon with circular tinted background (customizable size) |
| `DSActionRow` | Navigable row with icon, subtitle, badge, and RTL-aware chevron |
| `DSDataRow` | Read-only data display row |
| `DSSectionHeader` | Uppercase section title with optional icon and trailing text |
| `DSSheetHeader` | Sheet header with cancel/confirm actions and loading state |
| `DSPulseBadge` | Animated notification count badge with pulse |
| `DSStatCard` | Statistics card with circle icon background |
| `DSFloatingButton` | FAB with gradient capsule and optional label |
| `DSGradientText` | Text with gradient foreground |
| `DSRoleBadge` | Colored capsule badge for roles |
| `DSDivider` | Styled divider with horizontal padding |
| `DSDecorativeBackground` | Blurred gradient circles for decorative backgrounds |
| `DSApproveRejectButtons` | Paired approve/reject button row with loading state |

### Backwards Compatibility Components

- `UnifiedTextField` — ViewModifier for basic text field styling
- `UnifiedButtonStyle` — ButtonStyle matching DSPrimaryButton appearance

## View Modifiers

- `.glassCard(radius:)` — Solid card with border stroke + card shadow
- `.glassBackground(radius:)` — Solid background with border
- `.glassPill()` — Capsule shape with border
- `.dsCardShadow()` / `.dsSubtleShadow()` / `.dsGlowShadow()` / `.dsNeonShadow()` / `.dsAccentGlow()`
- `.dsGradientBackground()` — Primary gradient background
- `.dsBoldPress(_)` — Scale 0.95 bounce on press
- `.languageHorizontalOffset(_:y:)` — RTL-aware horizontal offset (from `DirectionalOffset.swift`)

## Button Styles

- `DSBoldButtonStyle` — Scale 0.95 + opacity 0.9 on press (default for DS buttons)
- `DSScaleButtonStyle` — Subtle scale 0.97 + opacity 0.9 on press

## Data Models

### FamilyMember (Core Model)

```swift
struct FamilyMember: Identifiable, Codable, Equatable
```

Key fields: `id`, `firstName`, `fullName`, `phoneNumber`, `birthDate`, `deathDate`, `isDeceased`, `role` (UserRole), `fatherId`, `photoURL`, `isPhoneHidden`, `isHiddenFromTree`, `sortOrder`, `bio` ([BioStation]), `status` (MemberStatus), `avatarUrl`, `isMarried`, `gender`, `createdAt`

**Nested types:**
- `UserRole`: `admin`, `supervisor`, `member`, `pending` — each has a `.color` property
- `MemberStatus`: `pending`, `active`, `frozen`
- `BioStation`: `year`, `title`, `details` — for biographical timeline

**CodingKeys** use snake_case mapping (e.g., `firstName` → `first_name`, `fatherId` → `father_id`)

### KuwaitPhone (Phone Utility)

Located in `FamilyMember.swift`. Provides:
- International phone support for 11 countries (Kuwait, Saudi, UAE, Qatar, Bahrain, Oman, Egypt, Jordan, Iraq, US, UK)
- Arabic/Eastern Arabic digit normalization
- E.164 formatting, local digit extraction, display formatting
- `normalizedForStorage()`, `detectCountryAndLocal()`, `e164()`, `display()`, `telURL()`

### NewsPost

Supports: text content, multiple images (`image_urls`), polls (`poll_question` + `poll_options`), approval workflow (`approval_status`, `approved_by`, `approved_at`). Related: `NewsPollVote`, `NewsLikeRecord`, `NewsCommentRecord`.

### AppNotification

Fields: `id`, `targetMemberId`, `title`, `body`, `kind`, `createdBy`, `createdAt`, `isRead`. Has `read` computed property and `createdDate` ISO8601 parser.

## Localization & RTL

- Use `L10n.t("عربي", "English")` for bilingual strings (from `Components/Shared/AppL10n.swift`)
- Check `L10n.isArabic` for directional logic (delegates to `LanguageManager.shared.selectedLanguage == "ar"`)
- Chevrons: `L10n.isArabic ? "chevron.left" : "chevron.right"`
- Use `DirectionalOffset.signedX()` or `.languageHorizontalOffset()` for RTL-aware positioning
- `LanguageManager` (singleton in `AuthViewModel.swift`): manages `selectedLanguage` via `@AppStorage`, provides `locale` and `layoutDirection`
- Layout direction and locale injected at app root via `.environment()` modifiers

## Logging

Use the `Log` enum from `Core/AppLogger.swift`:

```swift
Log.info("message")
Log.error("message")
Log.warning("message")
```

Uses `os.Logger` with subsystem from `Bundle.main.bundleIdentifier` and category `"App"`.

Supabase has its own `QuietSupabaseLogger` (in `SupabaseConfig.swift`) that only passes warnings and errors.

## Supabase Backend

### Client Configuration

- Client accessed via `SupabaseConfig.client` (singleton `SupabaseClient`)
- URL and anon key read from Info.plist keys (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) with hardcoded defaults
- OTP fallback endpoint for WhatsApp/Voice delivery via `SupabaseConfig.otpFallbackURL`

### Edge Functions

| Function | Purpose |
|----------|---------|
| `claude-ai` | AI assistant backend (chat, news generation, admin summaries) |
| `contact-email` | Contact form email delivery |
| `delete-account` | Account deletion logic |
| `otp-fallback` | Alternate OTP channels (WhatsApp, Voice) |
| `push-admins` | Push notifications to admin users |
| `push-notify` | General push notifications |

### Database Tables (from migrations)

Core tables: `family_members`, `admin_requests`, `notifications`, `news`, `news_poll_votes`, `news_likes`, `news_comments`, `diwaniyas`, `device_tokens`, `member_gallery_photos`

Key columns added over time: `approval_status` (news), `image_urls`/`poll_question`/`poll_options` (news media), international phone support, `gender`, `is_read` (notifications)

### Migration Naming Convention

Format: `YYYYMMDD_NNN_description.sql` or `YYYYMMDDHHMMSS_description.sql`

## Push Notifications

Handled by `PushNotificationDelegate` (UIApplicationDelegate + UNUserNotificationCenterDelegate):
- Registers for APNs on launch
- Posts `Notification.Name` events: `.didReceiveAPNSToken`, `.didReceivePushNotification`, `.didTapPushNotification`
- App entry point listens for these and calls `authVM.registerPushToken()` / `authVM.fetchNotifications()`

## ViewModels

### AuthViewModel (Central ViewModel)

The largest file (~2800+ lines). Manages:
- Authentication (OTP send/verify, session restore, sign out)
- Member data (fetch all members, current user profile, children)
- News (fetch, create, approve, polls, likes, comments)
- Admin requests (pending approvals, deceased, child add, phone change)
- Notifications (fetch, mark read, push token registration)
- Contact messages
- Feature flags for graceful degradation (`notificationsFeatureAvailable`, `newsApprovalFeatureAvailable`, `newsPollFeatureAvailable`)

Key published properties: `status`, `currentUser`, `allMembers`, `allNews`, `notifications`, `deceasedRequests`, `childAddRequests`, `phoneChangeRequests`

### AIViewModel

Invokes Supabase edge function `claude-ai` for:
- Chat conversations
- News content generation
- Admin dashboard summaries
- Family tree analysis

### DiwaniyasViewModel

Separate ViewModel for diwaniya CRUD: `fetchDiwaniyas()`, `fetchPendingDiwaniyas()`, `addDiwaniya()`, `deleteDiwaniya()`, `approveDiwaniya()`, `rejectDiwaniya()`

## Code Conventions

- SwiftUI views use `struct` conforming to `View`
- ViewModels are `@MainActor class` with `ObservableObject`
- Use `@Published` for reactive properties in ViewModels
- Use `async/await` for all asynchronous operations
- Supabase client accessed via `SupabaseConfig.client`
- Logging via `Log` enum (`Log.info()`, `Log.error()`, `Log.warning()`)
- All Codable models use `CodingKeys` with snake_case mapping to match Supabase column names
- Error handling: ViewModels catch errors and set `@Published errorMessage` strings
- Schema error detection: `AuthViewModel` has helpers to detect missing tables/columns for graceful degradation
- Appearance mode stored in `@AppStorage("appearanceMode")` with values: `"system"`, `"light"`, `"dark"`
- Views receive `selectedTab: Binding<Int>` for cross-tab navigation

## Figma MCP Integration Rules

When implementing designs from Figma using the Figma MCP server:

### Required Flow

1. Run `get_design_context` first to fetch the structured representation for the exact node(s)
2. If the response is too large, run `get_metadata` for the high-level node map, then re-fetch specific nodes
3. Run `get_screenshot` for a visual reference
4. Download any assets needed, then start implementation
5. Translate Figma output into this project's SwiftUI conventions and DS tokens
6. Validate against Figma for 1:1 visual parity

### Implementation Rules

- IMPORTANT: Treat Figma MCP output as a design reference, not final code — translate to SwiftUI + DS tokens
- IMPORTANT: Map Figma colors to `DS.Color` tokens, never hardcode hex values
- IMPORTANT: Map Figma spacing/padding to `DS.Spacing` tokens
- IMPORTANT: Map Figma corner radius to `DS.Radius` tokens
- IMPORTANT: Map Figma typography to `DS.Font` tokens (SF Rounded)
- Reuse existing DS components (`DSCard`, `DSPrimaryButton`, etc.) instead of creating new ones
- Use SF Symbols for icons — match Figma icons to the closest SF Symbol
- Respect the app's RTL/Arabic layout support
- Follow MVVM: put business logic in ViewModels, keep Views declarative

### Asset Handling

- IMPORTANT: If the Figma MCP server returns a localhost source for an image or SVG, use that source directly
- IMPORTANT: DO NOT import new icon packages — use SF Symbols
- IMPORTANT: DO NOT create placeholders if a source is provided
- Store downloaded assets in `FamilyTreeV2/FamilyTreeV2/Assets.xcassets/`
- App icons go in `AppIcon.appiconset`

## Known Issues / Notes

- **Duplicate files:** Several files have " 2" suffix copies (e.g., `MainHeaderView 2.swift`, `ContentView 2.swift`, migration files). These are backups — always edit the non-suffixed versions.
- **Dual directory structure:** Source files exist both at repo root (`/Components/`, `/Models/`, etc.) and inside `/FamilyTreeV2/` (the Xcode project). The canonical versions used by Xcode are inside `/FamilyTreeV2/FamilyTreeV2/`.
- **AuthViewModel size:** The `AuthViewModel.swift` is very large (~2800+ lines). It handles auth, members, news, notifications, admin requests, and contacts. New features should consider whether a separate ViewModel is more appropriate (like `DiwaniyasViewModel`).
