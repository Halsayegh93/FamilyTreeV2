import SwiftUI

// MARK: - Admin App Settings — إعدادات التطبيق
//
// تصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧): أقسام `DSComposerSection` وصفوف
// `.dsRowBox()` (أيقونة حقل + عنوان + وصف + مفتاح). المالك يعدّل، والمدير يتصفّح للقراءة
// (الأقسام معطّلة له كما كانت).
// ترتيب ٢٠٢٦-١٠-٠٩ (طلب المالك «أحس وايد أمور داخله ببعض» — خيار «أ»): مبدّل بالأعلى بثلاثة
// تبويبات، كلٌّ بأقسامه فقط — «التطبيق» (اللغة، الميزات، الأخبار، التصنيفات، أسماء الفروع) ·
// «الأعضاء» (التسجيل والأجهزة، عداد التعديل) · «النظام» (الصيانة، معلومات النظام، إعادة التعيين).
// أُزيلت أرقام الرأس المكرّرة (موجودة في «معلومات النظام»).
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
        case .approvals:        return L10n.t("إعدادات المسار", "Approval Path Settings")
        }
    }

    private var tabOptions: [DSSegmentOption<SettingsTab>] {
        [
            DSSegmentOption(id: .app, title: L10n.t("التطبيق", "App"), icon: "app.badge.fill"),
            DSSegmentOption(id: .members, title: L10n.t("الأعضاء", "Members"), icon: "person.2.fill"),
            DSSegmentOption(id: .system, title: L10n.t("النظام", "System"), icon: "gearshape.fill")
        ]
    }

    /// المالك يعدّل، باقي المدراء يتصفّحون فقط.
    private var canEdit: Bool { authVM.canManageSettings }

    var body: some View { page }

    private var alerts: AppSettingsAlerts {
        AppSettingsAlerts(
            showReset: $showResetConfirmation,
            showResetCooldown: $showResetCooldownAlert,
            onReset: { Task { await appSettingsVM.resetToDefaults(updatedBy: authVM.currentUser?.id) } }
        )
    }

    private var page: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.lg) {
                // المبدّل الواحد — نفس مقاس مبدّل لوحة الإدارة (الصفحة الكاملة فقط)
                if scope == .all {
                    DSSegmentedSwitch(options: tabOptions, selection: $tab)
                        .dsStaggerIn(0)
                }

                // إشعار وضع القراءة فقط (لغير المالك) — مرة واحدة تحت المبدّل
                if !canEdit {
                    readOnlyBanner
                }

                // الوضع الأفقي: الأقسام على عمودين
                AdaptiveCardStack(spacing: DS.Spacing.md, alignment: .leading) {
                    sections
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xxxl)
        }
        // الرأس الملوّن الموحّد (كان شريط النظام + بطاقة رأس)
        .dsSubPageHeader(scopeTitle,
                         subtitle: !canEdit
                            ? L10n.t("وضع القراءة فقط — التعديل للمالك", "Read-only — the owner edits")
                            : scope == .all ? L10n.t("التطبيق · الأعضاء · النظام", "App · Members · System") : nil)
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

    /// أقسام الإعداد المطلوب وحده (من صفّه في قسمه)، أو أقسام التبويب المختار في الصفحة الكاملة
    @ViewBuilder private var sections: some View {
        switch scope {
        case .all:
            tabSections
        case .featuresLanguage:
            languageSection
                .disabled(!canEdit)
            featuresSection
                .disabled(!canEdit)
        case .newsCategories:
            contentSection
                .disabled(!canEdit)
            categoriesSection
        case .branches:
            branchNamesSection
        case .cooldown:
            cooldownSection
                .disabled(!canEdit)
        case .maintenance:
            securitySection
                .disabled(!canEdit)
        case .systemInfo:
            systemInfoSection
        case .reset:
            resetSection
                .disabled(!canEdit)
        case .registration:
            registrationSection
                .disabled(!canEdit)
        case .approvals:
            approvalsSection
        }
    }

    /// أقسام التبويب المختار فقط (الصفحة الكاملة)
    @ViewBuilder private var tabSections: some View {
        switch tab {
        case .app:
            // لغة التطبيق الرسمية
            languageSection
                .disabled(!canEdit)
            // الميزات
            featuresSection
                .disabled(!canEdit)
            // الأخبار
            contentSection
                .disabled(!canEdit)
            // التصنيفات — الأخبار والمكتبة
            categoriesSection
            // أسماء الفروع — يتصفّحها غير المالك للقراءة (المربّع نفسه يمنع التعديل)
            branchNamesSection

        case .members:
            // التسجيل والأجهزة
            registrationSection
                .disabled(!canEdit)
            // عداد التعديل
            cooldownSection
                .disabled(!canEdit)
            // مسار الموافقات (طلب المالك ٢٠٢٦-١٠-١٥) — التعطيل لغير المالك داخل القسم («الردود الجاهزة» تُتصفّح)
            approvalsSection

        case .system:
            // وضع الصيانة
            securitySection
                .disabled(!canEdit)
            // معلومات النظام
            systemInfoSection
            // إعادة تعيين — يبقى مرئيّ بس مُعطّل لغير المالك
            resetSection
                .disabled(!canEdit)
        }
    }

    // MARK: - مسار الموافقات (طلب المالك ٢٠٢٦-١٠-١٥)
    /// مفتاح واحد يرجع للطريقة القديمة فوراً — المالك يعدّل والمدير يقرأ (مثل باقي الإعدادات).
    /// تحته والمسار شغّال («مسار الموافقات ٢»، طلب المالك ٢٠٢٦-١٠-١٦): المسار السريع، المهلة، الردود الجاهزة —
    /// كلٌّ يظهر إذا كان عموده/جدوله على السيرفر
    private var approvalsSection: some View {
        let s = appSettingsVM.settings
        return DSComposerSection(title: L10n.t("طلبات الوارد", "Inbox requests"),
                                 icon: "checkmark.seal.fill",
                                 tint: DS.Color.composerProject,
                                 index: 3) {
            settingToggle(
                icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                color: DS.Color.success,
                title: L10n.t("مسار الموافقات", "Approvals path"),
                subtitle: L10n.t("المختص يراجع ويرفع، المدير يعتمد، والمختص ينفّذ — إطفاؤه يرجّع الطريقة القديمة فوراً",
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
                    Button { templatesOpen = true } label: {
                        DSRow(icon: "text.badge.plus", tint: DS.Color.composerDiwaniya,
                              title: L10n.t("الردود الجاهزة", "Ready replies"),
                              subtitle: L10n.t("ردود قصيرة تظهر فوق ملاحظة القرار", "Short replies above the decision note")) {
                            HStack(spacing: DS.Spacing.xs) {
                                if !adminRequestVM.approvalTemplates.isEmpty {
                                    Text("\(adminRequestVM.approvalTemplates.count)")
                                        .dsFont(.caption)
                                        .foregroundColor(DS.Color.textTertiary)
                                        .monospacedDigit()
                                }
                                DSChevron()
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
            }
        }
        .task { await adminRequestVM.fetchApprovalTemplates() }
    }

    /// عنوان صندوق داخل القسم (قرص + عنوان + وصف) فوق محتواه
    private func approvalsBlock<Content: View>(icon: String, tint: Color, title: String, subtitle: String,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: icon, tint: tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title)
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(subtitle)
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
    }

    /// «المسار السريع»: شرائح الأنواع (اختيار متعدد) — المختار يبدأ عند المدير مباشرة
    private func fastTrackBlock(_ selected: [String]) -> some View {
        approvalsBlock(icon: "bolt.fill", tint: DS.Color.info,
                       title: L10n.t("المسار السريع", "Fast track"),
                       subtitle: L10n.t("هذه الأنواع تروح للمدير مباشرة بلا مراجعة المختص",
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
            slaGroup(L10n.t("المستعجل", "Urgent"), icon: "flame.fill", tint: DS.Color.error, rows: [
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
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
            }
            ForEach(rows, id: \.4) { row in
                HStack(spacing: DS.Spacing.sm) {
                    Text(row.0)
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
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

    private var branchNamesSection: some View {
        DSComposerSection(title: L10n.t("الفروع", "Branches"),
                          icon: "tree.fill",
                          tint: DS.Color.composerProject,
                          trailing: customBranchNamesCount > 0 ? "\(customBranchNamesCount)" : nil,
                          index: 5) {
            Button { branchNamesOpen = true } label: {
                DSRow(icon: "pencil", tint: DS.Color.composerProject,
                       title: L10n.t("أسماء الفروع", "Branch names"),
                       subtitle: L10n.t("اسم يظهر في قائمة اختيار الفرع",
                                        "A name shown in the branch picker list")) {
                    DSChevron()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(DSScaleButtonStyle())
        }
    }

    // MARK: - التصنيفات (طلب المالك)
    private var categoriesSection: some View {
        DSComposerSection(title: L10n.t("التصنيفات", "Categories"),
                          icon: "tag.fill",
                          tint: DS.Color.composerLibrary,
                          index: 4) {
            NavigationLink {
                CategoriesManagerView()
                    .environmentObject(authVM)
            } label: {
                DSRow(icon: "tag.fill", tint: DS.Color.accent,
                       title: L10n.t("تصنيفات الأخبار والمكتبة", "News & library categories"),
                       subtitle: L10n.t("الاسم والأيقونة واللون، والإخفاء والترتيب",
                                        "Name, icon, colour, hide and order")) {
                    DSChevron()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(DSScaleButtonStyle())
        }
    }

    // MARK: - لغة التطبيق الرسمية (طلب المالك)
    //
    // تُطبَّق على كل مستخدم لم يختر لغته بنفسه. من يغيّر اللغة من «الإعدادات»
    // تبقى لغته هو.
    private var languageSection: some View {
        DSComposerSection(title: L10n.t("لغة التطبيق الرسمية", "Official App Language"),
                          icon: "character.bubble.fill",
                          tint: DS.Color.actionNavy,
                          trailing: (appSettingsVM.settings.defaultLanguage ?? "ar") == "ar" ? "العربية" : "English",
                          index: 1) {
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
            .dsFieldFont(.footnote)
            .foregroundColor(DS.Color.fieldValue)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Registration & Membership
    private var registrationSection: some View {
        DSComposerSection(title: L10n.t("التسجيل والعضوية", "Registration & Membership"),
                          icon: "person.badge.key.fill",
                          tint: DS.Color.composerProject,
                          index: 1) {
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
            DSRow(icon: "iphone.gen3.badge.play", tint: DS.Color.info,
                   title: L10n.t("الحد الأقصى للأجهزة", "Max Devices"),
                   subtitle: L10n.t("عدد الأجهزة المسموحة لكل مستخدم", "Devices allowed per user")) {
                HStack(spacing: DS.Spacing.sm) {
                    Text("\(appSettingsVM.settings.maxDevicesPerUser)")
                        .dsFont(.title)
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
            }
        }
    }

    // MARK: - Content Settings
    private var contentSection: some View {
        DSComposerSection(title: L10n.t("الأخبار", "News"),
                          icon: "newspaper.fill",
                          tint: DS.Color.composerLibrary,
                          index: 3) {
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

    // MARK: - Features
    private var featuresSection: some View {
        DSComposerSection(title: L10n.t("الميزات", "Features"),
                          icon: "star.fill",
                          tint: DS.Color.actionNavy,
                          trailing: "\(enabledFeaturesCount)/3",
                          index: 2) {
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

    // MARK: - Security
    private var securitySection: some View {
        DSComposerSection(title: L10n.t("الصيانة", "Maintenance"),
                          icon: "lock.shield.fill",
                          tint: DS.Color.error,
                          trailing: appSettingsVM.settings.maintenanceMode ? L10n.t("مفعّل", "On") : nil,
                          index: 1) {
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
    }

    // MARK: - Edit Cooldown
    private var cooldownSection: some View {
        DSComposerSection(title: L10n.t("عداد التعديل", "Edit Cooldown"),
                          icon: "timer",
                          tint: DS.Color.composerProject,
                          index: 2) {
            // إيقاف / تشغيل العداد
            DSRow(icon: "pause.circle.fill", tint: DS.Color.warning,
                   title: L10n.t("إيقاف العداد", "Disable Cooldown"),
                   subtitle: L10n.t("السماح بالتعديل بدون حد (عادةً 3 تعديلات ثم موافقة الإدارة)",
                                    "Allow unlimited edits (normally 3 edits, then admin approval)")) {
                Toggle("", isOn: $cooldownDisabled)
                    .labelsHidden()
                    .tint(DS.Color.warning)
                    .accessibilityLabel(L10n.t("إيقاف العداد", "Disable Cooldown"))
                    .onChange(of: cooldownDisabled) { newValue in
                        ProfileEditCooldown.shared.isDisabled = newValue
                    }
            }

            // تصفير العداد
            Button { showResetCooldownAlert = true } label: {
                DSRow(icon: "arrow.counterclockwise.circle.fill", tint: DS.Color.warning,
                       title: L10n.t("تصفير العداد", "Reset Cooldown"),
                       subtitle: L10n.t("إعادة عدّاد التعديلات من الصفر", "Reset edit counters")) {
                    DSChevron()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(DSScaleButtonStyle())
        }
    }

    // MARK: - Read-Only Banner
    /// شارة "وضع القراءة فقط" — تظهر للمدير غير المالك
    private var readOnlyBanner: some View {
        DSNoteCard(L10n.t("تقدر تتصفّح الإعدادات. التعديل متاح للمالك فقط.",
                          "You can browse settings. Editing is owner-only."),
                   title: L10n.t("وضع القراءة فقط", "Read-only mode"),
                   icon: "eye.fill")
            .dsStaggerIn(0)
    }

    // MARK: - System Info
    private var systemInfoSection: some View {
        DSComposerSection(title: L10n.t("معلومات النظام", "System Info"),
                          icon: "info.circle.fill",
                          tint: DS.Color.actionNavy,
                          index: 2) {
            // حالة سريعة: التسجيل والصيانة
            HStack(spacing: DS.Spacing.xs) {
                DSStatusChip(
                    text: appSettingsVM.settings.allowNewRegistrations
                        ? L10n.t("التسجيل مفتوح", "Sign-up open")
                        : L10n.t("التسجيل مغلق", "Sign-up closed"),
                    icon: appSettingsVM.settings.allowNewRegistrations ? "person.badge.plus" : "person.fill.xmark",
                    tint: appSettingsVM.settings.allowNewRegistrations ? DS.Color.success : DS.Color.warning
                )
                if appSettingsVM.settings.maintenanceMode {
                    DSStatusChip(text: L10n.t("وضع الصيانة", "Maintenance"),
                                  icon: "wrench.and.screwdriver.fill", tint: DS.Color.error)
                }
                Spacer(minLength: 0)
            }

            infoRow(icon: "app.badge.fill",
                    label: L10n.t("إصدار التطبيق", "App Version"),
                    value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") + " (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
            infoRow(icon: "iphone",
                    label: L10n.t("المنصة", "Platform"),
                    value: UIDevice.current.systemName + " " + UIDevice.current.systemVersion)
            infoRow(icon: "person.3.fill",
                    label: L10n.t("أعضاء العائلة", "Family Members"),
                    value: "\(memberVM.allMembers.filter(\.isCountable).count)")
            infoRow(icon: "person.crop.circle.badge.checkmark",
                    label: L10n.t("مستخدمين مسجلين", "Registered Users"),
                    value: "\(registeredUsersCount)")
            infoRow(icon: "server.rack",
                    label: L10n.t("السيرفر", "Server"),
                    value: "Supabase · Stockholm")
            infoRow(icon: "clock.fill",
                    label: L10n.t("آخر تحديث", "Last Update"),
                    value: formatDate(appSettingsVM.settings.updatedAt))
        }
    }

    // MARK: - Reset
    private var resetSection: some View {
        // الزرّ الواحد بالأحمر (يسأل قبل التنفيذ)
        DSButton(L10n.t("إعادة تعيين الإعدادات", "Reset Settings"), icon: "arrow.counterclockwise",
                 role: .destructive) {
            showResetConfirmation = true
        }
        .dsStaggerIn(3)
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
        DSRow(icon: icon, tint: color, title: title, subtitle: subtitle) {
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
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: DS.Color.actionNavy)
                .accessibilityHidden(true)
            Text(label)
                .dsFieldFont(.sectionTitle)
                .foregroundColor(DS.Color.fieldValue)
                .lineLimit(1)
            Spacer(minLength: DS.Spacing.sm)
            Text(value)
                .dsFieldFont(.rowTitleCompact)
                .foregroundColor(DS.Color.fieldLabel)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .dsRowBox()
        .accessibilityElement(children: .combine)
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
