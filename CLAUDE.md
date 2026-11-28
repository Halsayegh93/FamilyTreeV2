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

### الأدوار والصلاحيات (تحديث 2026-09-21، و٢٠٢٦-١١-٠٧: مقترح «أدوار الإدارة» المعتمد — «مين يشوف وش» جدول على السيرفر)

**المبدأ:** الدور = **مجال عمل**، لا درجة صلاحية. المصدر الواحد لنصوص الأدوار وما يقدر/لا يقدر عليه كل دور: `Core/RoleGuides.swift` (يُعرض في «صلاحيات الأدوار» من «فريق الإدارة»، وورقة «تغيير الدور»، و«صلاحياتي» على «اليوم» بضمير المخاطب «مجالك: …» (`mandateForSelf`)، وعند تعيين دور).

| المجال | من يعمل فيه |
|---|---|
| الشجرة والأعضاء | المالك · المدير · المراقب |
| المحتوى والبلاغات | المالك · المدير · المشرف |
| النظام — قسم «التطبيق»، ورسائل الدخول ومحاولاته والأجهزة والتسجيل والمنع (بطاقة «الدخول والأمان») | المالكان (المدير يطّلع على «الفريق والأمان»: فريق الإدارة و«الاستخدام» بس) |

**«مين يشوف وش» على السيرفر (مقترح `samples/admin-roles` بموافقة المالك ٢٠٢٦-١١-٠٧، قاعدة المالك «كل شي يكون على قاعدة البيانات»):** ظهور الأقسام الستة وبطاقات «اليوم» وصفوف الأقسام لكل دور = مفتاح `app_config.admin_role_matrix` (json، يُقرأ عبر `app_config()` ← `AppConfigValues`، ويغيّره المالك بـ`set_app_config` بلا بناء). شكله `{"admin"|"monitor"|"supervisor": {"areas": {"inbox"…"app": "edit"|"read"|"none"}, "items": {"today.census": …}, "attention_fourth": "messages"|"tree_issues"|"reports"}}`. القارئ `Core/AdminRoleMatrix.swift` (`authVM.adminAccess(_:)` / `adminSees(_:)`): مفتاح أو دور أو خانة غائبة = افتراضيه المكتوب (= المقترح)، **المالكان دائماً كل شي ولا يدخلان الجدول**، والسقف: «التطبيق» و`app.settings`/`team.sms`/`team.registration`/`team.devices` لا تُفتح لغير المالك (يرفضها فحص السيرفر `trg_app_config_role_matrix_guard` ويقصّها التطبيق). الجدول **للظهور فقط** — `canApproveContent`… وحرّاس السيرفر كما هي. الترحيل `20261107200000_admin_role_matrix` (**مطبَّق ٢٠٢٦-١١-٠٧**، تجربة `node admin_role_matrix.test.mjs` ٥٥/٥٥؛ التراجع في `supabase/rollback/`). خانة جديدة = أضفها في `AdminRoleItem` وفي قائمة `private.admin_role_matrix_problem`.
**«الوارد» حسب الجدول (٢٠٢٦-١١-٠٧):** باب «رسائل الأعضاء» (صفحة `AdminInboxView`) وجلب الرسائل وعدّاداتها ومهامها وإشعاراتها في «إشعارات الإدارة» = `inbox.messages` (المالك والمدير؛ غيرهم بلا باب ولا صفحة ولو فُتح بـ`startsWithMessages`)؛ «صور مقترحة» = `inbox.photos` دائماً لا حسب مفتاح المسار (المالك والمدير والمراقب يعالجونها، المشرف لا) — `AdminAllRequestsView.reviewIncludesPhotos(for:)` يمرّ في `tabsForRole` و`reviewRequestsTotal(includePhotos:)` ونطاق «اليوم»؛ ⚙︎ «إعدادات مسار الموافقات» في الرأس = `inbox.approval_settings` (الصفحة تقفل مفاتيحها لغير المالك)؛ المراقب على طلب انضمام بلا مسار: «حوّل للمدير» (`forwardJoinToManager` = إشعار الإدارة الموجود بـ`request_id` = العضو المعلّق، الطلب لا يتغيّر؛ مع المسار يحلّ محله «يوصي بالرفض»). السيرفر: `20261107210000_contact_messages_owner_admin` (**مطبَّق ٢٠٢٦-١١-٠٧**) — `can_handle_admin_request` بلا `contact_message` للمراقب والمشرف وسياسة القراءة تخفيها عنهما (صاحبها يقرؤها)؛ تجربته القسم الأخير في `node admin_role_matrix.test.mjs` (٧٢/٧٢)، والتراجع في `supabase/rollback/`.

| القسم / البطاقة (الافتراضي) | المالكان | المدير | المراقب | المشرف |
|---|:---:|:---:|:---:|:---:|
| كلمات مربّع «الوارد» في «اليوم» — الحقيقة الرابعة | رسائل | رسائل | مشكلات الشجرة (يقولها مربّع «العائلة») | بلاغات |
| بطاقة «العائلة» في «اليوم» (الحلقات) | ✅ | ✅ | ✅ | ❌ |
| كلمات حال «الفريق والأمان» و«التطبيق» في «اليوم» | ✅ | ❌ («مجدول اليوم N» على مربّع «المناسبات») | ❌ | ❌ |
| مكبّر الصوت | ✅ | ✅ | ❌ | ❌ |
| الوارد · الرسائل · إعدادات مسار الموافقات | يعدّل · ✅ · يعدّل | يعدّل · ✅ · يقرأ | يعدّل · ❌ · ❌ | يعدّل · ❌ · ❌ |
| العائلة | يعدّل | يعدّل | يعدّل | ❌ |
| المناسبات · البطاقات | يعدّل · ✅ | يعدّل · ✅ | للاطلاع (الذكرى + الوفيات بلا تاريخ كامل) · ❌ | يعدّل · ✅ |
| الإحصاءات | العائلة + الموافقات | العائلة + الموافقات | العائلة بس | ❌ |
| الفريق والأمان | كل شي | للاطلاع: الفريق و«الاستخدام» (`AdminActiveMembersView`) | ❌ | ❌ |
| التطبيق | ✅ | ❌ | ❌ | ❌ |

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
| تقرير الموافقات والاستخدام (`canViewInsights` = `isAdmin`؛ «الإحصاءات ← العائلة» للمراقب من الجدول) | ✅ | ✅ | ❌ | ❌ | ❌ |
| نشر أخباره بلا مراجعة (`canAutoPublishNews` = `canModerate`) | ✅ | ✅ | ✅ | ✅ | ❌ |
| ما يحرسه السيرفر للمالك: إعدادات «التطبيق»، رسائل الدخول، الأجهزة، التسجيل والمنع، كلمات حال النظام (`canViewSystemSettings` = `isOwner`) | ✅ | ❌ | ❌ | ❌ | ❌ |
| استكمال تواريخ الوفاة («إدارة تواريخ الوفاة»، `canEditMembers`) | ✅ | ✅ | ✅ | ❌ | ❌ |
| تعديل إعدادات النظام والأمان (`canManageSettings`) | ✅ | ❌ | ❌ | ❌ | ❌ |
| منح الأدوار وسحبها (`canManageRoles`) | ✅ | ❌ | ❌ | ❌ | ❌ |
| إدارة الأجهزة المرتبطة (`canManageDevices`) | ✅ | ❌ | ❌ | ❌ | ❌ |
| الأرقام المحظورة (`canManageBannedPhones`) | ✅ | ❌ | ❌ | ❌ | ❌ |
| إضافة محتوى ينتظر موافقة الإدارة | ✅ | ✅ | ✅ | ✅ | ✅ |
| تعديل ملفه الشخصي مباشرة (العضو والمشرف: N مرات لكل حقل ثم بموافقة — الحدّ على السيرفر) | ✅ | ✅ | ✅ | ✅ | ✅ |

**ما لا يقدر عليه كل دور (ملخّص):**
- **المالكان:** تغيير دور المالك الثاني أو حذفه من التطبيق (السيرفر يرفضه: `prevent_role_self_promotion` و`trg_profiles_protect_delete`) — غير ذلك كل شي.
- **المدير:** قسم «التطبيق»، رسائل الدخول ومحاولاته، الأجهزة، التسجيل والمنع (بطاقة «الدخول والأمان»)، كلمات حال النظام في «اليوم»، تعديل إعدادات مسار الموافقات (يقرؤها)، منح الأدوار (يطّلع على فريق الإدارة)، تغيير دور المالك أو حذفه.
- **المراقب:** اعتماد أو رفض المحتوى، حذف المحتوى أو إخفاؤه، البلاغات، رسائل الأعضاء الخاصة، بطاقات التهنئة والتعزية، حذف الأعضاء أو تجميدهم، تسجيل عضو جديد، إرسال الإشعارات، الاستخدام وتقرير الموافقات، وكل صلاحيات المالك.
- **المشرف:** الاعتماد النهائي للمحتوى، طلبات الشجرة والصور المقترحة، الأعضاء وأرقامهم وإحصاءاتهم، رسائل الأعضاء الخاصة، حذف الأعضاء أو تجميدهم أو تسجيلهم، حذف الديوانيات، إرسال الإشعارات، وكل صلاحيات المالك.
- **العضو:** دخول لوحة الإدارة، النشر بدون موافقة، تعديل بيانات غيره أو حذف محتواه، رؤية الأرقام المخفية، رؤية الإحصائيات وسجل النشاط والطلبات.

**ملاحظات:**
- **المالكان اثنان** (٢٠٢٦-١١) — نفس الصلاحيات؛ اعرف المالك بالدور (`role = 'owner'`) لا بمعرّف ثابت (حُذف `AuthViewModel.ownerUUID` الاحتياطي 9849ab4f). لا ترقية لمالك ولا تغيير دور مالك من التطبيق، ويظهر للأعضاء كـ «مدير».
- `isAdmin` = المالك أو المدير · `canModerateTree` = `isAdmin` أو المراقب · `canModerateContent` = `isAdmin` أو المشرف.
- **ظهور الأقسام شرط واحد** `AdminArea.isVisible(for:)` = خانة القسم في جدول السيرفر (`authVM.adminAccess(area)`، و`isReadOnly(for:)` = عين «للاطلاع» بعد كلمة مربّعه في «اليوم») — قائمة العنوان والبحث (`AdminToolCatalog`، يصفّي أدوات القسم المخفي أيضاً) و«اليوم» تقرأ منه، و`AdminAreaGate` (AdminAreaGate.swift) يحرس صفحة القسم ومداخلها الأخرى (مسار محفوظ، إشعار، رابط): لغير صاحبها رأس القسم و«هذا القسم للمالك فقط» (أو «هذا القسم ليس ضمن صلاحياتك» لما ليس سقفه المالك) بلا بيانات. إشعار KWT SMS عند غير المالك يبقيه على «اليوم»، وكلمات حال «الفريق والأمان» و«التطبيق» للمالك وحده (المدير: «مجدول اليوم N» على مربّع «المناسبات»)، ووصول الإشعارات في «المناسبات» للمالك. **السيرفر (بانتظار موافقة المالك، لم يُطبَّق):** `20261025100000_owner_only_system_areas` (sms_admin_overview · sms_balance_status · sms_login_attempts للمالك؛ app_config() القيم للجميع والتصفّح للمالك؛ تنبيهات الرصيد و«محاولات دخول مريبة» للمالك؛ RLS الأجهزة وفكّ ربطها والأرقام المحظورة وسجل الإعدادات وكتابة أسماء العوائل للمالك) و`20261025100100_insights_owner_admin_only` (approvals_report بلا المراقب) — تجربة `node owner_only_system_areas.test.mjs`؛ ودالة الحافة kwtsms-admin تقبل المدير للقراءة حتى يُغيَّر `profileAllowed(…, ["owner"])`.
- «الوارد» يعرض لكل دور أنواع مجاله فقط (`tabsForRole`)، وأزرار الموافقة/الرفض تظهر لمن يملكها فقط (`canApprove(_:)` / `canReject(_:)` في `AdminAllRequestsView`).
- **تغيير الدور:** الضغط على صف المسؤول في «فريق الإدارة» (`AdminModeratorsView`) يفتح `ChangeRoleSheet` — بطاقات أدوار، كل بطاقة تعرض مجالها وكل «يقدر» و«ما يقدر» عند اختيارها، ثم تأكيد. السحب يترك إجراء «إزالة الصلاحية» فقط. للمالك وحده.
- كل ما يضيفه العضو (خبر، عنصر مكتبة، مشروع، ديوانية) ينتظر موافقة الإدارة، ويصلهم إشعار فوري، ويوافقون من زر النقاط في القسم نفسه أو من «الوارد».

