# AlmohamadAli Figma Handoff

## Goal

Translate the current iOS SwiftUI app into a structured Figma file for:

- Screen-by-screen UI reconstruction
- Shared component extraction
- Later component-to-code mapping

This document is the source-of-truth handoff for building the Figma file from the existing app.

## Figma File Structure

Recommended file name:

`AlmohamadAli App`

Recommended top-level Figma pages:

1. `00 Cover`
2. `01 Foundations`
3. `02 Components`
4. `03 Auth`
5. `04 Main App`
6. `05 Home`
7. `06 Tree`
8. `07 Profile`
9. `08 Projects`
10. `09 Story`
11. `10 Admin`
12. `11 Overlays & Sheets`
13. `12 QR & Utility`

## Foundations

Base the visual system on the app design system in:

- [DesignSystem.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Components/Shared/DesignSystem.swift)

Key visual direction:

- Brand tone: blue + emerald + indigo
- Primary feel: glossy, modern, soft neon, family-oriented
- Surface style: elevated system surfaces with gradients and glow
- Layout language: rounded cards, floating actions, capsule chips, layered headers

Core tokens to mirror in Figma:

- Colors:
  - `primary`
  - `secondary`
  - `accent`
  - `background`
  - `surface`
  - `surfaceElevated`
  - `textPrimary`
  - `textSecondary`
  - `textTertiary`
  - semantic `success`, `warning`, `error`, `info`
- Gradients:
  - `gradientPrimary`
  - `gradientSecondary`
  - `gradientAccent`
  - `gradientHome`
  - `gradientTree`
  - `gradientProfile`
  - `gradientAdmin`
- Typography:
  - `largeTitle`
  - `title1`
  - `title2`
  - `headline`
  - `body`
  - `callout`
  - `caption1`
- Shapes:
  - rounded cards
  - capsule chips
  - circular icon buttons
- Effects:
  - soft glow
  - subtle shadow
  - overlay icon treatments over gradients

## Components To Build First

These should be reusable Figma components before drawing all screens:

1. `MainHeader`
2. `Tab Bar`
3. `Primary Button`
4. `Floating Action Button`
5. `Icon Circle Button`
6. `Section Card`
7. `Stat Card`
8. `Quick Action Tile`
9. `Search Bar`
10. `Chip / Filter Pill`
11. `Profile Avatar`
12. `List Row`
13. `Empty State`
14. `Modal Sheet Header`
15. `News Card`
16. `Story Avatar`
17. `Tree Node Card`
18. `Settings Row`
19. `Form Field`
20. `QR Card`

## Priority Screen Order

Build screens in this order:

1. Splash
2. Login
3. Home
4. Tree
5. Profile
6. Notifications Center
7. Family Photos
8. Projects
9. Story Viewer
10. Admin Dashboard
11. Remaining admin screens
12. Utility sheets and QR flows

## Screen Inventory

### App

- [SplashScreenView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/App/SplashScreenView.swift)
- [RootView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/App/RootView.swift)
- [MainTabView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Main/MainTabView.swift)

### Auth

- [LoginView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Auth/LoginView.swift)
- [RegistrationView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Auth/RegistrationView.swift)
- [WaitingForApprovalView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Auth/WaitingForApprovalView.swift)
- [FrozenAccountView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Auth/FrozenAccountView.swift)
- [DeviceLimitView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Auth/DeviceLimitView.swift)

### Home

- [HomeNewsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Home/HomeNewsView.swift)
- [HomeNewsCardView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Home/HomeNewsCardView.swift)
- [NotificationsCenterView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Home/NotificationsCenterView.swift)
- [FamilyPhotoAlbumsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Home/FamilyPhotoAlbumsView.swift)
- [ContactCenterView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Home/ContactCenterView.swift)
- [AddNewsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Home/AddNewsView.swift)
- [EditNewsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Home/EditNewsView.swift)
- [NewsCommentsSheet.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Home/NewsCommentsSheet.swift)

### Tree

- [TreeView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/TreeView.swift)
- [TreeSearchOverlay.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/TreeSearchOverlay.swift)
- [TreeEditRequestView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/TreeEditRequestView.swift)
- [MemberDetailsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/MemberDetailsView.swift)
- [AdminMemberDetailSheet.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/AdminView/AdminMemberDetailSheet.swift)

### Profile

