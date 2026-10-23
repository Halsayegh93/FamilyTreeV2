import SwiftUI

// MARK: - صفحات الأقسام الستة (إعادة تصميم لوحة الإدارة — طلب المالك ٢٠٢٦-١٠-٢٠، «٦ أقسام»)
//
// كل قسم = رأس كحلي («‹ اليوم»، العنوان قائمة الأقسام، الوصف) + بطاقات صفوف تفتح الصفحات الموجودة كما هي (لا منطق
// جديد). «المناسبات والإعلانات» صفحتها الخاصة (`AdminOccasionsPage`: إنشاء · القادم · المنشور)، و«الفريق
// والأمان» تجمع «الفريق» و«من يدخل وكيف».
// فهرس الأدوات `AdminToolCatalog` هو المصدر الواحد: الأقسام والبحث الشامل وجدول الانتقال (REACHABILITY.md)
// يقرؤون منه — كل ميزة لها صفّ واحد في قسم واحد، والصلاحيات كما كانت تماماً.

/// أداة في قسم: صفّ يفتح صفحة موجودة، أو إجراء (فتح شجرة النساء في تبويب الشجرة)
struct AdminTool: Identifiable {
    enum Kind {
        case page(() -> AnyView)
        case action(() -> Void)
    }

    let id: String
    let area: AdminArea
    /// عنوان البطاقة التي يقع فيها الصفّ داخل القسم
    let group: String
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    var keywords: [String] = []
    let kind: Kind
    /// للبحث الشامل فقط — لا يُرسم في صفحة قسمه (بيته في مكان آخر، مثل جرس «اليوم»)
    var searchOnly = false
    /// اسم بيته في نتائج البحث بدل اسم القسم
    var place: String? = nil
}

@MainActor
enum AdminToolCatalog {

