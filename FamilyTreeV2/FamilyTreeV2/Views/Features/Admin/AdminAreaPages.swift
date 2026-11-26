import SwiftUI

// MARK: - صفحات الأقسام الستة (إعادة تصميم لوحة الإدارة — طلب المالك ٢٠٢٦-١٠-٢٠، «٦ أقسام»)
//
// كل قسم = رأس كحلي («‹ اليوم»، العنوان قائمة الأقسام، الوصف) + بطاقات صفوف تفتح الصفحات الموجودة كما هي (لا منطق
// جديد). «المناسبات والإعلانات» صفحتها الخاصة (`AdminOccasionsPage`: إنشاء · القادم · المنشور)، و«الفريق
// والأمان» تجمع «الفريق» و«من يدخل وكيف».
// فهرس الأدوات `AdminToolCatalog` هو المصدر الواحد: الأقسام والبحث الشامل وجدول الانتقال (REACHABILITY.md)
// يقرؤون منه — كل ميزة لها صفّ واحد في قسم واحد، والصلاحيات كما كانت تماماً.
// U19 (٢٠٢٦-١١-٢٦): المعرّف ← القسم والبيت والكلمات في `AdminCatalogTool` (AdminCatalogLogic.swift، مفحوص بـ
// tests/admin-redesign/U19)، والبيت ← الصفحة في `AdminToolCatalog.homePage(_:)`.

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

    /// كل أدوات اللوحة المتاحة لهذا الدور — بالترتيب داخل كل قسم. المعرّف وقسمه وبيته وكلماته من `AdminCatalogTool`
    /// (AdminCatalogLogic.swift، يُفحص بلا محاكي)؛ هنا ما يظهر (العنوان والوصف والرمز) ومن يراه
    static func tools(authVM: AuthViewModel, adminRequestVM: AdminRequestViewModel) -> [AdminTool] {
        var t: [AdminTool] = []
        let isAdmin = authVM.isAdmin
        func add(_ tool: AdminCatalogTool, group: String, title: String, subtitle: String, icon: String, tint: Color,
                 searchOnly: Bool = false, place: String? = nil) {
            let home = tool.home
            t.append(AdminTool(id: tool.rawValue, area: tool.area, group: group, title: title, subtitle: subtitle,
                               icon: icon, tint: tint, keywords: tool.keywords, kind: .page { homePage(home) },
                               searchOnly: searchOnly, place: place))
        }

        // ١ الوارد — جذر القسم «الوارد» (`AdminAllRequestsView`) وفيه أبواب «المنجز» و«طلبات الخصوصية» و«بانتظار المراجعة»؛
        // «رسائل الأعضاء» صفحة وحدها (spec C.4)، و⚙︎ «إعدادات مسار الموافقات»
        let inbox = AdminArea.inbox.title
        add(.inboxRequests, group: inbox, title: L10n.t("الطلبات", "Requests"),
            subtitle: L10n.t("ما ينتظر قراراً، والمنجز وطلبات الخصوصية", "Awaiting a decision, done and privacy requests"),
            icon: "tray.full.fill", tint: DS.Color.primary)
        // «رسائل الأعضاء» — للمالك والمدير (جدول «مين يشوف وش» من السيرفر)
        if authVM.adminSees(.inboxMessages) {
            add(.inboxMessages, group: inbox, title: AdminInboxView.title,
                subtitle: L10n.t("رسائل «تواصل مع الإدارة»", "“Contact admin” messages"),
                icon: "bubble.left.and.bubble.right.fill", tint: DS.Color.sea)
        }
        // المالك يعدّل والمدير يقرأ (الصفحة نفسها تقفل مفاتيحها لغير المالك — `canManageSettings`)
        if authVM.adminSees(.inboxApprovalSettings) {
            add(.inboxSettings, group: inbox, title: L10n.t("إعدادات مسار الموافقات", "Approval path settings"),
                subtitle: L10n.t("مسار الموافقات، المهلة، الاعتماد المباشر، نماذج الردود",
                                 "Approvals path, SLA, direct approval, reply templates"),
                icon: "gearshape.fill", tint: DS.Color.slate)
        }

        // ٢ العائلة — جذر القسم (`AdminMembersPage`) وفيه «يحتاج مراجعتك» و«نساء العائلة»؛ «＋» و«⋯ ← تقرير PDF» في رأسه
        if authVM.canEditMembers {
            let family = AdminArea.family.title
            add(.familyMembers, group: family, title: L10n.t("الأعضاء", "Members"),
                subtitle: L10n.t("بحث وتصفية، و«يحتاج مراجعتك»، وورقة لكل عضو",
                                 "Search and filters, “Needs your review”, one sheet per member"),
                icon: "person.3.sequence.fill", tint: DS.Color.palm)
            // نفس شرط «＋» في رأس «العائلة»: الصلاحية × القسم «يعدّل» في جدول السيرفر (F2)
            if authVM.canRegisterMembers && authVM.adminCanEdit(.family) {
                add(.familyRegister, group: family, title: L10n.t("تسجيل عضو جديد", "Register a new member"),
                    subtitle: L10n.t("عضو جديد بصورته ورقمه", "A new member with photo and phone"),
                    icon: "person.badge.plus", tint: DS.Color.palm)
            }
            if isAdmin {
                add(.familyExport, group: family, title: L10n.t("تقرير PDF بالأعضاء", "Members PDF report"),
                    subtitle: L10n.t("زرّ ⋯ في «العائلة» — بالتصفية الحالية", "The ⋯ button in Family — with the current filter"),
                    icon: "doc.text.fill", tint: DS.Color.accent)
            }
        }

        // ٣ المناسبات والإعلانات — جذر القسم (`AdminOccasionsPage`)؛ الكلمات القديمة تجد بيتها الجديد
        if authVM.canModerate || authVM.canSendNotifications {
            let occasions = AdminArea.occasions.title
            add(.occasionsCreate, group: occasions, title: occasions,
                subtitle: authVM.canSendNotifications
                    ? L10n.t("إعلان · إعلان وفاة · بطاقة تهنئة أو تعزية · إعلان تحديث التطبيق",
                             "Announcement · obituary · greeting or condolence card · app update notice")
                    : L10n.t("بطاقة تهنئة أو تعزية", "Greeting or condolence card"),
                icon: "plus.circle.fill", tint: DS.Color.sadu)
        }

        // ٤ الإحصاءات (كان «المؤشرات») — جذر القسم هو «إحصاءات العائلة» نفسها، و«تقرير الموافقات» صفحة منه (spec C.12)
        let stats = AdminArea.metrics.title
        if authVM.adminSees(.metricsFamily) {
            add(.metricsFamily, group: stats, title: L10n.t("إحصاءات العائلة", "Family statistics"),
                subtitle: L10n.t("العائلة والراحلون، في التطبيق، النمو والأعمار والأدوار",
                                 "Family and departed, in the app, growth, ages and roles"),
                icon: "chart.bar.fill", tint: DS.Color.palm)
        }
        // تقرير الموافقات — بيته الواحد صفحته (بابها آخر «الإحصاءات»)
        if adminRequestVM.approvalsWorkflowOn && authVM.adminSees(.metricsApprovals) {
            add(.metricsApprovals, group: stats, title: L10n.t("تقرير الموافقات", "Approvals report"),
                subtitle: L10n.t("المنجز، وقت كل مرحلة، حسب النوع، أداء الإدارة", "Done, time per stage, by type, team"),
                icon: "chart.bar.doc.horizontal", tint: DS.Color.warning)
        }

        // «إشعارات الإدارة» — بيتها جرس «اليوم». صفّ للبحث الشامل فقط؛ الكلمات القديمة («سجل التعديلات») تجد بيتها
        if authVM.canModerate {
            add(.todayNotices, group: inbox, title: L10n.t("إشعارات الإدارة", "Admin notifications"),
                subtitle: L10n.t("الطلبات ونشاط الفريق (سجل التعديلات) وتنبيهات النظام",
                                 "Requests, team activity (change log) and system alerts"),
                icon: "bell.badge.fill", tint: DS.Color.primary, searchOnly: true,
                place: L10n.t("اليوم ← الجرس", "Today ← bell"))
        }

        // ٥ الفريق والأمان (`AdminTeamAreaView`): فريق الإدارة · رسائل رمز الدخول · التسجيل والمنع · الأجهزة والإشعارات ·
        // الاستخدام. المالكان كل شي؛ المدير للاطلاع: فريق الإدارة و«الاستخدام» (الجدول من السيرفر — الباقي للمالك)
        let team = AdminArea.team.title
        if authVM.adminSees(.teamMembers) {
            add(.teamMembers, group: team, title: L10n.t("فريق الإدارة", "Admin team"),
                subtitle: authVM.canManageRoles
                    ? L10n.t("الأعضاء حسب الدور، وصلاحيات الأدوار — إضافة وتغيير",
                             "Members by role and role permissions — add and change")
                    : L10n.t("الأعضاء حسب الدور، وصلاحيات الأدوار", "Members by role and role permissions"),
                icon: "person.3.fill", tint: DS.Color.primary)
        }
        if authVM.adminSees(.teamSms) {
            add(.accessSms, group: team, title: L10n.t("رسائل رمز الدخول (KWT SMS)", "Sign-in code messages (KWT SMS)"),
                subtitle: L10n.t("الرصيد، طلبات رمز الدخول، إعدادات الإرسال", "Balance, code requests, sending settings"),
                icon: "ellipsis.message.fill", tint: DS.Hub.securityFill)
        }
        if authVM.adminSees(.teamRegistration) {
            add(.accessRegistration, group: team, title: L10n.t("التسجيل والمنع", "Sign-up and blocking"),
                subtitle: L10n.t("السماح بالتسجيل · الأرقام الممنوعة من التسجيل",
                                 "Allow sign-ups · numbers blocked from signing up"),
                icon: "person.crop.circle.badge.checkmark", tint: DS.Color.palm)
        }
        // «الأجهزة والإشعارات» و«الاستخدام» بيتان (spec C.13، B.7) — كانا صفّاً واحداً للمالك
        if authVM.adminSees(.teamDevices) {
            add(.accessDevices, group: team, title: L10n.t("الأجهزة والإشعارات", "Devices and notifications"),
                subtitle: L10n.t("وصول الإشعارات، الأجهزة المرتبطة، إشعار تجريبي، عدد الأجهزة لكل عضو",
                                 "Notification reach, linked devices, test notification, devices per member"),
                icon: "iphone", tint: DS.Color.sea)
        }
        if authVM.adminSees(.teamUsage) {
            add(.accessUsage, group: team, title: L10n.t("الاستخدام", "Usage"),
                subtitle: L10n.t("المستخدمون الآن، النشطون واتجاههم، الجلسات وأكثر الشاشات — التطبيق والموقع",
                                 "Using now, active members and trend, sessions and top screens — app and web"),
                icon: "waveform.path.ecg", tint: DS.Color.palm)
        }

        // ٦ التطبيق — جذر القسم هو الإعدادات نفسها (`AdminAppAreaPage`)؛ القوائم وفرض التحديث والأخطاء صفحاتها. للمالك وحده
        if authVM.adminSees(.appSettings) {
            let app = AdminArea.app.title
            add(.appSections, group: app, title: L10n.t("إعدادات التطبيق", "App settings"),
                subtitle: L10n.t("الأقسام الظاهرة · وضع الصيانة · حدّ التعديلات · النظام",
                                 "Visible sections · Maintenance · Self-edit limit · System"),
                icon: "switch.2", tint: DS.Color.primary)
            add(.appCategories, group: app, title: L10n.t("تصنيفات الأخبار والمكتبة", "News & library categories"),
                subtitle: L10n.t("الاسم والأيقونة واللون، والإخفاء والترتيب", "Name, icon, colour, hide and order"),
                icon: "tag.fill", tint: DS.Color.accent)
            add(.appNames, group: app, title: L10n.t("أسماء العوائل والفروع", "Family and branch names"),
                subtitle: L10n.t("يختار منها العضو عائلته، وأسماء قائمة الفروع", "Members pick their family; branch list names"),
                icon: "person.2.crop.square.stack.fill", tint: DS.Color.accent)
            add(.appForceUpdate, group: app, title: L10n.t("فرض التحديث", "Force update"),
                subtitle: L10n.t("أقل إصدار مسموح للآيفون والأندرويد", "Minimum allowed version for iPhone and Android"),
                icon: "arrow.down.app.fill", tint: DS.Color.primary)
            add(.appErrors, group: app, title: AdminErrorsText.pageTitle,
                subtitle: L10n.t("ما يصل Sentry من الآيفون والأندرويد والموقع، ووين صار",
                                 "What reaches Sentry from iPhone, Android and web, and where"),
                icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
        }
        // قسم لا يظهر لدورك (جدول «مين يشوف وش» من السيرفر) لا تظهر أدواته في البحث أيضاً
        return t.filter { $0.area.isVisible(for: authVM) }
    }

    /// بيت الأداة — الصفحة التي تفتحها (spec B.7). المكان الواحد من المعرّف إلى الصفحة؛ يُبنى عند الفتح فقط
    /// (`AdminLazyPage`)، ومن يدفعها يمرّر قسمها واسم ما فُتحت منه (`AdminToolRow`)
    static func homePage(_ home: AdminCatalogHome) -> AnyView {
        switch home {
        case .inboxRoot:        return AnyView(AdminAllRequestsView())
        case .messagesPage:     return AnyView(AdminInboxView())
        case .approvalSettings: return AnyView(AdminAppSettingsView(scope: .approvals))
        case .familyRoot:       return AnyView(AdminMembersPage())
        case .registerMember:   return AnyView(AdminRegisterMemberView())
        case .memberReport:     return AnyView(AdminReportsView())
        case .occasionsRoot:    return AnyView(AdminOccasionsPage())
        case .statsRoot:        return AnyView(AdminMetricsAreaView())
        case .approvalsReport:  return AnyView(ApprovalsReportView())
        case .adminNotices:     return AnyView(AdminNotificationsPage())
        case .moderators:       return AnyView(AdminModeratorsView())
        case .sms:              return AnyView(AdminSmsView())
        case .registrationBans: return AnyView(AdminRegistrationBansView())
        case .usage:            return AnyView(AdminActiveMembersView())
        case .devices:          return AnyView(AdminPushHealthView())
        case .appRoot:          return AnyView(AdminAppAreaPage())
        case .categories:       return AnyView(CategoriesManagerView())
        case .familyNames:      return AnyView(AdminFamilyNamesView())
        case .forceUpdate:      return AnyView(AdminForceUpdateView())
        case .errors:           return AnyView(AdminErrorsPage())
        }
    }
}

