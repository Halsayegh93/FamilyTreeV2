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
- `can_handle_admin_request(type)` — المراقب: طلبات الشجرة والأعضاء؛ المشرف: البلاغات والرسائل؛ المالك/المدير: الكل.
- **مسار الموافقات** (`20261015120000_approvals_workflow`، طلب المالك ٢٠٢٦-١٠-١٥، مرفوع والمفتاح مطفأ): خلف `app_settings.approvals_workflow` (مطفأ = المسار القديم حرفياً). العضو يرسل ← المختص (`workflow_specialist_role`: المشرف للبلاغات، المراقب لغيرها، `contact_message` خارج المسار؛ لا مختص نشط → المالك/المدير مكانه) يوصي أو يطلب معلومات ← المالك/المدير يعتمد (يرجع للمختص) أو «اعتماد وتنفيذ الحين» (تجاوز) أو يرفض (أي مرحلة) أو يرجّع ← المختص ينفّذ بمسار الموافقة القديم نفسه. المراحل في `admin_requests.stage` والسجل في `admin_request_steps`؛ الانتقال بـ `advance_admin_request(id, action, note)` فقط، و`trg_zz_admin_request_workflow` يرفض التنفيذ قبل الاعتماد (`approval_needs_manager`) حتى من النسخ القديمة. الآيفون: `ApprovalWorkflow.swift`، `AdminRequestViewModel+Approvals.swift`، `ApprovalWorkflowViews.swift`، والمفتاح في ⚙︎ «الوارد» ← «إعدادات مسار الموافقات». لا أحد يراجع طلبه هو كمختص إلا المالك (`20261015130000_approvals_owner_own_request`). «طلب معلومات» منظّم (`20261015150000_approvals_info_fields`): المختص يختار الناقص (`info_fields`: phone/birth_date/death_date/full_name/text) والعضو يرد بحقل لكل مطلوب، يفحصه السيرفر ويحفظه في `info_reply`؛ `advance_admin_request(p_request_id, p_action, p_note, p_fields, p_values)` مرشّح واحد. جانب العضو يتكلم عن «الإدارة» لا «المختص»، ويظهر مساره متى ما كان للطلب `stage` ولو لم يصل المفتاح. **مسار الموافقات ٢** (`20261016120000_approvals_v2`، ٢٠٢٦-١٠-١٦): أولوية (`priority`، الوفاة مستعجلة تلقائياً)، استلام (`assigned_to` — `claim`/`release`، المالك يأخذ، `claimed_by_other`)، تصعيد وتذكير تلقائي (`approvals_sla_tick` بمهمة pg_cron `approvals-sla` كل ١٥ دقيقة، المهل في `app_settings.approvals_*_hours`؛ المتصعّد يتصرف فيه المالك/المدير بدل المختص — `can_act_as_specialist`)، مسار سريع (`approvals_fast_types`، افتراضياً `child_add` → يبدأ عند المدير)، ردود جاهزة (`approval_templates`)، ملاحظات داخلية (`admin_request_notes`، لا يراها صاحب الطلب)، تقرير (`approvals_report(p_from, p_to)`). الآيفون: `ApprovalsV2.swift`، `AdminRequestViewModel+ApprovalsV2.swift`، `ApprovalsReportView.swift`، `ApprovalsV2SettingsViews.swift`. تجربة: `node approvals_v2.test.mjs`. الأندرويد والموقع لم يُحدَّثا بعد — لا يُشغَّل المفتاح دائماً قبلهم. تجربة: `node approvals_workflow.test.mjs`. التراجع في `supabase/rollback/`.
- **رسائل الدخول · KWT SMS للإدارة** (`20261020150000_kwtsms_daily_stats` + `20261020151000_kwtsms_admin_overview`، حيّة ٢٠٢٦-١٠-٢٠): القراءة عبر `sms_admin_overview()` وحدها (المالك والمدير، غيرهما 42501؛ `kwtsms_deliveries` و`kwtsms_daily_stats` مقفولة عن التطبيقات، بلا رقم هاتف — آخر ٤ خانات من البصمة فقط). الإجراءات عبر الدالة الطرفية `kwtsms-admin` بجلسة المستخدم: `balance`/`senderid`/`coverage`/`status`/`validate` للمالك والمدير، و`test_send` للمالك وحده لرقم ملفه مرة كل ١٠ دقائق (نقطة واحدة)؛ بيانات حساب KWT في Edge Secrets لا تخرج، والأخطاء رموز (`owner_only`، `wait_10_minutes`، `provider_error`+`provider_code`…) يترجمها `SmsAdminError`. عتبات التنبيه `app_settings.sms_low_threshold` (٠ يطفئ) و`sms_urgent_threshold` (≤ المنخفض) و`sms_low_repeat_hours`/`sms_urgent_repeat_hours` (١–١٦٨) يقرؤها `finish_kwtsms_send`، ويعدّلها المالك وحده من صفحة KWT SMS (`AppSettingsViewModel.updateSmsAlerts` يكتب الأربعة في تحديث واحد). الآيفون: `AdminSmsData.swift` (المخزن والنداءات) و`AdminSmsView.swift`/`AdminSmsSections.swift`؛ `sms_balance_status()` احتياط إن فشلت النظرة. تجربة: `node kwtsms_admin_stats.test.mjs`. التراجع في `supabase/rollback/`.
- `is_moderator()` يعتمد `current_user_role()` فالمجمّد يفقد صلاحياته. دوال النشاط للمالك/المدير/المراقب. دوال البحث بالرقم/الاسم ليست لـ anon.
- **الأرقام المخفية:** اقرأ الأعضاء من `members_masked` (لا `profiles` بـ `select()`)، وفي الـ embed: `member:members_masked!member_id(*)`. المرحلة الثانية (بعد تحديث الكل): إلغاء قراءة عمود `phone_number` من `profiles`.
- قبل أي تعديل على السيرفر: جرّبه داخل `begin; … rollback;` بجلسة `authenticated` (`set_config('request.jwt.claims', …)`).

