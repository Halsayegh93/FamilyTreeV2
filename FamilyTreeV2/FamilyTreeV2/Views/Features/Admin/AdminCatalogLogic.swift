import Foundation

// MARK: - فهرس الأدوات والبوابة — المنطق الخالص (إعادة تصميم الإدارة ٢٠٢٦-١١-٢٦، الوحدة U19)
//
// ١) `AdminCatalogTool`: كل معرّفات فهرس الأدوات (`AdminToolCatalog` في AdminAreaPages.swift) — ثابتة، لا يُحذف معرّف
//    (البحث الشامل وجدول الانتقال يقرآنها). لكل معرّف قسمه وبيته الواحد (`AdminCatalogHome`، spec B.7) وكلماته: الكلمات
//    القديمة تجد البيت الجديد («المؤشرات» ← «الإحصاءات»، «الرسائل» ← صفحة «رسائل الأعضاء»…).
//    الصفحة نفسها لكل بيت يرسمها `AdminToolCatalog.homePage(_:)` — المكان الواحد من المعرّف إلى الصفحة.
// ٢) `AdminGateLogic`: رسالة `AdminAreaGate` حين يرفض قسماً — «هذا القسم للمالك فقط» للقسم المقصور على المالك بسقف جدول
//    الأدوار وحده («التطبيق والنظام»: كل خاناته `isOwnerOnly`)، وغيره «هذا القسم ليس ضمن صلاحياتك» («الفريق والصلاحيات»
//    يراه المدير).
// ٣) `AdminAreaNames` و`AdminAreaLayout` (٢٠٢٦-١١-٢٨، ترتيب المالك المعتمد `admin-ia`/`admin-sections`): أسماء الأقسام الستة،
//    ومجموعات كل قسم بعناوينها الصغيرة وترتيبها — الصفحات ترسم عناوينها من هنا.
//
// يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u19-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Core/ArabicTextNormalizer.swift FamilyTreeV2/FamilyTreeV2/Core/NameSearch.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminCatalogLogic.swift tests/admin-redesign/U19/main.swift && /tmp/u19-logic

// MARK: - ١) الفهرس