### حماية السيرفر (فحص الثغرات 2026-09-22)

القاعدة: **أي صلاحية في جدول الأدوار لازم يطبّقها السيرفر أيضاً** — إخفاء زر في التطبيق لا يكفي. الحراس الحالية (migrations `20260922170000`…`20260922230000`):
- `trg_zz_deceased_no_admin_role` — المتوفى لا يحمل دوراً إدارياً (يرجع «عضو» عند تسجيل الوفاة، ويُرفض تعيينه).
- **حذف الابن من «عائلتي» لكل عضو** (`20261016150000_remove_self_child`، طلب المالك ٢٠٢٦-١٠-١٦): `remove_self_child(p_child_id)` — أبناء المتصل فقط، بلا حساب دخول، المتوفى للمالك/المدير، يحذف طلب «إضافة ابن» المعلّق عنه، وحماية روابط العائلة تبقى؛ يُشعَر المالك والمدراء. سحب «إضافة ابن» من «طلباتي» يستدعيها أيضاً. تجربة: `node remove_self_child.test.mjs`.
- `trg_profiles_protect_delete` — لا حذف للمالك ولا للنفس من التطبيق (حذف الحساب الذاتي عبر `delete-account` بمفتاح الخدمة لا يتأثر). **لا تضع جدولاً لا يقرؤه `authenticated` (مثل `auth.users`) في نفس عبارة شرط مع غيره** — Postgres يفحص صلاحية كل جداول العبارة عند بدء التنفيذ ولو لم يُقيَّم الشق، فكان «حذف نهائي» من التطبيق يفشل (403) من ١ إلى ١٥ أكتوبر؛ الشرط الداخلي في `if` منفصل (`20261015170000_profiles_delete_guard_fix`).
- **حماية روابط العائلة (2026-10-01، `20261001150000_protect_family_links`)** — طلب المالك: «لا تفصل عن الأعضاء الربط نهائياً»:
  - روابط العائلة الست (`profiles.father_id/mother_id/husband_id` و`women_members.parent_id/mother_id/husband_id`) صارت **NO ACTION** بدل SET NULL، و`trg_family_links_protect_delete` يرفض حذف أي شخص له أبناء/بنات/زوجة مرتبطون برسالة عربية (`hint = family_links_protected`). التطبيق يحذف السجل **أولاً** (الإشعارات والأجهزة والصور تُحذف معه CASCADE) ويعرض الرسالة إن رُفض — لا تحذف المرتبطات قبله.
  - نقل الملف لمعرّف جديد (`adopt_tree_profile` عند أول دخول، `merge_member_into_tree` في «ربط بالشجرة») ينقل عقدة شجرة النساء ومن يشير لها عبر `repoint_women_node` — كان يفصل الزوجة والبنات بصمت — ويحمل روابط الشخص نفسه (أمّه، أبوه، زوجه) للعقدة الجديدة إن نقصتها (`20261001190000`؛ هكذا ضاعت أم المالك ٢٨/٩). أي دالة جديدة تنقل/تحذف ملفاً يجب أن تستدعيها قبل الحذف.
  - `trg_zzz_family_links_guard`: أي عملية بلا مستخدم (دالة سيرفر، مفتاح الخدمة، SQL صيانة) لا تفرّغ رابطاً — تبقى القيمة وتُسجَّل `blocked`. الفصل المقصود من مستخدم (إزالة زوجة، تصحيح أب) مسموح ومسجَّل. للصيانة المقصودة فقط: `set_config('family.allow_unlink','on', true)`.
  - كل تغيير في رابط يُسجَّل في `family_link_history` (قبل/بعد/من/متى) — للاسترجاع، يقرؤه المالك والمدير.
  - التراجع: `supabase/rollback/20261001150000_protect_family_links_rollback.sql`.
  - تجربة محلية قبل أي تعديل على هذه الدوال: `cd supabase/tests/family_links && npm install && node test.mjs` (قاعدة معزولة، لا تلمس السيرفر).