- [ProfileView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Profile/ProfileView.swift)
- [EditProfileView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Profile/EditProfileView.swift)
- [AddChildSheet.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Profile/AddChildSheet.swift)
- [EditChildSheet.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Profile/EditChildSheet.swift)
- [PrivacySettingsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Profile/PrivacySettingsView.swift)
- [SettingsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Profile/SettingsView.swift)
- [QRCodeSheet.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Profile/QRCodeSheet.swift)
- [QRScannerView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Profile/QRScannerView.swift)
- [DeepLinkKinshipView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Profile/DeepLinkKinshipView.swift)

### Projects

- [FamilyProjectsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Projects/FamilyProjectsView.swift)
- [ProjectDetailView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Projects/ProjectDetailView.swift)

### Story

- [AddStorySheet.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Story/AddStorySheet.swift)
- [StoryViewerView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Story/StoryViewerView.swift)

### Diwaniyas

- [DiwaniyasView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Diwaniyas/DiwaniyasView.swift)

### Admin

- [AdminDashboardView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminDashboardView.swift)
- [AdminActivateAccountsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminActivateAccountsView.swift)
- [AdminAllRequestsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminAllRequestsView.swift)
- [AdminAnalyticsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminAnalyticsView.swift)
- [AdminAppSettingsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminAppSettingsView.swift)
- [AdminBannedPhonesView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminBannedPhonesView.swift)
- [AdminDevicesView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminDevicesView.swift)
- [AdminIncompleteMembersView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminIncompleteMembersView.swift)
- [AdminMembersDirectoryView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMembersDirectoryView.swift)
- [AdminMembersManagementView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMembersManagementView.swift)
- [AdminModeratorsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminModeratorsView.swift)
- [AdminNotificationsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminNotificationsView.swift)
- [AdminPendingRequestsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminPendingRequestsView.swift)
- [AdminRegisterMemberView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminRegisterMemberView.swift)
- [AdminReportsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminReportsView.swift)
- [AdminSecuritySettingsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminSecuritySettingsView.swift)
- [AdminStoriesView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminStoriesView.swift)
- [AdminTreeHealthView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTreeHealthView.swift)
- [ApprovalSheet.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/ApprovalSheet.swift)
- [AddSonByAdminSheet.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AddSonByAdminSheet.swift)

## First Three Screen Specs

### 1. Splash

Reference:

- [SplashScreenView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/App/SplashScreenView.swift)

Figma intent:

- centered brand mark
- premium gradient background
- brief loading state
- bilingual-safe spacing

### 2. Login

Reference:

- [LoginView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Auth/LoginView.swift)

Main blocks:

- animated background
- logo section
- phone entry card
- OTP entry state
- primary CTA
- helper / error / timer states

### 3. Home

Reference:

- [HomeNewsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Home/HomeNewsView.swift)

Main blocks:

- top gradient header
- quick actions
- family stories rail
- news feed
- FAB add post
- nested sub-pages for photos, projects, contact

## Code Connect Readiness

For later component mapping, prioritize these code-backed SwiftUI components:

- `MainHeaderView`
- `DSPrimaryButton`
- `DSFloatingButton`
- `PhoneNumberTextField`
- `DSProfilePhotoPicker`
- `CachedAsyncImage`
- reusable cards in the design system

Important limitation right now:

- Figma plan visible in this session is `Pro`
- Official Code Connect requires `Organization` or `Enterprise`

So next phase should be:

1. Build Figma screens and reusable components
2. Standardize component names to match SwiftUI names
3. Upgrade plan if official Code Connect is required
4. Then create mapping files / links

## Next Execution Plan

Immediate next build order inside Figma:

1. `Splash`
2. `Login`
3. `Main Tab Shell`
4. `Home`
5. `Tree`
6. `Profile`
7. `Notifications`
8. `Family Photos`
9. `Projects`
10. `Admin Dashboard`
11. all remaining screens

## Detailed Screen Specs

### Splash Screen Spec

Source:

- [SplashScreenView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/App/SplashScreenView.swift)

Frame setup:

- Device: iPhone portrait
- Background: `DS.Color.background`
- Layout: vertically centered composition with generous top and bottom breathing room

Visual structure:

1. `Animated Logo Core`
   - centered circular brand image
   - size approximately `100x100`
   - nested inside layered circular system:
     - main brand circle
     - soft glow fill
     - pulse ring
     - two angular rotating rings
     - shimmer pass layer
2. `Brand Text Stack`
   - title: `عائلة المحمدعلي / Al-Mohammadali Family`
   - subtitle: `شجرة العائلة / Family Tree`
   - centered alignment