/// معرّف أداة في الفهرس — `rawValue` هو `AdminTool.id`
nonisolated enum AdminCatalogTool: String, CaseIterable, Hashable {
    case inboxRequests = "inbox.requests"
    case inboxMessages = "inbox.messages"
    case inboxSettings = "inbox.settings"
    case familyMembers = "family.members"
    case familyRegister = "family.register"
    case familyExport = "family.export"
    case occasionsCreate = "occasions.create"
    case metricsFamily = "metrics.family"
    case metricsApprovals = "metrics.approvals"
    case todayNotices = "today.notices"
    case teamMembers = "team.members"
    case accessSms = "access.sms"
    case accessRegistration = "access.registration"
    case accessUsage = "access.usage"
    /// جديد (U19): «الأجهزة والإشعارات» صار بيتاً وحده (spec C.13) — كان مدموجاً في `access.usage` للمالك
    case accessDevices = "access.devices"
    case appSections = "app.sections"
    case appCategories = "app.categories"
    case appNames = "app.names"
    case appForceUpdate = "app.forceUpdate"
    case appErrors = "app.errors"

    /// القسم (`AdminArea.rawValue`) — قسم مخفي لدورك تختفي أدواته من البحث
    var areaKey: String {
        switch self {
        case .inboxRequests, .inboxMessages, .inboxSettings, .todayNotices: return "inbox"
        case .familyMembers, .familyRegister, .familyExport: return "family"
        case .occasionsCreate: return "occasions"
        // «الاستخدام» في «الإحصاءات» منذ ٢٠٢٦-١١-٢٨ (كان في «الفريق والأمان»)
        case .metricsFamily, .metricsApprovals, .accessUsage: return "metrics"
        case .teamMembers, .accessRegistration: return "team"
        // رسائل رمز الدخول والأجهزة في «التطبيق والنظام» ← «النظام» منذ ٢٠٢٦-١١-٢٨ (للمالك وحده كما كانتا)
        case .appSections, .appCategories, .appNames, .appForceUpdate, .appErrors, .accessSms, .accessDevices: return "app"
        }
    }

    /// البيت الواحد الذي تفتحه الأداة (spec B.7، B.6 «AdminToolCatalog»)
    var home: AdminCatalogHome {
        switch self {
        case .inboxRequests:      return .inboxRoot
        case .inboxMessages:      return .messagesPage
        case .inboxSettings:      return .approvalSettings
        case .familyMembers:      return .familyRoot
        case .familyRegister:     return .registerMember
        case .familyExport:       return .memberReport
        case .occasionsCreate:    return .occasionsRoot
        case .metricsFamily:      return .statsRoot
        case .metricsApprovals:   return .approvalsReport
        case .todayNotices:       return .adminNotices
        case .teamMembers:        return .moderators
        case .accessSms:          return .sms
        case .accessRegistration: return .registrationBans
        case .accessUsage:        return .usage
        case .accessDevices:      return .devices
        case .appSections:        return .appRoot
        case .appCategories:      return .categories
        case .appNames:           return .familyNames
        case .appForceUpdate:     return .forceUpdate
        case .appErrors:          return .errors
        }
    }

    /// كلمات البحث — الأسماء القديمة تبقى حتى تجد بيتها الجديد
    var keywords: [String] {
        switch self {
        case .inboxRequests:
            // «المنجز» و«طلبات الخصوصية» و«بانتظار المراجعة» صفوف أبواب في «الوارد» (spec C.2/C.5)
            return ["طلبات", "مراجعة", "انضمام", "موافقة", "بانتظار قرارك", "عاجل", "متأخر", "يحتاج انتباهك",
                    "المنجز", "المنجزة", "منجز اليوم", "بانتظار المراجعة", "مراجعة المنشورات",
                    "طلبات الخصوصية", "الخصوصية"]
        case .inboxMessages:
            return ["رسائل", "الرسائل", "تواصل", "رسائل الأعضاء", "تواصل مع الإدارة"]
        case .inboxSettings:
            return ["مسار", "مهلة", "ردود", "نماذج", "اعتماد مباشر", "المسار السريع"]
        case .familyMembers:
            // القوائم الست في «يحتاج مراجعتك» و«نساء العائلة» صفحات تحت جذر «العائلة» (spec C.8/C.9)
            return ["أعضاء", "سجل", "فروع", "عضو", "إدارة السجل", "بيانات العضو",
                    "المسجّلون", "مسجلون", "الأعضاء المسجّلون", "حسابات", "استخدام", "مسجّل", "موقوف", "تفعيل",
                    "بيانات ناقصة", "نواقص", "جودة", "استكمال", "محطة",
                    "مشكلات الشجرة", "مشكلات", "صحة", "سلامة", "يتيم", "مكرر",
                    "مراجعة", "يحتاج مراجعتك", "تحقق من الأحياء", "هل ما زالوا أحياء", "تواريخ الوفاة",
                    "شجرة النساء", "نساء العائلة", "النساء"]
        case .familyRegister:
            return ["تسجيل", "إضافة"]
        case .familyExport:
            return ["تقرير", "تقارير", "طباعة", "pdf"]
        case .occasionsCreate:
            return ["إعلان", "إعلانات", "إشعار", "إرسال", "جدولة", "وفاة", "عزاء", "تهنئة", "تعزية", "بطاقة",
                    "منشور", "مناسبة", "تحديث", "إصدار", "مستجدات", "إنشاء",
                    "القادم", "ذكرى", "راحلين", "مجدول", "مجدولة", "تعديل الإشعار", "إلغاء الإشعار", "وفيات",
                    "المنشور", "أُعلن", "مرسلة"]
        case .metricsFamily:
            // «المؤشرات» اسم القسم القديم (spec B.3)
            return ["المؤشرات", "مؤشرات", "إحصائيات", "إحصاءات", "إحصاء الأفراد", "أعداد الأعضاء", "أعمار", "أفراد",
                    "نمو", "رجال", "نساء", "أحياء", "متوفون", "الراحلون", "في التطبيق", "خارج العائلة", "الأدوار"]
        case .metricsApprovals:
            return ["المؤشرات", "تقرير", "تقرير الموافقات", "منجز", "مسار"]
        case .todayNotices:
            return ["إشعارات", "تنبيهات", "جرس", "سجل", "سجل التعديلات", "سجل النشاط", "تعديلات",
                    "نشاط الفريق", "يحتاج إجراء", "النظام"]
        case .teamMembers:
            // «الفريق والأمان» اسم القسم القديم (٢٠٢٦-١١-٢٨ ← «الفريق والصلاحيات»)
            return ["فريق", "مدير", "مراقب", "مشرف", "أدوار", "صلاحيات", "نطاقي", "الصلاحيات",
                    "الفريق والأمان", "الفريق والصلاحيات"]
        case .accessSms:
            return ["رسائل", "sms", "رصيد", "kwt", "محاولات", "مرسل", "طلبات رمز الدخول", "مريبة", "مشبوهة"]
        case .accessRegistration:
            return ["تسجيل", "شروط", "حظر", "محظور", "منع", "ممنوع"]
        case .accessUsage:
            return ["الاستخدام", "استخدام", "نشاط", "نشط", "نشطون", "الآن", "الحين", "مستخدمون", "جلسات",
                    "شاشات", "اتجاه", "دقائق", "آخر 24 ساعة"]
        case .accessDevices:
            return ["الأجهزة ووصول الإشعارات", "الأجهزة والإشعارات", "أجهزة", "الأجهزة", "إشعارات", "رموز", "وصول",
                    "وصول الإشعارات", "فصل", "تجربة", "تسجيل الأجهزة", "إشعار تجريبي",
                    "تسجيل فاشل", "بدون جهاز", "ما دخلوا"]
        case .appSections:
            // «حالة النظام» صارت حالة مربّع «التطبيق» وبطاقة حالته (spec B.2)
            return ["التطبيق والنظام", "لغة", "ميزات", "ديوانيات", "مشاريع", "استطلاعات", "أخبار", "اعتماد", "شجرة النساء",
                    "الأقسام الظاهرة للأعضاء", "عداد", "تعديل", "حد", "حدّ التعديلات الذاتية",
                    "صيانة", "تشغيل", "وضع الصيانة", "النظام", "حالة النظام", "معلومات", "إعادة التعيين", "افتراضي",
                    "استعادة"]
        case .appCategories:
            return ["تصنيفات", "قوائم"]
        case .appNames:
            return ["عوائل", "عائلة", "فروع", "قوائم"]
        case .appForceUpdate:
            return ["تحديث", "إجباري", "إصدار"]
        case .appErrors:
            return ["أخطاء", "خطأ", "أعطال", "عطل", "تعطل", "مشاكل", "Sentry", "سنتري", "كراش", "crash"]
        }
    }
}

