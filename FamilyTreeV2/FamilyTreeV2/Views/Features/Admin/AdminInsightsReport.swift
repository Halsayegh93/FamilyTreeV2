import SwiftUI
import Supabase
import Combine

// MARK: - «المؤشرات» = التقرير نفسه (الاتجاه «أ» «تقرير الشهر في صفحة القسم»، موافقة المالك ٢٠٢٦-١١-٠٧)
//
// بطاقتان، كل واحدة خلاصة بيتها وتنتهي بزرّ إليه:
//   العائلة — حلقة الأحياء/المتوفين بالعدد الكلي، المسجّلون في التطبيق، أعمدة آخر ٦ أشهر ← «إحصاءات العائلة» (`AdminAnalyticsView`)
//   الموافقات — حلقة انقبلت/انرفضت/تنتظر لآخر ٣٠ يوماً + أكثر الطلبات ← «تقرير الموافقات» (`ApprovalsReportView`)
// نفس مصادر الصفحتين بلا دوال سيرفر جديدة: الأعضاء المحمّلة + `WomenStore` + `app_usage_stats` (`AdminMemberCounts`)،
// و`approvals_report(p_from, p_to)` بفترة ٣٠ يوماً.

extension DS.Chart {
    /// أعمدة النمو المصغّرة في بطاقة «العائلة» بصفحة «المؤشرات»
    static let compactColumnHeight: CGFloat = 40
}

/// عنوان صغير فوق بطاقة الصفحة («العائلة»، «الموافقات»)
private struct InsightsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title)
                .dsFont(.sectionTitle)
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityAddTraits(.isHeader)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .adminCard()
        }
    }
}

/// صفّ المفتاح: نقطة اللون + الاسم … العدد في الطرف
private struct InsightsLegendRow: View {
    let label: String
    let value: Int?
    let tint: Color

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Circle()
                .fill(tint)
                .frame(width: DS.Icon.legendDotCompact, height: DS.Icon.legendDotCompact)
                .accessibilityHidden(true)
            Text(label)
                .dsFont(.label)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Spacing.sm)
            Text(verbatim: value.map { $0.formatted() } ?? "—")
                .dsFont(.caption)
                .monospacedDigit()
                .foregroundColor(DS.Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// الحلقة بجانب مفتاحها — فوقه من أحجام إمكانية الوصول
private struct InsightsRingBlock: View {
    let ring: DSRingGauge
    let rows: [InsightsLegendRow]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let legend = VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in row }
        }
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                ring
                legend
            }
        } else {
            HStack(alignment: .center, spacing: DS.Spacing.lg) {
                ring
                legend
            }
        }
    }
}

/// زرّ آخر البطاقة إلى الصفحة الكاملة — فوقه خطّ رفيع
private struct InsightsFooterLink: View {
    let title: String
    let make: () -> AnyView

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            AdminTapWrap(tap: .page(make), feel: .plain,
                         label: AnyView(AdminCardLinkLabel(title: title).frame(maxWidth: .infinity)))
        }
    }
}

// MARK: - بطاقة «العائلة»