- `trg_profiles_protect_sensitive_columns` — `is_admin`/`is_hr_member`/`hr_status` للمالك فقط؛ `is_approved=true` للإدارة؛ العضو المفعّل لا يغيّر في سجله: متوفى، تاريخ الوفاة، الأب، الإخفاء، اسم العائلة. القيم غير المتغيّرة تمر.
- `trg_content_force_pending` (أخبار، مشاريع، ديوانيات، مكتبة) — محتوى غير المالك/المدير يُحفظ `pending`؛ تغيير `approval_status` لغير `pending` للمالك/المدير فقط. استثناء: المراقب/المشرف ينشرون أخبارهم مباشرة، والكل إذا أُطفئت «مراجعة الأخبار».
- الهوية من `current_profile_id()` (app_metadata) — **لا تقرأ `raw_user_meta_data` للهوية** (المستخدم يعدّلها بنفسه).
- **الإشعارات تبدأ مع العضو من دخوله** (طلب المالك ٢٠٢٦-١٠-٠٤، `20261004150000`): إعلانات «للجميع» (`fanout_broadcast_notification`) تُنسخ فقط لمن له **جهاز مسجّل** (`device_tokens`، معيار المالك الأشد — `20261004170000`) — لا لمجرّد اسم في الشجرة، ولا لمن أُضيف رقمه بلا دخول، ولا لمن دخل بلا جهاز. وعند ربط حساب بملف شجرة (`adopt_tree_profile` أول دخول، `merge_member_into_tree` «ربط بالشجرة») تُحذف إشعارات الملف القديمة بدل نقلها. تجربة محلية: `node notifications_start.test.mjs` في `supabase/tests/family_links`.
- **`members_masked` للقراءة فقط** (`20261004120000`): الواجهة يملكها postgres (تتجاوز RLS) فكانت الكتابة عبرها تتجاوز حماية `profiles` — سُحبت INSERT/UPDATE/DELETE. لا تكتب أبداً عبر واجهة؛ اكتب في الجدول نفسه.
- **طلبات المراجعة: السيرفر يرفض المفبرك** (`20261004200000`، `trg_guard_admin_request_insert` قبل الإدراج فقط): الموافقة/الرفض في التطبيقات تنفّذ ما في الطلب (تعديل الشجرة يكتب على `details.targetMemberId`، رفض «إضافة ابن» يحذف ملف `new_value`، قبول أي بلاغ يحذف الخبر `new_value`). لغير الإدارة (الإدارة والسيرفر وصيانة SQL خارجه): الأنواع الحية فقط، الطلب عن نفسه في كل الأنواع عدا `tree_edit`، المعلّق/المجمّد يرسل الانضمام والتواصل فقط، الحالة «معلّق» ورد الإدارة فارغ دائماً. `tree_edit`: JSON بإجراء معروف، `targetMemberId`/`parentMemberId` = `member_id` (قارن كـ uuid — الآيفون يرسل حروفاً كبيرة)، الصورة من مسار رفع مقدّم الطلب، «طلب آخر» عن نفسه بسبب `profile_*` فقط، و**الأسماء المعروضة تُكتب من السيرفر** (`details` يُعاد تسلسله كـ jsonb). `child_add`: ابن أضافه للتو (أبوه = هو، خلال ساعة، بلا حساب، غير مكرر). `content_report` لا يشير لخبر. أي نوع طلب جديد أو حقل جديد في الحمولة → حدّث الحارس وتجربته `node admin_requests_guard.test.mjs`. التراجع في `supabase/rollback/`.
- **البحث بالرقم وتحرير الرقم** (`20261004210000`): `find_profiles_by_phone` — غير المفعّل (دخول أول/تسجيل/مجمّد) يبحث برقم حسابه فقط، والمفعّل والإدارة بأي رقم (فحص «لعضو آخر» عند تغيير الرقم). `find_profile_id_by_auth_phone` داخلية فقط (لا تنفيذ للمستخدمين). `release_orphan_auth_phone` لا يفك رقم حساب يتيم نشط خلال ٢٤ ساعة (يرجع `linked` → للإدارة). تجربة: `node phone_lookup.test.mjs`.
- **الحالة والرقم** (`20261004230000`، موافقة المالك): فك الرقم (`prepare_phone_unlink`) لا يفك التجميد — المجمّد والمحذوف يبقيان؛ المراقب يغيّر الحالة من «معلّق»/بلا حالة إلى «مفعّل» كعضو فقط (التجميد وفكّه للمالك والمدير، مثل `canFreezeMembers`)؛ `free_phone_for_reregistration` (النسخ القديمة) لا تحرّر رقم أحد الإدارة أو عضو له حساب دخول (`phone_in_use`). تجربة: `node status_and_phone_guards.test.mjs`.
- **البحث بالاسم عند التسجيل يتجاهل اسم العائلة** (`20261005180000`، موافقة المالك): `search_members_by_name` يستبعد أسماء `family_names` (+ «المحمدعلي») من أجزاء الاسم المكتوب — كان «عبدالله اياد المحمدعلي» لا يجد «عبدالله اياد عبدالحميد…» فيُنشأ حساب منفصل خارج الشجرة. تجربة: `node name_search.test.mjs`. ومعه في التطبيق: لا تفعيل لحساب بلا أب (`activateAccount`)، و«موقعي» يوضّح «حسابك غير مربوط بالشجرة بعد». الموقع: «ربط» يستدعي `merge_member_into_tree` (كان يفعّل فقط).
- **حذف الحساب يُبقي الاسم** (`20261005190000`، طلب المالك «اسمه بدون عضو محذوف»): `finalize_account_deletion` لا يكتب «عضو محذوف» — الاسم والموضع والروابط تبقى كسجلّ نسب، وكل البيانات الشخصية والمحتوى وحساب الدخول تُحذف كما كانت. نصوص التأكيد وسياسة الخصوصية (iOS/Android) محدّثة. تجربة: `node keep_name_on_deletion.test.mjs`.
- **«ربط بالشجرة» بحراس** (`20261004180000`): `merge_member_into_tree` يرفض سجل شجرة لأحد الإدارة أو له حساب دخول، وحساباً جديداً لأحد الإدارة. تجربة: `node merge_guards.test.mjs`.
- **الرفع للأعضاء المفعّلين فقط** (`20261007120000`، فحص ١٠-٠٧ ع-١، موافقة المالك): كل رفع/استبدال في `storage.objects` يشترط `current_user_role()` ضمن (مالك، مدير، مراقب، مشرف، عضو) — الاستثناء الوحيد صورة المسجّل المعلّق نفسه `<معرّفه>.jpg` في `avatars` (التسجيل يرفعها بعد حفظ ملفه). سياسة رفع «القصص» حُذفت. قواعد المسار كما هي ويُقبل `current_profile_id()` بجانب `auth.uid()`. حدود المستودعات: `avatars`/`news`/`gallery`/`family-gallery` صور jpeg/png/heic/webp ≤ ١٠ ميغابايت، `family-archive` pdf + الصور ≤ ٢٥ ميغابايت — أي رفع جديد بنوع آخر (gif، فيديو) أو حجم أكبر يحتاج تعديل المستودع أولاً.
- **إعلان الوفاة للمالك والمدير ولوفاة حديثة** (`20261007130000`، م-٤): `announce_death` ترفض غيرهما (42501)، وترفض (`P0001`، `hint = death_not_recent`) وفاة بتاريخ خارج آخر ٣٠ يوماً بتوقيت الكويت (هامش يوم)، أو بلا تاريخ ولم تُسجَّل خلال ٣٠ يوماً. وقت التسجيل يختمه `trg_mark_death_recorded` (تعديل `is_deceased` إلى true في `profiles`/`women_members`) في `death_marks` (لا قراءة للتطبيقات).
- **الحذف من شجرة النساء للمالك والمدير** (`20261007140000`، م-٣): `women_members_write` (ALL) صارت `women_members_insert`/`_update` (مالك، مدير، مراقب) و`women_members_delete` (مالك، مدير) — حذف المراقب لا يمسّ صفاً بلا خطأ. الدوال (`move_child_gender`، `remove_self_*`، المزامنة) كما هي.
- **سياسات المالك بالهوية الموحّدة** (`20261007150000`، ن-٧): «Owner can update app_settings» = `current_user_role() = 'owner'` (تصمد لنقل حساب المالك وتحترم التجميد)؛ `projects_update/delete` تقبل `current_profile_id()` بجانب `auth.uid()`. تجربة الأربعة: `node audit_2026_10_07.test.mjs` (التراجع في `supabase/rollback/` يعيد الحي حرفياً).
- **بقية سياسات الإدارة بالهوية الموحّدة** (`20261007160000`، موافقة المالك ١٠-٠٧): `home_sections_write` (مالك، مدير، مراقب)، `web_sessions_admin_select` و`web_push_subs_admin_select` و`web_relatives_select` (الإدارة الأربعة)، `web_relatives_write` (مالك، مدير، مراقب) = `current_user_role()` بالأدوار نفسها — المجمّد يفقدها والحساب المنقول يحتفظ بها. لا سياسة باقية بنمط `p.id = auth.uid()` + الدور؛ أي سياسة جديدة بالدور → `current_user_role()`. تجربة: `node staff_policies_by_role.test.mjs`.
- **قرار طلبات المراجعة من السيرفر** (`20261007170000`، أ-٣، موافقة المالك ١٠-٠٧): `decide_admin_request(p_request_id, p_decision 'approve'|'reject', p_reason, p_overrides {"silent":true} لقبول إضافة الابن الجماعي فقط)` — SECURITY DEFINER: `can_handle_admin_request` + ليس طلبك (إلا المالك) + قفل + «معلّق»، ثم **نفس كتابات الآيفون السابقة** لكل نوع/إجراء والإشعارات نفسها (صاحب الطلب للمالك/المدير فقط) والإغلاق، في معاملة واحدة. الأنواع: `tree_edit` (كل الإجراءات)، `deceased_report`، `child_add`، `name_change`، `family_change`، `phone_change`، `photo_suggestion`، `news_report`، `content_report`؛ الانضمام/الربط/التواصل تبقى في التطبيقات (`unsupported_type`). أخطاؤه بـ `hint`: `not_allowed`، `own_request`، `already_handled`، `bad_payload`، `phone_in_use`، `request_not_found` (+ أخطاء الحراس كـ `family_links_protected`). ترجع `admin_push` (التطبيق يرسله لـ `push-admins`)، `death_announcement` (مربّع الإعلان)، `storage_cleanup` (حذف ملف الاقتراح بـ Storage API). الآيفون يستدعيها (`AdminRequestViewModel.decideOnServer`)؛ الأندرويد والموقع ما زالا يكتبان مباشرة. **أي تعديل على طريقة تطبيق نوع طلب → في الدالة لا في التطبيق.** المسارات القديمة لم تُسحب بعد — خطة الإقفال وجدول الأنواع في `docs/approvals-server-2026-10-07.md`. تجربة: `node decide_admin_request.test.mjs`.
- **فحص ٢٠٢٦-١٠-٢٤** (`20261024120000_descendant_edit_guard` + `20261024130000_audit_server_batch` + `20261024181150_add_or_link_self_relative`، موافقة المالك): `trg_profiles_descendant_guard` (للكتابة المباشرة من التطبيقات فقط، `current_user = authenticated`) — غير المالك/المدير/المراقب لا يغيّر في سجل غيره الوفاة/الأب/الإخفاء/اسم العائلة/الدور/الحالة، وتاريخ الوفاة يبقى، ومن له حساب دخول (`profile_has_login`) لا يُعدَّل سجله إلا ترتيب الأبناء. دوال «عائلتي» في شجرة النساء عبر `my_active_women_node()` (المفعّل فقط)، `remove/update_self_woman_child` لا تمسّ من لها حساب، والمتوفاة يحذفها المالك/المدير. `add_family_child` (لغير أبنائك) و`move_child_gender` للمالك/المدير/المراقب — المشرف خارجها. `get_members_last_signin` بـ `current_user_role()` (مالك/مدير/مراقب). `news_update_moderator` بلا المراقب، والعضو يرفع صور خبره في `news/<معرّفه>/`. حذف طلبات المراجعة للمالك/المدير + صاحب الطلب يسحب طلبه المعلّق. `trg_admin_request_payload_lock`: لا تغيير لنوع/صاحب/تفاصيل الطلب بعد دخوله المسار (`stage`). `family-archive` لا يُسرد/يُوقَّع إلا المعتمد وما رفعته والإدارة (المستودع عام حتى تُحدَّث الأندرويد والموقع). لا سرد للمستودعات العامة لغير المسجّلين. `add_or_link_self_relative(p_kind 'wife'|'mother'|'sister', p_father_id, p_woman_id?, p_name?)`: الأم/الزوجة من بنات أب في الشجرة، والأخت تحت أبيه هو (الأخت من الشجرة فقط لا من «حسابي»). تجارب: `node descendant_edit_guard.test.mjs` · `node add_or_link_self_relative.test.mjs`. التراجع في `supabase/rollback/`.
- **حدّ التعديلات الذاتية على السيرفر** (٢٠٢٦-١١-٢٨، `20261128160000` + `20261128161000`، مطبَّقان): كان المفتاح و«إعادة ضبط العدّاد» والعدّاد على الجهاز. الآن `app_config.profile_edit_limit_enabled`/`profile_free_edits`، والعدّاد لكل عضو في `profile_edit_counts` يعدّه `trg_profiles_self_edit_limit` (الميلاد، الحالة الاجتماعية، السيرة، الصورة، الرقم — العضو والمشرف فقط؛ «إظهار الرقم» خارج الحدّ) ويرفض بعده (`edit_limit_reached`). الآيفون: `ProfileEditCooldown` يقرأ `profile_edit_limits()` (`ProfileEditLimitState`، فحص PE1) عند فتح التعديل وقبل الحفظ؛ المفتاح `set_app_config(…, bool)` وإعادة الضبط `reset_profile_edit_counts()` لكل الأعضاء.
- `can_handle_admin_request(type)` — المراقب: طلبات الشجرة والأعضاء؛ المشرف: البلاغات والرسائل؛ المالك/المدير: الكل.
- **مسار الموافقات** (`20261015120000_approvals_workflow`، طلب المالك ٢٠٢٦-١٠-١٥، مرفوع والمفتاح مطفأ): خلف `app_settings.approvals_workflow` (مطفأ = المسار القديم حرفياً). العضو يرسل ← المختص (`workflow_specialist_role`: المشرف للبلاغات، المراقب لغيرها، `contact_message` خارج المسار؛ لا مختص نشط → المالك/المدير مكانه) يوصي أو يطلب معلومات ← المالك/المدير يعتمد (يرجع للمختص) أو «اعتماد وتنفيذ الحين» (تجاوز) أو يرفض (أي مرحلة) أو يرجّع ← المختص ينفّذ بمسار الموافقة القديم نفسه. المراحل في `admin_requests.stage` والسجل في `admin_request_steps`؛ الانتقال بـ `advance_admin_request(id, action, note)` فقط، و`trg_zz_admin_request_workflow` يرفض التنفيذ قبل الاعتماد (`approval_needs_manager`) حتى من النسخ القديمة. الآيفون: `ApprovalWorkflow.swift`، `AdminRequestViewModel+Approvals.swift`، `ApprovalWorkflowViews.swift`، والمفتاح في ⚙︎ «الوارد» ← «إعدادات مسار الموافقات». لا أحد يراجع طلبه هو كمختص إلا المالك (`20261015130000_approvals_owner_own_request`). «طلب معلومات» منظّم (`20261015150000_approvals_info_fields`): المختص يختار الناقص (`info_fields`: phone/birth_date/death_date/full_name/text) والعضو يرد بحقل لكل مطلوب، يفحصه السيرفر ويحفظه في `info_reply`؛ `advance_admin_request(p_request_id, p_action, p_note, p_fields, p_values)` مرشّح واحد. جانب العضو يتكلم عن «الإدارة» لا «المختص»، ويظهر مساره متى ما كان للطلب `stage` ولو لم يصل المفتاح. **مسار الموافقات ٢** (`20261016120000_approvals_v2`، ٢٠٢٦-١٠-١٦): أولوية (`priority`، الوفاة مستعجلة تلقائياً)، استلام (`assigned_to` — `claim`/`release`، المالك يأخذ، `claimed_by_other`)، تصعيد وتذكير تلقائي (`approvals_sla_tick` بمهمة pg_cron `approvals-sla` كل ١٥ دقيقة، المهل في `app_settings.approvals_*_hours`؛ المتصعّد يتصرف فيه المالك/المدير بدل المختص — `can_act_as_specialist`)، مسار سريع (`approvals_fast_types`، افتراضياً `child_add` → يبدأ عند المدير)، ردود جاهزة (`approval_templates`)، ملاحظات داخلية (`admin_request_notes`، لا يراها صاحب الطلب)، تقرير (`approvals_report(p_from, p_to)`). الآيفون: `ApprovalsV2.swift`، `AdminRequestViewModel+ApprovalsV2.swift`، `ApprovalsReportView.swift`، `ApprovalsV2SettingsViews.swift`. تجربة: `node approvals_v2.test.mjs`. الأندرويد والموقع لم يُحدَّثا بعد — لا يُشغَّل المفتاح دائماً قبلهم. تجربة: `node approvals_workflow.test.mjs`. التراجع في `supabase/rollback/`.
- **رسائل الدخول · KWT SMS للإدارة** (`20261020150000_kwtsms_daily_stats` + `20261020151000_kwtsms_admin_overview`، حيّة ٢٠٢٦-١٠-٢٠): القراءة عبر `sms_admin_overview()` وحدها (المالك والمدير، غيرهما 42501؛ `kwtsms_deliveries` و`kwtsms_daily_stats` مقفولة عن التطبيقات، بلا رقم هاتف — آخر ٤ خانات من البصمة فقط). الإجراءات عبر الدالة الطرفية `kwtsms-admin` بجلسة المستخدم: `balance`/`senderid`/`coverage`/`status`/`validate` للمالك والمدير، و`test_send` للمالك وحده لرقم ملفه مرة كل ١٠ دقائق (نقطة واحدة)؛ بيانات حساب KWT في Edge Secrets لا تخرج، والأخطاء رموز (`owner_only`، `wait_10_minutes`، `provider_error`+`provider_code`…) يترجمها `SmsAdminError`. عتبات التنبيه `app_settings.sms_low_threshold` (٠ يطفئ) و`sms_urgent_threshold` (≤ المنخفض) و`sms_low_repeat_hours`/`sms_urgent_repeat_hours` (١–١٦٨) يقرؤها `finish_kwtsms_send`، ويعدّلها المالك وحده من صفحة KWT SMS (`AppSettingsViewModel.updateSmsAlerts` يكتب الأربعة في تحديث واحد). الآيفون: `AdminSmsData.swift` (المخزن والنداءات) و`AdminSmsView.swift`/`AdminSmsSections.swift`؛ `sms_balance_status()` احتياط إن فشلت النظرة. تجربة: `node kwtsms_admin_stats.test.mjs`. التراجع في `supabase/rollback/`.
- `is_moderator()` يعتمد `current_user_role()` فالمجمّد يفقد صلاحياته. دوال النشاط للمالك/المدير/المراقب. دوال البحث بالرقم/الاسم ليست لـ anon.
- **الأرقام المخفية:** اقرأ الأعضاء من `members_masked` (لا `profiles` بـ `select()`)، وفي الـ embed: `member:members_masked!member_id(*)`. المرحلة الثانية (بعد تحديث الكل): إلغاء قراءة عمود `phone_number` من `profiles`.
- قبل أي تعديل على السيرفر: جرّبه داخل `begin; … rollback;` بجلسة `authenticated` (`set_config('request.jwt.claims', …)`).