/// بيت أمر — الصفحة الوحيدة التي يعمل فيها (spec B.7). الأداة باب إليه فقط
nonisolated enum AdminCatalogHome: String, CaseIterable, Hashable {
    /// جذر «الوارد» (`AdminAllRequestsView`) — وفيه أبواب «المنجز» و«طلبات الخصوصية» و«بانتظار المراجعة»
    case inboxRoot
    /// «رسائل الأعضاء» (`AdminInboxView` صفحةً)
    case messagesPage
    /// «إعدادات مسار الموافقات» (`AdminAppSettingsView(scope: .approvals)`)
    case approvalSettings
    /// جذر «العائلة» (`AdminMembersPage`) — وفيه «يحتاج مراجعتك» و«نساء العائلة»
    case familyRoot
    /// «تسجيل عضو جديد» (`AdminRegisterMemberView`)
    case registerMember
    /// «تقرير PDF» (`AdminReportsView`)
    case memberReport
    /// جذر «المناسبات والإعلانات» (`AdminOccasionsPage`)
    case occasionsRoot
    /// جذر «الإحصاءات» (`AdminMetricsAreaView`)
    case statsRoot
    /// «تقرير الموافقات» (`ApprovalsReportView`)
    case approvalsReport
    /// «إشعارات الإدارة» (`AdminNotificationsPage`)
    case adminNotices
    /// «فريق الإدارة» (`AdminModeratorsView`)
    case moderators
    /// «رسائل رمز الدخول» (`AdminSmsView`)
    case sms
    /// «التسجيل والمنع» (`AdminRegistrationBansView`)
    case registrationBans
    /// «الاستخدام» (`AdminActiveMembersView`)
    case usage
    /// «الأجهزة والإشعارات» (`AdminPushHealthView`)
    case devices
    /// جذر «التطبيق» (`AdminAppAreaPage`)
    case appRoot
    /// «تصنيفات الأخبار والمكتبة» (`CategoriesManagerView`)
    case categories
    /// «أسماء العوائل والفروع» (`AdminFamilyNamesView`)
    case familyNames
    /// «فرض التحديث» (`AdminForceUpdateView`)
    case forceUpdate
    /// «الأخطاء» (`AdminErrorsPage`)
    case errors
}