    /// كل أدوات اللوحة المتاحة لهذا الدور — بالترتيب داخل كل قسم
    static func tools(authVM: AuthViewModel, adminRequestVM: AdminRequestViewModel) -> [AdminTool] {
        var t: [AdminTool] = []
        let isAdmin = authVM.isAdmin
        let role = authVM.currentUser?.role
        func page(_ make: @escaping () -> some View) -> AdminTool.Kind { .page { AnyView(make()) } }

        // ١ الوارد — صفحة القسم هي «الطلبات» (`AdminAllRequestsView`)؛ هذه الصفوف للبحث الشامل: الطلبات · الرسائل · ⚙︎
        // («تقرير الموافقات» بيته «المؤشرات»، و«مشكلات الشجرة» شريحة في «العائلة» — الدفعة ب ٢٠٢٦-١٠-٢٠)
        t.append(AdminTool(id: "inbox.requests", area: .inbox, group: L10n.t("الوارد", "Inbox"),
                           title: L10n.t("الطلبات", "Requests"),
                           subtitle: L10n.t("كل ما ينتظر قراراً — بالنوع والمهلة", "Everything awaiting a decision"),
                           icon: "tray.full.fill", tint: DS.Color.primary,
                           keywords: ["طلبات", "مراجعة", "انضمام", "موافقة", "بانتظار قرارك", "عاجل", "متأخر", "يحتاج انتباهك"],
                           kind: page { AdminAllRequestsView() }))
        t.append(AdminTool(id: "inbox.messages", area: .inbox, group: L10n.t("الوارد", "Inbox"),
                           title: L10n.t("الرسائل", "Messages"),
                           subtitle: L10n.t("رسائل الأعضاء من «تواصل مع الإدارة»", "Members' “Contact admin” messages"),
                           icon: "bubble.left.and.bubble.right.fill", tint: DS.Color.sea,
                           keywords: ["رسائل", "تواصل", "رسائل الأعضاء"],
                           kind: page { AdminAllRequestsView(startsWithMessages: true) }))
        if authVM.canViewSystemSettings {
            t.append(AdminTool(id: "inbox.settings", area: .inbox, group: L10n.t("الوارد", "Inbox"),
                               title: L10n.t("إعدادات مسار الموافقات", "Approval path settings"),
                               subtitle: L10n.t("مسار الموافقات، المهلة، الاعتماد المباشر، نماذج الردود",
                                                "Approvals path, SLA, direct approval, reply templates"),
                               icon: "gearshape.fill", tint: DS.Color.slate,
                               keywords: ["مسار", "مهلة", "ردود", "نماذج", "اعتماد مباشر", "المسار السريع"],
                               kind: page { AdminAppSettingsView(scope: .approvals) }))
        }

        // ٢ العائلة — صفحة القسم هي صفحة الأعضاء الواحدة (`AdminMembersPage`)؛ هذه الصفوف للبحث الشامل فقط
        // (تفتح الصفحة على شريحتها، والكلمات القديمة تجد بيتها الجديد)
        if authVM.canEditMembers {
            let members = L10n.t("الأعضاء", "Members")
            t.append(AdminTool(id: "family.members", area: .family, group: members,
                               title: L10n.t("الأعضاء", "Members"),
                               subtitle: L10n.t("بحث وشرائح، وورقة لكل عضو بكل أوامره", "Search, filters and one sheet per member"),
                               icon: "person.3.sequence.fill", tint: DS.Color.palm,
                               // الشرائح الثلاث («المسجّلون» · «بيانات ناقصة» · «مشكلات الشجرة») تُفتح من داخل الصفحة نفسها
                               keywords: ["أعضاء", "سجل", "فروع", "عضو", "إدارة السجل", "بيانات العضو",
                                          "المسجّلون", "مسجلون", "الأعضاء المسجّلون", "حسابات", "استخدام", "مسجّل", "موقوف", "تفعيل",
                                          "بيانات ناقصة", "نواقص", "جودة", "استكمال", "محطة",
                                          "مشكلات الشجرة", "مشكلات", "صحة", "سلامة", "يتيم", "مكرر"],
                               kind: page { AdminMembersPage() }))
            if authVM.canRegisterMembers {
                t.append(AdminTool(id: "family.register", area: .family, group: members,
                                   title: L10n.t("تسجيل عضو جديد", "Register a new member"),
                                   subtitle: L10n.t("عضو جديد بصورته ورقمه", "A new member with photo and phone"),
                                   icon: "person.badge.plus", tint: DS.Color.palm,
                                   keywords: ["تسجيل", "إضافة"],
                                   kind: page { AdminRegisterMemberView() }))
            }
            // «شجرة النساء» أُزيل اختصارها من الإدارة (طلب المالك ٢٠٢٦-١٠-٢٠ «شيله»): بيتها الواحد تبويب الشجرة
            // «تقارير PDF» — بيتها الواحد «⋯ ← تصدير» في صفحة الأعضاء (الدفعة ج؛ كانت صفّاً في «المؤشرات»)
            if isAdmin {
                t.append(AdminTool(id: "family.export", area: .family, group: members,
                                   title: L10n.t("تصدير قائمة الأعضاء (PDF)", "Export member list (PDF)"),
                                   subtitle: L10n.t("زر التقارير في صفحة الأعضاء — بالشريحة المختارة", "Reports button on the members page — with the chosen filter"),
                                   icon: "doc.text.fill", tint: DS.Color.accent,
                                   keywords: ["تقرير", "تقارير", "طباعة", "pdf"],
                                   kind: page { AdminReportsView() }))
            }
        }

        // ٣ المناسبات والإعلانات — صفحة القسم (`AdminOccasionsPage`): «إنشاء» · «القادم» · «المنشور» (الدفعة ب ٢٠٢٦-١٠-٢٠)؛
        // هذه الصفوف للبحث الشامل وتفتح الصفحة نفسها (الكلمات القديمة تجد بيتها الجديد)
        if authVM.canModerate || authVM.canSendNotifications {
            let occasions = AdminArea.occasions.title
            t.append(AdminTool(id: "occasions.create", area: .occasions, group: occasions,
                               title: occasions,
                               subtitle: authVM.canSendNotifications
                                ? L10n.t("إعلان · إعلان وفاة · بطاقة تهنئة أو تعزية · إعلان تحديث التطبيق",
                                         "Announcement · obituary · greeting or condolence card · app update notice")
                                : L10n.t("بطاقة تهنئة أو تعزية", "Greeting or condolence card"),
                               icon: "plus.circle.fill", tint: DS.Color.sadu,
                               keywords: ["إعلان", "إعلانات", "إشعار", "إرسال", "جدولة", "وفاة", "عزاء", "تهنئة", "تعزية", "بطاقة",
                                          "منشور", "مناسبة", "تحديث", "إصدار", "مستجدات", "إنشاء",
                                          "القادم", "ذكرى", "راحلين", "مجدول", "مجدولة", "تعديل الإشعار", "إلغاء الإشعار", "وفيات",
                                          "المنشور", "أُعلن", "مرسلة"],
                               kind: page { AdminOccasionsPage() }))
        }

        // ٤ المؤشرات — ثلاثة مداخل للقراءة: العائلة · الاستخدام · الموافقات («سجل التعديلات» صار «نشاط الفريق» في
        // «إشعارات الإدارة» — الدفعة ٥). كل رقم في بيته هنا، و«اليوم» يعرض أرقاماً تفتحه فقط
        let insights = L10n.t("أرقام وسجل", "Numbers & history")
        if isAdmin || role == .monitor {
            // المراقب: الأعداد فقط (`AdminAnalyticsView` يقرأ الدور)
            t.append(AdminTool(id: "metrics.family", area: .metrics, group: insights,
                               title: L10n.t("العائلة", "The family"),
                               subtitle: isAdmin ? L10n.t("الأفراد والأحياء، المسجّلون، النمو والأعمار والأدوار",
                                                          "Members, living, registered, growth, ages and roles")
                                                 : L10n.t("أعداد الأفراد والأحياء والمسجّلين", "Members, living and registered counts"),
                               icon: "person.3.fill", tint: DS.Color.palm,
                               keywords: ["إحصائيات", "إحصاءات", "إحصاء الأفراد", "أعداد الأعضاء", "أعمار", "أفراد", "نمو",
                                          "رجال", "نساء", "أحياء", "متوفون"],
                               kind: page { AdminAnalyticsView() }))
        }
        if isAdmin {
            t.append(AdminTool(id: "metrics.usage", area: .metrics, group: insights,
                               title: L10n.t("الاستخدام", "Usage"),
                               subtitle: L10n.t("المستخدمون الآن، النشطون واتجاههم، الجلسات وأكثر الشاشات — التطبيق والموقع",
                                                "Using now, active members and trend, sessions and top screens — app and web"),
                               icon: "bolt.fill", tint: DS.Color.sea,
                               keywords: ["نشاط", "نشط", "الآن", "مستخدمون", "جلسات", "شاشات", "اتجاه", "دقائق"],
                               kind: page { AdminActiveMembersView() }))
        }
        // تقرير الموافقات — بيته الواحد هنا (كان أيضاً في رأس «الوارد» وصفّه ومربّع «منجز هذا الأسبوع»)
        if adminRequestVM.approvalsWorkflowOn && (isAdmin || role == .monitor) {
            t.append(AdminTool(id: "metrics.approvals", area: .metrics, group: insights,
                               title: L10n.t("الموافقات", "Approvals"),
                               subtitle: L10n.t("المنجز، وقت كل مرحلة، حسب النوع، أداء الإدارة", "Done, time per stage, by type, team"),
                               icon: "chart.bar.doc.horizontal", tint: DS.Color.warning,
                               keywords: ["تقرير", "تقرير الموافقات", "منجز", "مسار"],
                               kind: page { ApprovalsReportView() }))
        }
        // «إشعارات الإدارة» — بيتها جرس «اليوم» (صفحة واحدة: الطلبات ونشاط الفريق والنظام، وفيها بحث «سجل التعديلات»).
        // صفّ للبحث الشامل فقط (لا يُرسم في صفحة قسم)؛ الكلمات القديمة تجد بيتها الجديد
        if authVM.canModerate {
            t.append(AdminTool(id: "today.notices", area: .metrics, group: insights,
                               title: L10n.t("إشعارات الإدارة", "Admin notifications"),
                               subtitle: L10n.t("الطلبات ونشاط الفريق (سجل التعديلات) وتنبيهات النظام",
                                                "Requests, team activity (change log) and system alerts"),
                               icon: "bell.badge.fill", tint: DS.Color.primary,
                               keywords: ["إشعارات", "تنبيهات", "جرس", "سجل", "سجل التعديلات", "سجل النشاط", "تعديلات",
                                          "نشاط الفريق", "يحتاج إجراء", "النظام"],
                               kind: page { AdminNotificationsPage() }, searchOnly: true,
                               place: L10n.t("اليوم ← الجرس", "Today ← bell")))
        }

        // ٥ الفريق والأمان — أربعة مداخل: فريق الإدارة · رسائل رمز الدخول · التسجيل والمنع · الأجهزة ووصول الإشعارات
        // (صفحة القسم `AdminTeamAreaView` في `AdminTeamArea.swift`؛ «صلاحيات الأدوار» داخل فريق الإدارة)
        if isAdmin {
            t.append(AdminTool(id: "team.members", area: .team, group: L10n.t("الفريق", "Team"),
                               title: L10n.t("فريق الإدارة", "Admin team"),
                               subtitle: authVM.canManageRoles ? L10n.t("الأعضاء حسب الدور، وصلاحيات الأدوار — إضافة وتغيير",
                                                                        "Members by role and role permissions — add and change")
                                                               : L10n.t("الأعضاء حسب الدور، وصلاحيات الأدوار", "Members by role and role permissions"),
                               icon: "person.3.fill", tint: DS.Color.primary,
                               keywords: ["فريق", "مدير", "مراقب", "مشرف", "أدوار", "صلاحيات", "نطاقي", "صلاحياتي"],
                               kind: page { AdminModeratorsView() }))
        }
        if authVM.canViewSystemSettings {
            let access = L10n.t("الدخول والأمان", "Sign-in and security")
            t.append(AdminTool(id: "access.sms", area: .team, group: access,
                               title: L10n.t("رسائل رمز الدخول (KWT SMS)", "Sign-in code messages (KWT SMS)"),
                               subtitle: L10n.t("الرصيد، طلبات رمز الدخول، إعدادات الإرسال",
                                                "Balance, code requests, sending settings"),
                               icon: "ellipsis.message.fill", tint: DS.Hub.securityFill,
                               keywords: ["رسائل", "sms", "رصيد", "kwt", "محاولات", "مرسل"],
                               kind: page { AdminSmsView() }))
            t.append(AdminTool(id: "access.registration", area: .team, group: access,
                               title: L10n.t("التسجيل والمنع", "Sign-up and blocking"),
                               subtitle: L10n.t("السماح بالتسجيل · الأرقام الممنوعة من التسجيل",
                                                "Allow sign-ups · numbers blocked from signing up"),
                               icon: "person.crop.circle.badge.checkmark", tint: DS.Color.palm,
                               keywords: ["تسجيل", "شروط", "حظر", "محظور", "منع", "ممنوع"],
                               kind: page { AdminRegistrationBansView() }))
            t.append(AdminTool(id: "access.devices", area: .team, group: access,
                               title: L10n.t("الأجهزة ووصول الإشعارات", "Devices and notification reach"),
                               subtitle: L10n.t("الأجهزة المرتبطة، وصول الإشعارات، عدد الأجهزة لكل عضو",
                                                "Linked devices, notification reach, devices per member"),
                               icon: "iphone.gen3", tint: DS.Color.primary,
                               keywords: ["أجهزة", "إشعارات", "رموز", "وصول", "فصل", "تجربة", "تسجيل الأجهزة", "إشعار تجريبي"],
                               kind: page { AdminPushHealthView() }))
        }

        // ٦ التطبيق — صفحة القسم هي الإعدادات نفسها (`AdminAppAreaPage`، المفاتيح في مكانها)؛ هذه الصفوف للبحث الشامل
        // (تفتح الصفحة أو قائمتها). «كل الإعدادات في صفحة واحدة» حُذفت — الصفحة نفسها صارت كل الإعدادات
        if authVM.canViewSystemSettings {
            let settings = L10n.t("التطبيق", "App")
            // صفحة واحدة لكل إعدادات التطبيق (الأقسام الظاهرة، الصيانة، حدّ التعديلات، النظام) — المفاتيح في مكانها
            t.append(AdminTool(id: "app.sections", area: .app, group: settings,
                               title: L10n.t("إعدادات التطبيق", "App settings"),
                               subtitle: L10n.t("الأقسام الظاهرة · وضع الصيانة · حدّ التعديلات · النظام",
                                                "Visible sections · Maintenance · Self-edit limit · System"),
                               icon: "switch.2", tint: DS.Color.primary,
                               keywords: ["لغة", "ميزات", "ديوانيات", "مشاريع", "استطلاعات", "أخبار", "اعتماد",
                                          "الأقسام الظاهرة للأعضاء", "عداد", "تعديل", "حد", "حدّ التعديلات الذاتية",
                                          "صيانة", "تشغيل", "وضع الصيانة", "النظام", "معلومات", "إعادة التعيين", "افتراضي", "استعادة"],
                               kind: page { AdminAppAreaPage() }))
            t.append(AdminTool(id: "app.categories", area: .app, group: settings,
                               title: L10n.t("تصنيفات الأخبار والمكتبة", "News & library categories"),
                               subtitle: L10n.t("الاسم والأيقونة واللون، والإخفاء والترتيب", "Name, icon, colour, hide and order"),
                               icon: "tag.fill", tint: DS.Color.accent,
                               keywords: ["تصنيفات", "قوائم"],
                               kind: page { CategoriesManagerView() }))
            // «أسماء العوائل» (من «العائلة») + «أسماء الفروع» في صفحة واحدة
            t.append(AdminTool(id: "app.names", area: .app, group: settings,
                               title: L10n.t("أسماء العوائل والفروع", "Family and branch names"),
                               subtitle: L10n.t("يختار منها العضو عائلته، وأسماء قائمة الفروع", "Members pick their family; branch list names"),
                               icon: "person.2.crop.square.stack.fill", tint: DS.Color.accent,
                               keywords: ["عوائل", "عائلة", "فروع", "قوائم"],
                               kind: page { AdminFamilyNamesView() }))
            t.append(AdminTool(id: "app.forceUpdate", area: .app, group: settings,
                               title: L10n.t("فرض التحديث", "Force update"),
                               subtitle: L10n.t("أقل إصدار مسموح للآيفون والأندرويد", "Minimum allowed version for iPhone and Android"),
                               icon: "arrow.down.app.fill", tint: DS.Color.primary,
                               keywords: ["تحديث", "إجباري", "إصدار"],
                               kind: page { AdminForceUpdateView() }))
        }
        return t
    }
}

