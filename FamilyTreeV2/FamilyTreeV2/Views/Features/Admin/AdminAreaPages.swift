import SwiftUI

// MARK: - صفحات الأقسام الثمانية (إعادة تصميم لوحة الإدارة — طلب المالك ٢٠٢٦-١٠-٢٠)
//
// كل قسم = رأس كحلي («‹ اليوم»، العنوان، الوصف) + بطاقات صفوف تفتح الصفحات الموجودة كما هي (لا منطق جديد).
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
}

@MainActor
enum AdminToolCatalog {

    /// كل أدوات اللوحة المتاحة لهذا الدور — بالترتيب داخل كل قسم
    static func tools(authVM: AuthViewModel, adminRequestVM: AdminRequestViewModel) -> [AdminTool] {
        var t: [AdminTool] = []
        let isAdmin = authVM.isAdmin
        let role = authVM.currentUser?.role
        func page(_ make: @escaping () -> some View) -> AdminTool.Kind { .page { AnyView(make()) } }

        // ١ الوارد
        t.append(AdminTool(id: "inbox.requests", area: .inbox, group: L10n.t("الوارد", "Inbox"),
                           title: L10n.t("الطلبات", "Requests"),
                           subtitle: L10n.t("كل ما ينتظر قراراً — بالنوع والمهلة", "Everything awaiting a decision"),
                           icon: "tray.full.fill", tint: DS.Color.primary,
                           keywords: ["طلبات", "مراجعة", "انضمام", "موافقة"],
                           kind: page { AdminAllRequestsView() }))
        t.append(AdminTool(id: "inbox.messages", area: .inbox, group: L10n.t("الوارد", "Inbox"),
                           title: L10n.t("رسائل الأعضاء", "Member messages"),
                           subtitle: L10n.t("رسائل «تواصل مع الإدارة»", "“Contact admin” messages"),
                           icon: "bubble.left.and.bubble.right.fill", tint: DS.Color.sea,
                           keywords: ["رسائل", "تواصل"],
                           kind: page { AdminAllRequestsView(startsWithMessages: true) }))
        if adminRequestVM.approvalsWorkflowOn && (isAdmin || role == .monitor) {
            t.append(AdminTool(id: "inbox.report", area: .inbox, group: L10n.t("الوارد", "Inbox"),
                               title: L10n.t("تقرير الموافقات", "Approvals report"),
                               subtitle: L10n.t("المراحل والأداء والتصعيدات", "Stages, performance, escalations"),
                               icon: "chart.bar.xaxis", tint: DS.Color.warning,
                               kind: page { ApprovalsReportView() }))
        }
        if authVM.canViewSystemSettings {
            t.append(AdminTool(id: "inbox.settings", area: .inbox, group: L10n.t("الوارد", "Inbox"),
                               title: L10n.t("إعدادات المسار", "Approval path settings"),
                               subtitle: L10n.t("مسار الموافقات، المهلة، المسار السريع، الردود الجاهزة",
                                                "Approvals path, SLA, fast track, ready replies"),
                               icon: "gearshape.fill", tint: DS.Color.slate,
                               keywords: ["مسار", "مهلة", "ردود"],
                               kind: page { AdminAppSettingsView(scope: .approvals) }))
        }

        // ٢ العائلة
        if authVM.canEditMembers {
            let registry = L10n.t("السجل والحسابات", "Registry & accounts")
            t.append(AdminTool(id: "family.directory", area: .family, group: registry,
                               title: L10n.t("سجل الأعضاء", "Member registry"),
                               subtitle: L10n.t("تصفّح الفروع، أو ابحث بالاسم أو الرقم", "Browse branches or search"),
                               icon: "person.3.sequence.fill", tint: DS.Color.palm,
                               keywords: ["أعضاء", "سجل", "فروع", "عضو"],
                               kind: page { AdminMembersManagementView(initialTab: .directory) }))
            t.append(AdminTool(id: "family.accounts", area: .family, group: registry,
                               title: L10n.t("الحسابات والاستخدام", "Accounts & usage"),
                               subtitle: L10n.t("محطة التفعيل: أكمل نواقص كل عضو", "Activation station"),
                               icon: "person.crop.circle.badge.checkmark", tint: DS.Color.palm,
                               keywords: ["تفعيل", "حسابات"],
                               kind: page { AdminMembersManagementView(initialTab: .accounts) }))
            t.append(AdminTool(id: "family.quality", area: .family, group: registry,
                               title: L10n.t("جودة البيانات", "Data quality"),
                               subtitle: L10n.t("الأفراد والمفعّلة والنواقص", "Members, active, gaps"),
                               icon: "checklist", tint: DS.Color.palm,
                               keywords: ["نواقص", "بيانات"],
                               kind: page { AdminMembersManagementView(initialTab: .overview) }))
            if authVM.canRegisterMembers {
                t.append(AdminTool(id: "family.register", area: .family, group: registry,
                                   title: L10n.t("تسجيل عضو", "Register member"),
                                   subtitle: L10n.t("عضو جديد بصورته ورقمه", "A new member with photo and phone"),
                                   icon: "person.badge.plus", tint: DS.Color.palm,
                                   keywords: ["تسجيل", "إضافة"],
                                   kind: page { AdminRegisterMemberView() }))
            }
            t.append(AdminTool(id: "family.families", area: .family, group: registry,
                               title: L10n.t("أسماء العوائل", "Family names"),
                               subtitle: L10n.t("يختار منها العضو عائلته", "Members pick their family from these"),
                               icon: "person.2.crop.square.stack.fill", tint: DS.Color.accent,
                               keywords: ["عوائل", "عائلة"],
                               kind: page { AdminMembersManagementView(initialTab: .families) }))
            let tree = L10n.t("الشجرة", "Tree")
            t.append(AdminTool(id: "family.health", area: .family, group: tree,
                               title: L10n.t("صحة الشجرة", "Tree health"),
                               subtitle: L10n.t("بلا أب، بلا اسم، رابط مكسور، رقم مكرر", "Unlinked, unnamed, broken, duplicate"),
                               icon: "stethoscope", tint: DS.Color.warning,
                               keywords: ["صحة", "يتيم", "مكرر"],
                               kind: page { AdminTreeHealthView() }))
            t.append(AdminTool(id: "family.women", area: .family, group: tree,
                               title: L10n.t("شجرة النساء", "Women's tree"),
                               subtitle: L10n.t("تُدار من تبويب الشجرة", "Managed from the Tree tab"),
                               icon: "person.2.fill", tint: DS.Color.female,
                               keywords: ["نساء", "بنات"],
                               kind: .action {
                                   TreeTabContainer.openWomenOnAppear = true
                                   NotificationCenter.default.post(name: .openWomenTree, object: nil)
                               }))
        }

        // ٣ المناسبات
        let occasions = L10n.t("المناسبات", "Occasions")
        if isAdmin {
            t.append(AdminTool(id: "occasions.deaths", area: .occasions, group: occasions,
                               title: L10n.t("الوفيات والإعلان", "Deaths & obituaries"),
                               subtitle: L10n.t("وفيات آخر 30 يوماً — أعلن بنص جاهز", "Last 30 days — announce with ready text"),
                               icon: NewsTypeHelper.icon(for: "وفاة"), tint: DS.Color.slate,
                               keywords: ["وفاة", "إعلان", "عزاء"],
                               kind: page { DeathAnnouncementsPage() }))
        }
        if authVM.canModerate {
            t.append(AdminTool(id: "occasions.memorial", area: .occasions, group: occasions,
                               title: L10n.t("ذكرى الراحلين", "Memorials"),
                               subtitle: L10n.t("الذكرى القريبة وتكميل التاريخ", "Upcoming anniversaries and dates"),
                               icon: "moon.stars.fill", tint: DS.Color.sadu,
                               keywords: ["ذكرى", "راحلين"],
                               kind: page { DeceasedMemorialView() }))
            t.append(AdminTool(id: "occasions.posts", area: .occasions, group: occasions,
                               title: L10n.t("منشورات المناسبات", "Occasion posts"),
                               subtitle: L10n.t("تهنئة، إعلان عزاء، مشاركة عزاء", "Congrats and condolences"),
                               icon: "photo.on.rectangle.angled", tint: DS.Color.accent,
                               keywords: ["منشور", "تهنئة", "مناسبة"],
                               kind: page { OccasionComposerView() }))
        }

        // ٤ الإعلانات
        if authVM.canSendNotifications {
            let send = L10n.t("إرسال للأعضاء", "Send to members")
            t.append(AdminTool(id: "ann.notify", area: .announcements, group: send,
                               title: L10n.t("إشعار للأعضاء", "Notify members"),
                               subtitle: L10n.t("للجميع أو لدولة أو لأعضاء — الآن أو بجدولة", "Everyone, a country or people — now or later"),
                               icon: "bell.badge.fill", tint: DS.Color.sea,
                               keywords: ["إشعار", "إرسال"],
                               kind: page { AdminMessagingHubView() }))
            t.append(AdminTool(id: "ann.update", area: .announcements, group: send,
                               title: L10n.t("رسالة تحديث التطبيق", "App update message"),
                               subtitle: L10n.t("ما الجديد في «المستجدات» + إشعار", "What's new in Updates + a notification"),
                               icon: "megaphone.fill", tint: DS.Color.sea,
                               keywords: ["تحديث", "إصدار"],
                               kind: page { AdminMessagingHubView(startsWithUpdate: true) }))
            t.append(AdminTool(id: "ann.scheduled", area: .announcements, group: send,
                               title: L10n.t("المجدولة", "Scheduled"),
                               subtitle: L10n.t("الإشعارات التي تنتظر وقتها — من شريطها في «إشعار للأعضاء»",
                                                "Waiting notifications — from their bar in Notify"),
                               icon: "clock.badge.checkmark.fill", tint: DS.Color.sea,
                               keywords: ["مجدول"],
                               kind: page { AdminMessagingHubView() }))
            t.append(AdminTool(id: "ann.push", area: .announcements, group: L10n.t("هل يصلهم؟", "Does it reach them?"),
                               title: L10n.t("وصول الإشعارات", "Notification reach"),
                               subtitle: L10n.t("رموز الأجهزة، التجربة، والتنظيف", "Device tokens, test and cleanup"),
                               icon: "bell.and.waves.left.and.right.fill", tint: DS.Color.info,
                               keywords: ["رموز", "أجهزة", "تجربة"],
                               kind: page { AdminPushHealthView() }))
        }

        // ٥ المؤشرات
        let numbers = L10n.t("أرقام وسجل", "Numbers & history")
        if isAdmin {
            t.append(AdminTool(id: "metrics.analytics", area: .metrics, group: numbers,
                               title: L10n.t("الإحصائيات", "Statistics"),
                               subtitle: L10n.t("الأعمار والأدوار والنمو والأخبار", "Ages, roles, growth, news"),
                               icon: "chart.bar.xaxis", tint: DS.Color.palm,
                               keywords: ["إحصائيات", "أعمار"],
                               kind: page { AdminAnalyticsView() }))
            t.append(AdminTool(id: "metrics.live", area: .metrics, group: numbers,
                               title: L10n.t("النشاط الآن", "Live activity"),
                               subtitle: L10n.t("الدخول وآخر نشاط — التطبيق والموقع", "Sign-ins and activity — app and web"),
                               icon: "bolt.fill", tint: DS.Color.palm,
                               keywords: ["نشط", "الآن"],
                               kind: page { AdminActiveMembersView() }))
        }
        if isAdmin || role == .monitor {
            t.append(AdminTool(id: "metrics.activity", area: .metrics, group: numbers,
                               title: L10n.t("سجل النشاط", "Activity log"),
                               subtitle: L10n.t("كل تعديل: من وماذا ومتى", "Every change: who, what, when"),
                               icon: "clock.arrow.circlepath", tint: DS.Color.primary,
                               keywords: ["سجل", "تعديلات"],
                               kind: page { AdminActivityLogView() }))
        }
        if adminRequestVM.approvalsWorkflowOn && (isAdmin || role == .monitor) {
            t.append(AdminTool(id: "metrics.approvals", area: .metrics, group: numbers,
                               title: L10n.t("تقرير الموافقات", "Approvals report"),
                               subtitle: L10n.t("المراحل والأداء", "Stages and performance"),
                               icon: "chart.bar.doc.horizontal", tint: DS.Color.warning,
                               kind: page { ApprovalsReportView() }))
        }
        if isAdmin {
            t.append(AdminTool(id: "metrics.pdf", area: .metrics, group: numbers,
                               title: L10n.t("تقارير PDF", "PDF reports"),
                               subtitle: L10n.t("تصفية الأعضاء وتصدير ملف للطباعة", "Filter members and export"),
                               icon: "doc.text.fill", tint: DS.Color.accent,
                               keywords: ["تقرير", "طباعة", "pdf"],
                               kind: page { AdminReportsView() }))
        }

        // ٦ الفريق
        if isAdmin {
            let team = L10n.t("الفريق", "Team")
            t.append(AdminTool(id: "team.members", area: .team, group: team,
                               title: L10n.t("فريق الإدارة بالأدوار", "Admin team by role"),
                               subtitle: authVM.canManageRoles ? L10n.t("إضافة وتغيير الدور وإزالته", "Add, change and remove roles")
                                                               : L10n.t("عرض — الأدوار يمنحها المالك", "View — the owner grants roles"),
                               icon: "person.3.fill", tint: DS.Color.primary,
                               keywords: ["فريق", "مدير", "مراقب", "مشرف"],
                               kind: page { AdminModeratorsView() }))
            t.append(AdminTool(id: "team.roles", area: .team, group: team,
                               title: L10n.t("ما يقدر عليه كل دور", "What each role can do"),
                               subtitle: L10n.t("يقدر / ما يقدر لكل دور", "Can / can't for every role"),
                               icon: "list.bullet.rectangle.portrait.fill", tint: DS.Color.primary,
                               keywords: ["صلاحيات", "أدوار"],
                               kind: page { AdminRolesGuideView() }))
            if let guide = authVM.currentUser.flatMap({ RoleGuide.forRole($0.role) }) {
                t.append(AdminTool(id: "team.scope", area: .team, group: team,
                                   title: L10n.t("نطاقي", "My scope"),
                                   subtitle: guide.mandate,
                                   icon: guide.icon, tint: guide.color,
                                   kind: page { AdminMyScopeView(guide: guide) }))
            }
        }

        // ٧ الدخول والأمان
        if authVM.canViewSystemSettings {
            let access = L10n.t("من يدخل وكيف", "Who signs in and how")
            t.append(AdminTool(id: "access.sms", area: .access, group: access,
                               title: L10n.t("رسائل الدخول · KWT SMS", "Sign-in messages · KWT SMS"),
                               subtitle: L10n.t("الرصيد، المرسل، الحدود والتنبيهات", "Balance, sender, limits, alerts"),
                               icon: "ellipsis.message.fill", tint: DS.Hub.securityFill,
                               keywords: ["رسائل", "sms", "رصيد", "kwt"],
                               kind: page { AdminSmsView() }))
            t.append(AdminTool(id: "access.devices", area: .access, group: access,
                               title: L10n.t("الأجهزة", "Devices"),
                               subtitle: authVM.canManageDevices ? L10n.t("أجهزة كل عضو وفصلها", "Each member's devices and sign-out")
                                                                 : L10n.t("عرض — الفصل للمالك", "View — the owner signs out"),
                               icon: "iphone.gen3", tint: DS.Color.primary,
                               keywords: ["أجهزة", "فصل"],
                               kind: page { AdminDevicesView() }))
            t.append(AdminTool(id: "access.banned", area: .access, group: access,
                               title: L10n.t("الأرقام المحظورة", "Banned numbers"),
                               subtitle: L10n.t("منع التسجيل برقم", "Block sign-up by number"),
                               icon: "phone.down.fill", tint: DS.Color.error,
                               keywords: ["حظر", "محظور"],
                               kind: page { AdminBannedPhonesView() }))
            t.append(AdminTool(id: "access.registration", area: .access, group: access,
                               title: L10n.t("قواعد التسجيل", "Sign-up rules"),
                               subtitle: L10n.t("السماح بالتسجيل وحدّ الأجهزة", "Allow sign-ups and device limit"),
                               icon: "person.crop.circle.badge.checkmark", tint: DS.Color.palm,
                               keywords: ["تسجيل", "أجهزة"],
                               kind: page { AdminAppSettingsView(scope: .registration) }))
        }

        // ٨ التطبيق
        if authVM.canViewSystemSettings {
            let content = L10n.t("المحتوى والميزات", "Content & features")
            let ops = L10n.t("التشغيل", "Operations")
            t.append(AdminTool(id: "app.features", area: .app, group: content,
                               title: L10n.t("الميزات واللغة", "Features & language"),
                               subtitle: L10n.t("لغة التطبيق، الديوانيات، النساء، المشاريع، الاستطلاعات", "Language and sections"),
                               icon: "switch.2", tint: DS.Color.primary,
                               keywords: ["لغة", "ميزات"],
                               kind: page { AdminAppSettingsView(scope: .featuresLanguage) }))
            t.append(AdminTool(id: "app.news", area: .app, group: content,
                               title: L10n.t("الأخبار والتصنيفات", "News & categories"),
                               subtitle: L10n.t("مراجعة الأخبار وتصنيفات الأخبار والمكتبة", "News review and categories"),
                               icon: "newspaper.fill", tint: DS.Color.accent,
                               keywords: ["أخبار", "تصنيفات"],
                               kind: page { AdminAppSettingsView(scope: .newsCategories) }))
            t.append(AdminTool(id: "app.branches", area: .app, group: content,
                               title: L10n.t("أسماء الفروع", "Branch names"),
                               subtitle: L10n.t("أسماء تظهر في قائمة الفروع", "Names shown in the branch list"),
                               icon: "arrow.triangle.branch", tint: DS.Color.palm,
                               keywords: ["فروع"],
                               kind: page { AdminAppSettingsView(scope: .branches) }))
            t.append(AdminTool(id: "app.cooldown", area: .app, group: content,
                               title: L10n.t("عداد التعديل", "Edit counter"),
                               subtitle: L10n.t("٣ تعديلات ثم بموافقة — إيقاف أو تصفير", "3 edits then approval — pause or reset"),
                               icon: "timer", tint: DS.Color.info,
                               keywords: ["عداد", "تعديل"],
                               kind: page { AdminAppSettingsView(scope: .cooldown) }))
            t.append(AdminTool(id: "app.forceUpdate", area: .app, group: ops,
                               title: L10n.t("التحديث الإجباري", "Force update"),
                               subtitle: L10n.t("أقل رقم بناء للآيفون والأندرويد", "Minimum build for iPhone and Android"),
                               icon: "arrow.down.app.fill", tint: DS.Color.primary,
                               keywords: ["تحديث", "إجباري"],
                               kind: page { AdminForceUpdateView() }))
            t.append(AdminTool(id: "app.maintenance", area: .app, group: ops,
                               title: L10n.t("الصيانة", "Maintenance"),
                               subtitle: L10n.t("إيقاف مؤقت أو قراءة فقط", "Pause or read-only"),
                               icon: "wrench.and.screwdriver.fill", tint: DS.Color.warning,
                               keywords: ["صيانة"],
                               kind: page { AdminAppSettingsView(scope: .maintenance) }))
            t.append(AdminTool(id: "app.info", area: .app, group: ops,
                               title: L10n.t("معلومات النظام", "System info"),
                               subtitle: L10n.t("الإصدار وآخر تحديث للإعدادات", "Version and last settings change"),
                               icon: "info.circle.fill", tint: DS.Color.slate,
                               kind: page { AdminAppSettingsView(scope: .systemInfo) }))
            t.append(AdminTool(id: "app.reset", area: .app, group: ops,
                               title: L10n.t("إعادة التعيين", "Reset"),
                               subtitle: L10n.t("إرجاع الإعدادات للافتراضي", "Restore default settings"),
                               icon: "arrow.counterclockwise", tint: DS.Color.error,
                               kind: page { AdminAppSettingsView(scope: .reset) }))
            t.append(AdminTool(id: "app.all", area: .app, group: ops,
                               title: L10n.t("كل الإعدادات في صفحة واحدة", "All settings on one page"),
                               subtitle: L10n.t("التطبيق · الأعضاء · النظام", "App · Members · System"),
                               icon: "slider.horizontal.3", tint: DS.Color.slate,
                               kind: page { AdminAppSettingsView() }))
        }
        return t
    }
}