/// البحث في الفهرس — نفس البحث الدقيق الواحد في التطبيق (`NameSearch`: كل كلمة بداية كلمة وبالترتيب)
enum AdminCatalogLogic {
    /// تطابق الأداة: نصوصها الظاهرة (العنوان، الوصف، مكانها) أو كلماتها
    static func matches(query: String, texts: [String], tool: AdminCatalogTool) -> Bool {
        NameSearch.matches(query: query, any: texts + tool.keywords)
    }

    /// الأدوات المطابقة بترتيبها — `texts` نصوص كل أداة الظاهرة (فارغة = الكلمات وحدها)
    static func tools(matching query: String, among tools: [AdminCatalogTool] = AdminCatalogTool.allCases,
                      texts: (AdminCatalogTool) -> [String] = { _ in [] }) -> [AdminCatalogTool] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return tools.filter { matches(query: q, texts: texts($0), tool: $0) }
    }
}

// MARK: - ٢) رسالة البوابة

nonisolated enum AdminGateLogic {
    enum Message: Equatable {
        /// القسم مقصور على المالك بسقف جدول الأدوار — لا يفتحه الجدول لأي دور آخر
        case ownerOnly
        /// القسم يُفتح لأدوار أخرى، وليس لدورك
        case notInRole

        var title: String {
            switch self {
            case .ownerOnly: return L10n.t("هذا القسم للمالك فقط.", "This section is for the owner only.")
            case .notInRole: return L10n.t("هذا القسم ليس ضمن صلاحياتك.", "This section isn't part of your permissions.")
            }
        }

        /// السطر تحت العنوان — أين يجد صلاحياته (صفّ «صلاحياتي» في «اليوم» للمدير والمراقب والمشرف)
        var hint: String {
            L10n.t("تجد صلاحياتك في «صلاحياتي» على «اليوم».", "Your permissions are under “My permissions” on Today.")
        }
    }

    /// خانات القسم في جدول الأدوار: مفاتيح `AdminRoleItem` التي تبدأ باسم القسم («team.sms» ← «team»)
    static func itemKeys(of areaKey: String, in allItemKeys: [String]) -> [String] {
        allItemKeys.filter { $0.hasPrefix(areaKey + ".") }
    }

    /// للمالك فقط = للقسم خانات، وكلها تحت سقف المالك (`AdminRoleItem.isOwnerOnly`). «التطبيق» (`app.settings`) كذلك؛
    /// «الفريق والأمان» لا («فريق الإدارة» و«الاستخدام» يراهما المدير)، والقسم بلا خانات («العائلة») لا
    static func message(areaKey: String, allItemKeys: [String], ownerOnlyItemKeys: Set<String>) -> Message {
        let items = itemKeys(of: areaKey, in: allItemKeys)
        guard !items.isEmpty, items.allSatisfy({ ownerOnlyItemKeys.contains($0) }) else { return .notInRole }
        return .ownerOnly
    }
}