### تحديثات ٢٠٢٦-١١-٢٧ (التسجيل الجديد، الفئات، المكرر)

- **التسجيل بعد رمز الدخول** (`SignupOriginViews.swift`، `SignupOriginRules.swift`؛ السيرفر `20261127160000_outside_family_signup`): «التسجيل» بمربّعين «من العائلة / من خارج العائلة» بلا نص فرعي ولا «مَن أنت». من العائلة: الجنس أولاً · الاسم الرباعي (٤ أجزاء، «عبد الله» جزء واحد) · تاريخ الميلاد، والصورة الكبيرة للذكر فقط بعد اختيار «ذكر»، بلا اختيار الأب (الإدارة تربطه). من خارج العائلة: الاسم الثلاثي (٣) · العائلة نصاً · الميلاد · الجنس ← الإدارة. بعد القبول «استكمال التسجيل»: «هل الأم من العائلة؟» نعم ← «اسم الوالدة الرباعي» (٤)، والوالد من الاسم المسجّل؛ لا ← تأكيد «لا يمكن تغيير هذا الاختيار لاحقاً» ثم `mark_outside_mother()` = `daughter_son_lineage.limited_at` (صلاحيات محدودة — **لا يُعرض للعضو شيء عنها**؛ القسم المخفي لا يظهر مدخله، ومن وصله برابط يرجع للرئيسية). نص رسمي، لا «أبوك/أباك/أمك» — «الوالد/الوالدة». «رجوع» يحفظ ما كُتب.
- **الزوج أو الزوجة من العائلة** (٢٠٢٦-١١-٢٨، العيّنة `reports/app-review/signup-who/spouse2.html`؛ السيرفر `20261128150000_outside_spouse_link` + `20261128151000_member_access_incomplete_limited`، مطبَّقان): «استكمال التسجيل» ثلاث نقاط — «هل الوالدة من العائلة؟» لا ← «هل أحد أفراد أسرتك من العائلة؟» (`person.3.fill`): «الزوجة» للرجل/«الزوج» للمرأة («من عائلة المحمدعلي»، رمز «خاتمان» المرسوم `SignupRingsGlyph`) · «لا يوجد» = `mark_outside_mother` (مقيّد) ← «بيانات الزوجة»: الاسم الرباعي و«المحمدعلي» ثابتة في طرف الحقل ← `submit_spouse_link(p_name)` (الإرسال وهو معلّق = تعديل الطلب نفسه ويغلق «طلب المعلومات») ← «تم إرسال البيانات» (`my_spouse_request`) و«تعديل البيانات». الطلب `lineage_request` بـ`kind = outside_spouse`. «الوارد» (`OutsideSpouseRequest.swift`، القواعد `SpouseLinkRules`): `spouse_link_suggestions` · «ربط» `link_outside_spouse(p_request_id, p_target_id, p_wife_node_id)` (الزوجة: عقدة البنت ← عقدة ذكر `is_outside_family` بمعرّف ملفه أو ربط زوجها من خارج العائلة بلا حساب؛ الزوج: الرجل ← عقدة زوجة بمعرّف ملفها `husband_id` = الرجل، وعقدة الرجل في شجرة النساء تُنشأ إن غابت) · «إضافة «فلانة» تحت والدها وربط الزوج» `add_daughter_and_link_spouse` · «طلب معلومات» `ask_join_completion([spouse_name])` (`my_completion_ask` kind = `spouse`) · «رفض» `reject_spouse_request`. بعد الربط يُحذف صفّ `daughter_son_lineage` فتصير الفئة `outside_spouse` بقاعدتها. المقاسات توكنات: `DS.TextRole.signupQuestion` ١٩، `DS.Icon.choiceTileHeight` ٩٦ و`choiceTileIcon` ٣٦ (`SignupChoiceTile`). **القيود الافتراضية على السيرفر** `app_config.member_category_access_defaults` (يقرؤه `member_access_allows` و`MemberAccess.sees(…, defaults:)`): «لم يستكمل» و«مقيّد» بلا شجرة النساء وتفاصيل الأعضاء والتعليق والإعجاب والنشر، والملف للعرض (بلا تعديل/عائلتي/«الطلبات المرسلة» `profile.my_requests`/الصورة `profile.photo`/الرقم/الرمز)؛ «مقيّد» أيضاً بلا الشجرة والديوانيات والمكتبة والمشاريع. `daughter_sons_locked_sections` = شجرة النساء وتفاصيل الأعضاء. الأقسام المقفلة تختفي بلا رسالة (`locksSilently`). **الزوجة صاحبة الحساب وزوجها من خارج العائلة:** مفتاحا «إظهار الزوج في الشجرة» و«إظهار الأبناء» داخل «الأسرة» تحت خانة الزوج (`WomanVisibilityAdminSection(mode: .own)`) عبر `women_family_set_visibility` نفسها (كانت عين خانة الزوج — أُزيلت لهذه الحالة). معاينات: `-uiPreviewSignup family[-f]|spouse[-f]|sent[-f]|admin-spouse[-found]|profile-spouse`. فحص: `tests/admin-redesign/SP1`.
- **«الوارد»:** طلبات الانضمام شريحتان «من العائلة · من خارج العائلة» برقمَي ما يظهر تحتهما، و«استكمال التسجيل» صفّ مستقل بعدده. الربط بمربّعات التسجيل نفسها (`AdminJoinBoxes.swift`): الاقتراح بالاسم الكامل، الكلمات المطابقة بالأخضر، شريحة سنة الميلاد فقط، لا صورة لمتقدّمة أنثى. «طلب استكمال البيانات» (`20261127180000`).
- **بطاقة العضو للإدارة:** «ابن بنت»/«بنت بنت» حسب الجنس · «لم يستكمل/لم تستكمل التسجيل» (صفّ نسب بلا `completed_at` ولا `limited_at`) · «أمّه/أمّها فلانة» · «صلاحيات محدودة».
- **«صلاحيات الأعضاء حسب الفئة»** (الفريق والأمان، المالك؛ `Core/MemberAccess.swift`، `MemberAccessAdminPage.swift`؛ السيرفر `20261127190000` + `20261127210000`، مطبَّقان): `app_config.member_category_access` = `{فئة: {شاشة أو شاشة.داخلية: bool}}`، الغائب = الافتراضي (كما اليوم). الفئات من `my_member_category()`: family_man · family_woman · daughter_son · daughter_daughter · incomplete («لم يستكمل التسجيل») · limited · outside_spouse (الإدارة `staff` خارجها، وحساب مراجعة أبل لا يدخل incomplete). الشاشة الأم المطفأة تُطفئ ما تحتها (رمادي + «مخفية مع الشاشة»). **الإبلاغ والحظر خارج الجدول، ظاهران دائماً.** `member_access_allows(key)` على السيرفر لما يُقرأ.
- **شجرة العائلة للرجال فقط** (`20261127130000`، `trg_zzzz_family_tree_men_only`): لا أنثى بأب في `profiles`؛ الآيفون ينبّه «شجرة العائلة للرجال فقط» واسم البنت في «إضافة ابن» ينتقل لشجرة النساء، وبعد التنبيه يبقى الجنس فارغاً حتى يختاره المستخدم. أرقام النساء مخفية عن الأعضاء تلقائياً (`20261127120000`).
- **«بنت بنت»** (`20261127150000`) بآلية «ابن بنت» نفسها؛ عقدة البنت/الابن الجديدة في شجرة النساء بمعرّف ملفه (`20261127170000`) لأن النسخ القديمة تبحث بالمعرّف.
- **تغيير الرقم عن النفس فقط** (`20261127220000`): `tree_edit` بإجراء `edit_phone` عن غيرك يُرفض (`admin_request_phone_not_self`)؛ الإدارة خارج الحارس.
- **«المكرر والأخطاء»** في «العائلة» (`AdminIssuesPage.swift`، `AdminDuplicateNames.swift`): أسماء مكررة (نفس الأب + نفس الاسم بعد التطبيع ة/ه، «أبناء فلان»/«بنات فلان»، الاسم كاملاً + عدد الأبناء + «أُضيف في»؛ «ليسا مكرّرين» محلي للجهاز) · مشكلات الشجرة الخمس · «أرقام بدون أسماء» (المالك والمدير؛ اتصال/واتساب؛ تُحذف تلقائياً بعد ٣٠ يوماً بـ`private.cleanup_nameless_signups` كل ليلة ٣:٤٠، `20261127230000`).
- **صورة زوج البنت من خارج العائلة:** لا زرّ إدارة؛ هو بنفسه، أو زوجته/ابنه باقتراح صورة (`add_photo`) من بطاقته في شجرة النساء — حين يكون له حساب فقط.
- **Sentry بالعربي:** صفحة «الأخطاء» بالعربي، ودالة `sentry-alert-ar` للبريد العربي (تحتاج خطوات المالك في المتصفح).

