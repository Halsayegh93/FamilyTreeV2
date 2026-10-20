import SwiftUI

// MARK: - Admin App Settings — إعدادات التطبيق
//
// بشكل «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠ «كل الصفحات بنفس شكل «اليوم»»، `AdminPageKit`): رأس كحلي باسم الإعداد ووصفه
// ورمزه وأرقامه الحقيقية (وشارة «للقراءة — يعدّلها المالك» لغير المالك) ← بطاقات بيضاء، أولها يصعد فوق الرأس،
// والصفوف داخلها مفصولة بخط (`AdminControlRow` للمفاتيح والعدّادات). المالك يعدّل، والمدير يتصفّح للقراءة
// (البطاقات معطّلة له كما كانت).
// ترتيب ٢٠٢٦-١٠-٠٩ (طلب المالك «أحس وايد أمور داخله ببعض» — خيار «أ»): الصفحة الكاملة بثلاثة تبويبات صارت شرائح
// في الرأس، كلٌّ بأقسامه فقط — «التطبيق» (اللغة، الميزات، الأخبار، التصنيفات، أسماء الفروع) ·
// «الأعضاء» (التسجيل والأجهزة، عداد التعديل، مسار الموافقات) · «النظام» (الصيانة، معلومات النظام، إعادة التعيين).
// الصفحة الكاملة بلا أرقام في الرأس (أُزيلت المكرّرة ٢٠٢٦-١٠-٠٩ — موجودة في «معلومات النظام»).
struct AdminAppSettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    /// «مسار الموافقات ٢»: الردود الجاهزة
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    @State private var showResetConfirmation = false
    @State private var showResetCooldownAlert = false
    @State private var cooldownDisabled = ProfileEditCooldown.shared.isDisabled
    @State private var tab: SettingsTab = .app
    /// مربّع «أسماء الفروع» (شجرة الفروع بوضع التسمية)
    @State private var branchNamesOpen = false
    /// مربّع «الردود الجاهزة» («مسار الموافقات ٢»)
    @State private var templatesOpen = false

    /// تبويبات الصفحة
    private enum SettingsTab: Hashable { case app, members, system }

    /// إعادة تصميم لوحة الإدارة (طلب المالك ٢٠٢٦-١٠-٢٠): كل إعداد يُفتح من صفّه في قسمه («التطبيق»،
    /// «الدخول والأمان»، ⚙︎ «الوارد») — نفس الأقسام والمفاتيح والصلاحيات تماماً، الصفحة تعرض المطلوب فقط.
    /// `.all` = الصفحة الكاملة بتبويباتها الثلاثة كما كانت.
    enum Scope: Hashable {
        case all
        case featuresLanguage, newsCategories, branches, cooldown
        case maintenance, systemInfo, reset
        case registration, approvals
    }

    private let scope: Scope

    init(scope: Scope = .all) {
        self.scope = scope
    }

    private var scopeTitle: String {
        switch scope {
        case .all:              return L10n.t("إعدادات التطبيق", "App Settings")
        case .featuresLanguage: return L10n.t("الميزات واللغة", "Features & Language")
        case .newsCategories:   return L10n.t("الأخبار والتصنيفات", "News & Categories")
        case .branches:         return L10n.t("أسماء الفروع", "Branch Names")
        case .cooldown:         return L10n.t("عداد التعديل", "Edit Counter")
        case .maintenance:      return L10n.t("الصيانة", "Maintenance")
        case .systemInfo:       return L10n.t("معلومات النظام", "System Info")
        case .reset:            return L10n.t("إعادة التعيين", "Reset")
        case .registration:     return L10n.t("قواعد التسجيل", "Sign-up Rules")
        case .approvals:        return L10n.t("إعدادات مسار الموافقات", "Approval Path Settings")
        }
    }

    /// سطر الوصف تحت العنوان (نفس معاني صفوف الأقسام)
    private var scopeSubtitle: String {
        switch scope {
        case .all:              return L10n.t("التطبيق · الأعضاء · النظام", "App · Members · System")
        case .featuresLanguage: return L10n.t("لغة التطبيق والأقسام الظاهرة للأعضاء", "App language and the sections members see")
        case .newsCategories:   return L10n.t("مراجعة الأخبار والاستطلاعات وتصنيفات الأخبار والمكتبة",
                                              "News review, polls, and news & library categories")
        case .branches:         return L10n.t("أسماء تظهر في قائمة الفروع", "Names shown in the branch list")
        case .cooldown:         return L10n.t("٣ تعديلات ثم بموافقة — إيقاف أو تصفير", "3 edits then approval — pause or reset")
        case .maintenance:      return L10n.t("إيقاف التطبيق مؤقتاً للصيانة", "Pause the app for maintenance")
        case .systemInfo:       return L10n.t("الإصدار والأعضاء وآخر تحديث للإعدادات", "Version, members and the last settings change")
        case .reset:            return L10n.t("إرجاع الإعدادات للقيم الافتراضية", "Restore default settings")
        case .registration:     return L10n.t("السماح بالتسجيل وحدّ الأجهزة لكل عضو", "Allow sign-ups and the device limit")
        case .approvals:        return ""
        }
    }

    /// رمز الصفحة (نفس رمز صفّها في القسم)
    private var scopeGlyph: String {
        switch scope {
        case .all:              return "slider.horizontal.3"
        case .featuresLanguage: return "switch.2"
        case .newsCategories:   return "newspaper.fill"
        case .branches:         return "arrow.triangle.branch"
        case .cooldown:         return "timer"
        case .maintenance:      return "wrench.and.screwdriver.fill"
        case .systemInfo:       return "info.circle.fill"
        case .reset:            return "arrow.counterclockwise"
        case .registration:     return "person.crop.circle.badge.checkmark"
        case .approvals:        return "gearshape.fill"
        }
    }

    /// المالك يعدّل، باقي المدراء يتصفّحون فقط.
    private var canEdit: Bool { authVM.canManageSettings }

    var body: some View {
        // «إعدادات المسار» بشكل «اليوم» (`AdminPageKit`) — باقي النطاقات في `page`
        if scope == .approvals { approvalsPage } else { page }
    }

    private var alerts: AppSettingsAlerts {
        AppSettingsAlerts(
            showReset: $showResetConfirmation,
            showResetCooldown: $showResetCooldownAlert,
            onReset: { Task { await appSettingsVM.resetToDefaults(updatedBy: authVM.currentUser?.id) } }
        )
    }

    private var page: some View {
        let cards = scopeCards
        return AdminPage(header: pageHeader,
                         lead: cards.first,
                         content: cardStack(Array(cards.dropFirst())))
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .task {
                await appSettingsVM.fetchSettings()
            }
            .modifier(alerts)
            // أسماء الفروع — شجرة الفروع نفسها بوضع التسمية (مربّع طويل كبقية استدعاءاتها)
            .dsTallBox(isPresented: $branchNamesOpen) {
                BranchPickerSheet(
                    allMembers: memberVM.allMembers,
                    renamesBranches: true,
                    canRename: canEdit,
                    onRename: { id, name in
                        Task {
                            await appSettingsVM.updateBranchName(name, for: id, updatedBy: authVM.currentUser?.id)
                        }
                    }
                )
                .environmentObject(appSettingsVM)
            }
            // «مسار الموافقات ٢»: الردود الجاهزة — المالك يضيف ويحذف، والمدير يقرأ
            .dsCenterBox(isPresented: $templatesOpen) {
                ApprovalTemplatesBox(adminRequestVM: adminRequestVM, canEdit: canEdit) { templatesOpen = false }
            }
    }

    /// بقية البطاقات بعد الأولى — الوضع الأفقي على عمودين
    private func cardStack(_ cards: [AnyView]) -> AnyView {
        guard !cards.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(AdaptiveCardStack(spacing: DS.Hub.stackSpacing, alignment: .leading) {
            ForEach(Array(cards.enumerated()), id: \.offset) { $0.element }
        })
    }

    // MARK: - الرأس

    private var pageHeader: AdminPageHeader {
        AdminPageHeader(title: scopeTitle,
                        subtitle: scopeSubtitle,
                        glyph: scopeGlyph,
                        readOnly: !canEdit,
                        kpis: scopeKPIs,
                        chips: scope == .all ? tabChips : [])
    }

    /// شرائح التبويبات الثلاثة (كانت مبدّلاً تحت الرأس) — الصفحة الكاملة فقط
    private var tabChips: [AdminPageChip] {
        [
            AdminPageChip(id: "app", title: L10n.t("التطبيق", "App"), icon: "app.badge.fill",
                          selected: tab == .app) { tab = .app },
            AdminPageChip(id: "members", title: L10n.t("الأعضاء", "Members"), icon: "person.2.fill",
                          selected: tab == .members) { tab = .members },
            AdminPageChip(id: "system", title: L10n.t("النظام", "System"), icon: "gearshape.fill",
                          selected: tab == .system) { tab = .system }
        ]
    }

    /// وصلت الإعدادات من السيرفر (القيم الافتراضية بلا تاريخ تحديث) — قبلها «—» في الأرقام
    private var settingsLoaded: Bool { appSettingsVM.settings.updatedAt != nil }

    /// أرقام الرأس من الإعدادات المحمّلة أصلاً (بلا طلبات جديدة) — للنطاقات التي لها أكثر من قيمة تُعرض
    private var scopeKPIs: [AdminPageKPI] {
        let s = appSettingsVM.settings
        let ready = settingsLoaded
        func state(_ on: Bool, _ onText: String, _ offText: String) -> String { ready ? (on ? onText : offText) : "—" }
        func tint(_ on: Bool) -> Color { ready ? (on ? DS.Hub.kpiMine : DS.Hub.kpiLate) : DS.Color.textOnPrimary }
        switch scope {
        case .featuresLanguage:
            return [
                AdminPageKPI(ready ? ((s.defaultLanguage ?? "ar") == "ar" ? "العربية" : "English") : "—",
                             L10n.t("اللغة الرسمية", "Official language"), icon: "character.bubble"),
                AdminPageKPI(ready ? L10n.t("\(enabledFeaturesCount) من 3", "\(enabledFeaturesCount) of 3") : "—",
                             L10n.t("ميزات ظاهرة", "Features shown"), icon: "star")
            ]
        case .newsCategories:
            return [
                AdminPageKPI(state(s.newsRequiresApproval, L10n.t("تعمل", "On"), L10n.t("متوقفة", "Off")),
                             L10n.t("مراجعة الأخبار", "News review"), icon: "checkmark.shield",
                             tint: tint(s.newsRequiresApproval)),
                AdminPageKPI(state(s.pollsEnabled ?? true, L10n.t("مسموحة", "On"), L10n.t("متوقفة", "Off")),
                             L10n.t("الاستطلاعات", "Polls"), icon: "chart.bar")
            ]
        case .registration:
            return [
                AdminPageKPI(state(s.allowNewRegistrations, L10n.t("مفتوح", "Open"), L10n.t("مغلق", "Closed")),
                             L10n.t("التسجيل", "Sign-up"), icon: "person.badge.plus",
                             tint: tint(s.allowNewRegistrations)),
                AdminPageKPI(ready ? "\(s.maxDevicesPerUser)" : "—",
                             L10n.t("أجهزة لكل عضو", "Devices per member"), icon: "iphone.gen3")
            ]
        case .systemInfo:
            let loadedMembers = !memberVM.allMembers.isEmpty
            return [
                AdminPageKPI(loadedMembers ? "\(memberVM.allMembers.filter(\.isCountable).count)" : "—",
                             L10n.t("أعضاء العائلة", "Family members"), icon: "person.3"),
                AdminPageKPI(loadedMembers ? "\(registeredUsersCount)" : "—",
                             L10n.t("مستخدمون مسجّلون", "Registered users"), icon: "person.crop.circle.badge.checkmark",
                             tint: DS.Hub.kpiMine)
            ]
        default:
            return []
        }
    }

    // MARK: - أرقام مساعدة

    private var registeredUsersCount: Int {
        memberVM.allMembers.filter { $0.isCountable && $0.phoneNumber != nil && !($0.phoneNumber ?? "").isEmpty }.count
    }

    /// الميزات الظاهرة للأعضاء (الديوانيات، المشاريع، شجرة النساء)
    private var enabledFeaturesCount: Int {
        let s = appSettingsVM.settings
        // «ألبوم الصور» أُزيل — لا يوجد قسم ألبوم في التطبيق (طلب المالك ٢٠٢٦-١٠-٠٧)
        return [s.diwaniyasEnabled ?? true, s.projectsEnabled ?? true, s.womenTreeEnabled ?? true]
            .filter { $0 }.count
    }

    // MARK: - البطاقات

    /// بطاقات الإعداد المطلوب وحده (من صفّه في قسمه)، أو بطاقات التبويب المختار في الصفحة الكاملة
    private var scopeCards: [AnyView] {
        switch scope {
        case .all:              return tabCards
        case .featuresLanguage: return [languageCard, featuresCard]
        case .newsCategories:   return [contentCard, categoriesCard]
        case .branches:         return [branchNamesCard]
        case .cooldown:         return [cooldownCard]
        case .maintenance:      return [securityCard]
        case .systemInfo:       return [systemInfoCard]
        case .reset:            return [resetCard]
        case .registration:     return [registrationCard]
        case .approvals:        return [AnyView(approvalsSection)]
        }
    }

    /// بطاقات التبويب المختار فقط (الصفحة الكاملة)
    private var tabCards: [AnyView] {
        switch tab {
        case .app:
            // اللغة، الميزات، الأخبار، التصنيفات (الأخبار والمكتبة)، أسماء الفروع (يتصفّحها غير المالك للقراءة —
            // المربّع نفسه يمنع التعديل)
            return [languageCard, featuresCard, contentCard, categoriesCard, branchNamesCard]
        case .members:
            // التسجيل والأجهزة، عداد التعديل («مسار الموافقات» خرج من هنا — بيته الوحيد ⚙︎ «الوارد»، الدفعة ب ٢٠٢٦-١٠-٢٠)
            return [registrationCard, cooldownCard]
        case .system:
            // الصيانة، معلومات النظام، إعادة التعيين (تبقى مرئية ومعطّلة لغير المالك)
            return [securityCard, systemInfoCard, resetCard]
        }
    }

    // MARK: - مسار الموافقات (طلب المالك ٢٠٢٦-١٠-١٥)
    /// مفتاح واحد يرجع للطريقة القديمة فوراً — المالك يعدّل والمدير يقرأ (مثل باقي الإعدادات).
    /// تحته والمسار شغّال («مسار الموافقات ٢»، طلب المالك ٢٠٢٦-١٠-١٦): المسار السريع، المهلة، الردود الجاهزة —
    /// كلٌّ يظهر إذا كان عموده/جدوله على السيرفر
    private var approvalsSection: some View {
        let s = appSettingsVM.settings
        // بلا عنوان بطاقة — الصفحة نفسها «إعدادات مسار الموافقات» (بيتها الوحيد ⚙︎ «الوارد»)
        return AdminSectionCard {
            AdminRowsCardBody {
                settingToggle(
                    icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                    color: DS.Color.success,
                    title: L10n.t("مسار الموافقات", "Approvals path"),
                    subtitle: L10n.t("المراجِع المختص يراجع ويرفع، المدير يعتمد، والمراجِع المختص ينفّذ — إطفاؤه يرجّع الطريقة القديمة فوراً",
                                     "The specialist reviews, the manager approves, the specialist carries out — off returns the old way instantly"),
                    isOn: s.approvalsWorkflow ?? false,
                    key: "approvals_workflow"
                )
                .disabled(!canEdit)
                if s.approvalsWorkflow == true {
                    if let fastTypes = s.approvalsFastTypes {
                        fastTrackBlock(fastTypes)
                            .disabled(!canEdit)
                    }
                    if s.approvalsSlaHours != nil || s.approvalsEscalateHours != nil {
                        slaBlock
                            .disabled(!canEdit)
                    }
                    if adminRequestVM.approvalTemplatesAvailable == true {
                        AdminTapRow(icon: "text.badge.plus", tint: DS.Color.composerDiwaniya,
                                    title: L10n.t("نماذج الردود", "Reply templates"),
                                    subtitle: L10n.t("ردود قصيرة تظهر فوق ملاحظة القرار", "Short replies above the decision note"),
                                    value: adminRequestVM.approvalTemplates.isEmpty ? nil : "\(adminRequestVM.approvalTemplates.count)",
                                    tap: .action { templatesOpen = true })
                    }
                }
            }
        }
        .task { await adminRequestVM.fetchApprovalTemplates() }
    }

    /// عنوان مجموعة داخل البطاقة (مربّع أيقونة + عنوان + وصف) فوق محتواها — صفّ بين خطّين لا صندوق
    private func approvalsBlock<Content: View>(icon: String, tint: Color, title: String, subtitle: String,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.md) {
                AdminIconSquare(symbol: icon, tint: tint)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title)
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(subtitle)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.Spacing.sm + 2)
    }

    /// «المسار السريع»: شرائح الأنواع (اختيار متعدد) — المختار يبدأ عند المدير مباشرة
    private func fastTrackBlock(_ selected: [String]) -> some View {
        approvalsBlock(icon: "bolt.fill", tint: DS.Color.info,
                       title: L10n.t("الاعتماد المباشر", "Direct approval"),
                       subtitle: L10n.t("هذه الأنواع تروح للمدير مباشرة بلا مراجعة المراجِع المختص",
                                        "These types go straight to the manager, skipping the specialist")) {
            ChangedWordsFlow(spacing: DS.Spacing.xs) {
                ForEach(ApprovalTypeTitle.workflowTypes, id: \.self) { type in
                    let on = selected.contains(type)
                    DSChipButton(ApprovalTypeTitle.title(type), icon: on ? "checkmark" : ApprovalTypeTitle.icon(type),
                                 tint: DS.Color.info, isSelected: on, size: .small) {
                        toggleFastType(type, in: selected)
                    }
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toggleFastType(_ type: String, in selected: [String]) {
        var next = selected
        if let i = next.firstIndex(of: type) { next.remove(at: i) } else { next.append(type) }
        // ترتيب ثابت (ترتيب العرض) — وأي نوع لا يعرفه هذا الإصدار يبقى كما هو
        let known = ApprovalTypeTitle.workflowTypes.filter(next.contains)
        let unknown = next.filter { !ApprovalTypeTitle.workflowTypes.contains($0) }
        next = known + unknown
        appSettingsVM.settings.approvalsFastTypes = next
        Task { await appSettingsVM.updateSetting("approvals_fast_types", value: next, updatedBy: authVM.currentUser?.id) }
    }

    /// «المهلة»: تذكير بعد / تصعيد بعد — للعادي (بخطوة ٦ ساعات) وللمستعجل (بخطوة ساعة)
    private var slaBlock: some View {
        let s = appSettingsVM.settings
        let sla = Int(s.approvalsSlaHours ?? 24), esc = Int(s.approvalsEscalateHours ?? 48)
        let uSla = Int(s.approvalsUrgentSlaHours ?? 6), uEsc = Int(s.approvalsUrgentEscalateHours ?? 12)
        return approvalsBlock(icon: "timer", tint: DS.Color.warning,
                              title: L10n.t("المهلة", "Deadlines"),
                              subtitle: L10n.t("تذكير لمن عنده الطلب، ثم تصعيد للمدير إذا تأخر",
                                               "A reminder to whoever holds it, then escalation to the manager")) {
            slaGroup(L10n.t("العادي", "Normal"), icon: "clock.fill", tint: DS.Color.actionNavy, rows: [
                (L10n.t("تذكير بعد", "Remind after"), sla, 6...max(6, esc - 6), 6, "approvals_sla_hours"),
                (L10n.t("تصعيد بعد", "Escalate after"), esc, min(336, sla + 6)...336, 6, "approvals_escalate_hours")
            ])
            slaGroup(L10n.t("العاجل", "Urgent"), icon: "flame.fill", tint: DS.Color.error, rows: [
                (L10n.t("تذكير بعد", "Remind after"), uSla, 1...max(1, uEsc - 1), 1, "approvals_urgent_sla_hours"),
                (L10n.t("تصعيد بعد", "Escalate after"), uEsc, min(72, uSla + 1)...72, 1, "approvals_urgent_escalate_hours")
            ])
        }
    }

    private func slaGroup(_ title: String, icon: String, tint: Color,
                          rows: [(String, Int, ClosedRange<Int>, Int, String)]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .dsGlyph(DS.Glyph.xs)
                    .foregroundColor(tint.dsReadableGlyph)
                    .accessibilityHidden(true)
                Text(title)
                    .dsFont(.label)
                    .foregroundColor(DS.Color.textPrimary)
            }
            ForEach(rows, id: \.4) { row in
                HStack(spacing: DS.Spacing.sm) {
                    Text(row.0)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textSecondary)
                    Spacer(minLength: DS.Spacing.sm)
                    ApprovalHoursStepper(value: row.1, range: row.2, step: row.3, label: "\(title) — \(row.0)") { v in
                        setHours(row.4, v)
                    }
                }
            }
        }
        .padding(.top, DS.Spacing.xxs)
    }

    /// تحديث متفائل للساعات ثم الحفظ
    private func setHours(_ key: String, _ value: Int) {
        let v = Double(value)
        switch key {
        case "approvals_sla_hours": appSettingsVM.settings.approvalsSlaHours = v
        case "approvals_escalate_hours": appSettingsVM.settings.approvalsEscalateHours = v
        case "approvals_urgent_sla_hours": appSettingsVM.settings.approvalsUrgentSlaHours = v
        case "approvals_urgent_escalate_hours": appSettingsVM.settings.approvalsUrgentEscalateHours = v
        default: return
        }
        Task { await appSettingsVM.updateSetting(key, value: value, updatedBy: authVM.currentUser?.id) }
    }

    // MARK: - أسماء الفروع (طلب المالك ٢٠٢٦-١٠-٠٩)
    /// عدد الفروع التي لها اسم مخصّص
    private var customBranchNamesCount: Int {
        (appSettingsVM.settings.branchNames ?? [:]).values
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var branchNamesCard: AnyView {
        AnyView(AdminSectionCard(title: L10n.t("الفروع", "Branches"),
                                 tag: customBranchNamesCount > 0
                                    ? L10n.t("\(customBranchNamesCount) اسم مخصّص", "\(customBranchNamesCount) custom")
                                    : nil) {
            AdminTapRow(icon: "pencil", tint: DS.Color.composerProject,
                        title: L10n.t("أسماء الفروع", "Branch names"),
                        subtitle: L10n.t("اسم يظهر في قائمة اختيار الفرع", "A name shown in the branch picker list"),
                        tap: .action { branchNamesOpen = true })
        })
    }

    // MARK: - التصنيفات (طلب المالك)
    private var categoriesCard: AnyView {
        AnyView(AdminSectionCard(title: L10n.t("التصنيفات", "Categories")) {
            AdminTapRow(icon: "tag.fill", tint: DS.Color.accent,
                        title: L10n.t("تصنيفات الأخبار والمكتبة", "News & library categories"),
                        subtitle: L10n.t("الاسم والأيقونة واللون، والإخفاء والترتيب", "Name, icon, colour, hide and order"),
                        tap: .page { [authVM] in AnyView(CategoriesManagerView().environmentObject(authVM)) })
        })
    }

    // MARK: - لغة التطبيق الرسمية (طلب المالك)
    //
    // تُطبَّق على كل مستخدم لم يختر لغته بنفسه. من يغيّر اللغة من «الإعدادات»
    // تبقى لغته هو.
    private var languageCard: AnyView {
        AnyView(AdminSectionCard(title: L10n.t("لغة التطبيق الرسمية", "Official App Language"),
                                 tag: (appSettingsVM.settings.defaultLanguage ?? "ar") == "ar" ? "العربية" : "English") {
            // المبدّل الواحد (`DSSegmentedSwitch`) بدل مبدّل النظام الرمادي
            DSSegmentedSwitch(options: [
                DSSegmentOption(id: "ar", title: "العربية", icon: "character.bubble.fill.ar"),
                DSSegmentOption(id: "en", title: "English", icon: "textformat.abc")
            ], selection: Binding(
                get: { appSettingsVM.settings.defaultLanguage ?? "ar" },
                set: { newValue in
                    Task {
                        await appSettingsVM.updateSetting(
                            "default_language",
                            value: newValue,
                            updatedBy: authVM.currentUser?.id
                        )
                    }
                }
            ), size: .regular)
            .accessibilityLabel(L10n.t("لغة التطبيق الرسمية", "Official App Language"))

            Text(L10n.t(
                "لغة التطبيق لكل الأعضاء. من يغيّر لغته من «الإعدادات» تبقى لغته هو.",
                "The app language for all members. Anyone who picks a language in Settings keeps their own."
            ))
            .dsFont(.footnote)
            .foregroundColor(DS.Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(!canEdit))
    }

    // MARK: - Registration & Membership
    private var registrationCard: AnyView {
        AnyView(AdminSectionCard(title: L10n.t("التسجيل والعضوية", "Registration & Membership")) {
            AdminRowsCardBody {
                // السماح بالتسجيل الجديد
                settingToggle(
                    icon: "person.badge.plus",
                    color: DS.Color.palm,
                    title: L10n.t("السماح بالتسجيل", "Allow Registrations"),
                    subtitle: L10n.t("السماح لأعضاء جدد بالتسجيل في التطبيق", "Allow new registrations"),
                    isOn: appSettingsVM.settings.allowNewRegistrations,
                    key: "allow_new_registrations"
                )

                // الحد الأقصى للأجهزة
                AdminControlRow(icon: "iphone.gen3.badge.play", tint: DS.Color.info,
                                title: L10n.t("الحد الأقصى للأجهزة", "Max Devices"),
                                subtitle: L10n.t("عدد الأجهزة المسموحة لكل مستخدم", "Devices allowed per user"),
                                control: AnyView(maxDevicesControl))
            }
        }
        .disabled(!canEdit))
    }

    private var maxDevicesControl: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text("\(appSettingsVM.settings.maxDevicesPerUser)")
                .dsFont(.statValue)
                .foregroundColor(AppSection.admin.ink)
                .monospacedDigit()
                .frame(minWidth: DS.Icon.section)
                .accessibilityHidden(true)

            Stepper(
                "\(appSettingsVM.settings.maxDevicesPerUser)",
                value: Binding(
                    get: { appSettingsVM.settings.maxDevicesPerUser },
                    set: { newVal in
                        appSettingsVM.settings.maxDevicesPerUser = newVal
                        Task {
                            await appSettingsVM.updateSetting(
                                "max_devices_per_user",
                                value: newVal,
                                updatedBy: authVM.currentUser?.id
                            )
                        }
                    }
                ),
                in: 1...10
            )
            .labelsHidden()
            .accessibilityLabel(L10n.t("الحد الأقصى للأجهزة", "Max Devices"))
            .accessibilityValue("\(appSettingsVM.settings.maxDevicesPerUser)")
        }
        .fixedSize()
    }

    // MARK: - Content Settings
    private var contentCard: AnyView {
        AnyView(AdminSectionCard(title: L10n.t("الأخبار", "News")) {
            AdminRowsCardBody {
                // موافقة الأخبار
                settingToggle(
                    icon: "checkmark.shield.fill",
                    color: DS.Color.accent,
                    title: L10n.t("موافقة الأخبار", "News Approval"),
                    subtitle: L10n.t("يتطلب موافقة المدير قبل نشر الأخبار", "Require admin approval"),
                    isOn: appSettingsVM.settings.newsRequiresApproval,
                    key: "news_requires_approval"
                )

                // الاستطلاعات
                settingToggle(
                    icon: "chart.bar.fill",
                    color: DS.Color.info,
                    title: L10n.t("الاستطلاعات", "Polls"),
                    subtitle: L10n.t("السماح بإضافة استطلاعات في الأخبار", "Allow polls in news posts"),
                    isOn: appSettingsVM.settings.pollsEnabled ?? true,
                    key: "polls_enabled"
                )
            }
        }
        .disabled(!canEdit))
    }

    // MARK: - Features
    private var featuresCard: AnyView {
        AnyView(AdminSectionCard(title: L10n.t("الميزات", "Features"),
                                 tag: L10n.t("\(enabledFeaturesCount) من 3 ظاهرة", "\(enabledFeaturesCount) of 3 on")) {
            AdminRowsCardBody {
                settingToggle(
                    icon: AppSection.diwaniyas.symbol,   // «مجلس»
                    color: AppSection.admin.ink,
                    title: L10n.t("الديوانيات", "Diwaniyas"),
                    subtitle: L10n.t("إظهار تاب الديوانيات للأعضاء", "Show Diwaniyas tab to members"),
                    isOn: appSettingsVM.settings.diwaniyasEnabled ?? true,
                    key: "diwaniyas_enabled"
                )

                settingToggle(
                    icon: "briefcase.fill",
                    color: DS.Color.accent,
                    title: L10n.t("مشاريع العائلة", "Family Projects"),
                    subtitle: L10n.t("إظهار قسم المشاريع في الرئيسية", "Show Projects section on Home"),
                    isOn: appSettingsVM.settings.projectsEnabled ?? true,
                    key: "projects_enabled"
                )

                // إخفاء «شجرة النساء» من قسم الشجرة (طلب المالك ٢٠٢٦-١٠-٠٧) — للجميع حتى يُعاد تشغيلها من هنا
                settingToggle(
                    icon: "person.2.fill",
                    color: DS.Color.female,
                    title: L10n.t("شجرة النساء", "Women's Tree"),
                    subtitle: L10n.t("إظهار تبويب النساء في قسم الشجرة", "Show the Women tab in the Tree section"),
                    isOn: appSettingsVM.settings.womenTreeEnabled ?? true,
                    key: "women_tree_enabled"
                )
            }
        }
        .disabled(!canEdit))
    }

    // MARK: - Security
    private var securityCard: AnyView {
        AnyView(AdminSectionCard(title: L10n.t("الصيانة", "Maintenance"),
                                 tag: appSettingsVM.settings.maintenanceMode ? L10n.t("مفعّل", "On") : nil) {
            // وضع الصيانة
            settingToggle(
                icon: "wrench.and.screwdriver.fill",
                color: DS.Color.error,
                title: L10n.t("وضع الصيانة", "Maintenance Mode"),
                subtitle: L10n.t("إيقاف التطبيق مؤقتاً للصيانة (المدراء فقط)", "Maintenance mode (admin only)"),
                isOn: appSettingsVM.settings.maintenanceMode,
                key: "maintenance_mode"
            )
        }
        .disabled(!canEdit))
    }

    // MARK: - Edit Cooldown
    private var cooldownCard: AnyView {
        AnyView(AdminSectionCard(title: L10n.t("عداد التعديل", "Edit Cooldown"),
                                 tag: cooldownDisabled ? L10n.t("موقوف", "Paused") : nil) {
            AdminRowsCardBody {
                // إيقاف / تشغيل العداد
                AdminControlRow(icon: "pause.circle.fill", tint: DS.Color.warning,
                                title: L10n.t("إيقاف العداد", "Disable Cooldown"),
                                subtitle: L10n.t("السماح بالتعديل بدون حد (عادةً 3 تعديلات ثم موافقة الإدارة)",
                                                 "Allow unlimited edits (normally 3 edits, then admin approval)"),
                                control: AnyView(cooldownToggle))

                // تصفير العداد
                AdminTapRow(icon: "arrow.counterclockwise.circle.fill", tint: DS.Color.warning,
                            title: L10n.t("تصفير العداد", "Reset Cooldown"),
                            subtitle: L10n.t("إعادة عدّاد التعديلات من الصفر", "Reset edit counters"),
                            tap: .action { showResetCooldownAlert = true })
            }
        }
        .disabled(!canEdit))
    }

    private var cooldownToggle: some View {
        Toggle("", isOn: $cooldownDisabled)
            .labelsHidden()
            .tint(DS.Color.warning)
            .accessibilityLabel(L10n.t("إيقاف العداد", "Disable Cooldown"))
            .onChange(of: cooldownDisabled) { newValue in
                ProfileEditCooldown.shared.isDisabled = newValue
            }
    }

    // MARK: - System Info
    private var systemInfoCard: AnyView {
        let s = appSettingsVM.settings
        return AnyView(AdminSectionCard(title: L10n.t("معلومات النظام", "System Info")) {
            // حالة سريعة: التسجيل والصيانة
            HStack(spacing: DS.Spacing.xs) {
                DSStatusChip(
                    text: s.allowNewRegistrations
                        ? L10n.t("التسجيل مفتوح", "Sign-up open")
                        : L10n.t("التسجيل مغلق", "Sign-up closed"),
                    icon: s.allowNewRegistrations ? "person.badge.plus" : "person.fill.xmark",
                    tint: s.allowNewRegistrations ? DS.Color.success : DS.Color.warning
                )
                if s.maintenanceMode {
                    DSStatusChip(text: L10n.t("وضع الصيانة", "Maintenance"),
                                  icon: "wrench.and.screwdriver.fill", tint: DS.Color.error)
                }
                Spacer(minLength: 0)
            }

            AdminRowsCardBody {
                infoRow(icon: "app.badge.fill",
                        label: L10n.t("إصدار التطبيق", "App Version"),
                        value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") + " (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                infoRow(icon: "iphone",
                        label: L10n.t("المنصة", "Platform"),
                        value: UIDevice.current.systemName + " " + UIDevice.current.systemVersion)
                // صفحة «معلومات النظام» وحدها تعرض العددين في الرأس — لا تكرار
                if scope != .systemInfo {
                    infoRow(icon: "person.3.fill",
                            label: L10n.t("أعضاء العائلة", "Family Members"),
                            value: "\(memberVM.allMembers.filter(\.isCountable).count)")
                    infoRow(icon: "person.crop.circle.badge.checkmark",
                            label: L10n.t("مستخدمين مسجلين", "Registered Users"),
                            value: "\(registeredUsersCount)")
                }
                infoRow(icon: "server.rack",
                        label: L10n.t("السيرفر", "Server"),
                        value: "Supabase · Stockholm")
                infoRow(icon: "clock.fill",
                        label: L10n.t("آخر تحديث", "Last Update"),
                        value: formatDate(s.updatedAt))
            }
        })
    }

    // MARK: - Reset
    private var resetCard: AnyView {
        AnyView(AdminSectionCard(title: L10n.t("إعادة التعيين", "Reset")) {
            Text(L10n.t("كل الإعدادات ترجع للقيم الافتراضية — يسأل قبل التنفيذ.",
                        "Every setting returns to its default — asks before it runs."))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            // الزرّ الواحد بالأحمر (يسأل قبل التنفيذ)
            DSButton(L10n.t("إعادة تعيين الإعدادات", "Reset Settings"), icon: "arrow.counterclockwise",
                     role: .destructive) {
                showResetConfirmation = true
            }
        }
        .disabled(!canEdit))
    }

    // MARK: - Helpers

    private func settingToggle(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        isOn: Bool,
        key: String
    ) -> some View {
        AdminControlRow(icon: icon, tint: color, title: title, subtitle: subtitle, control: AnyView(
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { newVal in
                    Task {
                        await appSettingsVM.updateSetting(
                            key,
                            value: newVal,
                            updatedBy: authVM.currentUser?.id
                        )
                    }
                }
            ))
            .labelsHidden()
            .tint(AppSection.admin.ink)
            .accessibilityLabel(title)
        ))
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        AdminInfoRow(icon: icon, tint: DS.Color.primary, title: label, trailing: AnyView(
            Text(value)
                .dsFont(.chip)
                .foregroundColor(DS.Color.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        ))
    }

    private func formatDate(_ isoString: String?) -> String {
        guard let isoString, !isoString.isEmpty else {
            return L10n.t("غير محدد", "N/A")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else {
            // try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: isoString) else {
                return isoString
            }
            return formatDisplayDate(date)
        }
        return formatDisplayDate(date)
    }

    private func formatDisplayDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}


// MARK: - «إعدادات المسار» بشكل «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠ «كل الصفحات بنفس شكل «اليوم»»)
//
// رأس كحلي بحال المسار وأرقامه (السريع، مهلة التذكير، الردود الجاهزة) ثم قسم «طلبات الوارد» نفسه —
// نفس المفاتيح والصلاحيات والحفظ ومربّع الردود الجاهزة تماماً.
extension AdminAppSettingsView {
    var approvalsPage: some View {
        AdminPage(header: approvalsHeader, lead: AnyView(approvalsSection), content: AnyView(EmptyView()))
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .task {
                await appSettingsVM.fetchSettings()
            }
            // «مسار الموافقات ٢»: الردود الجاهزة — المالك يضيف ويحذف، والمدير يقرأ
            .dsCenterBox(isPresented: $templatesOpen) {
                ApprovalTemplatesBox(adminRequestVM: adminRequestVM, canEdit: canEdit) { templatesOpen = false }
            }
    }

    private var approvalsHeader: AdminPageHeader {
        let s = appSettingsVM.settings
        let on = s.approvalsWorkflow
        let running = on == true
        let templatesKnown = adminRequestVM.approvalTemplatesAvailable == true
        var kpis = [
            AdminPageKPI(on.map { $0 ? L10n.t("يعمل", "On") : L10n.t("متوقف", "Off") } ?? "—",
                         L10n.t("المسار", "Path"), icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                         tint: running ? DS.Hub.kpiMine : DS.Hub.kpiLate),
            AdminPageKPI(running ? s.approvalsFastTypes.map { "\($0.count)" } ?? "—" : "—",
                         L10n.t("اعتماد مباشر", "Direct approval"), icon: "bolt.fill"),
            AdminPageKPI(running ? s.approvalsSlaHours.map { L10n.t("\(Int($0)) س", "\(Int($0))h") } ?? "—" : "—",
                         L10n.t("تذكير بعد", "Remind after"), icon: "timer")
        ]
        if running && templatesKnown {
            kpis.append(AdminPageKPI("\(adminRequestVM.approvalTemplates.count)", L10n.t("نماذج الردود", "Templates"),
                                     icon: "text.badge.plus", tap: .action { templatesOpen = true }))
        }
        return AdminPageHeader(
            title: L10n.t("إعدادات مسار الموافقات", "Approval Path Settings"),
            subtitle: L10n.t("مسار الموافقات، المهلة، الاعتماد المباشر، نماذج الردود",
                             "Approvals path, SLA, direct approval, reply templates"),
            glyph: "gearshape.fill",
            readOnly: !canEdit,
            kpis: kpis)
    }
}

/// تنبيها «إعادة التعيين» و«تصفير العداد» — مشتركة بين الصفحة والنسخة المضمّنة
private struct AppSettingsAlerts: ViewModifier {
    @Binding var showReset: Bool
    @Binding var showResetCooldown: Bool
    let onReset: () -> Void

    func body(content: Content) -> some View {
        content
            .dsAlert(
                L10n.t("إعادة تعيين", "Reset Settings"),
                isPresented: $showReset
            ) {
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
                Button(L10n.t("إعادة تعيين", "Reset"), role: .destructive) { onReset() }
            } message: {
                Text(L10n.t(
                    "سيتم إرجاع جميع الإعدادات إلى القيم الافتراضية",
                    "All settings will be restored to default values"
                ))
            }
            .dsAlert(
                L10n.t("تصفير العداد", "Reset Cooldown"),
                isPresented: $showResetCooldown
            ) {
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
                Button(L10n.t("تصفير", "Reset"), role: .destructive) {
                    ProfileEditCooldown.shared.resetAllCooldowns()
                }
            } message: {
                Text(L10n.t(
                    "سيتم إعادة تعيين جميع فترات الانتظار وسيصبح بإمكانك التعديل فوراً",
                    "All cooldown timers will be reset and you can edit immediately"
                ))
            }
    }
}