3. `Loading Indicator`
   - 3-dot horizontal loader
   - status label: `جاري التحقق / Verifying...`

Figma build notes:

- Create the splash as a polished presentation screen, not a plain loading view
- Keep motion notes in comments:
  - logo elastic scale-in
  - text fade-in
  - pulse ring
  - dual ring rotation
  - shimmer sweep
  - dot cycling

Primary components used:

- `Brand / Logo Circle`
- `Loader / Dots`
- `Text / Brand Title`
- `Text / Brand Subtitle`

---

### Login Screen Spec

Source:

- [LoginView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Auth/LoginView.swift)

Frame setup:

- Device: iPhone portrait
- Background: top-to-center soft brand gradient over app background
- Main layout: vertically centered hero + auth card

Screen states to design:

1. `Phone Entry`
2. `OTP Verification`
3. `Error`
4. `Resend Timer Active`

Shared layout:

1. `Logo Section`
   - circular app icon
   - brand title
   - subtitle
2. `Auth Card`
   - rounded elevated card
   - glow shadow
   - compact, centered
   - max width visually around `380`

Phone entry card content:

1. country code mini input on left
2. vertical divider
3. mobile number field
4. primary CTA button:
   - default: `Continue`
   - disabled state
   - loading state
   - resend timer state

OTP card content:

1. lock icon header
2. title `Verification Code`
3. helper row showing current phone
4. edit icon to go back
5. OTP text field centered
6. error/status area
7. confirm CTA
8. resend area with timer

Figma components needed:

- `Auth / Logo Header`
- `Input / Country Code`
- `Input / Phone`
- `Input / OTP`
- `Button / Primary`
- `Status / Error Text`
- `Icon Button / Small Edit`

Interaction notes:

- state transition between phone and OTP should slide + fade
- focus border becomes primary
- disabled CTA uses inactive fill

---

### Main Tab Shell Spec

Source:

- [MainTabView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Main/MainTabView.swift)

Tabs:

1. Home
2. Tree
3. Diwaniyas
4. Profile
5. Admin when user can moderate

Design notes:

- build standard iOS bottom tab shell
- selected icon uses filled SF symbol treatment
- tint uses `DS.Color.primary`
- add optional 5th admin tab variant

Component needed:

- `Navigation / Bottom Tab Bar`

---

### Home Screen Spec

Source:

- [HomeNewsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Home/HomeNewsView.swift)
- [HomeNewsCardView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Home/HomeNewsCardView.swift)

Main sections:

1. `Main Header`
2. `Quick Actions`
3. `Stories`
4. `News Feed`
5. `Floating Add Button`

Header:

- use `MainHeader`
- gradient-backed top area
- notification trigger on the right
- strong app-home identity

Quick actions:

- horizontal chips / compact cards
- actions:
  - Photos
  - Projects
  - Contact
- each action uses icon circle + label

Stories:

- titled section
- horizontal rail
- first item is `Add Story`
- rest are family members with gradient ring
- optional count badge for multiple stories

News feed:

- section header with icon
- optional inline search row
- stacked news cards
- support post actions:
  - like
  - comment
  - report
  - delete/edit where relevant

FAB:

- bottom trailing floating plus button

Sub-page variants to design under Home:

1. `Family Photos`
2. `Family Projects`
3. `Contact Center`

Figma components needed:

- `Header / Main`
- `Action / Quick Chip`
- `Story / Circle Item`
- `Card / News`
- `Button / Floating Plus`
- `Search / Inline`

---

### Tree Screen Spec

Source:

- [TreeView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/TreeView.swift)
- [TreeSearchOverlay.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/TreeSearchOverlay.swift)
- [MemberDetailsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Tree/MemberDetailsView.swift)

Main structure:

1. `Header`
2. `Search Overlay`
3. `Interactive Tree Canvas`
4. `Floating Tool Cluster`
5. `Kinship Banner`

Canvas:

- large central scrollable area
- family hierarchy visualized as connected cards/nodes
- cards centered with lots of whitespace
- zoom states should be annotated in Figma comments, not drawn as multiple files unless needed

Header tools:

- notifications
- request tree edit
- my location in tree

Overlay tools:

- zoom controls
- reset / recenter affordances

States to include:

1. default tree
2. searched member highlight
3. kinship path highlighted
4. empty state

Supporting screens under Tree:

- `Tree Edit Request`
- `Member Details`
- `Admin Member Detail`