### التحديث الإجباري
`app_settings.ios_min_build` / `android_min_build` (+ `ios_update_url` / `android_update_url`): أي نسخة رقم بنائها أقل تنقفل بشاشة «حدّث التطبيق» (`ForceUpdateView` / `_ForceUpdateScreen`). المالك مستثنى. التحكم من «الإدارة ← التطبيق ← حالة التطبيق ← فرض التحديث». نسخ الأندرويد القديمة تقرأ `force_update` + `latest_build` فقط («إيقاف نسخ الأندرويد القديمة»). **ارفع رقم البناء مع كل إصدار** (`CURRENT_PROJECT_VERSION` / `pubspec` + `kAppBuild`).

### لوحة الإدارة «مركز القيادة» (إعادة التصميم ٢٠٢٦-١١-٢٦ — الخطة `docs/superpowers/plans/2026-11-26-admin-redesign.md`)

**القواعد:**
- **كل طلب جديد في الإدارة يتبع §A من المواصفة** `/Users/hasan/Developer/reports/admin-redesign/design-spec.md` (والنماذج `admin-redesign.html` بجانبها): أرضية بيضاء (`DS.Hub.background`)، رأس كحلي مسطّح، الذهبي على الكحلي وحده، العناوين ≤ ٢٢ والنص ١٣–١٥ والأرقام ١٥–١٧ شبه عريضة، لا عريض إلا العناوين، لمس ≥ ٤٤، كلمات عربية قصيرة. القطع من العُدّة لا من جديد: الرأس والبطاقة والصفّ والحبّة وسطر الأرقام `AdminHeaderLine` (`AdminHubKit.swift`)، الصفحة الداخلية `AdminPage` + `AdminPageHeader` (`AdminPageKit.swift`)، المربّعات (`AdminTileKit.swift`)، الفلاتر `AdminFilterPanel`/`AdminFilterSheet` (`AdminFilterKit.swift`) و`DSFilterChips(style: .admin)`/`DSSearchField(style: .admin)` (`DSAdminPage.swift`)، العقود (`AdminContracts.swift`)؛ المقاسات والألوان `DS.Hub` و`DS.Chart` و`DS.Ring` فقط.
- **لا تبويبات علوية ولا مبدّلات (`DSSegmentedSwitch`) ولا أشرطة أقسام في الإدارة.** الشرائح فلاتر فقط: بُعد واحد ≤ ٥ خيارات = صفّ شرائح يلتفّ؛ بُعدان فأكثر = ورقة «الفلاتر». اختيار عرضٍ لا فلتر = `Menu` أصلية. قائمة ثانية داخل صفحة = صفّ باب يدفع صفحتها.
- **بيت واحد لكل أمر** (spec B.7): الأمر يعمل في مكان واحد، وما سواه رقم أو صفّ باب يفتح البيت (الاستثناء: مكبّر الصوت في «اليوم» يفتح المنشئ). داخل البيت السحب والضغط المطوّل و«تحديد» اختصارات للأمر نفسه. **الرقم = القائمة (T2):** رقم بسهم يفتح قائمة أول رقم فيها يساويه؛ الصفر باهت بلا سهم ولا ضغطة؛ «—» قبل الوصول، لا صفر.
- **`AdminStoreHealth`** (`idle · loading · loaded(at:) · failed(lastGood:) · denied`، AdminContracts.swift) يحكم كل كلمة حال وحبّة وعدد شريحة ورقم رأس: التحميل هيكل رمادي **ولا يقول «تعذّر التحميل» أبداً**؛ الكلمة الهادئة («سليم»، «يعمل للجميع»، «لا جديد») بعد وصول بياناتها فقط؛ الفشل بلا بيانات «تعذّر التحميل ↻» يعيد جلب مخزنه وحده؛ الفشل بعد تحميل ناجح يبقي الكلمة + «آخر تحديث 9:12»؛ المرفوض مخفي أو للاطلاع بلا إعادة. كل مخزن تُقرأ منه كلمة له محوّل إلى هذا الحال في ملفه.
- **الصلاحية:** كل أمر = صلاحية الدور (`canApprove`، `canEditMembers`…) × «يعدّل» في جدول السيرفر `authVM.adminCanEdit(area)`. القسم «للاطلاع» بلا أزرار: سطر «للاطلاع فقط — التعديل للمالك» بقفل في رأس صفحته، وعين `eye` بعد كلمة مربّعه في «اليوم» (كلمة «للاطلاع» وحدها حين لا كلمة حال؛ القارئ الصوتي يقولها دائماً).
- **التنقّل:** المربّع والرقم وقائمة العنوان «الوارد ⌄» (`AdminAreaTitleMenu`) تمرّ بـ`AdminAreaRouter`: `.area(area, hop)` يستبدل مسار «اليوم» (لا تكدّس أقسام)، والهبوط (`AdminInboxLanding`، `AdminMembersLanding`، `AdminWomenLanding`، `AdminStatsAnchor`، `AdminOccasionsAnchor`) في `landings[hop]` يُقرأ مرة بـ`take` — المعاملات الصريحة تغلبه، ويُمسح مع كل انتقال وإعادة ضغط التبويب ومغادرته وبوابة رافضة. لا حالات جديدة في `AdminReviewDestination`. الصفحة المدفوعة لا ترث البيئة: كل دفع يمرّر `.adminArea(…)` و`.adminBackTitle(…)`، وكل دفع من «اليوم» رجوعه «الإدارة» (`AdminArea.homeTitle`، عنوان رأسه). `AdminAreaGate` يحرس كل مدخل للقسم: «هذا القسم للمالك فقط» لما سقفه المالك («التطبيق»)، وغيره «هذا القسم ليس ضمن صلاحياتك»، بلا بيانات.
- **حارس المكدس:** كل وجهة رابط خلف `AdminLazyPage { AnyView(…) }`، وكل بطاقة أو طبقة كبيرة نوع مستقل خلف `AnyView`، والمنشئ في نافذته `AdminCreateWindow`. الحدود: «اليوم» ≤ ٧٢٠ ك.ب، تبويب الإدارة ≤ ٨٠٠، الصفحات ≤ ٦٠٠، الفحص الواحد ≤ ٦٤. المقياس يرى الخيط الرئيسي والصفحات التي عليها `.debugStackProbe(…)` فقط — صفحة بلا مسبار لا تُقاس. **أدوات DEBUG** (`Core/DebugAdminProbe.swift`؛ لا تُبنى في الإصدار ولا تُحفظ في UserDefaults): `-tmpStackDepth -tmpStackCheck` (سطر `STACK page=… peakKB=… limitKB=… PASS|FAIL`)، `-tmpAdminRole owner|admin|monitor|supervisor` و`-tmpRoleMatrix '<json>'` (يغيّران ما يراه الدور فقط — السيرفر يجيب بالحساب الحقيقي، وكل كتابة عبر `DebugAdminProbe.dryRun` تُسجَّل «DRY-RUN» بنجاح مصطنع)، `-tmpFailStores sms,devices,accounts,usage,notices,inbox,census[@ثوانٍ]` (فشل مصطنع؛ `@` يفشل بعد أول تحميل ناجح)، و`scripts/admin-verify-unit.sh <unit> <screen> [--role … --fail … --stack --push …]` (بناء ← تثبيت على المحاكي ← لقطات فاتح/داكن/AX3 + أسطر الفحص). المنطق الخالص لكل وحدة يُفحص بلا محاكي: `tests/admin-redesign/<unit>/main.swift` (أمر `swiftc` في رأس كل ملف).
- **المربّعات:** مربّع القسم `AdminRowTile` **مربّع، ٣ في الصفّ** (طلب المالك ٢٠٢٦-١١-٢٧ «خل المربعات بشكل مربع ٣ جنب بعض»: الرمز في الوسط فوق ← الاسم ← سطر الحال، كلها في الوسط؛ `AdminTileGridMath.areaColumns` ٣، وعمودان من أحجام إمكانية الوصول؛ الصفّ الناقص يتوسّط بمربّعات بعرض عمود؛ المربّع يطول ولا يُقصّ إن كبر الخط) بفراغ ١٠، والاسم سطر واحد: «المناسبات» اسم مربّعها المختصر (`AdminArea.tileTitle`) و«المناسبات والإعلانات» للعنوان والقارئ الصوتي. `AdminHubTile`/`AdminTileGrid` للبحث والأدوات فقط. القوائم الثلاث (هنا، رسائل الأعضاء، مركز الإشعارات العام) بشكل واحد من `DSNoticeKit.swift` (أيام، بطاقة لكل يوم، `DSNoticeRow`).
- **الرسوم والحركة:** `DSRingGauge`/`DSMeterBar`/`DSGaugeLegend` (`DSGauges.swift`) بألوان `DS.Chart` المفحوصة (الحلقة للإحصاء وحده، والشريط ٨ للنسبة الواحدة)؛ تمتلئ وتعدّ مرة عند الظهور الأول (`DS.Ring.fill`) وبلا حركة بعدها إلا لتغيّر ≥ ١٠ نقاط/٢٠٪؛ `dsCardCascade` أول ظهور فقط؛ نبضة `dsUrgentPulse` على رمز العاجل وحده؛ النجاح `DSMomentToast` أو `dsAlert(…, moment:)`؛ «تقليل الحركة» ثابت.
- **استثناءات مقصودة:** صفر سطر الرأس أبيض ٥٥٪ (`DS.Hub.lineZero`، ٥٫٧:١)؛ بطاقات الإدارة بلا ظلّ ولا جلد طيني (إطار `DS.Hub.cardStroke`، وما يجب أن يُرى `DS.Hub.frameStroke`)؛ `hubKPI` (٢٠) خرج من الإدارة — رقم الرأس `hubLineNumber` ١٥ ومربّعات الأرقام الزجاجية حُذفت. ألوان `DS.Hub.kpi*` لمسار `.status` القديم وما لم يُرحَّل فقط.
- لا مفهوم «الجيل» في واجهة الإدارة (طلب المالك ٢٠٢٦-١٠-٢٠): لا رقم ولا عنوان ولا كلمة بحث ولا نصّ قارئ صوتي فيه «الجيل/الأجيال» (تقارير PDF مستثناة)؛ العمق مفتاح داخلي فقط. نصّ من متغيّرين → `Text(verbatim:)`. المسميات الرسمية: عضو مسجّل · مقيّد في الشجرة · طلب انضمام قيد المراجعة · حساب موقوف · متوفى؛ «تسجيل في التطبيق» · «إيقاف الحساب» · «منع الرقم من التسجيل»؛ بانتظار قرارك · عاجل · متأخر.