extension AdminCatalogTool {
    /// قسم الأداة في التطبيق (`areaKey` واحد من الستة — يفحصه tests/admin-redesign/U19)
    var area: AdminArea { AdminArea(rawValue: areaKey) ?? .inbox }
}

// MARK: - التوجيه

/// صفحة القسم — «الوارد» صفحة الطلبات نفسها، والباقي بطاقات أدواته. كل ما يُفتح منها يتبع القسم (`adminArea`)
struct AdminAreaView: View {
    let area: AdminArea

    var body: some View {
        // قسم ليس لدورك (مسار قديم، رابط، إشعار): رسالة بدل الصفحة
        AdminAreaGate(area: area) { page }.adminArea(area)
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

/// أدوات مجمّعة بعنوان كل مجموعة: صفوف (نتائج البحث — عنوان المجموعة فوق بطاقة صفوفها، spec A.4–A.6)، أو مربّعات
/// بالمنتصف (طلب المالك ٢٠٢٦-١٠-٢٤ «الايقونات بالمنتصف مع المسميات»)
struct AdminToolCards: View {
    enum Style {
        /// عنوان فوق بطاقة صفوف (نتائج البحث)
        case rows
        /// عنوان صغير ثم شبكة مربّعات؛ `captions` = سطر الرقم الحيّ محجوز في كل مربّع (يصل الرقم بلا قفزة)
        case tiles(captions: Bool)
    }

    let tools: [AdminTool]
    var hints: [String: String] = [:]
    /// تلميحات تحذير (بلون التحذير) — في المربّعات شارة «!» على الأيقونة
    var warnings: Set<String> = []
    /// وصف الصف يظهر في البحث فقط (صفوف الأقسام تكتفي بالعنوان — الوصف يكرر عنوان الصفحة)
    var showsSubtitle: Bool = false
    var style: Style = .rows
    /// اسم ما فُتحت منه الصفحة على زرّ رجوعها («بحث») — nil = اسم قسم الأداة
    var backTitle: String? = nil
    /// عدد المجموعة في طرف عنوانها (نتائج البحث)
    var showsCount: Bool = false

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
            switch style {
            case .rows:
                VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
                    AdminSectionLabel(title: group.title,
                                      trailing: showsCount ? AdminNumberText.grouped(group.tools.count) : nil)
                    AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                        ForEach(group.tools) { tool in
                            AdminToolRow(tool: tool, hint: hints[tool.id], warn: warnings.contains(tool.id),
                                         showsSubtitle: showsSubtitle, backTitle: backTitle)
                        }
                    }
                }
            case .tiles(let captions):
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    AdminSectionLabel(title: group.title)
                    AdminTileGrid(count: group.tools.count) {
                        ForEach(Array(group.tools.enumerated()), id: \.element.id) { index, tool in
                            AdminToolTile(tool: tool, caption: hints[tool.id], warn: warnings.contains(tool.id),
                                          reservesCaption: captions, index: index)
                        }
                    }
                }
            }
        }
    }
}