struct AdminInsightsFamilyCard: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @State private var counts = AdminMemberCounts()
    @State private var usage: AppUsageStats? = AppUsageStats.cached

    var body: some View {
        let growth = Self.monthlyGrowth(memberVM.allMembers)
        InsightsGroup(title: L10n.t("العائلة", "The family")) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                InsightsRingBlock(
                    ring: DSRingGauge(progress: progress, tint: DS.Color.accent, size: DS.Ring.medium,
                                      track: DS.Ring.restTrack, center: .count(counts.total),
                                      caption: L10n.t("فرد", "people")),
                    rows: [
                        InsightsLegendRow(label: L10n.t("أحياء", "Living"), value: counts.totalAlive, tint: DS.Color.accent),
                        InsightsLegendRow(label: L10n.t("متوفون", "Deceased"), value: counts.totalDeceased,
                                          tint: DS.Color.deceased),
                        InsightsLegendRow(label: L10n.t("مسجّلون في التطبيق", "Registered in the app"),
                                          value: counts.accounts, tint: DS.Color.success)
                    ])
                HStack(alignment: .bottom, spacing: DS.Spacing.md) {
                    InsightsGrowthColumns(months: growth, tint: DS.Color.sea)
                    VStack(spacing: DS.Spacing.xxs) {
                        Text(verbatim: Self.signed(growth.last?.count ?? 0))
                            .dsFont(.hubKPI)
                            .monospacedDigit()
                            .foregroundColor(DS.Color.sea)
                        Text(L10n.t("انضافوا هالشهر", "added this month"))
                            .dsFont(.micro)
                            .foregroundColor(DS.Color.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .accessibilityElement(children: .combine)
                }
                InsightsFooterLink(title: L10n.t("إحصاءات العائلة كاملة", "Full family statistics")) {
                    AnyView(AdminAnalyticsView())
                }
            }
        }
        .onAppear { counts = AdminMemberCounts.seeded(members: memberVM.allMembers); counts.setUsage(usage) }
        .onChange(of: memberVM.allMembers.count) { _ in refreshCounts() }
        .task { await load() }
    }

    private var progress: Double? {
        guard let total = counts.total, let alive = counts.totalAlive, total > 0 else { return nil }
        return Double(alive) / Double(total)
    }

    private func refreshCounts() {
        var c = AdminMemberCounts.seeded(members: memberVM.allMembers)
        c.setUsage(usage)
        counts = c
    }

    private func load() async {
        if WomenStore.cache.isEmpty { _ = try? await WomenStore.fetch() }
        if let u = await AppUsageStats.fetch() { usage = u }
        refreshCounts()
    }

    private static func signed(_ n: Int) -> String {
        n > 0 ? "\u{2066}+\(n.formatted())\u{2069}" : "0"
    }

    /// آخر ٦ أشهر — نفس حساب «نمو الأعضاء» في «إحصاءات العائلة» (تاريخ الإنشاء، السجلّات بلا اسم لا تُعدّ)
    static func monthlyGrowth(_ members: [FamilyMember]) -> [(label: String, count: Int)] {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        parser.locale = Locale(identifier: "en_US_POSIX")
        let calendar = Calendar.current
        let now = Date()
        var perMonth: [Int: Int] = [:]
        for member in members where member.hasName {
            guard let created = member.createdAt,
                  let date = parser.date(from: String(created.prefix(19))) else { continue }
            let c = calendar.dateComponents([.year, .month], from: date)
            guard let year = c.year, let month = c.month else { continue }
            perMonth[year * 100 + month, default: 0] += 1
        }
        return (0..<6).reversed().map { offset in
            guard let start = calendar.date(byAdding: .month, value: -offset, to: now) else { return ("", 0) }
            let c = calendar.dateComponents([.year, .month], from: start)
            let month = c.month ?? 1
            return (calendar.shortMonthSymbols[(month - 1) % 12], perMonth[(c.year ?? 0) * 100 + month] ?? 0)
        }
    }
}

