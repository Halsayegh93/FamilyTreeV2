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
│   └── Admin/
│       ├── AdminRequest.swift        ← Admin action requests
│       ├── PhoneChangeRequest.swift  ← Phone change requests
│       └── AppNotification.swift     ← In-app notifications
├── ViewModels/
│   ├── Auth/
│   │   └── AuthViewModel.swift       ← Central ViewModel (~2800 lines, manages auth + data)
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
│       ├── Auth/                     ← LoginView, RegistrationView, WaitingForApprovalView, FrozenAccountView, DeviceLimitView
│       ├── Home/                     ← HomeNewsView, ContactCenterView, NotificationsCenterView
│       ├── Tree/                     ← TreeView, TreeViewPrototype, MemberDetailsView
│       │   └── AdminView/            ← AdminMemberControlView, AdminMemberDetailSheet
│       ├── Profile/                  ← ProfileView, EditProfileView, SettingsView, AddChildSheet, EditChildSheet, AddChildRequestView
│       ├── Diwaniyas/                ← DiwaniyasView
│       ├── Admin/                    ← AdminDashboardView + 15 admin management views
├── Core/
│   ├── SupabaseConfig.swift          ← Supabase client setup + OTP fallback config
│   ├── AppLogger.swift               ← Log enum (info, error, warning) via os.Logger
│   └── PushNotificationDelegate.swift ← APNs registration & notification handling
└── supabase/
    ├── config.toml                   ← Supabase CLI config
    ├── functions/                    ← Edge functions (TypeScript)
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
                                         → accountFrozen (frozen by admin)
                                         → fullyAuthenticated → MainTabView
