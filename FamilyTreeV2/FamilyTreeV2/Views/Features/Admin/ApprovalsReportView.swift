import SwiftUI

// MARK: - «تقرير الموافقات» (طلب المالك ٢٠٢٦-١٠-١٦ مسار الموافقات ٢)
//
// من زرّ الرسم في رأس «طلبات المراجعة» ومربّع «النظام» في لوحة الإدارة — للمالك والمدير والمراقب.
// الفترة (هذا الشهر · الشهر الماضي · ٣ شهور) ← الأرقام ← «وقت كل مرحلة» (أشرطة بالساعات على مقياس واحد) ←
// «حسب النوع» ← «أداء الإدارة». الأرقام من `approvals_report` على السيرفر.

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
        case RequestType.joinRequest.rawValue: return L10n.t("انضمام", "Join")
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

    private var canSee: Bool { authVM.isAdmin || authVM.currentUser?.role == .monitor }

    private var periodOptions: [DSSegmentOption<ApprovalsReportPeriod>] {
        [
            DSSegmentOption(id: .thisMonth, title: L10n.t("هذا الشهر", "This month"), icon: "calendar"),
            DSSegmentOption(id: .lastMonth, title: L10n.t("الشهر الماضي", "Last month"), icon: "calendar.badge.clock"),
            DSSegmentOption(id: .threeMonths, title: L10n.t("3 شهور", "3 months"), icon: "calendar.day.timeline.left")
        ]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.lg) {
                if canSee {
                    DSSegmentedSwitch(options: periodOptions, selection: $vm.period, size: .regular)
                        .dsStaggerIn(0)
                    content
                } else {
                    DSEmptyView(L10n.t("للمالك والمدير والمراقب", "For the owner, admins and monitors"),
                                message: L10n.t("تقرير الموافقات لفريق الشجرة والأعضاء.", "The approvals report is for the tree team."),
                                style: .card)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xxxl)
            .dsLandscapeReadable()
        }
        .dsSubPageHeader(L10n.t("تقرير الموافقات", "Approvals report"), subtitle: periodSubtitle)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task(id: vm.period) {
            guard canSee else { return }
            await vm.load()
        }
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

    @ViewBuilder private var content: some View {
        switch vm.state {
        case .idle:
            loader
        case .loading where vm.report == ApprovalsReport():
            loader
        case .unavailable:
            DSEmptyView(L10n.t("التقرير يحتاج تحديث السيرفر", "The report needs a server update"),
                        message: L10n.t("يظهر بعد تحديث السيرفر لمسار الموافقات.", "It appears after the approvals server update."),
                        icon: "chart.bar.xaxis", style: .card)
        case .failed(let message):
            DSStateCard(icon: "exclamationmark.triangle.fill", title: message, tint: DS.Color.warning,
                        actionTitle: L10n.t("إعادة المحاولة", "Try again")) {
                Task { await vm.load() }
            }
        default:
            report
                .opacity(vm.state == .loading ? DS.Opacity.disabled : 1)
                .animation(.easeInOut(duration: 0.2), value: vm.state)
        }
    }

    private var loader: some View {
        DSPageLoader(L10n.t("جارٍ تجهيز التقرير…", "Preparing the report…"), fillsSpace: false)
            .padding(.top, DS.Spacing.xl)
    }

    // MARK: التقرير

    @ViewBuilder private var report: some View {
        let t = vm.report.totals
        VStack(spacing: DS.Spacing.sm) {
            DSStatsRow([
                DSHeroStat(value: "\(t.submitted)", label: L10n.t("مقدّمة", "Submitted"), icon: "tray.and.arrow.down.fill"),
                DSHeroStat(value: "\(t.executed)", label: L10n.t("منفّذة", "Done"), icon: "checkmark.seal.fill"),
                DSHeroStat(value: "\(t.rejected)", label: L10n.t("مرفوضة", "Rejected"), icon: "xmark.circle.fill"),
                DSHeroStat(value: "\(t.pending)", label: L10n.t("معلّقة", "Pending"), icon: "hourglass")
            ])
            DSStatsRow([
                DSHeroStat(value: "\(t.urgent)", label: L10n.t("مستعجلة", "Urgent"), icon: "flame.fill"),
                DSHeroStat(value: "\(t.escalated)", label: L10n.t("متصعّدة", "Escalated"), icon: "arrow.up.forward.circle.fill"),
                DSHeroStat(value: "\(t.fastTrack)", label: L10n.t("مسار سريع", "Fast track"), icon: "bolt.fill"),
                DSHeroStat(value: "\(t.overdueNow)", label: L10n.t("متأخرة الآن", "Late now"), icon: "exclamationmark.circle.fill")
            ], tint: DS.Color.warning)
        }
        .dsStaggerIn(1)

        if t.submitted == 0 && vm.report.types.isEmpty && vm.report.staff.isEmpty {
            DSEmptyView(L10n.t("لا طلبات في هذه الفترة", "No requests in this period"),
                        message: L10n.t("جرّب فترة أطول.", "Try a longer period."), style: .card)
        } else {
            stagesSection
            typesSection
            staffSection
        }
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
            StageBar(id: "review", title: L10n.t("مراجعة المختص", "Specialist review"), hours: s.reviewHours, tint: ApprovalStage.review.tint),
            StageBar(id: "approve", title: L10n.t("اعتماد المدير", "Manager approval"), hours: s.approveHours, tint: ApprovalStage.approve.tint),
            StageBar(id: "execute", title: L10n.t("التنفيذ", "Carrying out"), hours: s.executeHours, tint: ApprovalStage.execute.tint),
            StageBar(id: "info", title: L10n.t("ردّ العضو", "Member's reply"), hours: s.infoHours, tint: ApprovalStage.info.tint)
        ]
    }

    private var stagesSection: some View {
        let bars = stageBars
        let maxHours = max(bars.compactMap(\.hours).max() ?? 0, 0.0001)
        return DSComposerSection(title: L10n.t("وقت كل مرحلة", "Time per stage"), icon: "clock.fill",
                                 tint: DS.Color.actionNavy, trailing: L10n.t("متوسط", "Average"), index: 2) {
            VStack(spacing: DS.Spacing.md) {
                ForEach(bars) { bar in
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        HStack {
                            Text(bar.title)
                                .dsFieldFont(.subtitle)
                                .foregroundColor(DS.Color.fieldLabel)
                            Spacer(minLength: DS.Spacing.sm)
                            Text(Self.hoursText(bar.hours))
                                .dsFieldFont(.rowTitleCompact)
                                .foregroundColor(DS.Color.fieldLabel)
                                .monospacedDigit()
                        }
                        // الشريط على مقياس واحد (أطول مرحلة = العرض كاملاً)
                        GeometryReader { geo in
                            let fraction = CGFloat((bar.hours ?? 0) / maxHours)
                            Capsule()
                                .fill(bar.tint.dsReadableGlyph)
                                .frame(width: bar.hours == nil ? 0 : max(DS.Spacing.sm, geo.size.width * fraction))
                        }
                        .frame(height: DS.Spacing.sm)
                        .background(Capsule().fill(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke)))
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
        return DSComposerSection(title: L10n.t("حسب النوع", "By type"), icon: "square.grid.2x2.fill",
                                 tint: DS.Color.actionNavy, trailing: rows.isEmpty ? nil : "\(rows.count)", index: 3) {
            if rows.isEmpty {
                Text(L10n.t("لا بيانات.", "No data."))
                    .dsFieldFont(.footnote)
                    .foregroundColor(DS.Color.fieldValue)
            } else {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(rows) { row in typeRow(row) }
                }
            }
        }
    }

    private func typeRow(_ row: ApprovalsReport.TypeRow) -> some View {
        let pending = max(0, row.count - row.executed - row.rejected)
        let title = row.label.flatMap { $0.isEmpty ? nil : $0 } ?? ApprovalTypeTitle.title(row.type)
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: ApprovalTypeTitle.icon(row.type), tint: DS.Color.actionNavy)
                    .accessibilityHidden(true)
                Text(title)
                    .dsFieldFont(.rowTitleCompact)
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1)
                Spacer(minLength: DS.Spacing.sm)
                Text("\(row.count)")
                    .dsFont(.statValue)
                    .foregroundColor(DS.Color.fieldLabel)
                    .monospacedDigit()
            }
            DSDistributionBar(segments: [
                .init(id: "done", value: row.executed, tint: DS.Color.success),
                .init(id: "rejected", value: row.rejected, tint: DS.Color.reject),
                .init(id: "pending", value: pending, tint: DS.Color.warning)
            ], height: DS.Spacing.sm)
            Text(L10n.t("منفّذة \(row.executed) · مرفوضة \(row.rejected) · معلّقة \(pending)",
                        "Done \(row.executed) · Rejected \(row.rejected) · Pending \(pending)"))
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
        }
        .dsRowBox()
        .accessibilityElement(children: .combine)
    }

    // MARK: أداء الإدارة

    private var staffSection: some View {
        let rows = vm.report.staff.sorted { $0.actions > $1.actions }
        return DSComposerSection(title: L10n.t("أداء الإدارة", "Team performance"), icon: "person.3.fill",
                                 tint: DS.Color.actionNavy, trailing: rows.isEmpty ? nil : "\(rows.count)", index: 4) {
            if rows.isEmpty {
                Text(L10n.t("لا إجراءات في هذه الفترة.", "No actions in this period."))
                    .dsFieldFont(.footnote)
                    .foregroundColor(DS.Color.fieldValue)
            } else {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(rows) { row in staffRow(row) }
                }
            }
        }
    }

    private func staffRow(_ row: ApprovalsReport.StaffRow) -> some View {
        let member = row.memberId.flatMap { memberVM.member(byId: $0) }
        let name = row.name.flatMap { $0.isEmpty ? nil : $0 } ?? member?.firstName ?? "—"
        let role = row.role.flatMap(FamilyMember.UserRole.init(rawValue:)) ?? member?.role
        return HStack(alignment: .center, spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(name)
                        .dsFieldFont(.rowTitleCompact)
                        .foregroundColor(DS.Color.fieldLabel)
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
        .dsRowBox()
        .accessibilityElement(children: .combine)
    }
}
