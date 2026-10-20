import SwiftUI

// MARK: - «إعدادات مسار الموافقات» — بيتها الوحيد ⚙︎ «الوارد»
//
// كانت هذه الصفحة «إعدادات التطبيق» كلها (٩ نطاقات + «كل الإعدادات في صفحة واحدة» بثلاث شرائح). منذ الدفعة ج من «نفّذ كل
// المقترح» (٢٠٢٦-١٠-٢٠): إعدادات التطبيق صارت صفحة قسم «التطبيق» نفسها (`AdminAppAreaPage`، المفاتيح في مكانها)، و«السماح
// بالتسجيل» في «التسجيل والمنع» و«عدد الأجهزة المسموح لكل عضو» في «الأجهزة ووصول الإشعارات» (الفريق والأمان). بقي هنا نطاق
// مسار الموافقات وحده (رأس كحلي بحال المسار وأرقامه ثم قسم «طلبات الوارد») — المالك يعدّل، والمدير يقرأ.
struct AdminAppSettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    /// «مسار الموافقات ٢»: الردود الجاهزة
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    /// مربّع «الردود الجاهزة» («مسار الموافقات ٢»)
    @State private var templatesOpen = false

    /// النطاق الباقي (يُبقي نداء ⚙︎ «الوارد» كما هو)
    enum Scope: Hashable {
        case approvals
    }

    init(scope: Scope = .approvals) {}

    /// المالك يعدّل، باقي المدراء يتصفّحون فقط.
    private var canEdit: Bool { authVM.canManageSettings }

    var body: some View {
        approvalsPage
    }

    // MARK: - مسار الموافقات (طلب المالك ٢٠٢٦-١٠-١٥)
    /// مفتاح واحد يرجع للطريقة القديمة فوراً — المالك يعدّل والمدير يقرأ (مثل باقي الإعدادات).
    /// تحته والمسار شغّال («مسار الموافقات ٢»، طلب المالك ٢٠٢٦-١٠-١٦): المسار السريع، المهلة، الردود الجاهزة —
    /// كلٌّ يظهر إذا كان عموده/جدوله على السيرفر
    private var approvalsSection: some View {
        let s = appSettingsVM.settings
        return AdminSectionCard(title: L10n.t("طلبات الوارد", "Inbox requests")) {
            AdminRowsCardBody {
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
                        AdminTapRow(icon: "text.badge.plus", tint: DS.Color.composerDiwaniya,
                                    title: L10n.t("الردود الجاهزة", "Ready replies"),
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
                         L10n.t("مسار سريع", "Fast track"), icon: "bolt.fill"),
            AdminPageKPI(running ? s.approvalsSlaHours.map { L10n.t("\(Int($0)) س", "\(Int($0))h") } ?? "—" : "—",
                         L10n.t("تذكير بعد", "Remind after"), icon: "timer")
        ]
        if running && templatesKnown {
            kpis.append(AdminPageKPI("\(adminRequestVM.approvalTemplates.count)", L10n.t("ردود جاهزة", "Replies"),
                                     icon: "text.badge.plus", tap: .action { templatesOpen = true }))
        }
        return AdminPageHeader(
            title: L10n.t("إعدادات المسار", "Approval Path Settings"),
            subtitle: L10n.t("مسار الموافقات، المهلة، المسار السريع، الردود الجاهزة",
                             "Approvals path, SLA, fast track, ready replies"),
            glyph: "gearshape.fill",
            readOnly: !canEdit,
            kpis: kpis)
    }
}