// MARK: - التوجيه

/// صفحة القسم — «الوارد» صفحة الطلبات نفسها، والباقي بطاقات أدواته
struct AdminAreaView: View {
    let area: AdminArea

    var body: some View {
        switch area {
        case .inbox:         AdminAllRequestsView()
        case .family:        AdminFamilyAreaView()
        case .metrics:       AdminMetricsAreaView()
        case .access:        AdminToolsAreaView(area: .access, readOnlyBadge: true)
        case .app:           AdminToolsAreaView(area: .app, readOnlyBadge: true)
        default:             AdminToolsAreaView(area: area)
        }
    }
}

/// بطاقات أدوات القسم مجمّعة بعنوان كل مجموعة
struct AdminToolCards: View {
    let tools: [AdminTool]
    var hints: [String: String] = [:]
    /// تلميحات تحذير (بلون التحذير)
    var warnings: Set<String> = []

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
                    AdminToolRow(tool: tool, hint: hints[tool.id], warn: warnings.contains(tool.id))
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

    var body: some View {
        switch tool.kind {
        case .page(let make):
            NavigationLink { AdminLazyPage(make: make) } label: { label }
                .buttonStyle(.plain)
        case .action(let run):
            Button(action: run) { label }
                .buttonStyle(.plain)
        }
    }