// MARK: - التوجيه

/// صفحة القسم — «الوارد» صفحة الطلبات نفسها، والباقي بطاقات أدواته. كل ما يُفتح منها يتبع القسم (`adminArea`)
struct AdminAreaView: View {
    let area: AdminArea

    var body: some View {
        page.adminArea(area)
    }

    private var page: AnyView {
        switch area {
        case .inbox:     return AnyView(AdminAllRequestsView())
        case .family:    return AnyView(AdminMembersPage())
        case .metrics:   return AnyView(AdminMetricsAreaView())
        case .team:      return AnyView(AdminTeamAreaView())
        case .app:       return AnyView(AdminAppAreaPage())
        case .occasions: return AnyView(AdminOccasionsPage())
        }
    }
}

/// بطاقات أدوات القسم مجمّعة بعنوان كل مجموعة
struct AdminToolCards: View {
    let tools: [AdminTool]
    var hints: [String: String] = [:]
    /// تلميحات تحذير (بلون التحذير)
    var warnings: Set<String> = []
    /// وصف الصف يظهر في البحث فقط (صفوف الأقسام تكتفي بالعنوان — الوصف يكرر عنوان الصفحة)
    var showsSubtitle: Bool = false

    private var groups: [(title: String, tools: [AdminTool])] {
        var order: [String] = []
        var map: [String: [AdminTool]] = [:]
        for tool in tools {
            if map[tool.group] == nil { order.append(tool.group) }
            map[tool.group, default: []].append(tool)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        ForEach(groups, id: \.title) { group in
            VStack(alignment: .leading, spacing: 0) {
                AdminCardHeader(title: group.title)
                ForEach(Array(group.tools.enumerated()), id: \.element.id) { index, tool in
                    if index > 0 { AdminRowDivider() }
                    AdminToolRow(tool: tool, hint: hints[tool.id], warn: warnings.contains(tool.id), showsSubtitle: showsSubtitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .adminCard()
        }
    }
}

/// صفّ أداة واحد — يفتح صفحتها (أو ينفّذ إجراءها)
struct AdminToolRow: View {
    let tool: AdminTool
    var hint: String? = nil
    var warn: Bool = false
    var showsSubtitle: Bool = true

    var body: some View {
        switch tool.kind {
        case .page(let make):
            // اسم القسم على زر «رجوع» الصفحة الداخلية (AdminPageKit)، وقسمها في قائمة العنوان (من البحث أيضاً)
            NavigationLink { AdminLazyPage(make: make).adminBackTitle(tool.area.title).adminArea(tool.area) } label: { label }
                .buttonStyle(.plain)
        case .action(let run):
            Button(action: run) { label }
                .buttonStyle(.plain)
        }
    }

    private var label: some View {
        AdminListRow(icon: tool.icon, tint: tool.tint, title: tool.title, subtitle: showsSubtitle ? tool.subtitle : nil) {
            if let hint {
                Text(hint)
                    .dsFont(.caption)
                    .monospacedDigit()
                    .foregroundColor(warn ? DS.Color.warning : DS.Color.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

// MARK: - «صلاحياتي» (سطر «اليوم» للمراقب والمشرف)

/// «صلاحياتي» (كان «نطاقي») — ما يقدر عليه دورك وما لا يقدر (البطاقة تصعد فوق الرأس). تُفتح من سطر «صلاحياتي» في
/// «اليوم» للمراقب والمشرف (بيته الوحيد؛ للمالك والمدير «دورك» مميّز في فريق الإدارة ← صلاحيات الأدوار)
struct AdminMyScopeView: View {
    let guide: RoleGuide
    @Environment(\.adminBackTitle) private var opener

    var body: some View {
        AdminPage(header: AdminPageHeader(back: opener ?? L10n.t("اليوم", "Today"),
                                          title: L10n.t("صلاحياتي · \(guide.title)", "My permissions · \(guide.title)"),
                                          subtitle: guide.mandate,
                                          glyph: guide.icon),
                  lead: AnyView(AdminRoleGuideCard(guide: guide, showsTitle: false)),
                  content: AnyView(EmptyView()))
    }
}

struct AdminRoleGuideCard: View {
    let guide: RoleGuide
    var showsTitle: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if showsTitle {
                HStack(spacing: DS.Spacing.md) {
                    AdminIconSquare(symbol: guide.icon, tint: guide.color)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(guide.title)
                            .dsFont(.headline)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(guide.mandate)
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                AdminRowDivider()
            }
            ForEach(guide.can, id: \.self) { line($0, allowed: true) }
            ForEach(guide.cannot, id: \.self) { line($0, allowed: false) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private func line(_ text: String, allowed: Bool) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .dsGlyph(DS.Glyph.md)
                .foregroundColor(allowed ? DS.Color.success : DS.Color.textTertiary)
                .padding(.top, DS.Spacing.xxs)
                .accessibilityHidden(true)
            Text(text)
                .dsFont(.subtitle)
                .foregroundColor(allowed ? DS.Color.textPrimary : DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(allowed ? text : L10n.t("غير مسموح: \(text)", "Can't: \(text)"))
    }
}

// MARK: - البحث الشامل

/// بحث في اللوحة: الأدوات والإعدادات بأسمائها، والأعضاء بالاسم أو الرقم، والطلبات (يفتح «الوارد» بالبحث)
struct AdminSearchView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @State private var query = ""
    /// ورقة العضو (نفس ورقة «العائلة») على نتائج البحث
    @State private var sheet: AdminMemberSheetContext?

    private var q: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var tools: [AdminTool] {
        guard !q.isEmpty else { return [] }
        let needle = ArabicTextNormalizer.normalizeForSearch(q)
        return AdminToolCatalog.tools(authVM: authVM, adminRequestVM: adminRequestVM).filter { tool in
            ([tool.title, tool.subtitle, tool.place ?? tool.area.title] + tool.keywords)
                .contains { ArabicTextNormalizer.normalizeForSearch($0).contains(needle) }
        }
    }

    private var members: [FamilyMember] {
        guard authVM.canEditMembers, q.count >= 2 else { return [] }
        let needle = ArabicTextNormalizer.normalizeForSearch(q)
        let digits = q.filter(\.isNumber)
        return Array(memberVM.allMembers.filter { m in
            ArabicTextNormalizer.normalizeForSearch(m.fullName).contains(needle)
                || (digits.count >= 3 && (m.phoneNumber ?? "").contains(digits))
        }.prefix(20))
    }

    var body: some View {
        AdminHubPage {
            AdminBandHeader(title: L10n.t("بحث", "Search"),
                            subtitle: L10n.t("عضو، طلب، أو إعداد", "A member, a request or a setting")) {
                EmptyView()
            } accessory: {
                DSSearchField(text: $query, placeholder: L10n.t("بحث بالاسم أو الرقم أو الأداة", "Name, number or tool"))
                    .padding(.top, DS.Spacing.md)
            }
        } content: {
            if q.isEmpty {
                DSNoteCard(L10n.t("اكتب اسم عضو أو رقمه، أو اسم أداة مثل «الأجهزة» أو «وضع الصيانة».",
                                  "Type a member's name or number, or a tool like “Devices” or “Maintenance mode”."),
                           icon: "magnifyingglass")
            } else {
                if adminRequestVM.approvalsWorkflowOn || authVM.canModerate {
                    VStack(alignment: .leading, spacing: 0) {
                        NavigationLink { AdminLazyPage { AnyView(AdminAllRequestsView(initialSearch: q).adminArea(.inbox)) } } label: {
                            AdminListRow(icon: "tray.full.fill", tint: DS.Color.primary,
                                         title: L10n.t("ابحث في الوارد عن «\(q)»", "Search the inbox for “\(q)”"))
                        }
                        .buttonStyle(.plain)
                    }
                    .adminCard()
                }
                if !tools.isEmpty {
                    AdminToolCards(tools: tools.map {
                        AdminTool(id: $0.id, area: $0.area, group: L10n.t("الأدوات", "Tools"), title: $0.title,
                                  subtitle: "\($0.place ?? $0.area.title) · \($0.subtitle)", icon: $0.icon, tint: $0.tint,
                                  keywords: $0.keywords, kind: $0.kind)
                    }, showsSubtitle: true)
                }
                if !members.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        AdminCardHeader(title: L10n.t("الأعضاء", "Members"), badge: members.count, badgeTint: DS.Color.palm)
                        let ids = members.map(\.id)
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, m in
                            if index > 0 { AdminRowDivider() }
                            Button { sheet = AdminMemberSheetContext(ids: ids, start: index) } label: {
                                AdminListRow(icon: m.isDeceased == true ? "person.fill.xmark" : "person.fill",
                                             tint: DS.Color.palm, title: m.displayFullName,
                                             subtitle: m.phoneNumber.map { KuwaitPhone.display($0) })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .adminCard()
                }
                if tools.isEmpty && members.isEmpty {
                    DSEmptyView(L10n.t("لا نتائج", "No results"),
                                message: L10n.t("جرّب كلمة أخرى", "Try another word"), style: .card)
                }
            }
        }
        .dsTallBox(item: $sheet) { context in
            AdminMemberSheet(ids: context.ids, start: context.start)
        }
    }
}

extension Notification.Name {
    /// يفتح تبويب الشجرة على «شجرة النساء» (من «العائلة» في لوحة الإدارة)
    static let openWomenTree = Notification.Name("openWomenTree")
}
