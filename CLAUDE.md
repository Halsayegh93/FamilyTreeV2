# CLAUDE.md — FamilyTreeV2

## Project Overview

FamilyTreeV2 is a native iOS family tree application for the Al-Muhammadali family (عائلة المحمدعلي). It manages genealogical data, family news, diwaniyas (gatherings), notifications, and admin operations. The app is bilingual (Arabic primary, English secondary) with RTL support.

## Tech Stack

- **Frontend:** Swift 5+ / SwiftUI (iOS native)
- **Backend:** Supabase (PostgreSQL, Auth, Storage, Edge Functions, Realtime)
- **Edge Functions:** Deno v2 runtime (TypeScript)
- **Package Manager:** Swift Package Manager (SPM)
- **AI Integration:** Claude API (`claude-haiku-4-5`) via Supabase Edge Functions
- **Push Notifications:** APNs with JWT authentication
- **Authentication:** Phone OTP (SMS, WhatsApp, Voice call fallback)

## Project Structure

```
FamilyTreeV2/
├── FamilyTreeV2/              # App entry point (FamilyTreeV2App.swift, ContentView, Info.plist, Assets)
├── Core/                      # Utilities: SupabaseConfig, AppLogger, PushNotificationDelegate
├── Models/                    # Data models (Codable structs)
│   ├── Tree/                  #   FamilyMember, MemberGalleryPhoto
│   ├── News/                  #   NewsPost
│   ├── Admin/                 #   AdminRequest, AppNotification, PhoneChangeRequest
│   ├── AI/                    #   AIModels
│   └── Diwaniyas/             #   Diwaniya
├── ViewModels/                # State management (@MainActor ObservableObject classes)
│   ├── Auth/                  #   AuthViewModel (central state hub, ~2800 lines)
│   ├── AI/                    #   AIViewModel
│   └── DiwaniyasViewModel.swift
├── Views/                     # SwiftUI screens
│   ├── App/                   #   RootView, SplashScreenView, AppIconPreview
│   ├── Main/                  #   MainTabView, MainContentView
│   └── Features/              #   Auth, Home, Tree, Admin, AI, Diwaniyas, Profile
├── Components/                # Reusable UI components
│   ├── Shared/                #   DesignSystem (DS), AppL10n (L10n), UIComponents, ImageCropperView
│   ├── Home/                  #   HomeHeaderView, NewsCardView
│   └── Tree/                  #   MemberNodeView
├── supabase/                  # Backend infrastructure
│   ├── config.toml            #   Local dev configuration
│   ├── migrations/            #   12 SQL migration files (20260209 — 20260228)
│   ├── functions/             #   Edge Functions (claude-ai, push-notify, push-admins, contact-email, otp-fallback, delete-account)
│   └── seed/                  #   seed_dummy.sql for development
├── docs/                      # MVP_ROADMAP_AR.md, figma-design-guide.md
└── Localizable.xcstrings      # String catalog for localization
```

## Architecture

**MVVM (Model-View-ViewModel)**

- **Models** — `Codable` structs with `CodingKeys` mapping Swift camelCase to Postgres snake_case
- **ViewModels** — `@MainActor class: ObservableObject` with `@Published` properties; `AuthViewModel` is the central hub managing auth state, members, news, notifications, admin requests, and more
- **Views** — SwiftUI views using `@StateObject`, `@ObservedObject`, `@EnvironmentObject`

**Key patterns:**
- `SupabaseConfig.client` is a singleton (`SupabaseClient`) used throughout
- `LanguageManager.shared` singleton manages locale, layout direction, RTL
- `L10n.t("عربي", "English")` for inline bilingual strings
- `DS.*` (DesignSystem enum) provides all design tokens: colors, typography, spacing, shadows, components
- Async/await for all network operations
- `@ViewBuilder` for composable view helpers

## Database Schema

Core tables in PostgreSQL via Supabase:

| Table | Purpose |
|-------|---------|
| `profiles` | Family members — id, full_name, first_name, phone_number, birth_date, death_date, is_deceased, role, status, father_id, sort_order, bio_json, avatar_url, is_married |
| `news` | News posts with approval workflow (pending/approved/rejected) |
| `admin_requests` | Member modification requests (phone change, deceased status, child add) |
| `diwaniyas` | Family gatherings with approval workflow |
| `notifications` | Push and in-app notifications |
| `device_tokens` | APNs device tokens |
| `news_media` | Media attachments for news |
| `news_polls` | Polls with voting |
| `member_gallery_photos` | Per-member photo galleries |