    private var label: some View {
        AdminListRow(icon: tool.icon, tint: tool.tint, title: tool.title, subtitle: tool.subtitle) {
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

/// قسم بلا بطاقات خاصة: الرأس + بطاقات أدواته
struct AdminToolsAreaView: View {
    let area: AdminArea
    var readOnlyBadge: Bool = false
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @ObservedObject private var sms = SmsBalanceStore.shared

    var body: some View {
        let tools = AdminToolCatalog.tools(authVM: authVM, adminRequestVM: adminRequestVM).filter { $0.area == area }
        AdminHubPage {
            AdminBandHeader(title: area.title, subtitle: area.subtitle,
                            badge: readOnlyBadge && !authVM.canManageSettings
                                ? L10n.t("للقراءة — يعدّلها المالك", "Read-only — the owner edits") : nil)
        } content: {
            AdminAreaTop(area: area)
            if tools.isEmpty {
                DSEmptyView(L10n.t("لا أدوات لدورك هنا", "No tools for your role here"), style: .card)
            } else {
                AdminToolCards(tools: tools, hints: hints, warnings: warnings)
            }
        }
        .task {
            if area == .access { await sms.refresh() }
            if area == .announcements { await notificationVM.fetchScheduledNotifications() }
            if area == .occasions && memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
        }
    }

    private var hints: [String: String] {
        var h: [String: String] = [:]
        if let balance = sms.status?.balance {
            h["access.sms"] = L10n.t("\(SmsBalanceText.points(balance)) نقطة", "\(SmsBalanceText.points(balance)) pts")
        }
        if !authVM.bannedPhones.isEmpty { h["access.banned"] = "\(authVM.bannedPhones.count)" }
        let scheduled = notificationVM.scheduledNotifications.count
        if scheduled > 0 { h["ann.scheduled"] = "\(scheduled)" }
        if area == .occasions {
            let memorial = DeceasedMemorialBoard(memberVM.allMembers)
            if memorial.withinWeek > 0 {
                h["occasions.memorial"] = L10n.t("\(memorial.withinWeek) هالأسبوع", "\(memorial.withinWeek) this week")
            }
            let recent = memberVM.allMembers.filter {
                $0.isDeceased == true && $0.role != .pending && DeathRecency.isRecent($0.deathDate)
            }.count
            if recent > 0 { h["occasions.deaths"] = L10n.t("\(recent) حديثة", "\(recent) recent") }
        }
        if area == .team {
            let staff = memberVM.allMembers.filter {
                [.owner, .admin, .monitor, .supervisor].contains($0.role) && $0.isDeceased != true && $0.status != .frozen
            }.count
            h["team.members"] = "\(staff)"
        }
        return h
    }

    private var warnings: Set<String> {
        return sms.needsTopUp ? ["access.sms"] : []
    }
}

// MARK: - العائلة

struct AdminFamilyAreaView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @State private var usage: AppUsageStats? = AppUsageStats.cached

    var body: some View {
        let tools = AdminToolCatalog.tools(authVM: authVM, adminRequestVM: adminRequestVM).filter { $0.area == .family }
        let stats = memberStats
        AdminHubPage {
            AdminBandHeader(title: AdminArea.family.title, subtitle: AdminArea.family.subtitle) {
                EmptyView()
            } accessory: {
                HStack(spacing: DS.Spacing.sm) {
                    AdminKPITile(value: "\(stats.total)", label: L10n.t("الأفراد", "Members"), icon: "person.3")
                    AdminKPITile(value: "\(stats.active)", label: L10n.t("مفعّلة", "Active"), icon: "checkmark.seal",
                                 tint: DS.Hub.kpiMine)
                    AdminKPITile(value: "\(stats.pending)", label: L10n.t("بانتظار", "Pending"), icon: "clock",
                                 tint: DS.Hub.kpiLate)
                }
                .padding(.top, DS.Spacing.md)
            }
        } content: {
            AdminAreaQuickActions(area: .family)
            AdminToolCards(tools: tools)
            if let usage { usageCard(usage) }
        }
        .task {
            if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
            usage = await AppUsageStats.fetch() ?? usage
        }
    }

    private var memberStats: (total: Int, active: Int, pending: Int) {
        var total = 0, active = 0, pending = 0
        for m in memberVM.allMembers where m.role != .pending && m.isDeceased != true && m.isCountable {
            total += 1
            if m.status == .active { active += 1 } else if m.status == nil || m.status == .pending { pending += 1 }
        }
        return (total, active, pending)
    }

    /// «استخدام التطبيق»: فعّال · بلا جهاز · ما دخل · دون رقم — كل فئة تفتح قائمتها
    private func usageCard(_ u: AppUsageStats) -> some View {
        let rows: [(AppUsageCategory, String, Int, Color)] = [
            (.active, L10n.t("فعّال (رقم وجهاز)", "Active (phone + device)"), u.active + u.idle, DS.Color.success),
            (.loginNoDevice, L10n.t("دخل بلا جهاز", "Signed in, no device"), u.loginNoDevice, DS.Color.info),
            (.neverLogged, L10n.t("ما دخل أبداً", "Never signed in"), u.neverLogged, DS.Color.warning),
            (.noPhone, L10n.t("دون رقم", "No phone"), u.noPhone, DS.Color.textTertiary)
        ]
        let total = rows.reduce(0) { $0 + $1.2 }
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminCardHeader(title: L10n.t("استخدام التطبيق", "App usage"))
            DSDistributionBar(segments: rows.map { .init(id: $0.0.rawValue, value: $0.2, tint: $0.3) },
                              height: DS.Spacing.md)
            Text(L10n.t("من \(total) حيّاً", "of \(total) living"))
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { AdminRowDivider() }
                    NavigationLink { AdminLazyPage { AnyView(AppUsageMembersView(category: row.0)) } } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Circle().fill(row.3).frame(width: DS.Icon.legendDot, height: DS.Icon.legendDot)
                            Text(row.1)
                                .dsFont(.subtitle)
                                .foregroundColor(DS.Color.textPrimary)
                            Spacer(minLength: DS.Spacing.sm)
                            Text("\(row.2)")
                                .dsFont(.chip)
                                .monospacedDigit()
                                .foregroundColor(row.3.dsReadableGlyph)
                            DSChevron()
                        }
                        .frame(minHeight: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }
}

// MARK: - المؤشرات

struct AdminMetricsAreaView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    /// إناث شجرة النساء — تبدأ من كاشها إن فُتحت قبلاً
    @State private var women: (total: Int, alive: Int, deceased: Int)? = Self.womenCounts(WomenStore.cache)

    var body: some View {
        let tools = AdminToolCatalog.tools(authVM: authVM, adminRequestVM: adminRequestVM).filter { $0.area == .metrics }
        AdminHubPage {
            AdminBandHeader(title: AdminArea.metrics.title, subtitle: AdminArea.metrics.subtitle)
        } content: {
            // «نبض العائلة» انتقل من «اليوم» إلى هنا (طلب المالك ٢٠٢٦-١٠-٢٠ «الأقسام فوق + قائمة وحدة»)
            AdminPulseTiles()
            familyMembersCard
            AdminToolCards(tools: tools, hints: hints)
        }
        .task {
            if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
            if let rows = try? await WomenStore.fetch(), let counts = Self.womenCounts(rows) { women = counts }
        }
    }

    private static func womenCounts(_ rows: [FamilyMember]) -> (total: Int, alive: Int, deceased: Int)? {
        guard !rows.isEmpty else { return nil }
        let females = rows.filter { $0.isFemale }
        let deceased = females.filter { $0.isDeceased == true }.count
        return (females.count, females.count - deceased, deceased)
    }

    private var hints: [String: String] {
        let unread = notificationVM.unreadActivityLogCount
        return unread > 0 ? ["metrics.activity": L10n.t("\(unread) جديد", "\(unread) new")] : [:]
    }

    /// «أفراد العائلة» (بطاقة اللوحة القديمة): الرجال والنساء — الأحياء والمتوفون. أعدادها المختصرة في «اليوم»
    private var familyMembersCard: some View {
        var total = 0, alive = 0, deceased = 0
        for m in memberVM.allMembers where m.role != .pending {
            total += 1
            if m.isDeceased == true { deceased += 1 } else { alive += 1 }
        }
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminCardHeader(title: L10n.t("أفراد العائلة", "Family members"))
            HStack(spacing: DS.Spacing.sm) {
                GenderRingPanel(title: L10n.t("الرجال", "Men"), dot: DS.Color.male,
                                total: total, alive: alive, deceased: deceased, loading: memberVM.allMembers.isEmpty)
                GenderRingPanel(title: L10n.t("النساء", "Women"), dot: DS.Color.female,
                                total: women?.total ?? 0, alive: women?.alive ?? 0, deceased: women?.deceased ?? 0,
                                loading: women == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }
}

/// حلقة جنس في «أفراد العائلة»: نسبة الأحياء حلقةً بلون المعنى (`DSRing`) والعدد في وسطها
struct GenderRingPanel: View {
    let title: String
    let dot: Color
    let total: Int
    let alive: Int
    let deceased: Int
    let loading: Bool

    private var share: Double { total > 0 && !loading ? Double(alive) / Double(total) : 0 }

    var body: some View {
        let ink = dot.dsReadableGlyph
        HStack(spacing: DS.Spacing.sm) {
            DSRing(progress: share, tint: ink, lineWidth: DS.Spacing.xs + 1, size: DS.Icon.sizeLg) {
                Text(loading ? "—" : "\(total)")
                    .dsFont(.headline)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, DS.Spacing.xsm)
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.rowTitleCompact)
                    .foregroundColor(ink)
                    .lineLimit(1)
                line(L10n.t("أحياء", "Alive"), alive)
                line(L10n.t("متوفون", "Deceased"), deceased)
            }
            Spacer(minLength: 0)
        }
        .dsRowBox()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("\(title): \(total)، أحياء \(alive)، متوفون \(deceased)",
                                   "\(title): \(total), alive \(alive), deceased \(deceased)"))
    }