```

- **OTP delivery:** SMS (default), WhatsApp, Voice call via `OTPDeliveryChannel`
- **Roles:** `owner`, `admin`, `monitor`, `supervisor`, `member`, `pending` (defined in `FamilyMember.UserRole`)
- **Member statuses:** `pending`, `active`, `frozen`
- **Moderation:** `canModerate` = owner OR admin OR monitor OR supervisor (controls Admin tab visibility)

### الأدوار والصلاحيات (تحديث 2026-09-21)

**المبدأ:** الدور = **مجال عمل**، لا درجة صلاحية. المصدر الواحد لنصوص الأدوار وما يقدر/لا يقدر عليه كل دور: `Core/RoleGuides.swift` (يُعرض في «الأدوار» بلوحة الإدارة، وورقة «تغيير الدور»، وبانر «مجالك»، وعند تعيين دور).

| المجال | من يعمل فيه |
|---|---|
| الشجرة والأعضاء | المالك · المدير · المراقب |
| المحتوى والبلاغات | المالك · المدير · المشرف |
| النظام (الأدوار، الأمان، الأجهزة، الأرقام المحظورة) | المالك |

| الصلاحية | المالك | المدير | المراقب | المشرف | العضو |
|---|:---:|:---:|:---:|:---:|:---:|
| دخول لوحة الإدارة (`canModerate`) | ✅ | ✅ | ✅ | ✅ | ❌ |
| **اعتماد/رفض المحتوى**: أخبار، مكتبة، مشاريع، ديوانيات (`canApproveContent` = `isAdmin`) | ✅ | ✅ | ❌ | ❌ | ❌ |
| **قبول/رفض طلبات الشجرة والأعضاء** (`canApproveTreeRequests` / `canRejectRequests` = `canModerateTree`) | ✅ | ✅ | ✅ | ❌ | ❌ |
| تعديل بيانات الأعضاء (`canEditMembers` = `canModerateTree`) | ✅ | ✅ | ✅ | ❌ | ❌ |
| معالجة صحة الشجرة | ✅ | ✅ | ✅ | ❌ | ❌ |
| حذف أخبار/تعليقات/صور (`canDeleteNews` … = `canModerateContent`) | ✅ | ✅ | ❌ | ✅ | ❌ |
| التعامل مع البلاغات | ✅ | ✅ | ❌ | ✅ | ❌ |
| إخفاء/إظهار عناصر المكتبة والمشاريع | ✅ | ✅ | ❌ | ❌ | ❌ |
| حذف ديوانيات (`canDeleteDiwaniyas`) | ✅ | ✅ | ❌ | ❌ | ❌ |
| حذف أعضاء (`canDeleteMembers`) | ✅ | ✅ | ❌ | ❌ | ❌ |
| تجميد الحسابات (`canFreezeMembers`) | ✅ | ✅ | ❌ | ❌ | ❌ |
| تسجيل عضو جديد (`canRegisterMembers`) | ✅ | ✅ | ❌ | ❌ | ❌ |
| إرسال إشعارات (`canSendNotifications`) | ✅ | ✅ | ❌ | ❌ | ❌ |
| رؤية الإحصائيات وسجل النشاط | ✅ | ✅ | ✅ | ❌ | ❌ |
| نشر أخباره بلا مراجعة (`canAutoPublishNews` = `canModerate`) | ✅ | ✅ | ✅ | ✅ | ❌ |
| تصفّح «إعدادات النظام» للقراءة (`canViewSystemSettings`) | ✅ | ✅ | ❌ | ❌ | ❌ |
| تعديل إعدادات النظام والأمان (`canManageSettings`) | ✅ | ❌ | ❌ | ❌ | ❌ |
| منح الأدوار وسحبها (`canManageRoles`) | ✅ | ❌ | ❌ | ❌ | ❌ |
| إدارة الأجهزة المرتبطة (`canManageDevices`) | ✅ | ❌ | ❌ | ❌ | ❌ |
| الأرقام المحظورة (`canManageBannedPhones`) | ✅ | ❌ | ❌ | ❌ | ❌ |
| إضافة محتوى ينتظر موافقة الإدارة | ✅ | ✅ | ✅ | ✅ | ✅ |
| تعديل ملفه الشخصي (٣ مرات ثم بموافقة) | ✅ | ✅ | ✅ | ✅ | ✅ |

**ما لا يقدر عليه كل دور (ملخّص):**
- **المالك:** لا شيء — كل صلاحيات التطبيق متاحة له.
- **المدير:** منح الأدوار، تعديل إعدادات النظام والأمان، إدارة الأجهزة، الأرقام المحظورة، تغيير دور المالك أو حذفه.
- **المراقب:** اعتماد أو رفض المحتوى، حذف المحتوى أو إخفاؤه، التعامل مع البلاغات، حذف الأعضاء أو تجميدهم، تسجيل عضو جديد، إرسال الإشعارات، وكل صلاحيات المالك.
- **المشرف:** الاعتماد النهائي للمحتوى، قبول أو رفض طلبات الشجرة، تعديل بيانات الأعضاء، حذف الأعضاء أو تجميدهم أو تسجيلهم، حذف الديوانيات، إرسال الإشعارات، رؤية الإحصائيات، وكل صلاحيات المالك.
- **العضو:** دخول لوحة الإدارة، النشر بدون موافقة، تعديل بيانات غيره أو حذف محتواه، رؤية الأرقام المخفية، رؤية الإحصائيات وسجل النشاط والطلبات.

**ملاحظات:**
- المالك (`owner`) UUID ثابت — لا يمكن ترقية أحد لمالك عبر التطبيق، ويظهر للأعضاء كـ «مدير».
- `isAdmin` = المالك أو المدير · `canModerateTree` = `isAdmin` أو المراقب · `canModerateContent` = `isAdmin` أو المشرف.
- شاشة «طلبات المراجعة» تعرض لكل دور تبويبات مجاله فقط، وأزرار الموافقة/الرفض تظهر لمن يملكها فقط (`canApprove(_:)` / `canReject(_:)` في `AdminAllRequestsView`).
- **تغيير الدور:** الضغط على صف المسؤول في «الأدوار» يفتح `ChangeRoleSheet` — بطاقات أدوار، كل بطاقة تعرض مجالها وكل «يقدر» و«ما يقدر» عند اختيارها، ثم تأكيد. السحب يترك إجراء «إزالة الصلاحية» فقط. للمالك وحده.
- كل ما يضيفه العضو (خبر، عنصر مكتبة، مشروع، ديوانية) ينتظر موافقة الإدارة، ويصلهم إشعار فوري، ويوافقون من زر النقاط في القسم نفسه أو من «طلبات المراجعة».

### حماية السيرفر (فحص الثغرات 2026-09-22)

القاعدة: **أي صلاحية في جدول الأدوار لازم يطبّقها السيرفر أيضاً** — إخفاء زر في التطبيق لا يكفي. الحراس الحالية (migrations `20260922170000`…`20260922230000`):
- `trg_zz_deceased_no_admin_role` — المتوفى لا يحمل دوراً إدارياً (يرجع «عضو» عند تسجيل الوفاة، ويُرفض تعيينه).
- `trg_profiles_protect_delete` — لا حذف للمالك ولا للنفس من التطبيق (حذف الحساب الذاتي عبر `delete-account` بمفتاح الخدمة لا يتأثر). `father_id` للأبناء يُفرَّغ تلقائياً (ON DELETE SET NULL) — لا تفرّغه قبل الحذف.
- `trg_profiles_protect_sensitive_columns` — `is_admin`/`is_hr_member`/`hr_status` للمالك فقط؛ `is_approved=true` للإدارة؛ العضو المفعّل لا يغيّر في سجله: متوفى، تاريخ الوفاة، الأب، الإخفاء، اسم العائلة. القيم غير المتغيّرة تمر.
- `trg_content_force_pending` (أخبار، مشاريع، ديوانيات، مكتبة) — محتوى غير المالك/المدير يُحفظ `pending`؛ تغيير `approval_status` لغير `pending` للمالك/المدير فقط. استثناء: المراقب/المشرف ينشرون أخبارهم مباشرة، والكل إذا أُطفئت «مراجعة الأخبار».
- الهوية من `current_profile_id()` (app_metadata) — **لا تقرأ `raw_user_meta_data` للهوية** (المستخدم يعدّلها بنفسه).
- `can_handle_admin_request(type)` — المراقب: طلبات الشجرة والأعضاء؛ المشرف: البلاغات والرسائل؛ المالك/المدير: الكل.
- `is_moderator()` يعتمد `current_user_role()` فالمجمّد يفقد صلاحياته. دوال النشاط للمالك/المدير/المراقب. دوال البحث بالرقم/الاسم ليست لـ anon.
- **الأرقام المخفية:** اقرأ الأعضاء من `members_masked` (لا `profiles` بـ `select()`)، وفي الـ embed: `member:members_masked!member_id(*)`. المرحلة الثانية (بعد تحديث الكل): إلغاء قراءة عمود `phone_number` من `profiles`.
- قبل أي تعديل على السيرفر: جرّبه داخل `begin; … rollback;` بجلسة `authenticated` (`set_config('request.jwt.claims', …)`).

### التحديث الإجباري
`app_settings.ios_min_build` / `android_min_build` (+ `ios_update_url` / `android_update_url`): أي نسخة رقم بنائها أقل تنقفل بشاشة «حدّث التطبيق» (`ForceUpdateView` / `_ForceUpdateScreen`). المالك مستثنى. التحكم من «إعدادات النظام ← التحديث الإجباري». نسخ الأندرويد القديمة تقرأ `force_update` + `latest_build` فقط («إيقاف نسخ الأندرويد القديمة»). **ارفع رقم البناء مع كل إصدار** (`CURRENT_PROJECT_VERSION` / `pubspec` + `kAppBuild`).

### إعدادات النظام (المالك والمدير فقط)
قسم واحد «الإدارة»: «استخدام التطبيق» (+ إجمالي المستخدمين = فعّال + خامل + بلا جهاز) ثم مربّعات: إعدادات التطبيق، فريق الإدارة، النشاط الآن، الأجهزة، التحديث الإجباري، الإشعارات والتحديثات، الأرقام المحظورة، حالة الإشعارات. «مهام السيرفر» و«أخطاء التطبيق» أُزيلت من التطبيق (المهام المجدولة تعمل على السيرفر). ميزة «القصص» أُزيلت كلياً.

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

Visual identity (October 2026) follows the designer's guide: navy #172536, gold #B89A5A, cream #F2EBDD. The token names and values match the website (`familytree-web/src/app/globals.css`) and the «المحمدعلي» design system. Values are light / dark.

- **Brand:** `primary` navy (#172536 / #7FA8D6), `primaryDark` (#0F1824 / #2B5F90), `primaryLight` (#5D6672 / #A9C4E4), `accent` = gold-text for text on light surfaces (#725D31 / #B89A5A), `accentDark` (#5A4927 / #9C8045), `accentLight` = gold for lines and frames (#B89A5A in both modes). `secondary` = `palm` (family green).
- **Gold rule:** gold text on light backgrounds uses `accent` (#725D31); the brighter #B89A5A is text only on navy.
- **Navy-and-gold family (عائلة الكحلي والذهبي) — the section and category colours.** The same colours the app always had (green, petrol, burgundy, slate, gold, navy), each kept in its hue but brought to one depth with a navy undertone, so they read as one family with the designer's navy and gold. Each has a text/icon colour (readable on white, black and dark cards), a `…Fill` for solid backgrounds under white text (fixed in both modes) and a `…Deep` for the tile gradient. The token names `palm`, `sea`, `sadu` and `slate` are kept for compatibility:
  - `palm` family green (#2C614B / #9ACBB1, fill #2C5846 → #10302B): family tree, members, kinship, Diwaniya cards. `secondary`, `neonCyan` point here.
  - `sea` petrol (#2C5D69 / #9AC6D2, fill #2C5460 → #112E3A): communication — messages, contact, phone. `gridContact`, `gridMessaging`.
  - `sadu` burgundy (#7B414A / #EAAAAF, fill #693940 → #382028): library, archive, photos. `neonPink`.
  - `slate` (#56606B / #B4BCC5, fill #4D5B67 → #333F49): neutral and pending. `neonPurple`, `pendingRole`.
  - Tiles also use `navyFill` (#324561 → #17263C) and `goldFill` (#806631 → #40351E).
  - Home tiles (`tileTree`…`tileContact`): green, navy, burgundy, gold, petrol — a tonal gradient from fill to deep, a navy veil at the bottom, a gold ring around the icon and the large watermark icon in gold. No Sadu diamonds on the tiles; the header keeps its white Sadu strip.
  - Roles keep their earlier hues at the family depth: owner plum (#594C7A / #C2B5E4), admin rose (#7E3F42 / #EDA9A8), monitor green (#286153 / #97CBB9), supervisor gold (#6C4F20 / #D9B88A), member blue (#32587C / #9DC2E7), pending slate. Publicly the owner shows the admin colour.
  - News types keep their earlier hues too: wedding rose (#944E62 / #F7ACBD; also `newsReminder` and `likeAction`), birth green (#316145 / #9DCBAC), death grey (#53545D / #BDBDC5), vote slate-blue (#415673 / #ABBFDD), invitation burgundy (#7C3E4C / #ECA8B2), announcement navy, congrats gold. `currentLocation` green (#2C623B / #9ACDA1), `female` rose (#92526F / #F4B1CB).
  - Rule: family colours are for sections and categories (pick by meaning). `success` / `warning` / `error` are only for real statuses (approved, pending, rejected, errors, destructive actions).
- **Semantic:** `success` (#216C4F), `warning` (#875C0A), `error` (#C0282A), `info` (#1F6FA3 / #5FA8DA — neutral notices and help links). Red badges and pills with white text use `errorFill` (#C0282A in both modes); `error` is for text and icons. Green and amber fills under white text use `successFill` / `warningFill`.
- **Fills under white text:** white (`textOnPrimary`) sits on `primaryFill` (#172536 / #2B5F90), never on `primary`, which lightens to #7FA8D6 in dark. On an adaptive colour that lightens in dark (palm, role colours, `info`…) use `onTint` for the text instead. `deceased` is `slate`; shapes under white use `deceasedFill` (= `slateFill`).
- **Surfaces:** `background` pure white / pure black (#FFFFFF / #000000), `surface` and `cardBackground` white (#FFFFFF / #1C1F25) — cards keep their border and shadow so they still lift off the white ground, `cardBackgroundSoft` cream (#F2EBDD / #23272E), `cardBorder` line (#DCCFB4 / #343A44), `cardBorderStrong` line-strong (#8A7B60 / #6B7380) for edges that must be visible (buttons, fields)
- **Text:** `textPrimary` ink (#172536 / #FFFFFF), `textSecondary` ink-muted (#4A5560 / #C9CED5), `textTertiary` ink-subtle (#6B7280 / #8A93A0), `textOnPrimary`. On band (headers, hero panels) secondary text is gold `accentLight`, not white at 70–85%.
- **Grid:** `gridTree` (= `primary`), `gridAlerts` (= `error`), `gridDiwaniya` (= `secondary`, palm), `gridContact` (= `sea`)
- **Gradients:** `gradientPrimary`, `gradientAccent`, `gradientWarm`, `gradientCool`, `gradientDark`, `gradientAuth`, `gradientFire`, `gradientOcean`, `gradientNeon`. The older names are now tonal gradients inside one family colour (fill → deep), never a mix of two colours. The identity uses flat color: `gradientPrimary` (navy #172536; #2B5F90 in dark so buttons and selected states stand out from dark cards) and `gradientAccent` are solid fills that keep their names for compatibility. Headers and hero panels use `gradientBand` (band: #172536; #1B2638 in dark, as on the website). Use these as fills only; navy text and icons use `primary`. Controls and cards are filled with one solid colour — no gradients; the only gradients are the home section tiles (same hue, fill → deep), the projects backdrop that carries the projects tile, and fading gold hairlines. Tinted icon circles use the colour at 15% (`DS.Icon.opacity`). Cards, buttons and fields have no glass; Liquid Glass stays on the tab bar, `dsGlass` and `glassPill()`.
- Hex colors via `Color(hex: "#XXXXXX")` extension

### Typography — `DS.Font`

- IBM Plex Sans Arabic everywhere — the app, the website and PDFs — for all text, titles and body (`DS.Font.Plex.*`, `Font.custom(_:size:relativeTo:)` so Dynamic Type still works). Weights 400/500/600/700 only: light/regular → Regular, medium → Medium, semibold → SemiBold, bold/heavy/black → Bold.
- Scale: `hero`, `largeTitle`, `title1`-`title3`, `headline`, `body`, `bodyBold`, `callout`, `calloutBold`, `subheadline`, `footnote`, `caption1` (500), `caption2` (600)
- Dynamic Type: use `DS.Font.scaled(size, weight:)` (or `DS.Font.plex`) instead of `.system(size:)` — it returns Plex at that size, scaling with the text style mapped from the size. Its `design:` argument is ignored.
- SF Symbols: style `Image(systemName:)` with `DS.Font.icon(size, weight:)` — the system font by text style, so symbols keep their size. Never put text on `icon()`.
- Fixed-size text inside tree nodes: `DS.Font.plexFixed(size, weight:)` (no Dynamic Type), never `.system(size:)`.
- PDFs and other UIKit drawing: `UIFont(name: DS.Font.Plex.bold, size:)` etc.

### Spacing — `DS.Spacing`

- `xs: 4` | `sm: 8` | `md: 12` | `lg: 16` | `xl: 20` | `xxl: 24` | `xxxl: 32` | `xxxxl: 40`

### Corner Radius — `DS.Radius`

- `sm: 8` | `md: 12` | `lg: 16` | `xl: 20` | `xxl: 24` | `xxxl: 28` | `full: 999`

### Icons — `DS.Icon`

- SF Symbols only. Sizes: `size: 46`, `sizeSm: 38`, `sizeLg: 58`, `opacity: 0.15`

### Logo

- The family's flat «المحمدعلي» mark: `Image("FamilyLogoNavy")` (navy; cream in dark mode) on light grounds, `Image("FamilyLogoCream")` on band and on the splash. The splash and the launch screen share `DS.Color.splashBackground` (the `LaunchBackground` colour asset): navy #172536 in light, pure black in dark. Never in a circle or badge, never shadowed or glowing; at least 32pt tall, with a quarter of its height clear on every side. The app icon (`AppIcon`, `AppIconImage`) is separate.

### Shadows — `DS.Shadow`

- `card` (black 0.06, r:8, y:2), `subtle` (black 0.03, r:4, y:1), `glow` (navy 0.16, r:14, y:4), `glowAccent` (gold 0.16, r:12, y:4), `neon` (navy 0.14, r:12, y:3), `none`

### Animations — `DS.Anim`

- Spring-based: `bouncy` (0.35/0.6), `snappy` (0.3/0.7), `smooth` (0.5/0.8), `elastic` (0.45/0.55)
- Timed: `quick` (0.2s easeOut), `medium` (0.35s easeInOut)

## DS Components

IMPORTANT: Always use existing DS components before creating custom views.

| Component | Use For |
|---|---|
| `DSCard` | Standard solid card container with border stroke + shadow |
| `DSGradientCard` | Card on a solid brand fill (navy by default) |
| `DSGlowCard` | Card with colored border accent |
| `DSPrimaryButton` | Full-width navy CTA (height: 58), flat fill, supports `useGradient` and custom `color` |
| `DSSecondaryButton` | White surface, line-strong edge, navy label (height: 52) |
| `DSTextField` | Text input with icon, label, focus glow, and secure mode |
| `DSIcon` | Icon with circular tinted background (customizable size) |
| `DSActionRow` | Navigable row with icon, subtitle, badge, and RTL-aware chevron |
| `DSDataRow` | Read-only data display row |
| `DSSectionHeader` | Uppercase section title with optional icon and trailing text |
| `DSSheetHeader` | Sheet header with cancel/confirm actions and loading state |
| `DSPulseBadge` | Notification count badge: three short pulses on appear and when the count changes, then still |
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
- `.dsGradientBackground()` — Band (deep navy) background
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
- `UserRole`: `owner`, `admin`, `monitor`, `supervisor`, `member`, `pending` — each has a `.color` property
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
- Write the family name «المحمدعلي» as one word everywhere — UI, posts and docs — the way the tree stores it. Post text joins «المحمد علي» typed with a space (`OccasionText.postText`, same as `postText` on the website). In Latin script: Al-Mohammad Ali.
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
- IMPORTANT: Map Figma typography to `DS.Font` tokens (IBM Plex Sans Arabic)
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