// MARK: - ٣) أسماء الأقسام ومجموعاتها (ترتيب المالك ٢٠٢٦-١١-٢٨)

/// أسماء الأقسام الستة — `AdminArea.title` يقرأ من هنا. «الفريق والأمان» ← «الفريق والصلاحيات»، و«التطبيق» ← «التطبيق
/// والنظام» (رسائل رمز الدخول والأجهزة انتقلتا إليه). `rawValue` المفاتيح ثابتة (جدول السيرفر)
nonisolated enum AdminAreaNames {
    static func title(_ areaKey: String) -> String {
        switch areaKey {
        case "inbox":     return L10n.t("الوارد", "Inbox")
        case "family":    return L10n.t("العائلة", "Family")
        case "occasions": return L10n.t("المناسبات والإعلانات", "Occasions & announcements")
        case "metrics":   return L10n.t("الإحصاءات", "Statistics")
        case "team":      return L10n.t("الفريق والصلاحيات", "Team & permissions")
        case "app":       return L10n.t("التطبيق والنظام", "App & system")
        default:          return areaKey
        }
    }
}

/// مجموعة صغيرة بعنوانها داخل صفحة قسم — الترتيب في `AdminAreaLayout.groups(_:)`
nonisolated enum AdminAreaGroup: String, CaseIterable, Hashable {
    // العائلة
    case review, members
    // المناسبات والإعلانات
    case upcoming, grief, joys, published
    // الإحصاءات
    case family, inApp, approvals, details
    // الفريق والصلاحيات
    case team, people
    // التطبيق والنظام
    case visible, lists, operations, system

    var title: String {
        switch self {
        case .review:     return L10n.t("يحتاج مراجعتك", "Needs your review")
        case .members:    return L10n.t("الأعضاء", "Members")
        case .upcoming:   return L10n.t("القادم", "Coming up")
        case .grief:      return L10n.t("عزاء وذكرى", "Condolences and memorials")
        case .joys:       return L10n.t("أفراح العائلة", "Family joys")
        case .published:  return L10n.t("المنشور", "Published")
        case .family:     return L10n.t("العائلة", "Family")
        case .inApp:      return L10n.t("في التطبيق", "In the app")
        case .approvals:  return L10n.t("الموافقات", "Approvals")
        case .details:    return L10n.t("التفاصيل", "Details")
        case .team:       return L10n.t("الفريق", "Team")
        case .people:     return L10n.t("الأعضاء", "Members")
        case .visible:    return L10n.t("الأقسام الظاهرة", "Visible sections")
        case .lists:      return L10n.t("القوائم", "Lists")
        case .operations: return L10n.t("التشغيل", "Operations")
        case .system:     return L10n.t("النظام", "System")
        }
    }
}

nonisolated enum AdminAreaLayout {
    /// مجموعات القسم بترتيبها (`AdminArea.rawValue`) — «الوارد» كما هو بلا مجموعات
    static func groups(_ areaKey: String) -> [AdminAreaGroup] {
        switch areaKey {
        case "family":    return [.review, .members]
        case "occasions": return [.upcoming, .grief, .joys, .published]
        case "metrics":   return [.family, .inApp, .approvals, .details]
        case "team":      return [.team, .people]
        case "app":       return [.visible, .lists, .operations, .system]
        default:          return []
        }
    }

    /// مجموعة الأداة داخل قسمها (nil = جذر القسم نفسه أو صفّ بحث فقط)
    static func group(of tool: AdminCatalogTool) -> AdminAreaGroup? {
        switch tool {
        case .familyMembers, .familyRegister, .familyExport: return .members
        case .metricsFamily:     return .family
        case .accessUsage:       return .inApp
        case .metricsApprovals:  return .approvals
        case .teamMembers:       return .team
        case .accessRegistration: return .people
        case .appSections:       return .visible
        case .appCategories, .appNames: return .lists
        case .appForceUpdate:    return .operations
        case .accessSms, .accessDevices, .appErrors: return .system
        case .inboxRequests, .inboxMessages, .inboxSettings, .todayNotices, .occasionsCreate: return nil
        }
    }
}
