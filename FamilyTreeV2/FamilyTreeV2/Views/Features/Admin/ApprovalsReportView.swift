import SwiftUI

// MARK: - «تقرير الموافقات» (طلب المالك ٢٠٢٦-١٠-١٦ مسار الموافقات ٢)
//
// بيته الوحيد «المؤشرات ← الموافقات» (الدفعة ج، ٢٠٢٦-١٠-٢٠؛ كان أيضاً في رأس «الوارد» وصفّه ومربّع «منجز هذا الأسبوع») —
// للمالك والمدير والمراقب.
// الفترة (هذا الشهر · الشهر الماضي · ٣ شهور) ← الأرقام ← «وقت كل مرحلة» (أشرطة بالساعات على مقياس واحد) ←
// «حسب النوع» ← «أداء الإدارة». الأرقام من `approvals_report` على السيرفر.
// بشكل «اليوم» (٢٠٢٦-١٠-٢٠): الفترة شرائح في الرأس الكحلي وأهم أربعة أرقام مربّعاته، والباقي بطاقات بيضاء.

/// أسماء أنواع الطلبات في المسار — مكان واحد للتقرير وإعداد «المسار السريع»
enum ApprovalTypeTitle {
    /// أنواع المسار بترتيب العرض (رسائل التواصل خارج المسار)
    static let workflowTypes: [String] = [
        RequestType.childAdd.rawValue, RequestType.treeEdit.rawValue, RequestType.deceasedReport.rawValue,
        RequestType.nameChange.rawValue, RequestType.familyChange.rawValue, RequestType.phoneChange.rawValue,
        RequestType.photoSuggestion.rawValue, RequestType.newsReport.rawValue, RequestType.contentReport.rawValue,
        RequestType.joinRequest.rawValue, RequestType.linkRequest.rawValue
    ]

    static func title(_ type: String) -> String {
        switch type {
        case RequestType.childAdd.rawValue: return L10n.t("إضافة ابن", "Add child")
        case RequestType.treeEdit.rawValue: return L10n.t("تعديل الشجرة", "Tree edit")
        case RequestType.deceasedReport.rawValue: return L10n.t("بلاغ وفاة", "Death report")
        case RequestType.nameChange.rawValue: return L10n.t("تغيير اسم", "Name change")
        case RequestType.familyChange.rawValue: return L10n.t("تغيير العائلة", "Family change")
        case RequestType.phoneChange.rawValue: return L10n.t("تغيير رقم", "Phone change")
        case RequestType.photoSuggestion.rawValue: return L10n.t("صورة مقترحة", "Suggested photo")
        case RequestType.newsReport.rawValue: return L10n.t("بلاغ عن خبر", "News report")
        case RequestType.contentReport.rawValue: return L10n.t("بلاغ محتوى", "Content report")
        case RequestType.joinRequest.rawValue: return L10n.t("طلب انضمام", "Join request")
        case RequestType.linkRequest.rawValue: return L10n.t("ربط بالشجرة", "Link to tree")
        default: return type
        }
    }

    static func icon(_ type: String) -> String {
        switch type {
        case RequestType.childAdd.rawValue: return "person.badge.plus"
        case RequestType.treeEdit.rawValue: return "arrow.triangle.branch"
        case RequestType.deceasedReport.rawValue: return "heart.slash.fill"
        case RequestType.nameChange.rawValue, RequestType.familyChange.rawValue: return "character.cursor.ibeam"
        case RequestType.phoneChange.rawValue: return "phone.arrow.right"
        case RequestType.photoSuggestion.rawValue: return "photo.fill"
        case RequestType.newsReport.rawValue, RequestType.contentReport.rawValue: return "exclamationmark.bubble.fill"
        case RequestType.joinRequest.rawValue, RequestType.linkRequest.rawValue: return "person.badge.clock.fill"
        default: return "doc.text.fill"
        }
    }
}