**«اليوم»** (تبويب «الإدارة» = `AdminDashboardView`): رأس التبويبات `MainHeaderView` بلا تعديل («الإدارة»، التحية، مكبّر الصوت `canSendNotifications` × `today.megaphone` ← المنشئ على «إعلان»، البحث `AdminSearchView`، الجرس بعدد غير المقروء وما يحتاج إجراء ← «إشعارات الإدارة») ← سطر التحية الذكي (`AdminTodayLogic`: «طلبان عاجلان في الوارد» › «اليوم ذكرى وفاة فلان» › «لم يُعلَن بعد عن وفاة فلان» › «5 طلبات بانتظار قرارك» › «انضمّ 3 أعضاء هذا الأسبوع» › «ما في طلبات — يوم هادئ»؛ زرّ يفتح بيت حقيقته) ← «العائلة» (`today.census`، `AdminCensusRings`): حلقات الإجمالي · الرجال · النساء (الحلقة نسبة الأحياء)، و«في التطبيق 170» و«خارج العائلة 50 · أحياء» (الأحياء وحدهم)، و«≈ نسبة الأحياء تقديرية» ما دام في «هل ما زالوا أحياء؟» من لم يُراجَع؛ كل رقم يفتح بيته (`AdminCensusRoutes`) ← «الأقسام»: مربّع لكل قسم ظاهر لدورك بكلمة حال بدل الشارات الحمراء — الوارد «2 عاجل · 5 بانتظارك» / «3 بلاغات» / «7 رسائل جديدة» / «لا جديد» (ترتيب `today.attention` + `attention_fourth`) · العائلة «4 مشكلات في الشجرة» / «سليمة ✓» · المناسبات «وفاة لم تُعلن» / «مجدول اليوم 2» / «ذكرى بعد 3 أيام» · الإحصاءات «170 في التطبيق» · الفريق والأمان (المالك) «محاولات مريبة» / «الرصيد منخفض» / «التسجيل متوقف» / «سليم ✓» · التطبيق «الصيانة مفعّلة» / «الإشعارات موقوفة» / «يعمل للجميع ✓»؛ الضغط يفتح القسم بهبوط ما تسمّيه الكلمة ← مكان «تواريخ الوفاة» (`DeathDatesSpot.swift`: أثناء الحملة ولمن يعدّل الأعضاء بطاقة «134 متوفى بلا تاريخ كامل» ← `DeathDatesCampaignPage`؛ بعدها «ذكرى الراحلين») ← «صلاحياتي» (المدير والمراقب والمشرف: «مجالك: …» = `RoleGuide.mandateForSelf` ← `AdminMyScopeView`) ← «آخر تحديث». تُحمَّل أرقام «العائلة» و«الوارد» أولاً ثم مخازن المربّعات بلا انتظار. الإشعار بلا `request_id` يفتح «الوارد» مصفّى بنوعه (`AdminInboxLanding(pushKind:)`)، و`.allRequests`/`.inboxItem`/`.treeEditRequests` خلف `AdminAreaGate(.inbox)`، و`sms_*` للمالك ← رسائل رمز الدخول (و«طلبات رمز الدخول» فوقها لـ`sms_suspicious`).
**«إشعارات الإدارة»** (`AdminNotificationsPage`، صفحة يفتحها الجرس وحده — ليست قسماً): شرائح بُعد واحد تلتفّ (الكل · يحتاج إجراء N · تغييرات الأعضاء · نشاط الفريق · النظام) ← البحث ← «12 غير مقروء … قراءة الكل» (زرّ نصّي كحلي) ← «يحتاج إجراء الآن» (حالات `AdminNoticeStore` + إشعارات الطلبات المعلّقة + `sms_suspicious` غير المقروء، بزرّ البيت: «إعلان» · «مراجعة» · «راجع» · «شحن الرصيد») ← الأيام. بيت «مقروء» و«حذف» (سحب، ضغط مطوّل، «تحديد») و«تنبيه» على «تمت إضافة ابن» (و«الملف» يفتح ورقة العضو) و«ما تغيّر» قبل ← بعد (`AdminNoticeDetailBox`). **مكان واحد لكل إشعار** (`AdminNotices.category`): للإدارة لا يظهر الإداري في مركز الإشعارات العام ولا في عدّاد جرسه، ويبقى هناك ما يخصّ العضو نفسه.
**«الوارد»** (`AdminAllRequestsView`): الرأس «الوارد ⌄» · ⚙︎ «إعدادات مسار الموافقات» (`AdminAppSettingsView(scope: .approvals)`، `inbox.approval_settings`) · «تحديد»، و«مجالك: …» للمراقب والمشرف، وسطر «بانتظار قرارك · عاجل · متأخر» (كل رقم يضبط «الحالة») ← أبواب «رسائل الأعضاء» (`AdminInboxView` صفحةً، `inbox.messages`) و«بانتظار المراجعة» (`PostReviewQueuePage`) ← شريط الفلاتر (بحث + ورقة: الحالة · المجموعة · النوع · المصدر) ← «الموافقة على كل طلبات إضافة ابن» ← باب «طلبات الخصوصية» ← الطلبات بالأيام ← باب «المنجز» (`AdminInboxHandledPage`، آخر ٣٠ يوماً للعرض). مربّع الطلب (`dsTallBox`) بشريط قرار سفلي: يتقدّم للطلب المعلّق التالي بعد نجاح مؤكَّد فقط وحين فُتح من القائمة (المفتوح بـ`focusId` يُغلق بعد القرار)، والخطأ يبقيه برسالة `hint` السيرفر. السحب (الطرف: «رفض» + «المزيد»، البداية: الموافقة + «حذف») والضغط المطوّل الأوامر نفسها. `focusId` · `initialFilter` · `initialSearch` · `startsWithMessages` (يدفع صفحة الرسائل لمن يملكها). رقم «الوارد» = ما طلبه أحد (`reviewRequestsTotal`) — «مشكلات الشجرة» بيتها «العائلة».
**«العائلة»** (`AdminMembersPage`): الرأس «العائلة ⌄» · ＋ تسجيل عضو (`canRegisterMembers`) · ⋯ «تقرير PDF» بالفلاتر الحالية (`isAdmin`، `AdminReportsView(scope:)`) · «2,729 رجل · 262 امرأة ‹ · 50 خارج العائلة ‹» ← صفّ «يحتاج مراجعتك» (`AdminReviewHubPage`: مشكلات الشجرة · هل ما زالوا أحياء؟ · تواريخ وفاة ناقصة ← `DeathDatesCampaignPage` · بيانات ناقصة · لم يفتحوا التطبيق · لم يدخلوا ٢١ يوماً، كلٌّ `AdminReviewListPage`) ← شريط الفلاتر (الحساب · الحالة · الفرع) ← القائمة (بالفروع بلا فلتر، وإلا أبجدياً؛ «عرض المزيد» كل ٤٠) ← ورقة العضو `AdminMemberSheet(ids:start:)` (بيت كل أوامر العضو: البيانات، النسب، «تسجيل في التطبيق»، الأجهزة و«تسجيل خروج» `canManageDevices`، «إيقاف الحساب» `canFreezeMembers`، الحذف؛ «منع الرقم» يفتح «التسجيل والمنع» بالرقم مملوءاً). «نساء العائلة» صفحة (`AdminWomenPanel(landing:)`، المالك والمدير؛ المراقب ← شجرة النساء). الحالات من إشارات العميل (`AdminMembersModel.swift`). «هل ما زالوا أحياء؟» (`AdminLivingCheck`): «حي ✓» محلية لكل مستخدم (`AdminLivingVerifiedStore`)، و«متوفى» = `AdminMemberDetailSheet(deathOnly: true)`.
**«المناسبات والإعلانات»** (`AdminOccasionsPage`): الرأس «＋ إنشاء» الذهبي ← المنشئ الواحد `AdminCreateWindow` («ماذا تنشئ؟» بأنواع دورك وحدها: إعلان · إعلان وفاة `DeathAnnouncementBox` · بطاقة تهنئة أو تعزية · إعلان تحديث التطبيق) وأرقام «وفاة لم تُعلن · مجدولة · ذكرى هذا الأسبوع» ← «أفراح العائلة» («بطاقة» على كل فرح) ← «عزاء وذكرى» (وفاة لم تُعلن «إعلان»، ذكرى ٣٠ يوماً، «متوفون بلا تاريخ وفاة كامل ‹») ← «الإعلانات عند الفتح» («إيقاف» بتأكيد) ← «الإعلانات» (مجدول «تعديل» · «إلغاء الموعد»، «المنشور ‹»، «تصل الإشعارات إلى N جهازاً ‹» للمالك). المراقب للاطلاع. الإعلان: النص · لمن (الكل · دولة · أعضاء) · متى، وزرّ واحد يقول ما سيحدث؛ الخبر `postNews(type: «إعلان», asAdminIdentity: true)` والإشعار `sendNotification`/`scheduleNotification(kind: admin_broadcast)` — إشعار واحد للأعضاء (`postNews(notifyAdmins: false)` حين يصل الإعلان للجميع).
**«الإحصاءات»** (كانت «المؤشرات»؛ `rawValue` `metrics`؛ الجذر `AdminMetricsAreaView` = صفحة `AdminAnalyticsView` نفسها): العائلة (الحلقات) · الراحلون · في التطبيق («170 لهم حساب») · جديد في الشجرة · الأعمار · الأدوار · الشجرة · خارج العائلة (الأحياء وحدهم) · «الموافقات» (← `ApprovalsReportView`، بيت تقرير الموافقات الوحيد) ثم «آخر تحديث». أقسام العائلة بخانة `metrics.family`، و«الموافقات» بـ`metrics.approvals` + مفتاح المسار؛ لا هذه ولا تلك = بطاقة فارغة تقول لماذا. الهبوط `AdminStatsAnchor` («في التطبيق» للمراقب؛ للمالك والمدير «في التطبيق 170 من 2,991» أخضر `DS.Hub.bandInApp` يفتح «العائلة» على {رجال، نساء} · لهم حساب · الأحياء = 170 بأسمائهم، و«خارج العائلة» على {خارج العائلة}؛ وحبّة «انضمّ 19 عضواً هذا الأسبوع» ٣٢ ولمسها ٤٤ تفتح «العائلة» على `AdminMembersLanding.joinedThisWeek` بالقاعدة الواحدة `AdminMembersLogic.joinedThisWeek` — طلب المالك ٢٠٢٦-١١-٢٧). «المؤشرات» كلمة بحث فقط.
**«الفريق والأمان»** (`AdminTeamArea`؛ المدير للاطلاع: «فريق الإدارة» و«الاستخدام»): بطاقة الحالة «الدخول والأمان» (المالك؛ حبّة «سليم ✓» / «شيئان يحتاجانك» / «تعذّر التحميل ↻») بصفّ لكل بيت: رسائل رمز الدخول (`AdminSmsView`، صفحة `AdminPage` بشكل v2 منذ ٢٠٢٦-١١-٢٧: حلقة الرصيد الكبيرة على الكحلي بكلمة حاله وكم يكفي و«شحن الرصيد» الذهبي — رابط الشحن الوحيد `SmsBalanceStore.rechargeURL` — و«تحديث الرصيد الآن»، ثم أقسام `SmsPageLogic.sections`: رموز الدخول المرسلة (اليوم/٧/٣٠ + هذه الساعة) · آخر 30 يوماً · آخر الإرسالات · «إعدادات الإرسال» صفوفاً مكانها الوحيد (لم تعد صفحة من ⋯؛ مهلة الرمز `sms_wait_seconds` ٣٠–٦٠٠) · حماية رسائل الدخول · تنبيهات الرصيد · الأدوات · صفّ «طلبات رمز الدخول» بحبّة المريبة غير المقروءة · «طريقة العمل» مطويّة) · محاولات دخول مريبة ← «طلبات رمز الدخول» (`SmsAttemptsListPage`، `sms_login_attempts(p_days)`؛ أعلاها «محاولات دخول مريبة» بالمعنى و«تم الاطلاع على الكل»، ولكل رقم مريب بطاقة `SmsSuspiciousCard`: المعنى، «لمن الرقم؟» (`find_profiles_by_phone`)، و«تم الاطلاع» (قراءة تنبيهات `sms_suspicious` لرقمه — نصّ التنبيه ينتهي بالرقم) · «اتصال» · «امنع الرقم من التسجيل» (`authVM.banPhone` نفسه، بتأكيد يقول إن حساب صاحبه يُوقَف — `freeze_member_on_ban`)؛ منطقها `AdminSmsLogic.swift`، فحصه `tests/admin-redesign/S1`. «اعرض الرمز» حُذف ٢٠٢٦-١٠-٢٩ — لا دالة له على السيرفر) · التسجيل والمنع (`AdminRegistrationBansView(prefillPhone:)`) · الأجهزة والإشعارات (`AdminPushHealthView`؛ `AdminDeviceReachStore` رقم واحد هنا وفي «المناسبات» و«اليوم») ← «فريق الإدارة» (باب `AdminModeratorsView`: الإضافة وتغيير الدور `ChangeRoleSheet` والإزالة و«صلاحيات الأدوار») ← «الاستخدام» (← `AdminActiveMembersView`).
**«التطبيق»** (`AdminAppArea`، للمالك وحده): بطاقة الحالة «حالة التطبيق» (الإصدار + «يعمل للجميع ✓» / «متوقف للأعضاء»؛ «وضع الصيانة» يسأل عند التشغيل فقط، «إشعارات الجوال» يسأل عند الإيقاف فقط، «فرض التحديث» ‹ `AdminForceUpdateView`) ← «ما يراه الأعضاء» ← «قواعد الأعضاء» (اعتماد الأخبار، منع لقطة الشاشة في المكتبة، حدّ التعديلات الذاتية، «إعادة ضبط العدّاد») ← «القوائم» (التصنيفات، «أسماء العوائل والفروع» `AdminFamilyNamesView`، أسماء عن التطبيق) ← «النظام» («الأخطاء» Sentry `AdminErrorsPage`، آخر تعديل، «استعادة الإعدادات الافتراضية»). الحفظ دوّارة صغيرة، والفشل يرجع القيمة + «لم يُحفظ. أعد المحاولة».
**تواريخ الوفاة:** البيت الوحيد `DeathDatesCampaignPage` (بحث وفلاتر، «أدخل التاريخ» ← `DeceasedDateBox` = `updateMemberHealthAndBirth` بلا إشعار). التخزين `profiles.death_date` — السنة وحدها YYYY-01-01، والسنة < 1700 هجري، و`death_date_unknown` قرار «غير معروف». مدة الحملة من `app_config` (`death_dates_campaign` + `death_dates_campaign_until`، ترحيل `20261025110000_death_dates_campaign_config` بانتظار موافقة المالك). كل قائمة تعرض تاريخاً غير كامل تكتب «لا يوجد تاريخ كامل للوفاة» (`AdminOccasionsText.deathLine`).
**أسماء الفروع** (`app_settings.branch_names jsonb` = `{"<uuid رأس الفرع بحروف صغيرة>": "الاسم"}`، `20261009120000`، القراءة لكل مسجّل والتعديل للمالك): تُسمّى من «التطبيق ← أسماء العوائل والفروع ← أسماء الفروع» (`BranchPickerSheet(renamesBranches: true)`، المسح = حذف المفتاح)، وتظهر في صفوف قائمة الفروع فقط (`BranchPickerSheet`، عناوين الفروع في «العائلة»؛ `AppSettingsViewModel.branchName(for:)`). القائمة بلا حقل بحث افتراضياً (`showsSearch: false`).

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