**Roles:** `pending`, `member`, `supervisor`, `admin`
**Statuses:** `pending`, `active`, `frozen`
**RLS:** Enabled on all tables with role-based policies.

## Key Conventions

### Swift Code Style
- camelCase for Swift properties, snake_case for database columns
- `CodingKeys` enums map between the two (e.g., `case firstName = "first_name"`)
- Comments in both Arabic and English are normal — preserve them
- No SwiftLint configured; follow existing formatting
- Use `DS.*` tokens for all UI styling — never hardcode colors/spacing
- Use `L10n.t("ar", "en")` for user-facing strings

### Phone Numbers
- `KuwaitPhone` utility (in `Models/Tree/FamilyMember.swift`) handles normalization, validation, E.164 formatting
- Supports 11 countries (KW, SA, AE, QA, BH, OM, EG, JO, IQ, US, GB)
- Kuwait numbers stored as raw 8 digits; international numbers stored with `+` prefix
- Arabic digit normalization (٠-٩ and ۰-۹ to 0-9)

### Supabase Configuration
- `SupabaseConfig.swift` reads URL/key from `Info.plist` with fallback defaults
- Local dev: API on port 54321, DB on port 54322, Studio on port 54323
- Migrations naming: `YYYYMMDD_NNN_description.sql`

### Edge Functions (TypeScript/Deno)
- Located in `supabase/functions/<function-name>/index.ts`
- Use `Deno.serve()` with CORS headers
- Authenticate via `Authorization` header (Supabase JWT)
- Environment variables for secrets (Claude API key, APNs key)

### Auth Flow
1. Phone number + OTP → Supabase Auth
2. Profile lookup → if exists: check role/status; if not: registration screen
3. `pending` role → waiting for admin approval screen
4. `active` status + non-pending role → full app access
5. 7-day trial period for new users

### AuthViewModel (`ViewModels/Auth/AuthViewModel.swift`)
This is the central state hub (~2800 lines). It manages:
- Authentication state (`AuthStatus` enum: checking, unauthenticated, authenticatedNoProfile, fullyAuthenticated, pendingApproval, trialExpired)
- Current user + all members list
- News feed, pending news, likes, comments, polls
- Notifications, admin requests, diwaniyas
- Push token registration
- Graceful schema error handling (missing tables/columns)

When modifying `AuthViewModel`, be careful — many views depend on its `@Published` properties via `@EnvironmentObject`.

## Supabase Local Development

```bash
# Start local Supabase
supabase start

# Apply migrations
supabase db reset

# Deploy edge functions
supabase functions serve

# Seed dummy data
psql -h localhost -p 54322 -U postgres -d postgres -f supabase/seed/seed_dummy.sql
```

## Build & Run

- Open `FamilyTreeV2.xcodeproj` in Xcode
- Resolve SPM packages (Supabase SDK)
- Build and run on iOS simulator or device
- No CI/CD pipeline configured — builds are manual via Xcode
- No automated test suite currently exists

## Common Tasks

### Adding a new database table
1. Create migration: `supabase/migrations/YYYYMMDD_NNN_description.sql`
2. Define RLS policies in the migration
3. Create corresponding Swift model in `Models/` with `Codable` + `CodingKeys`
4. Add fetch/mutate methods in the appropriate ViewModel

### Adding a new feature screen
1. Create view in `Views/Features/<Domain>/`
2. Add state properties to relevant ViewModel (usually `AuthViewModel`)
3. Add navigation in `MainTabView` or parent view
4. Use `DS.*` for styling, `L10n.t()` for text

### Adding a new Edge Function
1. Create `supabase/functions/<name>/index.ts`
2. Use `Deno.serve()`, add CORS handling
3. Authenticate with Supabase client from the auth header
4. Deploy with `supabase functions deploy <name>`

## Important Notes

- `AuthViewModel` is very large — consider whether new state belongs there or in a dedicated ViewModel
- The app targets the Al-Muhammadali family specifically — domain logic reflects family hierarchy (father_id tree)
- Arabic is the primary language; RTL layout is the default
- No automated tests exist — test manually via Xcode previews and simulator
- Secrets (Supabase URL/key) have hardcoded fallbacks in `SupabaseConfig.swift` — these should eventually move to secure build settings (`xcconfig`)