struct ApprovalsReportView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @StateObject private var vm: ApprovalsReportViewModel

    init(viewModel: ApprovalsReportViewModel? = nil) {
        _vm = StateObject(wrappedValue: viewModel ?? ApprovalsReportViewModel())
    }

    /// «المؤشرات» للمالك والمدير (أُخفيت عن المراقب ٢٠٢٦-١٠-٢٤)
    private var canSee: Bool { authVM.canViewInsights }

    private var periodOptions: [DSSegmentOption<ApprovalsReportPeriod>] {
        [
            DSSegmentOption(id: .thisMonth, title: L10n.t("هذا الشهر", "This month"), icon: "calendar"),
            DSSegmentOption(id: .lastMonth, title: L10n.t("الشهر الماضي", "Last month"), icon: "calendar.badge.clock"),
            DSSegmentOption(id: .threeMonths, title: L10n.t("3 شهور", "3 months"), icon: "calendar.day.timeline.left")
        ]
    }

    var body: some View {
        // بشكل «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠، `AdminPageKit`): رأس كحلي بأرقام الفترة وشرائحها ← بطاقة
        // «ملخص الفترة» تصعد فوقه ← «وقت كل مرحلة» ← «حسب النوع» ← «أداء الإدارة»
        AdminPage(header: header, lead: AnyView(leadCard), content: AnyView(cards))
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .task(id: vm.period) {
                guard canSee else { return }
                await vm.load()
            }
    }

    /// الأرقام من التقرير المحمّل — «—» قبل وصوله (أو بعد الفشل)
    private var loaded: Bool {
        switch vm.state {
        case .idle, .unavailable, .failed: return false
        case .loading: return vm.report != ApprovalsReport()
        default: return true
        }
    }

    private var header: AdminPageHeader {
        let t = vm.report.totals
        let ready = canSee && loaded
        return AdminPageHeader(
            title: L10n.t("تقرير الموافقات", "Approvals report"),
            subtitle: periodSubtitle,
            glyph: "chart.bar.xaxis",
            kpis: canSee ? [
                AdminPageKPI(AdminPageKPI.count(t.submitted, ready: ready), L10n.t("مقدّمة", "Submitted"),
                             icon: "tray.and.arrow.down.fill"),
                AdminPageKPI(AdminPageKPI.count(t.executed, ready: ready), L10n.t("منفّذة", "Done"),
                             icon: "checkmark.seal.fill", tint: DS.Hub.kpiMine),
                AdminPageKPI(AdminPageKPI.count(t.pending, ready: ready), L10n.t("معلّقة", "Pending"),
                             icon: "hourglass", tint: DS.Hub.kpiLate),
                AdminPageKPI(AdminPageKPI.count(t.overdueNow, ready: ready), L10n.t("متأخرة الآن", "Late now"),
                             icon: "exclamationmark.circle.fill", tint: DS.Hub.kpiHot)
            ] : [],
            chips: canSee ? periodOptions.map { option in
                AdminPageChip(id: option.id.rawValue, title: option.title, icon: option.icon,
                              selected: vm.period == option.id) { vm.period = option.id }
            } : [])
    }

    /// «١ أكتوبر – ١٦ أكتوبر»
    private var periodSubtitle: String {
        let range = vm.period.range()
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        f.setLocalizedDateFormatFromTemplate("d MMM")
        // «إلى» حصرية: آخر يوم = قبلها بلحظة
        return "\(f.string(from: range.from)) – \(f.string(from: range.to.addingTimeInterval(-1)))"
    }

    /// أول بطاقة (تصعد فوق الرأس): الصلاحية، التحميل، الحالات، أو «ملخص الفترة»
    private var leadCard: AnyView {
        guard canSee else {
            return AnyView(AdminPageStateCard(.empty(L10n.t("للمالك والمدير", "For the owner and admins"),
                                                     message: L10n.t("تقرير الموافقات من «المؤشرات».",
                                                                     "The approvals report lives in Insights."))))
        }
        switch vm.state {
        case .idle:
            return loader
        case .loading where vm.report == ApprovalsReport():
            return loader
        case .unavailable:
            return AnyView(AdminPageStateCard(.empty(L10n.t("التقرير يحتاج تحديث السيرفر", "The report needs a server update"),
                                                     message: L10n.t("يظهر بعد تحديث السيرفر لمسار الموافقات.",
                                                                     "It appears after the approvals server update."))))
        case .failed(let message):
            return AnyView(AdminPageStateCard(.error(message, retry: { Task { await vm.load() } })))
        default:
            return AnyView(summaryCard
                .opacity(vm.state == .loading ? DS.Opacity.disabled : 1)
                .animation(.easeInOut(duration: 0.2), value: vm.state))
        }
    }

    private var loader: AnyView {
        AnyView(AdminPageStateCard(.loading(L10n.t("جارٍ تجهيز التقرير…", "Preparing the report…"))))
    }

    /// باقي أرقام الفترة (الأربعة الأولى في الرأس) — كل رقم صفّ بشارته
    private var summaryCard: some View {
        let t = vm.report.totals
        return AdminSectionCard(title: L10n.t("ملخص الفترة", "Period summary"), spacing: 0) {
            AdminRowsCardBody {
                AdminTapRow(icon: "xmark.circle.fill", tint: DS.Color.reject, title: L10n.t("مرفوضة", "Rejected"),
                            value: "\(t.rejected)", valueTint: DS.Color.reject)
                AdminTapRow(icon: "flame.fill", tint: DS.Color.error, title: L10n.t("عاجلة", "Urgent"),
                            value: "\(t.urgent)", valueTint: DS.Color.error)
                AdminTapRow(icon: "arrow.up.forward.circle.fill", tint: DS.Color.warning,
                            title: L10n.t("متصعّدة", "Escalated"), value: "\(t.escalated)", valueTint: DS.Color.warning)
                AdminTapRow(icon: "bolt.fill", tint: DS.Color.info, title: L10n.t("الاعتماد المباشر", "Direct approval"),
                            value: "\(t.fastTrack)", valueTint: DS.Color.info)
            }
        }
    }

    /// البطاقات بعد الملخص — أو «لا طلبات» إن خلت الفترة
    private var cards: AnyView {
        guard canSee, loaded else { return AnyView(EmptyView()) }
        let t = vm.report.totals
        if t.submitted == 0 && vm.report.types.isEmpty && vm.report.staff.isEmpty {
            return AnyView(AdminPageStateCard(.empty(L10n.t("لا طلبات في هذه الفترة", "No requests in this period"),
                                                     message: L10n.t("جرّب فترة أطول.", "Try a longer period."))))
        }
        return AnyView(VStack(spacing: DS.Hub.stackSpacing) {
            AnyView(stagesSection)
            AnyView(typesSection)
            AnyView(staffSection)
        }
        .opacity(vm.state == .loading ? DS.Opacity.disabled : 1))
    }

    // MARK: وقت كل مرحلة

    private struct StageBar: Identifiable {
        let id: String
        let title: String
        let hours: Double?
        let tint: Color
    }

    private var stageBars: [StageBar] {
        let s = vm.report.stages
        return [
            StageBar(id: "review", title: L10n.t("المراجعة", "Review"), hours: s.reviewHours, tint: ApprovalStage.review.tint),
            StageBar(id: "approve", title: L10n.t("اعتماد المدير", "Manager approval"), hours: s.approveHours, tint: ApprovalStage.approve.tint),
            StageBar(id: "execute", title: L10n.t("التنفيذ", "Carrying out"), hours: s.executeHours, tint: ApprovalStage.execute.tint),
            StageBar(id: "info", title: L10n.t("ردّ العضو", "Member's reply"), hours: s.infoHours, tint: ApprovalStage.info.tint)
        ]
    }

    private var stagesSection: some View {
        let bars = stageBars
        let maxHours = max(bars.compactMap(\.hours).max() ?? 0, 0.0001)
        return AdminSectionCard(title: L10n.t("وقت كل مرحلة", "Time per stage"), tag: L10n.t("متوسط", "Average")) {
            VStack(spacing: DS.Spacing.md) {
                ForEach(bars) { bar in
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        HStack {
                            Text(bar.title)
                                .dsFont(.subtitle)
                                .foregroundColor(DS.Color.textPrimary)
                            Spacer(minLength: DS.Spacing.sm)
                            Text(Self.hoursText(bar.hours))
                                .dsFont(.hubRow)
                                .foregroundColor(DS.Color.textPrimary)
                                .monospacedDigit()
                        }
                        // مقارنة أطوال على مقياس واحد (أطول مرحلة = العرض كاملاً) — الشريط الموحّد لا الحلقة (الدفعة ١٠)
                        DSMeterBar(progress: bar.hours.map { $0 / maxHours }, tint: bar.tint.dsReadableGlyph,
                                   track: DS.Ring.emptyTrack)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(bar.title): \(Self.hoursText(bar.hours))")
                }
            }
        }
    }

    /// «٣٫٥ ساعة» / «٤٥ دقيقة» / «٢٫٣ يوم» — «—» بلا بيانات
    static func hoursText(_ hours: Double?) -> String {
        guard let hours, hours >= 0 else { return "—" }
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        nf.maximumFractionDigits = 1
        nf.minimumFractionDigits = 0
        func n(_ v: Double) -> String { nf.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v) }
        if hours < 1 {
            let minutes = max(1, (hours * 60).rounded())
            return L10n.t("\(n(minutes)) دقيقة", "\(n(minutes)) min")
        }
        if hours < 48 { return L10n.t("\(n(hours)) ساعة", "\(n(hours)) h") }
        return L10n.t("\(n(hours / 24)) يوم", "\(n(hours / 24)) d")
    }

    // MARK: حسب النوع

    private var typesSection: some View {
        let rows = vm.report.types.sorted { $0.count > $1.count }
        return AdminSectionCard(title: L10n.t("حسب النوع", "By type"), badge: rows.isEmpty ? nil : rows.count,
                                badgeTint: DS.Color.textSecondary, spacing: 0) {
            if rows.isEmpty {
                Text(L10n.t("لا بيانات.", "No data."))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
            } else {
                AdminRowsCardBody {
                    ForEach(rows) { row in typeRow(row) }
                }
            }
        }
    }

    private func typeRow(_ row: ApprovalsReport.TypeRow) -> some View {
        let pending = max(0, row.count - row.executed - row.rejected)
        let title = row.label.flatMap { $0.isEmpty ? nil : $0 } ?? ApprovalTypeTitle.title(row.type)
        let legend = L10n.t("منفّذة \(row.executed) · مرفوضة \(row.rejected) · معلّقة \(pending)",
                            "Done \(row.executed) · Rejected \(row.rejected) · Pending \(pending)")
        // صفّ الحلقة الموحّد (الدفعة ١٠، كان شريطاً): منفّذة · مرفوضة · معلّقة بألوان المعنى والعدد في وسطها
        return DSGaugeRow(gauge: DSRingGauge(parts: DSGaugePart.counts([("done", row.executed, DS.Color.success),
                                                                       ("rejected", row.rejected, DS.Color.reject),
                                                                       ("pending", pending, DS.Color.warning)]),
                                             size: DS.Ring.small, track: DS.Ring.emptyTrack, center: .count(row.count)),
                          title: title, subtitle: legend,
                          spoken: L10n.t("\(title): \(row.count)، \(legend)", "\(title): \(row.count), \(legend)"))
            .padding(.vertical, DS.Spacing.sm)
    }

    // MARK: أداء الإدارة

    private var staffSection: some View {
        let rows = vm.report.staff.sorted { $0.actions > $1.actions }
        return AdminSectionCard(title: L10n.t("أداء الإدارة", "Team performance"), badge: rows.isEmpty ? nil : rows.count,
                                badgeTint: DS.Color.textSecondary, spacing: 0) {
            if rows.isEmpty {
                Text(L10n.t("لا إجراءات في هذه الفترة.", "No actions in this period."))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
            } else {
                AdminRowsCardBody {
                    ForEach(rows) { row in staffRow(row) }
                }
            }
        }
    }

    private func staffRow(_ row: ApprovalsReport.StaffRow) -> some View {
        let member = row.memberId.flatMap { memberVM.member(byId: $0) }
        let name = row.name.flatMap { $0.isEmpty ? nil : $0 } ?? member?.firstName ?? "—"
        let role = row.role.flatMap(FamilyMember.UserRole.init(rawValue:)) ?? member?.role
        return HStack(alignment: .center, spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: "person.fill", tint: role?.color ?? DS.Color.primary)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(name)
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                    if let role {
                        DSStatusChip(text: AdminRequestViewModel.approvalRoleTitle(role), tint: role.color, size: .mini)
                    }
                }
                Text(L10n.t("إجراءات \(row.actions) · متوسط الرد \(Self.hoursText(row.avgResponseHours))",
                            "\(row.actions) actions · avg reply \(Self.hoursText(row.avgResponseHours))"))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Spacing.xs)
            if row.escalations > 0 {
                DSStatusChip(text: L10n.t("تصعيد \(row.escalations)", "\(row.escalations) escalated"),
                             icon: "arrow.up.forward.circle.fill", tint: DS.Color.error, size: .mini)
            }
        }
        .padding(.vertical, DS.Spacing.sm + DS.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}