### Logo

- The family's flat «المحمدعلي» mark: `Image("FamilyLogoNavy")` (navy; cream in dark mode) on light grounds, `Image("FamilyLogoCream")` on band and on the splash. The splash and the launch screen share `DS.Color.splashBackground` (the `LaunchBackground` colour asset): navy #172536 in light, pure black in dark. Never in a circle or badge, never shadowed or glowing; at least 32pt tall, with a quarter of its height clear on every side. The app icon (`AppIcon`, `AppIconImage`) is separate.

### Sections — `AppSection` (mechanism kept from «كل قسم بلونه»، ٢٠٢٦-١٠-٠٤؛ colours = identity since the 2026-10-17 merge)

- **Section chrome = `AppSection` (`Components/Shared/AppSection.swift`).** Since the merge with main's identity every section (the 5 tabs and `.library/.projects/.news`) resolves to the identity navy: header `headerGradient` = `gradientBand`, `fill` = `primaryFill`, `ink` = `primary`, `control` = `headerControlFill`, `gradient` (action buttons) = flat `gradientPrimary`. Home tiles are NOT section colours: they use the navy-and-gold family tile tokens (`tileTree` palm, `tileDiwaniya` navy, `tileLibrary` sadu, `tileProjects` gold, `tileContact` sea; `AppSection.HomeTile.library/projects/news` fill/deep/ink = sadu / gold / navyFill). The pre-merge per-section palette «البحري الخفيف» is in the history of `wip/ios-2026-10-02`. **Exception (2026-10-23):** `.projects` and `.library` take their colours from their home tile (`HomeTile.tile(for:)` — one source): `fill` = tile fill (gold #806631 / sadu #693940), `deep`/`control` = tile deep, `ink` = tile ink (`accent` / `sadu`), header = tile gradient fill → deep, action buttons flat tile fill; their header subtitle is cream `headerSubtitleOnTile` (#F2EBDD) via `AppSection.headerSubtitle`.
- **How it flows:** `MainTabView` puts `.dsSection(.home/.tree/.diwaniyas/.profile/.admin)` on each tab's content (both TabView code paths) → `@Environment(\.dsSection)` + `.tint(section.ink)`; the tab-bar tint is the selected tab's ink; `AppSection.current` tracks the selected tab for UI in separate windows (`dsAlert`/`DSPopupPresenter`, date picker, death notice). `dsCenterBox` / `dsTallBox` / `dsHalfBox` / `dsExtraBox` / `DSCenterPanel` / `DSExpandableCenterPanel` re-apply the section inside the presentation. Outside the tabs (login, splash, onboarding) the section is nil → brand navy.
- **Pages/boxes of a section without a tab:** put `.dsSectionPage(.library/.projects/.news/.admin)` on their ROOT (`FamilyArchiveView`, `FamilyProjectsView`, `AddProjectView`/`EditProjectView`, `MemberContactFormView` (→ `.admin` only inside the tabs), `AddNewsView`, `EditNewsView`, `NewsCommentsSheet`, and the boxes they open in a `fullScreenCover`) = `.dsSection` + registers the page while visible, so `AppSection.current` returns it (last open page of the selected tab, else the tab) for separate windows; it unregisters on disappear. Inside those screens use `AppSection.<section>.ink/fill` (or env-mapped `DS.Color.primary.dsChrome(in: section)` in views reused elsewhere). The Home sub-page header (`HomeNewsView.subPageHeader`) must take the page's section gradient, not `AppSection.home`.
- **Shared components map navy for you:** `DS.Color.primary` → `section.ink`, `DS.Color.actionNavy` → `section.fill` (`Color.dsChrome(in:)` / `dsChromeFill(in:)`); `DSActionFill.style()` resolves the section gradient from the environment at draw time (iOS 17+, iOS 16 falls back to `AppSection.current`); `dsReadableGlyph` maps every section fill to its ink; headers/heroes/boxes (`MainHeaderView`, `DSComposerHeader`, `DSPageHero`, `DSFilterChips`, `DSSegmentedSwitch`, `DSPrimaryButton`, `DSFloatingButton`, `DSStateKit`…) follow automatically. For chrome pass `DS.Color.primary`/`actionNavy` (or nothing); inside one tab's own screen use `AppSection.<tab>.ink/fill`.
- **Meaning colours — never section-coloured:** `brand`/`brandFill` (announcement, info, default news type, category fallback, default avatar), `male`/`maleFill` (sons, member node, male stats), `female`, `error`, `warning`, `success`, role pastels, news-type colours, `composerHusseiniya`, `currentLocation`, admin topic colours (`composerProject` green tree/members, `composerDiwaniya` blue messaging, `composerLibrary` gold content, red banned). `brand`/`male` have the same hex as navy but are separate instances, so the mapping never touches them — use them whenever navy *means* something.
- **Coloured headers:** two solid stops `tint → tint.dsHeroLight` (never `opacity(0.72)` — 12pt white subtitles keep ≥4.5:1); status-bar text forced white over them with `.dsLightStatusBar()` (iOS 27+).
- **رسومات وحركات (مجسّمات «الطين الصقيل»):** مكتبة المجسّمات `Components/Shared/FT5SFull.swift` (`FT5STrial.stateIcon/headerIcon/empty`، مجسّم القسم `AppSection.artIcon`) وأغلفتها في `Components/Home/ArtTrial.swift` (`DSStateIcon`، `TrialHeaderIcon`، `.trialCardSkin`، `DSClaySkin`). `FTKit.swift` (أدوات الرسم، الذهبي، التنفّس والظهور)، `FTTileScenes.swift` (مربّعات الرئيسية والصفحات الفاضية)، `FTMoments.swift` (`FTNewsBadge` ولحظات `dsAlert(…, moment:)`)، `FamilyArt.swift` = `EmptyStateArt` (داخل `DSEmptyView`). كلها Canvas/TimelineView، ثابتة عند t=0 مع «تقليل الحركة»، مخفية عن القارئ الصوتي؛ iOS 16 → لا `Path.subtracting` (استعمل `drawLayer` + `destinationOut`).

### «المكان الواحد» — where every knob lives («أسلوب واحد»، طلب المالك ٢٠٢٦-١٠-٠٧)

**Rule: no `repeatForever` for continuous motion** (فحص اللاق ٢٠٢٦-١٠-٠٨): ambient motion goes through the one shared clock —
`TrialObjectMotion` (breathing + glint, `FTAmbientClock`, 15 fps, pauses off-screen / while scrolling / behind a box) and
`DSAmbientSpin` (30 fps) — never a per-view `withAnimation(.repeatForever)` or `Timer.publish`; they re-composite the whole
screen every frame even at rest.