/// صفّ أداة واحد (spec A.6) — يفتح بيتها خلف `AdminLazyPage` بقسمها واسم ما فُتحت منه، أو ينفّذ إجراءها.
/// الضغط تظليل لا تصغير (`AdminRowPressStyle`)
struct AdminToolRow: View {
    let tool: AdminTool
    var hint: String? = nil
    var warn: Bool = false
    var showsSubtitle: Bool = true
    /// زرّ رجوع الصفحة: اسم ما فُتحت منه — nil = اسم قسم الأداة (صفوف داخل صفحة القسم)
    var backTitle: String? = nil

    var body: some View {
        switch tool.kind {
        case .page(let make):
            // اسم ما فُتحت منه على زرّ «رجوع» الصفحة (AdminPageKit)، وقسمها في قائمة العنوان (الصفحة المدفوعة لا ترث البيئة)
            NavigationLink {
                AdminLazyPage(make: make).adminBackTitle(backTitle ?? tool.area.title).adminArea(tool.area)
            } label: { label }
            .buttonStyle(AdminRowPressStyle())
        case .action(let run):
            Button(action: run) { label }
                .buttonStyle(AdminRowPressStyle())
        }
    }

    private var label: some View {
        AdminListRow(icon: tool.icon, tint: tool.tint, title: tool.title, subtitle: showsSubtitle ? tool.subtitle : nil) {
            if let hint {
                Text(hint)
                    .dsFont(.subtitle)
                    .monospacedDigit()
                    .foregroundColor(warn ? DS.Color.warning.dsReadableGlyph : DS.Color.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

// MARK: - «صلاحياتي» (سطر «اليوم» للمراقب والمشرف)

/// «صلاحياتي» (كان «نطاقي») — ما يقدر عليه دورك وما لا يقدر (البطاقة تصعد فوق الرأس). تُفتح من بطاقة «صلاحياتي» في
/// «اليوم» للمراقب والمشرف (بيته الوحيد؛ للمالك والمدير «دورك» مميّز في فريق الإدارة ← صلاحيات الأدوار)
struct AdminMyScopeView: View {
    let guide: RoleGuide
    @Environment(\.adminBackTitle) private var opener

    var body: some View {
        AdminPage(header: AdminPageHeader(back: opener ?? AdminArea.homeTitle,
                                          title: L10n.t("الصلاحيات · \(guide.title)", "My permissions · \(guide.title)"),
                                          subtitle: guide.mandateForSelf,
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

// MARK: - البحث الشامل (spec C.16 — بالعُدّة الجديدة، والتخطيط والسلوك كما هما)

/// بحث في اللوحة: الأدوات والإعدادات بأسمائها، والأعضاء بالاسم أو الرقم، والطلبات (يفتح «الوارد» بالبحث).
/// النتائج: عنوان كل مجموعة فوق بطاقة صفوفها (spec A.4–A.6)؛ العضو يفتح ورقته، والأداة بيتها خلف `AdminLazyPage`
/// بقسمها و«‹ بحث». أدوات القسم المخفي لدورك لا تظهر (`AdminToolCatalog`)
struct AdminSearchView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @State private var query = ""
    /// ورقة العضو (نفس ورقة «العائلة») على نتائج البحث
    @State private var sheet: AdminMemberSheetContext?
    /// «النساء»: البحث في إناث شجرة النساء وحدهنّ — للإدارة (طلب المالك ٢٠٢٦-١٠-٢٥ «بحث عن الإناث بس بالإدارة»)
    @State private var womenOnly = false
    @State private var women: [FamilyMember] = WomenStore.cache
    @State private var womenLoading = false
    /// وصلت شجرة النساء مرة (من الكاش أو الجلب) — قبلها هيكل لا «لا نتائج»
    @State private var womenLoaded = !WomenStore.cache.isEmpty
    /// آخر جلب لشجرة النساء فشل (والكاش فارغ ← بطاقة الخطأ بإعادة المحاولة، لا «لا نتائج»)
    @State private var womenFailed = false
    @State private var selectedWoman: FamilyMember?

    /// عنوان الصفحة — وهو زرّ رجوع ما تفتحه
    static var title: String { L10n.t("بحث", "Search") }

    private var q: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var tools: [AdminTool] {
        guard !q.isEmpty else { return [] }
        // البحث الدقيق الواحد (`NameSearch`): كل كلمة بداية كلمة بالترتيب — في العنوان والوصف والمكان وكلمات الأداة
        return AdminToolCatalog.tools(authVM: authVM, adminRequestVM: adminRequestVM).filter { tool in
            let texts = [tool.title, tool.subtitle, tool.place ?? tool.area.title]
            guard let id = AdminCatalogTool(rawValue: tool.id) else {
                return NameSearch.matches(query: q, any: texts + tool.keywords)
            }
            return AdminCatalogLogic.matches(query: q, texts: texts, tool: id)
        }
    }

    private var members: [FamilyMember] {
        guard authVM.canEditMembers, q.count >= 2 else { return [] }
        // البحث الدقيق الواحد (`NameSearch`): كل كلمة بداية كلمة بالترتيب — الاسم الأول التام أولاً؛ والرقم أرقاماً فقط
        if NameSearch.isPhoneQuery(q) {
            return Array(memberVM.allMembers.filter { NameSearch.phoneMatches(query: q, phone: $0.phoneNumber) }.prefix(20))
        }
        return Array(NameSearch.filter(memberVM.allMembers, query: q) { m in
            m.familyName == nil ? m.fullName : m.fullName + " " + m.displayFullName
        }.prefix(20))
    }

    /// إناث شجرة النساء المطابقات (الإدارة ترى المخفيّات أيضاً)
    private var womenResults: [FamilyMember] {
        guard womenOnly, !q.isEmpty else { return [] }
        return Array(NameSearch.filter(women.filter(\.isFemale), query: q, fromFirstName: true) { w in   // من الاسم الأول — «م» = مريم لا «… موسى»
            w.fullName.isEmpty ? w.firstName : w.fullName
        }.prefix(30))
    }

    /// «الوارد» يبحث في الطلبات — لمن يرى القسم
    private var searchesInbox: Bool {
        (adminRequestVM.approvalsWorkflowOn || authVM.canModerate) && AdminArea.inbox.isVisible(for: authVM)
    }

    private func loadWomen() async {
        guard !womenLoading else { return }
        womenLoading = true
        defer { womenLoading = false }
        do {
            let fresh = try await WomenStore.fetch()
            if !fresh.isEmpty { women = fresh }
            womenLoaded = true
            womenFailed = false
        } catch is CancellationError {
            return
        } catch {
            womenFailed = true
            Log.error("[AdminSearchView] women load failed: \(error.localizedDescription)")
        }
    }

    // MARK: الأجزاء

    /// «الكل» / «النساء» تحت الرأس — فلتر بُعد واحد بشرائح الإدارة (spec A.9 الاستعمال ١)، للإدارة وحدها
    private var scopePicker: some View {
        DSFilterChips(options: [
            DSFilterOption(id: false, title: L10n.t("الكل", "All"), icon: "magnifyingglass"),
            DSFilterOption(id: true, title: L10n.t("النساء", "Women"), icon: "figure.stand.dress")
        ], selection: $womenOnly, style: .admin)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var womenSection: some View {
        if q.isEmpty {
            DSNoteCard(L10n.t("اكتب اسمها — البحث في إناث شجرة النساء فقط.",
                              "Type her name — searches only the women in the women's tree."),
                       icon: "figure.stand.dress")
        } else if women.isEmpty && (womenLoading || (!womenLoaded && !womenFailed)) {
            AdminPageStateCard(.loading(L10n.t("جارٍ تحميل شجرة النساء…", "Loading the women's tree…")))
        } else if women.isEmpty && womenFailed {
            AdminPageStateCard(.error(L10n.t("تعذّر تحميل شجرة النساء", "Couldn't load the women's tree"),
                                      retry: { Task { await loadWomen() } }))
        } else if womenResults.isEmpty {
            DSEmptyView(L10n.t("لا نتائج", "No results"),
                        message: L10n.t("جرّب كلمة أخرى", "Try another word"), style: .card)
        } else {
            let found = womenResults
            VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
                AdminSectionLabel(title: L10n.t("النساء", "Women"), trailing: AdminNumberText.grouped(found.count))
                AdminRowsCard(dividerInset: AdminSearchPersonRow.dividerInset) {
                    ForEach(found) { w in
                        Button { selectedWoman = w } label: {
                            AdminSearchPersonRow(member: w, name: w.fullName.isEmpty ? w.firstName : w.fullName,
                                                 tint: w.isDeceased == true ? DS.Color.deceased : DS.Color.female,
                                                 line: w.isDeceased == true ? L10n.t("متوفاة", "Deceased")
                                                     : (w.isHiddenFromTree ? L10n.t("مخفية من الشجرة", "Hidden from the tree") : nil))
                        }
                        .buttonStyle(AdminRowPressStyle())
                        .accessibilityHint(L10n.t("يفتح التفاصيل", "Opens the details"))
                    }
                }
            }
        }
    }

    /// النتائج: «ابحث في الوارد» ثم الأدوات ثم الأعضاء — كل قائمة تُحسب مرة لكل رسم
    @ViewBuilder private func results(tools: [AdminTool], members: [FamilyMember]) -> some View {
        if searchesInbox {
            AdminRowsCard(dividerInset: AdminRowDivider.iconInset) {
                NavigationLink {
                    AdminLazyPage { [q] in
                        AnyView(AdminAllRequestsView(initialSearch: q).adminBackTitle(Self.title).adminArea(.inbox))
                    }
                } label: {
                    AdminListRow(icon: "tray.full.fill", tint: DS.Color.primary,
                                 title: L10n.t("ابحث في الوارد عن «\(q)»", "Search the inbox for “\(q)”"))
                }
                .buttonStyle(AdminRowPressStyle())
            }
        }
        if !tools.isEmpty {
            AdminToolCards(tools: tools.map {
                AdminTool(id: $0.id, area: $0.area, group: L10n.t("الأدوات", "Tools"), title: $0.title,
                          subtitle: "\($0.place ?? $0.area.title) · \($0.subtitle)", icon: $0.icon, tint: $0.tint,
                          keywords: $0.keywords, kind: $0.kind)
            }, showsSubtitle: true, backTitle: Self.title, showsCount: true)
        }
        if !members.isEmpty {
            let ids = members.map(\.id)
            VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
                AdminSectionLabel(title: L10n.t("الأعضاء", "Members"), trailing: AdminNumberText.grouped(members.count))
                AdminRowsCard(dividerInset: AdminSearchPersonRow.dividerInset) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, m in
                        Button { sheet = AdminMemberSheetContext(ids: ids, start: index) } label: {
                            AdminSearchPersonRow(member: m, name: m.displayFullName, tint: DS.Color.slate,
                                                 line: memberLine(m))
                        }
                        .buttonStyle(AdminRowPressStyle())
                        .accessibilityHint(L10n.t("يفتح بيانات العضو", "Opens the member details"))
                    }
                }
            }
        }
        if tools.isEmpty && members.isEmpty {
            DSEmptyView(L10n.t("لا نتائج", "No results"),
                        message: L10n.t("جرّب كلمة أخرى", "Try another word"), style: .card)
        }
    }

    /// سطر العضو: «متوفى» و/أو رقمه (يُقرأ من اليسار)
    private func memberLine(_ m: FamilyMember) -> String? {
        let phone = m.phoneNumber.flatMap { $0.isEmpty ? nil : "\u{2066}\(KuwaitPhone.display($0))\u{2069}" }
        let parts = [m.isDeceased == true ? L10n.t("متوفى", "Deceased") : nil, phone].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var emptyHint: String {
        authVM.canEditMembers
            ? L10n.t("اكتب اسم عضو أو رقمه، أو اسم أداة مثل «المناسبات» أو «إشعارات الإدارة».",
                     "Type a member's name or number, or a tool like “Occasions” or “Admin notifications”.")
            : L10n.t("اكتب اسم أداة مثل «المناسبات» أو «إشعارات الإدارة»، أو كلمة تبحث بها في الوارد.",
                     "Type a tool like “Occasions” or “Admin notifications”, or a word to search the inbox.")
    }

    var body: some View {
        AdminHubPage {
            AdminBandHeader(title: Self.title,
                            subtitle: L10n.t("عضو، طلب، أو إعداد", "A member, a request or a setting")) {
                EmptyView()
            } accessory: {
                DSSearchField(text: $query, placeholder: L10n.t("بحث بالاسم أو الرقم أو الأداة", "Name, number or tool"),
                              style: .admin)
                    .padding(.top, DS.Spacing.md)
            }
        } content: {
            if authVM.canEditMembers { scopePicker }
            if womenOnly {
                womenSection
            } else if q.isEmpty {
                DSNoteCard(emptyHint, icon: "magnifyingglass")
            } else {
                results(tools: tools, members: members)
            }
        }
        .dsTallBox(item: $sheet) { context in
            AdminMemberSheet(ids: context.ids, start: context.start)
        }
        .task(id: womenOnly) { if womenOnly { await loadWomen() } }
        // تفاصيل المرأة — نفس مربّع شجرة النساء
        .fullScreenCover(item: $selectedWoman) { w in
            WomanDetailSheet(
                woman: w,
                allWomen: women,
                me: authVM.currentUser,
                canEdit: authVM.canEditMembers,
                canDelete: authVM.canDeleteMembers,
                canAnnounceDeath: authVM.isAdmin,
                canModerate: authVM.canModerate,
                onChanged: { await loadWomen() },
                onOpenMember: { id in
                    selectedWoman = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { selectedWoman = women.first { $0.id == id } }
                }
            )
            .background(ClearPresentationBackground())
        }
        .transaction { t in if selectedWoman != nil { t.disablesAnimations = true } }
    }
}

/// صفّ شخص في نتائج البحث (spec A.6 «صفوف البيانات بالصورة»، مثل صفّ «العائلة»): الصورة ٤٠ · الاسم ١٥ (سطران مع الخط
/// الأكبر) · سطر ١٣ رمادي · ‹. المتوفى بصورة رمادية
private struct AdminSearchPersonRow: View {
    let member: FamilyMember
    let name: String
    let tint: Color
    let line: String?

    /// الفاصل يبدأ من النص بعد الصورة
    static let dividerInset: CGFloat = DS.Icon.avatar + DS.Spacing.md

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            // الرمادي للمتوفى فقط — بلا `grayscale(0)` على كل صفّ
            Group {
                if member.isDeceased == true {
                    DSMemberAvatar(name: name, avatarUrl: member.avatarUrl, size: DS.Icon.avatar, roleColor: tint)
                        .grayscale(1)
                } else {
                    DSMemberAvatar(name: name, avatarUrl: member.avatarUrl, size: DS.Icon.avatar, roleColor: tint)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(name.isEmpty ? L10n.t("بلا اسم", "No name") : name)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .dsNameLines()
                if let line {
                    Text(verbatim: line)
                        .dsFont(.subtitle)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DSChevron()
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: line == nil ? DS.Hub.rowMinHeight : DS.Hub.rowMinHeightTwoLines,
               alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension Notification.Name {
    /// يفتح تبويب الشجرة على «شجرة النساء» (من «العائلة» في لوحة الإدارة)
    static let openWomenTree = Notification.Name("openWomenTree")
}