    private func line(_ label: String, _ value: Int) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(label)
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textSecondary)
            Text(loading ? "—" : "\(value)")
                .dsFont(.chip)
                .monospacedDigit()
                .foregroundColor(DS.Color.textPrimary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

// MARK: - أعلى الأقسام: ما انتقل من «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠ «الأقسام فوق + قائمة وحدة»)
//
// «اليوم» صار: الرأس ← أعداد الأعضاء ← الأقسام ← تنبيهات ← «يحتاج قرارك». فما كان تحتها انتقل لأعلى قسمه بلا
// ضياع: كل إجراء سريع أعلى قسمه، «اليوم في العائلة» أعلى «المناسبات»، و«نبض العائلة» أعلى «المؤشرات».
// الصلاحيات كما كانت على «اليوم» حرفياً.

/// ما يسبق بطاقات الأدوات في الأقسام العامة (المناسبات، الإعلانات…)
struct AdminAreaTop: View {
    let area: AdminArea

    var body: some View {
        AdminAreaQuickActions(area: area)
        if area == .occasions {
            AdminFamilyTodayCard()
        }
    }
}

/// الإجراءات السريعة لقسم: أزرار كبسولة بعرض الصفحة — إشعار للأعضاء ← الإعلانات؛ منشور مناسبة وإعلان وفاة ←
/// المناسبات؛ تسجيل عضو وبحث عضو ← العائلة
struct AdminAreaQuickActions: View {
    let area: AdminArea
    @EnvironmentObject var authVM: AuthViewModel

    private struct Action: Identifiable {
        let id: String
        let icon: String
        let title: String
        let page: () -> AnyView
    }

    private var actions: [Action] {
        var list: [Action] = []
        switch area {
        case .announcements:
            if authVM.canSendNotifications {
                list.append(Action(id: "notify", icon: "megaphone", title: L10n.t("إشعار للأعضاء", "Notify members")) {
                    AnyView(AdminMessagingHubView())
                })
            }
        case .occasions:
            list.append(Action(id: "occasion", icon: "photo.on.rectangle", title: L10n.t("منشور مناسبة", "Occasion post")) {
                AnyView(OccasionComposerView())
            })
            if authVM.isAdmin {
                list.append(Action(id: "death", icon: NewsTypeHelper.icon(for: "وفاة"),
                                   title: L10n.t("إعلان وفاة", "Obituary")) {
                    AnyView(DeathAnnouncementsPage())
                })
            }
        case .family:
            if authVM.canRegisterMembers {
                list.append(Action(id: "register", icon: "person.badge.plus", title: L10n.t("تسجيل عضو", "Register")) {
                    AnyView(AdminRegisterMemberView())
                })
            }
            if authVM.canEditMembers {
                list.append(Action(id: "find", icon: "magnifyingglass", title: L10n.t("بحث عضو", "Find member")) {
                    AnyView(AdminMembersManagementView(initialTab: .directory))
                })
            }
        default:
            break
        }
        return list
    }

    var body: some View {
        let list = actions
        if !list.isEmpty {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(list) { action in
                    NavigationLink { AdminLazyPage(make: action.page) } label: {
                        AdminPillLabel(title: action.title, icon: action.icon, style: .navy,
                                       height: DS.Hub.pillHeightCard, fullWidth: true)
                    }
                    .buttonStyle(DSPressStyle())
                    .accessibilityLabel(action.title)
                }
            }
        }
    }
}