**Rule: no literals at call sites.** A size, font, colour, radius, opacity, spacing or button shape is written ONCE in the
files below and screens reference the token/component. Value repeats and has no token → add the token there first.
Meaning colours (error/success/warning, female, news types, deceased grey, `DS.Color.reject`) stay meaning colours.
Only true drawing code (Canvas art, tree-node geometry, guide illustrations' `GuideMetrics`) keeps local numbers.

| Knob | Where | Use |
|---|---|---|
| Typeface | ONE family: IBM Plex Sans Arabic. App root sets `.font(DS.Font.body)`; `DS.Font.scaled/body/callout/caption1…` are Plex too (SF only for `.monospaced`) | never `.system(size:)` for text |
| Text roles | `DS.TextRole` (`DesignSystem.swift`) = **Apple default Dynamic Type sizes** (طلب المالك ٢٠٢٦-١٠-٠٨ «حجم الخط الافتراضي في الآيفون»): each role = an Apple style at its «Large» size, `relativeTo:` that style, so it follows the phone's text-size setting. **Only titles may exceed body 17** (owner 2026-10-08): tabTitle/celebrationTitle/hubTitle title2 22 · heroTitle title1 28 · hubKPI title3 20 (admin numbers, owner-approved exception); **font review 2026-10-27** («نفضّل الأحجام الصغيرة» + «ما نبي شي غامق» — bold only for titles, at most semibold for a row title): pageTitle/emptyTitle/title/headline/statValue/hubPulse headline 17 · rowTitle/memberName/button/buttonLarge/hubRow subheadline 15 medium · body/callout/fieldValue subheadline 15 regular · subtitle/pageSubtitle/label/footnote footnote 13 (grey) · sectionTitle/boxSectionTitle footnote 13 semibold · chip/segmentCompact/hubButton/hubLabel footnote 13 medium · caption caption1 12 medium · badge caption2 11 semibold · micro caption2 11 medium; nothing outside titles is bold (selected states = medium/semibold, never bold); no 16 or body-17 non-title text; the old half-steps (`*Compact`) now equal their base style. Excluded from the Apple mapping: OTP digits (`codeDigit` 26 / `codeDigitCompact` 22, relativeTo title2 — unchanged by owner's request), tree-node sizes (`nodeCount` 16, `treeNodeMicro/Tiny` — they scale with the node, below) and the letter inside an avatar circle (`avatarInitial` 34, `avatarInitialLarge` 96). New role → `DS.TextRole(.style, weight:)`; `DS.Font.appleSize/textStyle(for:)` hold the scale | `.dsFont(.role)` · `.dsFieldFont(.role)` (same size — `DSFieldFont.boxReduction` = 0) · `DS.Font.role(.role)`; containers hug text (`minHeight`, never a fixed text height) | Drawn at size × `DS.Font.opticalScale` — **1.0 with Cairo** (`Plex.useCairo`, ٢٠٢٦-١٠-٢٤: 0.9 made Cairo smaller than the iPhone default) · 0.9 with Plex (Plex looks ~11% bigger than SF at the same pt, طلب المالك ٢٠٢٦-١٠-٠٨); fixed graphic sizes `TextRole(size:)` (OTP digits, tree nodes) are exempt. **Tree nodes scale as a whole with «حجم النص»** (طلب المالك ٢٠٢٦-١٠-٠٨ «بشي منظم»): `DS.TreeScale` (`DesignSystem.swift`) = ONE factor from `@Environment(\.dsTreeScale)` — xSmall .88 · small .92 · medium .96 · **large 1** · xLarge 1.1 · xxLarge 1.2 · xxxLarge **1.3 = `cap`** (accessibility sizes stay at the cap). Name, avatar, box, badges, gaps, connector lines (`TreeArtLines.layers(…, scale:)`) all × k — real metrics, never `scaleEffect`; the old `.dsTreeNode` pin is gone. Each tree reads the factor once into `@State` (stale `.equatable()` node closures), builds `FamilyTreeMetrics`/`WomenTreeMetrics(k:)` once per layout and stores it in `layout.m` — nodes, lines, camera read `layout.m`. Node text = `.dsTreeFont(role, k)` (fixed size = role.textSize × k rounded to a whole point, as Dynamic Type rounds — pixel-identical at Large), glyphs `.dsTreeGlyph(DS.Glyph.x, k)`. Zoom (fit, kinship, «موقعي») is in default-node units so the tree really grows (more panning); pinch/double-tap limits ÷ k keep the on-screen extremes; centring keeps a node's TOP where it is at Large so bigger nodes grow downward, not under the toolbar. New tree node → take `k` and multiply every size. A full name in a list row → `.dsNameLines()` (1 line at default/smaller, 2 lines when the phone text is larger — `DSBox.nameLinesLargeText`); field fonts by size (`dsFieldFont(DSBox.fieldValueSize)`) get the same × opticalScale as roles (فحص ٢٠٢٦-١٠-٠٨).
| SF glyphs | `DS.Glyph` micro 9.5 · xs 10.5 · sm 12 · md 14 · lg 16 · xl 18 · xxl 22 (+ `*Compact` −1) | `.dsGlyph(DS.Glyph.md)` |
| Spacing / radius / opacity / border | `DS.Spacing` (xxs 2 · xs 4 · xsm 6 · sm 8 · md 12 · lg 16 …), `DS.Radius`, `DS.Opacity` (tintFill .12, cardStroke .10, fieldStroke .15, tintStroke .30, selectedStroke .55 …), `DS.Border` | |
| Icon / avatar sizes | `DS.Icon` (tapTarget 44 · floatingButton 56 · row 32 · rowLarge 36 · state 52 · emptyArt 130 · avatar 40 · avatarRow 36 · memberHero 130 …) | |
| Card | `.dsCard()` (surface + hairline + clay skin, radius `DS.Card.radius` 12, padding 8); boxes: `DSComposerSection`, rows `.dsRowBox()` | never fill+stroke by hand |
| Buttons | ONE look, two sizes: `DSBox.buttonHeight` **44** (boxes/pages) · `buttonHeightLarge` **48** (main CTA of full-screen flows). Action = section fill, `.destructive` red, `.cancel` grey, `tint:` meaning colour (drawn via `Color.dsSolidFill`: warning/success → `DS.Color.warningFill/successFill`, the deep tone in both modes so white text stays ≥4.5:1 in dark) | `DSButton(…)`, `.buttonStyle(.ds(.cancel, size: .large))`, rows `DSBoxButtons { … }` (cancel on the physical left). `DSPrimaryButton` (48) / `DSSecondaryButton` (44 grey) resolve to the same spec |
| Box shell | `DSBox` (header ≥80 / compact ≥56 — minimums, the header grows with the text; section/field metrics, `alertIcon`, `composerIcon`), `DSFieldMetrics` (field/row heights) | `DSComposer`, `dsCenterBox` / `dsTallBox` / `dsHalfBox` / `dsExtraBox` |
| Sub-page header | `DSSubPageHeader.swift`: section gradient + clay object + white title/subtitle + back/close (`DSBox.pageHeader*`) | page in a NavigationStack: `.dsSubPageHeader(title, subtitle:) { DSHeaderButton(…) }`; own VStack: `DSSubPageHeader(title:subtitle:section:nav:)` (`nav: .back/.close/.none`) |
| Nav buttons | `DSNavButtons.swift`: `DSHeaderButton` / `DSBackButton` / `DSCloseButton`, `size: DSNavButtonSize` `.regular/.toolbar(34)/.mini(27)` | |
| State kit | `DSStateKit.swift`: `DSEmptyView(title, message:, style: .page/.card/.compact/.inline)` (section clay object + title + one line) · `DSPageLoader(text, fillsSpace:)` (same object breathing — no bare spinners; a tiny spinner only inside a button/chip) · `DSStateCard` · `DSNoteCard` · `DSOptionTiles` · `DSChipButton(…, size: .regular/.small/.mini, isLoading:)` · `DSStatusChip(…, size: .mini)` · `DSRow` · `DSSectionTitle` · `DSStatsRow` · `DSRing`/`DSDistributionBar` | |
| Switch / filters | `DSSegmentedSwitch(…, size: .large/.regular/.compact)` · `DSFilterChips` (`DSAdminPage.swift`) | never `pickerStyle(.segmented)` |
| Member picker | `DSMemberPickerBox` (search + results box; wife/husband/mother pickers) | |
| Member details kit | `DSMemberKit.swift` (2026-10-24, both trees): `DSLiveButton` = the one box button (`DSBoxButtonStyle`, 44/12/button font) in its role colour with a one-shot icon motion + shine — «تعديل مباشر»/«الإدارة» gold `directTint`, «طلب إضافة»/«عائلتي» palm `addTint`; «طلب تعديل» stays `DSButton` navy, «إغلاق» `.cancel`. `DSDetailsToggle` «عرض/إخفاء التفاصيل» (info-tinted, chevron disc turns) + `.dsDetailsSwipe` (swipe up on the box expands, down on its band collapses). `DSActionTileGrid`/`DSActionTile`/`DSTileGridLayout` = equal square tiles, balanced centred rows (no orphans), one colour per group (add palm · link sea · record navy), delete = one red `DSButton`. `DSPhoneCountryBadge` + `FamilyMember.dsVisiblePhone` = flag of a non-Kuwait number on the box band, only when the viewer may see the phone | one motion per appear, Reduce Motion = static |
| Clay objects | `FT5SFull.swift` (art library) + `Components/Home/ArtTrial.swift`: `DSStateIcon(icon, tint:, size:)`, `TrialHeaderIcon`, `.trialCardSkin`, `DSClaySkin`; section object = `AppSection.artIcon` (Diwaniyas «مجلس» `sofa.fill`) | |
| Landscape | `DS.Landscape` (panel/alert widths, column min width 340, tile/grid widths, empty/loader art, `tabBarClearance`) + `LandscapeLayout.swift`: `@Environment(\.dsLandscape)`, `AdaptiveCardStack`/`AdaptiveLazyStack`, `.dsLandscapeReadable()`, `.dsLandscapeScroll()`, `.dsLandscapeFitScroll()`, `.dsTabBarClearance()` (tab pages' scroll content) | portrait must stay identical |
| Spinner scale | `DS.Spinner.buttonScale/chipScale` | |
| Offline | `Core/OfflineHold.swift`: no connection → the splash (`SplashScreenView(waitingForNetwork: true)`) covers everything in its own window (level `.alert + 2`); 2 s grace mid-session, immediate at launch; on reconnect it fades out (state underneath kept) and posts `.networkRestoredAfterHold` (app re-checks profile + refreshes members/news/notifications). Debug: `-tmpOfflineFrom <s> -tmpOfflineTo <s>` | no offline/online banners (removed `OfflineBanner`, طلب المالك ٢٠٢٦-١٠-٠٨) |

Other tokens: `DS.Shadow` (`.dsCardShadow()`, `.dsSubtleShadow()`, `.dsGlowShadow()`), `DS.Anim` / `DSMotion` (press, cascade `dsCardCascade`, `dsStaggerIn`), `DS.Color` + `AppSection` (above). Press styles: `DSPressStyle`, `DSScaleButtonStyle`, `DSBoldButtonStyle`.
Legacy kit removed 2026-10-07 (`DSCard`, `DSTextField`, `DSIcon`, `DSSectionHeader`, `DSFormRow`, `DSLabeledFieldRow`, `DSDateField`, `DSGradientCard`, `DSGlowCard`, `DSStatCard`, `DSEmptyState`, `DSSheetHeader`, `Unified*`, `Sys*`, `glassCard`…) — do not reintroduce; the table above replaces them.

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

Fields: `id`, `targetMemberId`, `title`, `body`, `kind`, `createdBy`, `createdAt`, `isRead`. Has `read` computed property and `createdDate` ISO8601 parser. Admin-type rows (requests, team activity, system alerts) are classified by `AdminNotices.category` and, for moderators, live only in «إشعارات الإدارة» — never in the general `NotificationsCenterView` too.

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
- IMPORTANT: Map Figma typography to `DS.TextRole` roles (IBM Plex Sans Arabic — one typeface)
- Reuse existing DS components (`.dsCard()`, `DSButton`, `DSStateKit`, `DSSubPageHeader`…) instead of creating new ones
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