### التحديث الإجباري
`app_settings.ios_min_build` / `android_min_build` (+ `ios_update_url` / `android_update_url`): أي نسخة رقم بنائها أقل تنقفل بشاشة «حدّث التطبيق» (`ForceUpdateView` / `_ForceUpdateScreen`). المالك مستثنى. التحكم من «الإدارة ← التطبيق ← التشغيل ← فرض التحديث». نسخ الأندرويد القديمة تقرأ `force_update` + `latest_build` فقط («إيقاف نسخ الأندرويد القديمة»). **ارفع رقم البناء مع كل إصدار** (`CURRENT_PROJECT_VERSION` / `pubspec` + `kAppBuild`).

### لوحة الإدارة «مركز القيادة» (إعادة التصميم الكاملة، طلب المالك ٢٠٢٦-١٠-٢٠ — الاتجاه «أ» + لمستان من «ب»، ثم «نفّذ كل المقترح» بدفعاته أ/ب/ج)
**القواعد:** كل أمر له **بيت واحد** (صفّ في قسم واحد)، وما سواه **رقم حيّ يفتحه** فقط (أرقام «اليوم» و«حالة النظام» والرؤوس) — الاستثناء الوحيد مكبّر الصوت في رأس «اليوم». **لا شريط أقسام ولا تبويبات علوية ولا مبدّلات** (طلب المالك «مابي تويب علوي فكر بشي ابسط»): صفحة واحدة تتمرّر بعناوين صغيرة، والشرائح (`DSFilterChips`) فلاتر فقط. التنقّل بين الأقسام: عنوان صفحة القسم في الرأس الكحلي قائمة أصلية `Menu` «العائلة ⌄» (`AdminAreaTitleMenu` في `AdminHubKit.swift`، يرسمها `AdminBandHeader(isAreaRoot: true)`) بالأقسام الظاهرة لدورك والحالي بعلامة ✓ — الاختيار يستبدل مسار مكدس «اليوم» بصفحة القسم (`AdminReviewDestination.area(_, عدّاد)` عبر `AdminAreaRouter` الذي يضبطه «اليوم») بلا تكدّس؛ بلا ناقل أو بلا قسم يبقى العنوان نصّاً. الصفحات الداخلية (`AdminPageBand`/`AdminPage`): زرّ الرجوع باسم ما فُتحت منه + العنوان (`adminBackTitle` من البيئة). كل صفّ من فهرس واحد `AdminToolCatalog` (`AdminAreaPages.swift`؛ يقرؤه البحث الشامل وصفحات الأقسام — أغلب صفوفه للبحث فقط وتفتح بيت الأمر، والكلمات القديمة تجد بيتها الجديد). المسميات الرسمية من `PROPOSAL.md` §١٤: عضو مسجّل · مقيّد في الشجرة · طلب انضمام قيد المراجعة · حساب موقوف · متوفى؛ «تسجيل في التطبيق» (لا «تفعيل»)، «إيقاف الحساب» (لا «تجميد»)، «منع الرقم من التسجيل» (لا «حظر»)؛ بانتظار قرارك · عاجل · متأخر؛ الاعتماد المباشر · نماذج الردود · المراجِع المختص؛ فرض التحديث · حدّ التعديلات الذاتية · وضع الصيانة؛ تسجيل الأجهزة للإشعارات · النسخة الرسمية/نسخة الاختبار؛ طلبات رمز الدخول · ناجحة/مشبوهة؛ مسموح/غير مسموح؛ «للاطلاع فقط — التعديل للمالك» (`AdminPageHeader.readOnlyText`). الجرد والانتقال القديم ← الجديد: `admin-redesign/actions/IMPLEMENTED-A.md`/`-B.md`/`-C.md` و`admin-redesign/impl-shots/REACHABILITY.md` (خارج المستودع).
**«اليوم»** (تبويب «الإدارة» = `AdminDashboardView`): رأس كحلي (`DS.Hub`، حلقة ذهبية ساكنة) بالتحية و**سطر التحية الذكي** تحتها (الدفعة ١٠، `AdminTodayText.smartLine`: جملة واحدة من بيانات حقيقية بالأولوية — «اليوم ذكرى وفاة فلان» › «لم يُعلَن بعد عن وفاة فلان» (المالك والمدير) › «5 طلبات بانتظار قرارك» (مجال الدور) › «انضمّ 3 أعضاء هذا الأسبوع» (من مجاله الشجرة: المالك والمدير والمراقب — نفس «قُيّدوا هذا الأسبوع») › «ما في طلبات — يوم هادئ»؛ بلا رموز للوفاة، سطر واحد يُقصّ، محجوز أثناء التحميل، `DS.Hub.greetingLine`) والدور والتاريخ ومكبّر الصوت (`canSendNotifications`) والجرس (← «إشعارات الإدارة» بعدد غير المقروء + ما يحتاج إجراء الآن) ← **«المربّع اللي ينسحب»** (`AdminTodaySwipeCard.swift`، اختيار المالك ٢٠٢٦-١٠-٢٠ الدفعة ١٠): مربّع أبيض واحد يصعد فوق حافة الرأس (`headerOverlap`) بصفحتين تُسحبان أفقياً — ١) **«يحتاج انتباهك»** ٢) **«إحصاء الأفراد»** (أدناه) — وتحته نقطتا الصفحة (الحالية كبسولة ذهبية)؛ الأولى على اليمين والسحب يميناً يأتي بالثانية (بالإنجليزية بالعكس)، يتذكّر آخر صفحة لكل مستخدم (`@AppStorage` `admin.today.swipePage.<id>`)، الصفحتان بارتفاع أطولهما (`AdminPagerLayout` — لا يقفز ما تحته)، حلقات الثانية تمتلئ حين تظهر أول مرة (`dsGaugeHold`)؛ السحب من iOS 18 إيماءة UIKit أفقية فقط (`AdminHorizontalPan`، `cancelsTouchesInView` — السحب لا يفتح الرقم الذي بدأ عليه، والعمودي للتمرير) وقبله `DragGesture` متزامن؛ القارئ الصوتي الصفحة الظاهرة فقط، والنقاط عنصر قابل للتعديل بإجراءين «التالي/السابق»؛ المشرف (بلا «إحصاء الأفراد») صفحة واحدة بلا نقاط. **«يحتاج انتباهك»** (`AdminAttentionPanel`، الدفعة ٩ لوحة زجاجية في الرأس ثم صفحة على البطاقة): العنوان ثم الأرقام الأربعة (`AdminAttentionNumber` بـ`hubPulse` بألوان المعنى على الأبيض: ذهبي `accent` · `error` · `warning` · أساسي، في الوسط بخطوط رفيعة بينها، الاسم على سطرين محجوزين فوق الحجم الافتراضي و٢×٢ من أحجام إمكانية الوصول): بانتظار قرارك · عاجل · متأخر · رسائل — فلاتر مسار الموافقات ٢، تفتح «الوارد» بالفلتر أو الرسائل؛ ثم خطّ رفيع، ثم سطر **«حالة النظام»** في اللوحة نفسها (`AdminSystemStatusLine` + `AdminSystemStatus` في `AdminTodayModel.swift`، المالك والمدير فقط كظهور التنبيهات السابقة — المراقب والمشرف أرقام مجالهم فقط بلا سطر): «✓ النظام سليم» `success` حين تسلم كلها، «⚠︎ تنبيه / تنبيهان / 3 تنبيهات للنظام» `warning` (`AdminTodayText.arabicCount`، أرقام لاتينية)، و`error` (بنبضة هادئة `dsUrgentPulse`) حين يكون فيها عاجل (الصيانة مفعّلة أو الرصيد تحت «عاجل»)، و«حالة النظام» محايدة ما دام شيء لم يُحمَّل؛ السطر أسفل الصفحة بزوايا مدوّرة وتعبئة خفيفة من لونه (`DS.Hub.statusLineFill`؛ رمادية ما دام شيء لم يُحمَّل) و«⌄» في الطرف، لمس ٤٤ بعرض الصفحة، والقارئ الصوتي يقرأ الملخّص («حالة النظام: تنبيهان — الرصيد منخفض، 3 أجهزة بلا إشعارات»). الضغط يفتح **لوحة منبثقة** من السطر (`AdminSystemStatusPanel`: `popover` + `presentationCompactAdaptation(.popover)` على `DS.Color.surface` من iOS 16.4 — تحتها من iOS 18 — وقبل 16.4 `dsCenterBox` صغير؛ عرضها `DS.Hub.statusPanelWidth`، ومن أحجام إمكانية الوصول أعرض والإجراء تحت النص وتتمرّر) بصفّ لكل إشارة: نقطة بلون المعنى (`success`/`warning`/`error`) + الحالة + سطر ثانٍ + إجراء صغير (`AdminPillLabel`، كحلي حين تنبّه)؛ الصفّ كله زرّ يُغلق اللوحة ثم يدفع البيت في مسار «اليوم» (`AdminReviewDestination.status(_)` من `onDisappear` — الرابط داخل النافذة المنبثقة لا يدفع في المكدس): «الصيانة: مطفأة/مفعّلة» [الإعدادات] ← «التطبيق» · «الرصيد: N نقطة» [اشحن] (تحت عتبة منخفض/عاجل المحفوظة) ← رسائل رمز الدخول · «مجدول: N اليوم» [القادم] (كهرماني إن كان اليوم؛ «لاحقاً N») ← «المناسبات» · «بلا إشعارات: N أجهزة» [الأجهزة] (= غير مسجّلة + لم تُحدَّث منذ 30 يوماً من `AdminDeviceReachStore` — نفس رقم صفحتها) ← «الأجهزة ووصول الإشعارات». نفس المخازن بلا جلب جديد (`SmsBalanceStore`، `appSettingsVM`، `scheduledNotifications`، `AdminDeviceReachStore`) ← **«إحصاء الأفراد»** (الصفحة الثانية من المربّع المنسحب؛ كانت «أعداد الأعضاء»؛ المالك/المدير/المراقب؛ `AdminMemberCountsCard`، تصميم «ثلاث دوائر» اختيار المالك في الدفعة ٩): ثلاث حلقات `DSRingGauge` متوسطة متجاورة (المرجع الموحّد لكل مؤشرات اللوحة — الدفعة ١٠؛ `DS.Ring.medium`/`mediumCompact`/`mediumStacked`، بلا Charts) — الإجمالي · الرجال · النساء: العدد الكلي في الوسط `hubPulse` يعدّ من الصفر، والحلقة نسبة الأحياء بلونها (الإجمالي ذهبي `DS.Color.accent` — حبر قسم الإدارة هو كحلي الرجال نفسه — والرجال `male` والنساء `female`) فوق مسار المتوفين (`DS.Color.deceased` خافت — لا أحمر)، وتحتها الاسم بلونها و«54 حياً · 14 متوفى» (`AdminTodayText.arabicCount`؛ سطران إن ضاق) ← شريحة خضراء «✓ الأعضاء المسجّلون N ›» في الوسط (= active + idle + login_no_device)؛ كل رقم يفتح: الإجمالي ← «المؤشرات ← العائلة» · الرجال ← صفحة الأعضاء («متوفى» الرجال رابطه الخاص ← شريحة «متوفون») · النساء ← شجرة النساء · المسجّلون ← شريحة «مسجّلون»؛ صفّ واحد في الوضع الأفقي (بعرض عمود القراءة)، ومع XXXL تصغر الحلقات قليلاً وتلتفّ الأسماء، ومن أحجام إمكانية الوصول كل حلقة كتلة (حلقة صغيرة بجانب الاسم والعدد، ثم الأحياء والمتوفون صفّين بلمس ٤٤ تحت الاسم). الحلقة (`DSRingArcs`) تبدأ من أعلى وتدور مع عقارب الساعة في الاتجاهين، و`track:` لون الباقي ← شبكة **الأقسام الستة ٣×٢** (`AdminArea`): الوارد · العائلة · المناسبات والإعلانات · المؤشرات · الفريق والأمان · التطبيق (عمودان مع XXXL أو حين يرى الدور قسمين/أربعة؛ القسم الفارغ لدورك لا يُرسم؛ `rawValue` بقي `occasions`/`team`) ← **«بانتظار قرارك»** قائمة واحدة (القرارات والمهام معاً — مهامك بدائرة الإنجاز وما عند غيرك بمربّع نوعه، ورسائل الأعضاء مهام؛ أول ٣ + «عرض الكل» ← «الوارد» على «بانتظار قرارك»؛ يغذّيها `AdminTodayTaskStore` من حالة حقيقية بلا تأشير يدوي). بطاقة «تنبيهات» **حُذفت** (الأربعة صارت «حالة النظام»، والباقي «يحتاج إجراء» في «إشعارات الإدارة»). للمراقب والمشرف سطر «صلاحياتي» (`AdminMyScopeView`، كان «نطاقي» — بيته الوحيد).
**المؤشرات والحركة الموحّدة** (الدفعة ١٠، طلب المالك «وحّد شكلها كلها» + «الأرقام تعدّ» + «ظهور موحّد لكل الصفحات» + «نبضة للعاجل» + «لحظة نجاح»): كل مؤشر/نسبة في اللوحة بشكل حلقة «إحصاء الأفراد» من مكان واحد — `Components/Shared/DSGauges.swift` + `DS.Ring` (`DesignSystem.swift`): **`DSRingGauge`** بأربعة مقاسات (`mini` ٢٢ بجانب رقم بلا وسط · `small` ٤٦ صفّ · `medium` ٧٦ بطاقة · `large` ١٠٤ بطل الصفحة)، جزء واحد فوق مسار (`track` = الباقي: `DS.Ring.restTrack` رمادي المتوفين، `emptyTrack` قبل وصول الأرقام، `bandTrack` فوق الكحلي) أو أجزاء ٢–٣ بألوان المعنى (`DSGaugePart.counts`)، والرقم في الوسط (`.count`/`.percent`) بخط المقاس ويعدّ من الصفر، وكلمة تحته في المتوسطة والكبيرة (تختفي من أحجام إمكانية الوصول)؛ **`DSGaugeRow`** (الحلقة بجانب عنوان وسطر — فوقه من أحجام إمكانية الوصول)، **`DSRingValue`** (مصغّرة بجانب رقم: `AdminKPITile(ring:)`/`AdminPageKPI(ring:)`، `DSStatTile(ring:)`، طرف صفّ)، و**`DSMeterBar`** الشريط الواحد حيث الحلقة خطأ (توزيع ٤ أجزاء فأكثر، مقارنة أطوال، صفوف الأدوار والأعمار) بسُمك المتوسطة ومسارها + **`DSGaugeLegend`** المفتاح الواحد. `DSRing`/`DSDistributionBar`/`AdminMeter`/`AdminScoreRow` أغلفة عليها. أين: «إحصاء الأفراد» · اكتمال البيانات (ذهبي) وسلامة الشجرة (لون الحال) · المسجّلون (شريط ٤ أجزاء) · تسجيل الأجهزة (متوسطة ٣ أجزاء) · وصول الإشعارات في «المناسبات» ورأس «الفريق والأمان» (مصغّرة) · رصيد KWT (كبيرة على الكحلي، النقاط في وسطها — كان نصف دائرة ورقماً كبيراً) · قبول الفترات (مصغّرة) ونتائج ٣٠ يوماً (متوسطة) وهذه الساعة (مصغّرة) · تقرير الموافقات (النوع = صغيرة ٣ أجزاء بالعدد، وقت المراحل = شريط) · إحصاءات العائلة (أحياء الرأس مصغّرة، الملخّص كبيرة، المسجّلون/الجنس/الحالة الاجتماعية متوسطة، الأدوار والأعمار شريط، نسبة المتوفين مصغّرة) · تطابق الاسم في طلب الانضمام (صغيرة). يبقى رسم ٣٠ يوماً (KWT) وأعمدة النمو رسماً زمنياً، وشريط مراحل الطلب الخمس خطوات. **الحركة** (`DS.Ring.fill` ٠٫٧ ث تباطؤ بعد ٠٫١): الحلقة تمتلئ والرقم يعدّ معاً مرة عند الظهور الأول أو عند وصول الأرقام بعد «—»، وبعدها تتبدّل بلا حركة إلا لتغيّر واضح (١٠ نقاط مئوية/٢٠٪ — `DSGaugeMotion`، والتبديل بلا حركة لا يرث `withAnimation` من حوله)؛ «تقليل الحركة» ثابتة فوراً؛ لا مؤقّت ولا `TimelineView` (`DSCountUpText` `Animatable` — إطارات أثناء الحركة فقط، المعالج ٠٪ في السكون). أرقام «يحتاج انتباهك» `DSCountText`. **الظهور الموحّد** `dsCardCascade`: `AdminPage` (البطاقة الأولى ثم المحتوى؛ صفحات `.list` البطاقة الأولى، وصفوفها إن لم يكن لها دخولها)، `AdminHubPage` (كل ابن بترتيبه عبر `AdminCascadeLayout`)، بطاقات «اليوم» (المُعدِّل داخل `AnyView` — حارس المكدس)، صفوف «إشعارات الإدارة» وبطاقات «الوارد». **نبضة العاجل** `dsUrgentPulse` (`ArtTrial.swift`): هالة على رمز سطر «حالة النظام» حين يكون أحمر فقط، على `FTAmbientClock` (١٥ إطاراً، ~٣٪ معالج)، تقف خارج الشاشة/أثناء التمرير/خلف مربّع/مع «تقليل الحركة». **لحظة النجاح**: ما له تأكيد يبقى (`dsAlert(…, moment:)`، وأُضيف اهتزاز النجاح للإعلان والموافقات الجماعية)، وما لا تأكيد له — الموافقة/الاعتماد/التنفيذ في «الوارد» وطلبات الشجرة — `DSMomentToast` (`Components/Shared/DSMomentToast.swift`: كبسولة أعلى الشاشة بمجسّم `.approved` مصغّراً + «تمت الموافقة/تم الاعتماد/تم التنفيذ/تم التأكيد»، اهتزاز نجاح، تُعلن للقارئ الصوتي، نافذة `.alert` لا تلتقط اللمس، ١٫٨ ث) عبر `AdminApprovalMoment.after` (لا تظهر إن ظهر خطأ الفحص المحلي؛ «ربط» طلب الانضمام بلا لحظة)؛ إعلان الوفاة اهتزاز فقط بلا احتفال.
**أرضية اللوحة بيضاء** (طلب المالك ٢٠٢٦-١٠-٢٠ «ابيض بدال الكريمي»): `DS.Hub.background` أبيض في الفاتح (كان رملياً #F5F2EC) وأسود في الداكن كما كان — مكان واحد لكل صفحات اللوحة وأرضية «اليوم»؛ البطاقات البيضاء تنفصل بالإطار الرفيع (`DS.Opacity.cardStroke`) وظلّ البطاقة الخفيف، والخانات الداخلية `cardBackgroundSoft` كما هي. **مهلة رمز الدخول** (KWT): `sms_wait_seconds` ٣٠–٦٠٠ في السيرفر (`AppSettingsViewModel.smsWaitRange`)، درجات «−/+» ٣٠ · ٤٥ · ٦٠ · ٩٠ · ١٢٠ · ١٨٠ · ٣٠٠ · ٦٠٠، وملاحظة الصفّ «أقل شي 30 ثانية» (حدّ خدمة الدخول نفسها ٥ ث لكل رقم).
**«إشعارات الإدارة»** (`AdminNotificationsPage.swift`، صفحة `.list` يفتحها جرس «اليوم»؛ «سجل التعديلات» صار فيها): خطّ زمني واحد بالأيام (اليوم · أمس · التاريخ)، الأحدث أولاً، وشرائح فلتر: الكل · **يحتاج إجراء** (الحالات المشتقة الآن من `AdminNoticeStore` الذي يكتبه «اليوم»: وفاة لم يُعلن عنها للمالك والمدير «إعلان» ← المناسبات، مشكلات الشجرة للمراقب «مراجعة» ← العائلة، خلل في إعداد قاعدة البيانات؛ + إشعارات الطلبات ما دام طلبها معلّقاً — بمعرّف الطلب، وإلا ما دام غير مقروء — «مراجعة» ← «الوارد» على الطلب أو الرسائل) · **نشاط الفريق** (سجل التعديلات: تعديلات الأعضاء وشجرة النساء والمحتوى — الضغط يفتح «ما تغيّر» قبل ← بعد، `AdminNoticeDetailBox`) · **النظام** (`sms_balance_low` بزرّ «شحن الرصيد» ما دام الرصيد منخفضاً). بحث واحد (العنوان والنص)، السحب «مقروء»/«حذف» (كل عضو يحذف نسخته)، «قراءة الكل» و«تحديد» (مقروء + حذف) في الرأس. **مكان واحد لكل إشعار** (`AdminNotices.category`): للإدارة (`canModerate`) لا يظهر الإشعار الإداري في مركز الإشعارات العام ولا في عدّاد جرسه (`NotificationsCenterView.belongsToNotificationsTab` و`NotificationViewModel.isVisibleToUser` يستبعدانه؛ `unreadAdminNoticesCount` لجرس «اليوم»)؛ يبقى هناك ما يخصّ العضو نفسه (تعديل على بياناته `subject_member_id`، نتيجة طلبه، إعلانات العائلة ووفياتها `admin_broadcast`، `app_update`، رسائل الإدارة له `admin`، الإعجاب والتعليق، ردود «مسار الموافقات» لصاحب الطلب). إشعارات «مسار الموافقات» للطاقم (`admin` + `details.type = approval_workflow`) «يحتاج إجراء» هنا. العضو العادي لا يتغيّر عنده شيء.
**«الوارد»** = `AdminAllRequestsView` برأس كحلي، ثلاثة مداخل: «الطلبات · الرسائل» **شريحتا فلتر** + **حقل بحث واحد** للشريحتين (`AdminInboxView(embedded:sharedSearch:)`، الاسم أو الرقم والأرقام العربية تُطبَّع) + ⚙︎ **«إعدادات مسار الموافقات»** (`AdminAppSettingsView(scope: .approvals)` — النطاق الوحيد الباقي في هذا النوع؛ المالك يعدّل والمدير يقرأ). شرائح المسار، مجموعات ثم أنواع، بطاقات غنية (مراحل، خطّ مهلة، أزرار)، سحب البريد (الطرف: «رفض» + «المزيد»، البداية: الموافقة + الحذف)، وآخر القائمة «المنجز اليوم (N)» (`AdminInboxDoneToday` ← `AdminTodayTaskStore.doneToday`). «مشكلات الشجرة» ليست هنا (بيتها «العائلة»)، فرقم الوارد = ما طلبه أحد فقط (`reviewRequestsTotal`). منطق الموافقة والصلاحيات كما هو؛ `AdminAllRequestsView(focusId:)` يفتح طلباً بعينه (الإشعار يمرّر `request_id`).
**«العائلة» = صفحة الأعضاء الواحدة** (`AdminMembersPage`، بدل ٧ صفحات: سجل الأعضاء، جودة البيانات، الحسابات والاستخدام/محطة التفعيل، قوائم الاستخدام، صحة الشجرة، أسماء العوائل، تسجيل عضو): رأس كحلي («＋ تسجيل عضو جديد» `canRegisterMembers` · «⋯»: «تصدير قائمة الأعضاء (PDF)» `isAdmin` **بالشريحة والبحث الحاليين** (`AdminReportsView(scope:)`، بلا حقل بحث) وشجرة النساء · قائمة العنوان · **حقل بحث واحد** بالاسم أو الرقم · شرائح بالأعداد الحقيقية: الكل · مسجّلون · مقيّدون في الشجرة · متوفون · بيانات ناقصة · مشكلات الشجرة) ← «طلبا انضمام قيد المراجعة» رقم يفتح «الوارد» ← شرائح فرعية (في «الكل» «قُيّدوا هذا الأسبوع» حين يوجد جدد؛ في «متوفون» «تاريخ الوفاة غير مكتمل»؛ في «مسجّلون» «لا تصله الإشعارات») ← سطر ملخّص («اكتمال البيانات» + «ابدأ الاستكمال»، «سلامة الشجرة» + «ابدأ المراجعة») ← القائمة (بالفروع في «الكل» بلا بحث، `BranchPickerSheet.familyRoot`). الضغط على عضو ← **ورقة العضو الواحدة** `AdminMemberSheet` (`dsTallBox`، تتمرّر بلا تبويبات): الرأس (الحالة الرسمية + الاستخدام، اتصال/واتساب) ← «بيانات ناقصة»/«مشكلات الشجرة» بأزرار إصلاح (ومنها «استكمال تاريخ الوفاة» `DeceasedDateBox`) ← «البيانات» ← «النسب» ← «الحساب» (الرقم، «تسجيل في التطبيق»، آخر دخول، الأجهزة و«تسجيل خروج» — بيته الوحيد `canManageDevices`، إيقاف الحساب `canFreezeMembers`، منع الرقم `canManageBannedPhones`) ← «‹ السابق · حذف العضو نهائياً · التالي ›» داخل القائمة التي فُتحت منها. كل أمر هو نفسه بصلاحيته ونداء سيرفره والمربّعات الموجودة (`AdminMemberEditBoxes.swift`، والمحرّر الكامل `AdminMemberDetailSheet(showsAccount: false)`). **الحالات من إشارات العميل** (`AdminMembersModel.swift`): متوفى = `is_deceased` · طلب انضمام قيد المراجعة = الدور `pending` · حساب موقوف = `status frozen` · عضو مسجّل = في `app_usage_members` بفئة active/idle/login_no_device (`AdminAccountsStore`، كلها `has_login`) أو موقوف · مقيّد في الشجرة = الباقي من الأحياء. «مفعّل / بانتظار التفعيل» (`status` active/pending) تقسيم تاريخي **لا يُعرض في أي مكان**. البحث الشامل يفتح الورقة نفسها.
**«تحقق من الأحياء» و«أحياء (تقديري)»** (الدفعة ١٢، موافقة المالك ٢٠٢٦-١٠-٢٠): «حيّ» = «لا وفاة مسجّلة» فقط، فالأجيال القديمة تضخّم عدد الأحياء. شريحة «تحقق من الأحياء» في صفحة الأعضاء (`AdminLivingCheck` في `AdminMembersModel.swift`): غير المتوفين في **الأجيال القديمة** — الجيل = العمق من `BranchPickerSheet.familyRoot` بسلسلة الآباء (الرأس = ١، ترقيم «الأجيال» في التقارير)، والجيل قديم إذا كان وسيط سنوات الميلاد المعروفة فيه (٣ على الأقل) قبل ١٩٦٠ وكل ما فوقه قديم؛ يُستثنى أعضاء الإدارة والموقوف ومن له حساب دخول. القائمة جيلاً جيلاً («الجيل السادس · 95»)، الأولوية لمن بلا ميلاد أو ميلاده قبل ١٩٤٠. «متوفى» = مربّع `AdminMemberDetailSheet(deathOnly: true)` (نفس `saveAction` ونداءاته وإعلان الوفاة، التواريخ فقط، التاريخ اختياري — لا «السنة فقط»). «حي ✓» **محلية لكل مستخدم على جهازه** (`AdminLivingVerifiedStore`، UserDefaults `admin.livingVerified.<uid>`، بلا عمود سيرفر) و«إعادة إظهارهم» تمسحها. الشريحة تختفي حين تفرغ. «إحصاء الأفراد»: ما دام فيها من لم يُراجَع → أحياء الرجال والإجمالي «≈» تفتح الشريحة، وشارة «أحياء (تقديري)» في سطر العنوان تشرح العدد (`AdminMemberCounts.oldLiving`). **التسجيل يسأل عن الجنس** (مطلوب بلا اختيار مسبق، `DSGenderPicker(required:)`)، والوارد يُظهر «أنثى · تُربط بشجرة النساء» على طلب انضمام الأنثى (صفّه وتفاصيله) — الموافقة والربط كما هما؛ ربط حساب أنثى بعقدة شجرة النساء غير موجود في الآيفون بعد (`WomenStore.linkAccount` بلا واجهة، و«ربط بالشجرة» = `merge_member_into_tree` لملفات `profiles` فقط).
**«المناسبات والإعلانات»** = `AdminOccasionsPage` (صفحة واحدة تتمرّر بعناوين صغيرة): الرأس (العنوان قائمة الأقسام، ثلاثة أرقام للمالك والمدير: ذكرى هذا الأسبوع · وفاة لم يُعلن · إشعار مجدول، و«＋ إنشاء» ذهبي) ← **«القادم»** بالأيام (اليوم · هذا الأسبوع · لاحقاً): وفيات آخر ٣٠ يوماً لم يُعلن عنها («إعلان» ← المنشئ على «إعلان وفاة» جاهزاً)، الإشعارات المجدولة («إلغاء» بتأكيد)، ذكرى الراحلين خلال ٣٠ يوماً (`DeceasedMemorialBoard`؛ المراقب والمشرف: الذكرى فقط) ← **«المنشور»** (المالك والمدير: إعلانات ووفيات الأخبار + `app_update`/`admin_broadcast` من إشعاراتك، الأحدث أولاً) ← أرقام فقط تفتح بيوتها: «تصل الإشعارات إلى N جهازاً · P٪» ← «الأجهزة ووصول الإشعارات» (من `AdminDeviceReachStore` نفسه — رقم واحد بتعريف واحد في المكانين) و«N متوفى تاريخ وفاته غير مكتمل» ← العائلة ← متوفون. **«إنشاء» = المنشئ الواحد** (`AdminCreateComposer.swift`): نافذة مستقلّة `AdminCreateWindow` (مثل `DeathAnnouncementPresenter` — لا مُعدِّل عرض على «اليوم»، حارس المكدس) بمربّع «ماذا تنشئ؟» وأربعة أنواع (الظاهرة لدورك فقط): **إعلان** (`AdminAnnounceComposer`، `canSendNotifications`) · **إعلان وفاة** (اختيار المتوفى ثم `DeathAnnouncementBox` نفسه، `isAdmin`) · **بطاقة تهنئة أو تعزية** (`OccasionComposerView` بملء الشاشة فوق المربّع، `canModerate` — من لا يملك غيرها يُفتح له المصمّم مباشرة) · **إعلان تحديث التطبيق** (`AdminAppUpdateComposer` بتأكيد «نشر للجميع؟»، `sendNotification(kind: app_update)`). مكبّر الصوت في رأس «اليوم» يفتح المربّع نفسه على «إعلان». **الإعلان** (طلب المالك «اربط الإعلانات مع الإشعارات» ← «الاثنين مع بعض»): العنوان (فارغ = «عائلة المحمدعلي»)، النص، العناوين الجاهزة، ☑ «نشر كإعلان في الأخبار» و☑ «إرسال إشعار للأعضاء» (واحد على الأقل)، «خيارات أكثر» مطويّة (المستلمون: الكل/دولة/أعضاء — شرائح، والجدولة)، ثم «إرسال» بتأكيد. لا منطق جديد: الخبر = `postNews(type: «إعلان», asAdminIdentity: true)`، والإشعار = `sendNotification`/`scheduleNotification(kind: admin_broadcast)`. **الإشعار المزدوج**: نشر الخبر لا يُشعر الأعضاء (يُشعر الإدارة فقط «منشور جديد»؛ لا مشغّل على `news` غير `trg_content_force_pending`)، فمع الخيارين يصل الأعضاءَ إشعار واحد، و`postNews(notifyAdmins: false)` حين يصل الإعلان نفسه للجميع.
**«المؤشرات»** (`AdminInsightsArea.swift`) = بطاقة «أرقام وسجل» بثلاثة صفوف بأرقام حيّة: **العائلة** (`AdminAnalyticsView` «إحصاءات العائلة»: بيت «إحصاء الأفراد» + «المسجّلون في التطبيق من الأحياء»؛ المراقب الأعداد فقط) · **الاستخدام** (`AdminActiveMembersView`) · **الموافقات** (`ApprovalsReportView` — بيت تقرير الموافقات الوحيد). «سجل التعديلات» حُذف من هنا — بيته «إشعارات الإدارة» ← «نشاط الفريق» (`AdminActivityLogView` حُذف)، وفهرس الأدوات يجده بالبحث (`today.notices`، `searchOnly` + `place` «اليوم ← الجرس»).
**«الفريق والأمان»** (`AdminTeamArea.swift`): ثلاث إشارات حالة في الرأس (رصيد رسائل الدخول · التسجيل · وصول الإشعارات — أرقام↗ لبيوتها) ← بطاقة **«فريق الإدارة»** (`AdminModeratorsView`: الأعضاء حسب الدور ← «صلاحيات الأدوار» بدورك مميّزاً؛ «＋» للمالك بالمنتقي الموحّد `DSMemberPickerBox` ثم `ChangeRoleSheet(title:)`) ← «الدخول والأمان»: **رسائل رمز الدخول (KWT SMS)** · **التسجيل والمنع** (`AdminRegistrationBansView`: «السماح بالتسجيل» + «الأرقام الممنوعة من التسجيل» بلا بحث) · **الأجهزة ووصول الإشعارات** (`AdminPushHealthView`: تسجيل الأجهزة للإشعارات — تصلها (رمز صالح ومحدَّث خلال ٣٠ يوماً) · لم تُحدَّث منذ 30 يوماً · غير مسجّلة، الأجهزة المرتبطة، «عدد الأجهزة المسموح لكل عضو»، الأدوات: إرسال إشعار تجريبي · حذف التسجيلات غير الصالحة؛ `AdminDeviceReachStore` يجلب `device_tokens` مرة لها ولرأس القسم و«المناسبات» وإشارة «بلا إشعارات» في «حالة النظام» بـ«اليوم»؛ أجهزة عضو بعينه في ورقة العضو فقط). **رسائل رمز الدخول** (`AdminSmsView`، المالك والمدير): بيانات حيّة من `sms_admin_overview()` (`SmsBalanceStore`، يقرأ منه «حالة النظام» في «اليوم» ورأس القسم بالعتبات المحفوظة) — الرصيد وحالته وكم يكفي، «تحديث الرصيد الآن»، اليوم/٧/٣٠ يوماً، رسم ٣٠ يوماً، آخر الإرسالات مع «فحص الحالة» ← **«إعدادات الإرسال»** المكان الوحيد (الحدود الأربعة للمالك، رموز للجميع بالثانية، اسم المرسل، الدول المتاحة، نص الرسالة ومعاينتها) ← «تنبيهات الرصيد» (+ آخر تنبيه؛ المالك يعدّل والمدير يقرأ) ← الأدوات (إرسال رسالة تجريبية لرقمي · التحقق من رقم) ← **«طلبات رمز الدخول»** (`AdminSmsAttempts.swift`، `sms_login_attempts(p_days 1…30)` → `SmsLoginAttemptsStore`: من طلب رمزاً وكم مرة، ناجحة/مشبوهة (٥+ في ساعة)؛ الرقم كاملاً للمالك مع نسخ/اتصال من `phone_e164` ومخفياً للمدير — السيرفر يخفي والتطبيق يعرض كما وصل؛ يُحفظ ٣٠ يوماً، والرمز لا يُحفظ أبداً فلا واجهة توحي برؤيته) ← بطاقة مطويّة **«طريقة العمل»** (`SmsHowItWorksCard`، `AdminSectionCard(isOpen:summary:)`: المسار، ما يُحفظ وما لا يُحفظ أبداً، من يرى ماذا، معنى ناجحة/مشبوهة — النص نفسه للأندرويد لاحقاً). رابط الشحن الوحيد `SmsBalanceStore.rechargeURL`.
**«التطبيق»** = الإعدادات نفسها (`AdminAppArea.swift`، `AdminAppAreaPage`؛ المفاتيح في مكانها، خمس مجموعات تحت عناوين صغيرة): الأقسام الظاهرة للأعضاء (اللغة قائمة في مكانها، الديوانيات، شجرة النساء، المشاريع، الاستطلاعات، اعتماد الأخبار قبل نشرها) · القوائم (تصنيفات الأخبار والمكتبة · «أسماء العوائل والفروع» صفحة واحدة `AdminFamilyNamesView`) · التعديلات الذاتية (حدّ التعديلات الذاتية + إعادة ضبط العدّاد) · التشغيل (وضع الصيانة · فرض التحديث) · النظام (الإصدار، آخر تعديل، «استعادة الإعدادات الافتراضية»)؛ المدير شارة «للاطلاع فقط — التعديل للمالك» والمفاتيح معطّلة. لا «كل الإعدادات في صفحة واحدة».
**التقنية:** **الصفحة المدفوعة في `NavigationStack` لا ترث بيئة موضع الرابط ولا ما فوق المكدس**: قسم الصفحة (`.adminArea(_)`) يمرّره كل من يدفع صراحةً (صفوف الأقسام، `AdminTapWrap`، دافع صفحات `.list`، روابط «اليوم») — رابط جديد في اللوحة = مرّر `.adminArea(…)` مع `.adminBackTitle(…)`. **حارس المكدس**: وجهة `NavigationLink` بنوع صفحة ضخمة مباشرة تعمّق المكدس — «اليوم» نزل من ٧١٧ إلى ٤٥٦ ك.ب بعد وضع `AdminAllRequestsView` خلف `AdminLazyPage { AnyView(…) }`؛ كل وجهة رابط في اللوحة خلف `AdminLazyPage`، وكل بطاقة/طبقة كبيرة نوع مستقل خلف `AnyView` (جسما `AdminAllRequestsView` و`AdminInboxView` طبقات — كانا يفيضان بـ١٢٨ ك.ب)، وقِس `-tmpStackDepth` (اليوم ≤ ٧٢٠ — ٤١٧ بعد الدفعة ٨، تبويب الإدارة ≤ ٨٠٠ — ٧٩١–٧٩٥، الصفحات ≤ ٦٠٠ — «إشعارات الإدارة» ٤٠٨) و`-tmpStackCheck` (≤ ٦٤ ك.ب). الألوان والمقاسات في `DS.Hub` و`DS.TextRole.hub*` (أرقام الرأس استثناء مقصود من «لا نصّ فوق ١٧»). نصّ من متغيّرين بفاصل محايد → `Text(verbatim:)` (مفتاح الترجمة يعزل المتغيّرين فيقلب ترتيبهما في العربية).
**أسماء الفروع** (`app_settings.branch_names jsonb` = `{"<uuid رأس الفرع بحروف صغيرة>": "الاسم"}`، `20261009120000`، القراءة لكل مسجّل والتعديل للمالك بسياسة `app_settings` نفسها): تُسمّى من «التطبيق ← أسماء العوائل والفروع ← أسماء الفروع» (`BranchPickerSheet(renamesBranches: true)`، المسح = حذف المفتاح)، وتظهر **في صفوف قائمة الفروع فقط** (`BranchPickerSheet` — بحث الشجرة، مركز التقارير؛ وعناوين «حسب الفرع» في صفحة الأعضاء؛ تُقرأ من `AppSettingsViewModel.branchName(for:)` في البيئة). شريحة/حقل الفرع المختار والبحث وأسماء الأعضاء لا تتأثر. القائمة بلا حقل بحث افتراضياً (`showsSearch: false`).

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

- **Section chrome = `AppSection` (`Components/Shared/AppSection.swift`).** Since the merge with main's identity every section (the 5 tabs and `.library/.projects/.news`) resolves to the identity navy: header `headerGradient` = `gradientBand`, `fill` = `primaryFill`, `ink` = `primary`, `control` = `headerControlFill`, `gradient` (action buttons) = flat `gradientPrimary`. Home tiles are NOT section colours: they use the navy-and-gold family tile tokens (`tileTree` palm, `tileDiwaniya` navy, `tileLibrary` sadu, `tileProjects` gold, `tileContact` sea; `AppSection.HomeTile.library/projects/news` fill/deep/ink = sadu / gold / navyFill). The pre-merge per-section palette «البحري الخفيف» is in the history of `wip/ios-2026-10-02`.
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
| Text roles | `DS.TextRole` (`DesignSystem.swift`) = **Apple default Dynamic Type sizes** (طلب المالك ٢٠٢٦-١٠-٠٨ «حجم الخط الافتراضي في الآيفون»): each role = an Apple style at its «Large» size, `relativeTo:` that style, so it follows the phone's text-size setting. **Only titles may exceed body 17** (owner 2026-10-08): pageTitle/emptyTitle title3 20 · tabTitle/celebrationTitle title2 22 · heroTitle title1 28; every non-title text (numbers → `statValue` headline 17, names as values, fields, phone digits) ≤ 17 · title/headline headline 17 · body/rowTitle/button body 17 · callout 16 · subtitle/pageSubtitle/chip/segment/tileTitle subheadline 15 · sectionTitle/boxSectionTitle/label/footnote/chipCompact/segmentCompact footnote 13 · caption caption1 12 · badge/micro caption2 11; the old half-steps (`*Compact`) now equal their base style. Excluded from the Apple mapping: OTP digits (`codeDigit` 26 / `codeDigitCompact` 22, relativeTo title2 — unchanged by owner's request), tree-node sizes (`nodeCount` 16, `treeNodeMicro/Tiny` — they scale with the node, below) and the letter inside an avatar circle (`avatarInitial` 34, `avatarInitialLarge` 96). New role → `DS.TextRole(.style, weight:)`; `DS.Font.appleSize/textStyle(for:)` hold the scale | `.dsFont(.role)` · `.dsFieldFont(.role)` (same size — `DSFieldFont.boxReduction` = 0) · `DS.Font.role(.role)`; containers hug text (`minHeight`, never a fixed text height) | Drawn at size × `DS.Font.opticalScale` **0.9** (Plex looks ~11% bigger than SF at the same pt — matches the iPhone by eye, طلب المالك ٢٠٢٦-١٠-٠٨); fixed graphic sizes `TextRole(size:)` (OTP digits, tree nodes) are exempt. **Tree nodes scale as a whole with «حجم النص»** (طلب المالك ٢٠٢٦-١٠-٠٨ «بشي منظم»): `DS.TreeScale` (`DesignSystem.swift`) = ONE factor from `@Environment(\.dsTreeScale)` — xSmall .88 · small .92 · medium .96 · **large 1** · xLarge 1.1 · xxLarge 1.2 · xxxLarge **1.3 = `cap`** (accessibility sizes stay at the cap). Name, avatar, box, badges, gaps, connector lines (`TreeArtLines.layers(…, scale:)`) all × k — real metrics, never `scaleEffect`; the old `.dsTreeNode` pin is gone. Each tree reads the factor once into `@State` (stale `.equatable()` node closures), builds `FamilyTreeMetrics`/`WomenTreeMetrics(k:)` once per layout and stores it in `layout.m` — nodes, lines, camera read `layout.m`. Node text = `.dsTreeFont(role, k)` (fixed size = role.textSize × k rounded to a whole point, as Dynamic Type rounds — pixel-identical at Large), glyphs `.dsTreeGlyph(DS.Glyph.x, k)`. Zoom (fit, kinship, «موقعي») is in default-node units so the tree really grows (more panning); pinch/double-tap limits ÷ k keep the on-screen extremes; centring keeps a node's TOP where it is at Large so bigger nodes grow downward, not under the toolbar. New tree node → take `k` and multiply every size. A full name in a list row → `.dsNameLines()` (1 line at default/smaller, 2 lines when the phone text is larger — `DSBox.nameLinesLargeText`); field fonts by size (`dsFieldFont(DSBox.fieldValueSize)`) get the same × opticalScale as roles (فحص ٢٠٢٦-١٠-٠٨).
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