/// أعمدة صغيرة لكل شهر — الحالي بلونه كاملاً والسابقة أخفّ، ترتفع مرة عند الظهور (ثابتة مع «تقليل الحركة»)
private struct InsightsGrowthColumns: View {
    let months: [(label: String, count: Int)]
    let tint: Color
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let maxCount = max(months.map(\.count).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: DS.Spacing.xs) {
            ForEach(Array(months.enumerated()), id: \.offset) { index, month in
                let isCurrent = index == months.count - 1
                VStack(spacing: DS.Spacing.xxs) {
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(isCurrent ? tint : DS.Ring.restTrack)
                        .frame(height: shown || reduceMotion
                               ? max(CGFloat(month.count) / CGFloat(maxCount) * DS.Chart.compactColumnHeight,
                                     DS.Chart.columnMinHeight)
                               : DS.Chart.columnMinHeight)
                    Text(month.label)
                        .dsFont(.micro)
                        .foregroundColor(isCurrent ? DS.Color.textSecondary : DS.Color.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(month.label): \(month.count.formatted())"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .onAppear {
            guard !reduceMotion else { shown = true; return }
            withAnimation(DS.Ring.fill.delay(DS.Ring.fillDelay)) { shown = true }
        }
    }
}

// MARK: - بطاقة «الموافقات» (آخر ٣٠ يوماً)

@MainActor
final class AdminInsightsApprovalsStore: ObservableObject {
    enum State: Equatable { case loading, loaded, unavailable, failed }

    @Published var report = ApprovalsReport()
    @Published var state: State = .loading

    /// نفس `approvals_report` في «تقرير الموافقات» — من قبل ٣٠ يوماً إلى الآن
    func load() async {
        nonisolated struct Params: Encodable { let p_from: String; let p_to: String }
        let now = Date()
        let from = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let iso = ISO8601DateFormatter()
        do {
            let result: ApprovalsReport = try await SupabaseConfig.client
                .rpc("approvals_report", params: Params(p_from: iso.string(from: from), p_to: iso.string(from: now)))
                .execute()
                .value
            report = result
            state = .loaded
        } catch {
            guard !ErrorHelper.isCancellation(error) else { return }
            Log.warning("[Insights] تعذّر جلب خلاصة الموافقات: \(error)")
            let raw = ErrorHelper.description(error)
            state = ((error as? PostgrestError)?.code == "PGRST202" || raw.contains("could not find the function"))
                ? .unavailable : .failed
        }
    }
}

struct AdminInsightsApprovalsCard: View {
    @StateObject private var store = AdminInsightsApprovalsStore()

    var body: some View {
        let t = store.report.totals
        let ready = store.state == .loaded
        let decided = t.executed + t.rejected + t.pending
        InsightsGroup(title: L10n.t("الموافقات", "Approvals")) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                InsightsRingBlock(
                    ring: DSRingGauge(parts: ready ? (DSGaugePart.counts([("done", t.executed, DS.Color.success),
                                                                           ("rejected", t.rejected, DS.Color.error),
                                                                           ("pending", t.pending, DS.Color.warning)]) ?? [])
                                                   : nil,
                                      size: DS.Ring.medium, track: DS.Ring.emptyTrack,
                                      center: .count(ready ? decided : nil), caption: L10n.t("طلب", "requests")),
                    rows: [
                        InsightsLegendRow(label: L10n.t("انقبلت", "Approved"), value: ready ? t.executed : nil,
                                          tint: DS.Color.success),
                        InsightsLegendRow(label: L10n.t("انرفضت", "Rejected"), value: ready ? t.rejected : nil,
                                          tint: DS.Color.error),
                        InsightsLegendRow(label: L10n.t("تنتظر قرار", "Awaiting decision"), value: ready ? t.pending : nil,
                                          tint: DS.Color.warning)
                    ])
                stateNote
                if ready, !topTypes.isEmpty {
                    topTypesBlock
                }
                InsightsFooterLink(title: L10n.t("تقرير الموافقات كامل", "Full approvals report")) {
                    AnyView(ApprovalsReportView())
                }
            }
        }
        .task { await store.load() }
    }

    @ViewBuilder
    private var stateNote: some View {
        switch store.state {
        case .unavailable:
            note(L10n.t("التقرير يحتاج تحديث السيرفر", "The report needs a server update"))
        case .failed:
            note(L10n.t("تعذّر تحميل الأرقام — تحقّق من الاتصال", "Couldn't load the numbers — check the connection"))
        case .loaded where store.report.totals.submitted == 0 && topTypes.isEmpty:
            note(L10n.t("ما في طلبات خلال آخر 30 يوم", "No requests in the last 30 days"))
        default:
            EmptyView()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .dsFont(.footnote)
            .foregroundColor(DS.Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var topTypes: [ApprovalsReport.TypeRow] {
        Array(store.report.types.filter { $0.count > 0 }.sorted { $0.count > $1.count }.prefix(4))
    }

    private var topTypesBlock: some View {
        let maxCount = max(topTypes.first?.count ?? 1, 1)
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(L10n.t("أكثر الطلبات", "Top requests"))
                .dsFont(.sectionTitle)
                .foregroundColor(DS.Color.textSecondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(topTypes) { row in
                HStack(spacing: DS.Spacing.sm) {
                    Text(ApprovalTypeTitle.title(row.type))
                        .dsFont(.label)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: DS.Chart.barLabelWidth, alignment: .leading)
                    DSMeterBar(progress: Double(row.count) / Double(maxCount), tint: DS.Color.sea,
                               track: DS.Ring.emptyTrack)
                    Text(verbatim: row.count.formatted())
                        .dsFont(.caption)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(ApprovalTypeTitle.title(row.type)): \(row.count.formatted())"))
            }
        }
    }
}