/// «اليوم في العائلة» (كانت في «اليوم»): الذكرى القريبة، ووفيات آخر ٣٠ يوماً ومن أُضيف هذا الأسبوع (المالك والمدير
/// والمراقب). لا تُرسم بلا صفوف
struct AdminFamilyTodayCard: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel

    private var rows: [AdminFamilyTodayRow] {
        let all = memberVM.allMembers
        guard !all.isEmpty else { return [] }
        var rows: [AdminFamilyTodayRow] = []
        if let next = DeceasedMemorialBoard(all).upcoming.first {
            rows.append(AdminFamilyTodayRow(
                id: "memorial", icon: "moon.stars.fill", tint: DS.Color.sadu,
                title: L10n.t("ذكرى \(next.member.shortFullName)", "\(next.member.shortFullName)'s anniversary"),
                value: DeceasedMemorial.whenLabel(next.anniversary.daysUntil, arabic: L10n.isArabic),
                target: .memorial))
        }
        guard authVM.isAdmin || authVM.currentUser?.role == .monitor else { return rows }
        let deaths = all.filter { $0.isDeceased == true && $0.role != .pending && DeathRecency.isRecent($0.deathDate) }.count
        if deaths > 0 {
            rows.append(AdminFamilyTodayRow(
                id: "deaths", icon: NewsTypeHelper.icon(for: "وفاة"), tint: DS.Color.slate,
                title: L10n.t("وفيات آخر 30 يوماً", "Deaths in the last 30 days"),
                value: "\(deaths)", target: authVM.isAdmin ? .deaths : .memorial))
        }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let joined = all.filter { m in
            m.isDeceased != true && m.isCountable && (ApprovalWorkflow.date(m.createdAt).map { $0 >= weekAgo } ?? false)
        }.count
        if joined > 0 {
            rows.append(AdminFamilyTodayRow(
                id: "joined", icon: "person.crop.circle.badge.plus", tint: DS.Color.palm,
                title: L10n.t("أُضيفوا للشجرة هذا الأسبوع", "Added to the tree this week"),
                value: "\(joined)", target: .directory))
        }
        return rows
    }

    var body: some View {
        let rows = self.rows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                AdminCardHeader(title: L10n.t("اليوم في العائلة", "Today in the family"))
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { AdminRowDivider() }
                    NavigationLink { AdminLazyPage { Self.page(row.target) } } label: {
                        AdminListRow(icon: row.icon, tint: row.tint, title: row.title) {
                            Text(verbatim: row.value)
                                .dsFont(.chip)
                                .monospacedDigit()
                                .foregroundColor(DS.Color.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .adminCard()
        }
    }

    private static func page(_ target: AdminFamilyTodayRow.Target) -> AnyView {
        switch target {
        case .memorial:  return AnyView(DeceasedMemorialView())
        case .deaths:    return AnyView(DeathAnnouncementsPage())
        case .directory: return AnyView(AdminMembersManagementView(initialTab: .directory))
        }
    }
}

/// مربّع في «نبض العائلة»
struct AdminPulseTile: Identifiable {
    let id: String
    let icon: String
    let label: String
    let value: String
    var unit: String? = nil
    var valueTint: Color = DS.Color.textPrimary
    let note: String
    var meter: Double? = nil
    var meterTint: Color = DS.Color.primaryFill
    let page: () -> AnyView
}

/// «نبض العائلة» (كانت في «اليوم»): النشطون الآن (المالك والمدير)، الحسابات الفعّالة، رصيد رسائل الدخول (المالك
/// والمدير)، والمنجز هذا الأسبوع (مع مسار الموافقات) — كل مربّع يفتح صفحته. يجلب أرقامه عند فتح «المؤشرات»
struct AdminPulseTiles: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @ObservedObject private var sms = SmsBalanceStore.shared
    @Environment(\.dsLandscape) private var landscape
    @State private var activeNow: Int? = nil
    @State private var usage: AppUsageStats? = AppUsageStats.cached
    @State private var weekly: (executed: Int, rejected: Int)? = nil

    private var tiles: [AdminPulseTile] {
        var tiles: [AdminPulseTile] = []
        if authVM.isAdmin, let now = activeNow {
            tiles.append(AdminPulseTile(id: "active", icon: "bolt.fill", label: L10n.t("النشطون الآن", "Active now"),
                                        value: "\(now)", note: L10n.t("يستخدمون التطبيق الآن", "Using the app now")) {
                AnyView(AdminActiveMembersView())
            })
        }
        if authVM.isAdmin || authVM.currentUser?.role == .monitor, let u = usage {
            let living = u.active + u.idle + u.loginNoDevice + u.neverLogged + u.noPhone
            let activeAccounts = u.active + u.idle
            let share = living > 0 ? Double(activeAccounts) / Double(living) : 0
            tiles.append(AdminPulseTile(id: "accounts", icon: "iphone", label: L10n.t("حسابات فعّالة", "Active accounts"),
                                        value: "\(Int((share * 100).rounded()))%",
                                        note: L10n.t("\(activeAccounts) من \(living) حيّاً", "\(activeAccounts) of \(living) living"),
                                        meter: share) {
                AnyView(AppUsageMembersView(category: .active))
            })
        }
        if authVM.canViewSystemSettings, let balance = sms.status?.balance {
            let level = sms.level
            tiles.append(AdminPulseTile(id: "sms", icon: "ellipsis.message", label: L10n.t("رسائل الدخول", "Sign-in SMS"),
                                        value: SmsBalanceText.points(balance), unit: L10n.t("نقطة", "pts"),
                                        valueTint: level == .good ? DS.Color.textPrimary : level.tint,
                                        note: SmsBalanceText.enough(balance)) {
                AnyView(AdminSmsView(backTitle: AdminArea.metrics.title))
            })
        }
        if let w = weekly {
            tiles.append(AdminPulseTile(id: "done", icon: "checkmark.circle", label: L10n.t("منجز هذا الأسبوع", "Done this week"),
                                        value: "\(w.executed + w.rejected)",
                                        note: L10n.t("نُفّذ \(w.executed) · رُفض \(w.rejected)",
                                                     "\(w.executed) done · \(w.rejected) rejected")) {
                AnyView(ApprovalsReportView())
            })
        }
        return tiles
    }

    var body: some View {
        let tiles = self.tiles
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if !tiles.isEmpty {
                AdminSectionLabel(title: L10n.t("نبض العائلة", "Family pulse"))
                LazyVGrid(columns: AdminGrid.columns(landscape: landscape), spacing: AdminGrid.spacing) {
                    ForEach(tiles) { tile in
                        NavigationLink { AdminLazyPage(make: tile.page) } label: { AdminPulseTileView(tile: tile) }
                            .buttonStyle(DSPressStyle())
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        let isAdmin = authVM.isAdmin
        let isSystem = authVM.canViewSystemSettings
        let flowOn = adminRequestVM.approvalsWorkflowOn
        await withTaskGroup(of: Void.self) { group in
            if isAdmin {
                group.addTask { @MainActor in activeNow = await AdminTodayFetch.activeNowCount() }
            }
            // فشل الجلب يُبقي آخر قيمة محفوظة
            group.addTask { @MainActor in if let u = await AppUsageStats.fetch() { usage = u } }
            if isSystem {
                group.addTask { @MainActor in await SmsBalanceStore.shared.refresh() }
            }
            if flowOn {
                group.addTask { @MainActor in weekly = await AdminTodayFetch.weeklyDone() }
            }
        }
    }
}

struct AdminPulseTileView: View {
    let tile: AdminPulseTile

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(dsSymbol: tile.icon).dsGlyph(DS.Glyph.sm)
                Text(tile.label).lineLimit(1).minimumScaleFactor(0.8)
            }
            .dsFont(.caption)
            .foregroundColor(DS.Color.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Text(verbatim: tile.value)
                    .dsFont(.hubPulse)
                    .monospacedDigit()
                    .foregroundColor(tile.valueTint.dsReadableGlyph)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit = tile.unit {
                    Text(unit)
                        .dsFont(.caption)
                        .foregroundColor(tile.valueTint.dsReadableGlyph)
                }
            }
            Text(tile.note)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let meter = tile.meter {
                AdminMeter(progress: meter, tint: tile.meterTint)
                    .padding(.top, DS.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, minHeight: DS.Hub.tileMinHeight, alignment: .topLeading)
        .dsCard(padding: DS.Spacing.md, radius: DS.Hub.tileRadius)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - الفريق: الأدوار ونطاقي

/// «ما يقدر عليه كل دور» — من `RoleGuides` (المصدر الواحد لنصوص الأدوار)
struct AdminRolesGuideView: View {
    var body: some View {
        AdminHubPage {
            AdminBandHeader(backTitle: AdminArea.team.title,
                            title: L10n.t("ما يقدر عليه كل دور", "What each role can do"),
                            subtitle: L10n.t("الدور = مجال عمل، لا درجة صلاحية", "A role is a domain, not a rank"))
        } content: {
            ForEach(RoleGuide.all) { guide in
                AdminRoleGuideCard(guide: guide)
            }
        }
    }
}

/// «نطاقي» — ما يقدر عليه دورك وما لا يقدر
struct AdminMyScopeView: View {
    let guide: RoleGuide

    var body: some View {
        AdminHubPage {
            AdminBandHeader(title: L10n.t("نطاقي · \(guide.title)", "My scope · \(guide.title)"),
                            subtitle: guide.mandate)
        } content: {
            AdminRoleGuideCard(guide: guide, showsTitle: false)
        }
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

    private var q: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var tools: [AdminTool] {
        guard !q.isEmpty else { return [] }
        let needle = ArabicTextNormalizer.normalizeForSearch(q)
        return AdminToolCatalog.tools(authVM: authVM, adminRequestVM: adminRequestVM).filter { tool in
            ([tool.title, tool.subtitle, tool.area.title] + tool.keywords)
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
                DSNoteCard(L10n.t("اكتب اسم عضو أو رقمه، أو اسم أداة مثل «الأجهزة» أو «الصيانة».",
                                  "Type a member's name or number, or a tool like “Devices”."),
                           icon: "magnifyingglass")
            } else {
                if adminRequestVM.approvalsWorkflowOn || authVM.canModerate {
                    VStack(alignment: .leading, spacing: 0) {
                        NavigationLink { AdminLazyPage { AnyView(AdminAllRequestsView(initialSearch: q)) } } label: {
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
                                  subtitle: "\($0.area.title) · \($0.subtitle)", icon: $0.icon, tint: $0.tint,
                                  keywords: $0.keywords, kind: $0.kind)
                    })
                }
                if !members.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        AdminCardHeader(title: L10n.t("الأعضاء", "Members"), badge: members.count, badgeTint: DS.Color.palm)
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, m in
                            if index > 0 { AdminRowDivider() }
                            NavigationLink { AdminLazyPage { AnyView(AdminMemberDetailSheet(member: m)) } } label: {
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
    }
}

extension Notification.Name {
    /// يفتح تبويب الشجرة على «شجرة النساء» (من «العائلة» في لوحة الإدارة)
    static let openWomenTree = Notification.Name("openWomenTree")
}