Figma components needed:

- `Tree / Node Card`
- `Tree / Connector`
- `Tree / Search Overlay`
- `Banner / Kinship`
- `Tool / Floating Circle`

---

### Profile Screen Spec

Source:

- [ProfileView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Profile/ProfileView.swift)
- [EditProfileView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Profile/EditProfileView.swift)
- [PrivacySettingsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Profile/PrivacySettingsView.swift)

Main sections:

1. `Profile Header`
2. `Personal Info`
3. `Favorites`
4. `Children`
5. `General Actions`

Profile header:

- large avatar with gradient ring
- user full name
- role capsule
- children count capsule
- QR actions in header area

Personal info:

- section card
- 2-column info grid
- edit CTA row

Favorites:

- horizontal avatar rail

Children:

- card section
- grid mode
- reorder mode
- add child dashed card

General actions:

- gallery
- privacy
- settings
- sign out

Utility/profile-adjacent screens to design:

- `Edit Profile`
- `Add Child`
- `Edit Child`
- `Privacy Settings`
- `Settings`
- `QR Code`
- `QR Scanner`
- `Deep Link Kinship`

Figma components needed:

- `Profile / Hero Header`
- `Info / Grid Cell`
- `List / Settings Row`
- `Card / Child Item`
- `Card / Add Child Dashed`
- `Avatar / Member`

---

### Projects Screen Spec

Source:

- [FamilyProjectsView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Projects/FamilyProjectsView.swift)
- [ProjectDetailView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Projects/ProjectDetailView.swift)

Expected layout:

- projects listing
- project cards
- project details view
- family/community visual tone

Components:

- `Card / Project`
- `Section / Project Detail`

---

### Diwaniyas Screen Spec

Source:

- [DiwaniyasView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Diwaniyas/DiwaniyasView.swift)

Expected layout:

- list / map-aware social gathering screen
- search and filters
- location-driven cards

Components:

- `Card / Diwaniya`
- `Filter / Chip`
- `Search / Bar`

---

### Story Screens Spec

Source:

- [AddStorySheet.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Story/AddStorySheet.swift)
- [StoryViewerView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Story/StoryViewerView.swift)

Views to build:

1. add story sheet
2. full-screen story viewer

Components:

- `Story / Composer`
- `Story / Viewer Header`
- `Story / Progress Rail`

---

### Notifications and Utility Spec

Source:

- [NotificationsCenterView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Home/NotificationsCenterView.swift)
- [QRCodeSheet.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Profile/QRCodeSheet.swift)
- [QRScannerView.swift](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Profile/QRScannerView.swift)

Views:

1. notifications center
2. QR display
3. QR scanner

Components:

- `List / Notification Row`
- `QR / Display Card`
- `QR / Scanner Overlay`

---

### Admin Suite Spec

Source folder:

- [Admin Views](/Users/hasan/Desktop/Xcode/FamilyTreeV2/FamilyTreeV2/FamilyTreeV2/Views/Features/Admin)

Admin first-pass priority:

1. `Admin Dashboard`
2. `Pending Requests`
3. `Members Directory`
4. `Register Member`
5. `Notifications`
6. `Reports`
7. `Tree Health`
8. `Stories`
9. `Devices`
10. `Security`
11. `App Settings`

Admin visual guidance:

- same family app system, but denser and more operational
- more stats, chips, segmented controls, filters, tables/lists
- preserve gradients, but reduce playful motion feel

Admin component set:

- `Admin / Stat Tile`
- `Admin / Filter Chip`
- `Admin / Search Row`
- `Admin / Member Row`
- `Admin / Request Row`
- `Admin / Inline Action Buttons`
- `Admin / Empty State`

## Figma Build Checklist

For each screen:

1. create iPhone frame
2. apply page background token
3. place `MainHeader` or auth header where needed
4. use shared components before drawing unique layouts
5. annotate interactions in side notes
6. name layers to match SwiftUI concepts
7. keep bilingual text spacing safe
8. build light-mode first unless a screen is explicitly dark

## Component Naming Convention

Use code-aligned names where possible:

- `MainHeader`
- `DSPrimaryButton`
- `DSFloatingButton`
- `DSSectionHeader`
- `DSCard`
- `DSMemberAvatar`
- `PhoneNumberTextField`
- `NewsCard`
- `TreeNodeCard`
- `ProfileInfoCell`

This will make later code mapping much easier even if Code Connect is delayed.
