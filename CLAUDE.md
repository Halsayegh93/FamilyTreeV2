# FamilyTreeV2 - Project Rules

## Project Overview

FamilyTreeV2 is a SwiftUI family tree app for the Al-Mohammad Ali family. It uses MVVM architecture with Supabase backend. The app supports Arabic/English bilingual UI with full RTL layout support.

## Architecture

- **Pattern:** MVVM (Model-View-ViewModel)
- **UI Framework:** SwiftUI (iOS)
- **Backend:** Supabase (auth, database, storage)
- **State Management:** `@StateObject` at root, `@EnvironmentObject` for injection, `@Published` for reactivity
- **Concurrency:** async/await with `@MainActor` on ViewModels

### Directory Structure

```
Components/Shared/       → Reusable DS components (DesignSystem.swift, UIComponents.swift)
Components/{Feature}/    → Feature-specific components (Home/, Tree/)
Models/{Domain}/         → Codable data models
ViewModels/{Domain}/     → ViewModels (AuthViewModel, AIViewModel, DiwaniyasViewModel)
Views/{Feature}/         → Feature screens (Auth, Home, Tree, Profile, Admin, AI, Diwaniyas)
Views/App/               → App-level views (RootView, MainTabView, SplashScreenView)
Core/                    → Config & logging (SupabaseConfig, AppLogger)
FamilyTreeV2/            → Xcode project files & Assets.xcassets
```

## Design System (DS)

IMPORTANT: All UI must use the centralized `DS` enum from `Components/Shared/DesignSystem.swift`. Never hardcode colors, fonts, spacing, or radii.

### Colors — `DS.Color`

- **Brand:** `primary` (#2B7A9F Ocean Blue), `primaryDark`, `primaryLight`, `accent` (#516F80 Slate Blue), `accentDark`, `accentLight`
- **Semantic:** `success` (#2F5C3E), `warning` (#B88E33), `error` (#8C2A2A), `info` (#496885)
- **Surfaces:** `background`, `surface`, `surfaceElevated` (auto light/dark mode)
- **Text:** `textPrimary`, `textSecondary`, `textTertiary`, `textOnPrimary`
- **Grid:** `gridTree`, `gridAlerts`, `gridDiwaniya`, `gridContact`
- **Gradients:** `gradientPrimary`, `gradientAccent`, `gradientWarm`, `gradientCool`, `gradientDark`, `gradientAuth`, `gradientOcean`, `gradientNeon`
- Hex colors via `Color(hex: "#XXXXXX")` extension

### Typography — `DS.Font`

- Uses SF Rounded (`.system(.style, design: .rounded)`)
- Scale: `hero`, `largeTitle`, `title1`-`title3`, `headline`, `body`, `bodyBold`, `callout`, `calloutBold`, `subheadline`, `footnote`, `caption1`, `caption2`
- Dynamic Type: use `DS.Font.scaled(size, weight:)` instead of `.system(size:)`

### Spacing — `DS.Spacing`

- `xs: 4` | `sm: 8` | `md: 12` | `lg: 16` | `xl: 20` | `xxl: 24` | `xxxl: 32` | `xxxxl: 40`

### Corner Radius — `DS.Radius`

- `sm: 6` | `md: 10` | `lg: 14` | `xl: 18` | `xxl: 22` | `xxxl: 26` | `full: 999`

### Icons — `DS.Icon`

- SF Symbols only. Sizes: `size: 46`, `sizeSm: 38`, `sizeLg: 58`, `opacity: 0.15`

### Shadows — `DS.Shadow`

- `card`, `subtle`, `glow`, `glowAccent`, `neon`, `none`

### Animations — `DS.Anim`

- Spring-based: `bouncy`, `snappy`, `smooth`, `elastic`
- Timed: `quick` (0.2s), `medium` (0.35s)

## DS Components

IMPORTANT: Always use existing DS components before creating custom views.

| Component | Use For |
|---|---|
| `DSCard` | Standard solid card container |
| `DSGradientCard` | Gradient background card with glass overlay |
| `DSGlowCard` | Card with colored border accent |
| `DSPrimaryButton` | Full-width gradient CTA (height: 58) |
| `DSSecondaryButton` | Outlined secondary action (height: 52) |
| `DSTextField` | Text input with icon and focus glow |
| `DSIcon` | Icon with circular tinted background |
| `DSActionRow` | Navigable row with icon, badge, chevron |
| `DSDataRow` | Read-only data display row |
| `DSSectionHeader` | Uppercase section title with optional icon |
| `DSSheetHeader` | Sheet header with cancel/confirm actions |
| `DSPulseBadge` | Animated notification count badge |
| `DSStatCard` | Statistics card with icon circle |
| `DSFloatingButton` | FAB with gradient capsule |
| `DSGradientText` | Text with gradient foreground |
| `DSRoleBadge` | Colored capsule badge for roles |
| `DSDivider` | Styled divider with padding |

## View Modifiers

- `.glassCard(radius:)` — Solid card with border stroke + shadow
- `.glassBackground(radius:)` — Solid background with border
- `.glassPill()` — Capsule shape with border
- `.dsCardShadow()` / `.dsSubtleShadow()` / `.dsGlowShadow()` / `.dsNeonShadow()` / `.dsAccentGlow()`
- `.dsGradientBackground()` — Primary gradient background
- `.dsBoldPress(_)` — Scale 0.95 bounce on press

## Button Styles

- `DSBoldButtonStyle` — Scale 0.95 + opacity on press (default for DS buttons)
- `DSScaleButtonStyle` — Subtle scale 0.97 on press

## Localization & RTL

- Use `L10n.t("عربي", "English")` for bilingual strings (from `Components/Shared/AppL10n.swift`)
- Check `L10n.isArabic` for directional logic
- Chevrons: `L10n.isArabic ? "chevron.left" : "chevron.right"`
- Use `DirectionalOffset` for RTL-aware horizontal positioning
- `layoutDirection` environment variable is set globally at app init

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

## Code Conventions

- SwiftUI views use `struct` conforming to `View`
- ViewModels are `@MainActor class` with `ObservableObject`
- Use `@Published` for reactive properties in ViewModels
- Use `async/await` for all asynchronous operations
- Supabase client accessed via `SupabaseConfig.client`
- Logging via `AppLogger` (OS.Logger subsystem)
- Navigation uses tab-based `MainTabView` with 5 tabs (Home, Tree, Diwaniyas, Profile, Admin)
- Auth flow managed by `AuthViewModel` with states: unauthenticated, checking, authenticatedNoProfile, pendingApproval, trialExpired, fullyAuthenticated
