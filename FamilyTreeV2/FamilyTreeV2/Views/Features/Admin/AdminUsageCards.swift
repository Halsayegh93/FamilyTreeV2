import SwiftUI

// MARK: - بطاقات «الاستخدام» الجديدة (طلب المالك ٢٠٢٦-١٠-٢٢) — تحت «المستخدمون الآن» في `AdminActiveMembersView`
//
// بالترتيب: «النشطون في التطبيق» (ثلاث حلقات `DSRingGauge` — اليوم · ٧ أيام · ٣٠ يوماً من الأعضاء) ← «اتجاه النشطين»
// (مبدّل ٧ / ٣٠ / ٩٠، أعمدة نشطي اليوم + خط نشطي ٧ أيام بأسلوب رسم KWT) ← «الجلسات» (المجاميع + جلسات كل يوم)
// ← «أكثر الشاشات» ← «أكثر الأعضاء استخداماً» (الضغط يفتح ورقة العضو `AdminMemberSheet`). البيانات `AdminUsageData.swift`.
// حارس المكدس: كل بطاقة نوع مستقل خلف `AnyView` — لا جسم واحد ضخم. الرسوم ساكنة (لا حركة متكررة).

/// البطاقات كلها — المبدّل الواحد يغيّر فترة الاتجاه والجلسات معاً
struct AdminUsageInsights: View {
    @ObservedObject private var store = AdminUsageStore.shared

    var body: some View {
        VStack(spacing: DS.Hub.stackSpacing) {
            if store.denied && store.today == nil {
                DSNoteCard(L10n.t("أرقام الاستخدام للمالك والمدير فقط.", "Usage numbers are for the owner and admins only."),
                           icon: "lock.fill", tint: DS.Color.warning)
            } else {
                AnyView(AdminUsageRingsCard(store: store))
                AnyView(AdminUsageTrendCard(store: store))
                AnyView(AdminUsageSessionsCard(store: store))
                if let engagement = store.engagement, engagement.hasData {
                    if !engagement.screens.isEmpty {
                        AnyView(AdminUsageScreensCard(screens: engagement.screens))
                    }
                    if !engagement.members.isEmpty {
                        AnyView(AdminUsageMembersCard(members: engagement.members))
                    }
                }
            }
        }
        .task { await store.refresh() }
    }
}

// MARK: - النشطون (ثلاث حلقات)

private struct AdminUsageRingsCard: View {
    @ObservedObject var store: AdminUsageStore
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Ring: Identifiable {
        let id: String
        let title: String
        let value: Int?
        let tint: Color
    }

    private var members: Int? { store.today?.members }

    private var rings: [Ring] {
        let today = store.today
        return [
            Ring(id: "1d", title: L10n.t("اليوم", "Today"), value: today?.active1d, tint: DS.Color.success),
            Ring(id: "7d", title: AdminUsageText.period(7), value: today?.active7d, tint: DS.Color.sea),
            Ring(id: "30d", title: AdminUsageText.period(30), value: today?.active30d, tint: DS.Color.primary)
        ]
    }

    /// مقاس «إحصاء الأفراد»، وأصغر قليلاً مع XXXL
    private var ringSize: DS.Ring.Size { typeSize >= .xxxLarge ? DS.Ring.censusCompact : DS.Ring.census }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            AdminCardHeader(title: L10n.t("النشطون في التطبيق", "Active in the app")) {
                if let members {
                    Text(verbatim: Self.ofMembers(members))
                        .dsFont(.caption)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)
                }
            }
            if typeSize.isAccessibilitySize {
                AnyView(VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    ForEach(rings) { row($0) }
                })
            } else {
                AnyView(HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    ForEach(rings) { column($0) }
                })
            }
            Text(note)
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private var note: String {
        if store.today == nil && store.isFailed && !store.isLoading {
            return L10n.t("تعذّر جلب الأرقام الآن — اسحب للتحديث.", "Couldn't load the numbers — pull to refresh.")
        }
        return L10n.t("«اليوم» منذ 12:00 ص بتوقيت الكويت · العضو: حيّ برقم وجهاز مسجّل",
                      "“Today” is since 12:00 AM Kuwait time · a member is living with a phone and a registered device")
    }

    /// «من 33 عضواً» / «من 7 أعضاء»
    static func ofMembers(_ n: Int) -> String {
        guard L10n.isArabic else { return "of \(n) members" }
        return (3...10).contains(n) ? "من \(n) أعضاء" : "من \(n) عضواً"
    }

    private func share(_ value: Int?) -> Double? {
        guard let value, let members else { return nil }
        return members > 0 ? min(1, Double(value) / Double(members)) : 0
    }

    private func percent(_ value: Int?) -> Int? {
        guard let value, let members else { return nil }
        return DSGaugeText.share(value, of: members)
    }

    private func spoken(_ ring: Ring) -> String {
        guard let value = ring.value, let members else { return ring.title }
        let pct = percent(value).map { "، \(DSGaugeText.percent($0))" } ?? ""
        return L10n.t("\(ring.title): \(value) نشط من \(members)\(pct)", "\(ring.title): \(value) active of \(members)\(pct)")
    }

    /// عمود: الحلقة وعددها في الوسط، ثم الفترة بلونها، ثم النسبة
    private func column(_ ring: Ring) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            DSRingGauge(progress: share(ring.value), tint: ring.tint, size: ringSize,
                        center: .count(ring.value), caption: L10n.t("نشط", "active"))
            Text(ring.title)
                .dsFont(.hubRow)
                .foregroundColor(ring.tint.dsReadableGlyph)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: percent(ring.value).map { DSGaugeText.percent($0) } ?? "—")
                .dsFont(.footnote)
                .monospacedDigit()
                .foregroundColor(DS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(ring))
    }

    /// من أحجام إمكانية الوصول: صفّ نسبة (حلقة صغيرة بجانب الفترة والعدد)
    private func row(_ ring: Ring) -> some View {
        DSGaugeRow(gauge: DSRingGauge(progress: share(ring.value), tint: ring.tint, size: DS.Ring.small,
                                      center: .percent(percent(ring.value))),
                   title: ring.title,
                   subtitle: ring.value.map { value in
                       members.map { L10n.t("\(value) نشط من \($0)", "\(value) active of \($0)") } ?? "\(value)"
                   } ?? "—",
                   spoken: spoken(ring))
    }
}

// MARK: - الاتجاه

private struct AdminUsageTrendCard: View {
    @ObservedObject var store: AdminUsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminCardHeader(title: L10n.t("اتجاه النشطين", "Active members trend"))
            AdminUsagePeriodSwitch(store: store)
                .padding(.bottom, DS.Spacing.xs)
            content
            Text(L10n.t("تُحفظ لقطة كل ليلة 12:00 بتوقيت الكويت", "A snapshot is saved every night at 12:00 Kuwait time"))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private var content: AnyView {
        if let trend = store.trend {
            if trend.history.isEmpty {
                return AnyView(DSEmptyView(L10n.t("يبدأ الرسم من أول لقطة الليلة", "The chart starts with tonight's first snapshot"),
                                           icon: "chart.bar.fill", style: .inline))
            }
            return AnyView(AdminUsageTrendChartBlock(trend: trend, days: store.days))
        }
        return AnyView(AdminUsageStatus(store: store))
    }
}

/// المبدّل الواحد: ٧ / ٣٠ / ٩٠ يوماً
private struct AdminUsagePeriodSwitch: View {
    @ObservedObject var store: AdminUsageStore

    var body: some View {
        DSSegmentedSwitch(options: [
            DSSegmentOption(id: 7, title: AdminUsageText.period(7), icon: "calendar"),
            DSSegmentOption(id: 30, title: AdminUsageText.period(30), icon: "calendar.badge.clock"),
            DSSegmentOption(id: 90, title: AdminUsageText.period(90), icon: "clock.arrow.circlepath")
        ], selection: Binding(get: { store.days }, set: { store.select($0) }), size: .regular)
    }
}

/// قبل وصول بيانات الفترة: جارٍ الجلب، أو تعذّر
private struct AdminUsageStatus: View {
    @ObservedObject var store: AdminUsageStore

    var body: some View {
        if store.isFailed && !store.isLoading {
            DSEmptyView(L10n.t("تعذّر الجلب الآن — اسحب للتحديث", "Couldn't load — pull to refresh"),
                        icon: "wifi.exclamationmark", tint: DS.Color.error, style: .inline)
        } else {
            DSPageLoader(fillsSpace: false)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.sm)
        }
    }
}

/// السطر الملخّص + الرسم + طرفا المحور + المفتاح
private struct AdminUsageTrendChartBlock: View {
    let trend: AppUsageTrend
    let days: Int

    var body: some View {
        let slots = trend.slots(days: days)
        let daily = slots.map { $0.point?.active1d }
        let weekly = slots.map { $0.point?.active7d }
        let known = daily.compactMap { $0 }
        let average = known.isEmpty ? 0 : Int((Double(known.reduce(0, +)) / Double(known.count)).rounded())
        let busiest = known.max() ?? 0
        let summary = L10n.t("متوسط النشطين يومياً \(average) · أعلى يوم \(busiest)",
                             "Daily active average \(average) · busiest day \(busiest)")
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(verbatim: summary)
                .dsFont(.footnote)
                .monospacedDigit()
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            AdminUsageBarsChart(bars: daily, line: weekly)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.t("\(AdminUsageText.last(days)): \(summary)", "\(AdminUsageText.last(days)): \(summary)"))
            AdminUsageAxis(firstDay: slots.first?.day)
            AdminUsageLegend(bar: L10n.t("نشطون في اليوم", "Active that day"),
                             line: L10n.t("نشطون خلال 7 أيام", "Active within 7 days"))
        }
    }
}

// MARK: - الجلسات

private struct AdminUsageSessionsCard: View {
    @ObservedObject var store: AdminUsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            AdminCardHeader(title: L10n.t("الجلسات", "Sessions")) {
                Text(AdminUsageText.last(store.days))
                    .dsFont(.caption)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private var content: AnyView {
        guard let engagement = store.engagement else { return AnyView(AdminUsageStatus(store: store)) }
        guard engagement.hasData else {
            return AnyView(DSEmptyView(L10n.t("تبدأ الأرقام بعد تحديث التطبيق", "Numbers start after the app update"),
                                       icon: "iphone.gen3", style: .inline))
        }
        return AnyView(AdminUsageSessionsBody(engagement: engagement, days: store.days, today: store.today?.day))
    }
}

/// المجاميع (الجلسات · الدقائق · الأعضاء يومياً) ثم جلسات كل يوم
private struct AdminUsageSessionsBody: View {
    let engagement: AppUsageEngagement
    let days: Int
    let today: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let perDay = engagement.sessionsPerDay(days: days, today: today)
        let busiest = perDay.map(\.sessions).max() ?? 0
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if typeSize.isAccessibilitySize {
                AnyView(VStack(spacing: DS.Spacing.sm) { tiles })
            } else {
                AnyView(HStack(alignment: .top, spacing: DS.Spacing.sm) { tiles })
            }
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                AdminUsageBarsChart(bars: perDay.map { $0.sessions })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.t("جلسات كل يوم، أعلى يوم \(busiest)", "Sessions per day, busiest day \(busiest)"))
                AdminUsageAxis(firstDay: perDay.first?.day)
                AdminUsageLegend(bar: L10n.t("جلسات يومياً (أعلى يوم \(busiest))", "Sessions per day (busiest \(busiest))"))
            }
        }
    }

    @ViewBuilder private var tiles: some View {
        let usedDays = max(1, engagement.daily.filter { $0.sessions > 0 }.count)
        let sessions = engagement.totalSessions
        let minutes = engagement.totalMinutes
        let perDay = Int((Double(sessions) / Double(usedDays)).rounded())
        let perSession = sessions > 0 ? Int((Double(minutes) / Double(sessions)).rounded()) : 0
        AdminUsageTile(value: "\(sessions)", title: L10n.t("الجلسات", "Sessions"),
                       note: L10n.t("≈ \(perDay) يومياً", "≈ \(perDay) a day"))
        AdminUsageTile(value: "\(minutes)", title: L10n.t("الدقائق", "Minutes"),
                       note: perSession > 0 ? L10n.t("≈ \(perSession) د للجلسة", "≈ \(perSession) min a session")
                                            : L10n.t("أقل من دقيقة للجلسة", "Under a minute a session"))
        AdminUsageTile(value: "\(engagement.averageMembers)", title: L10n.t("عضو يومياً", "Members a day"),
                       note: L10n.t("متوسط الأيام", "Daily average"))
    }
}

/// مربّع رقم: الرقم الكبير، اسمه، وسطر صغير
private struct AdminUsageTile: View {
    let value: String
    let title: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(verbatim: value)
                .dsFont(.hubPulse)
                .monospacedDigit()
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: note)
                .dsFont(.caption)
                .monospacedDigit()
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Hub.kpiPadding)
        .background(RoundedRectangle(cornerRadius: DS.Hub.kpiRadius, style: .continuous).fill(DS.Color.cardBackgroundSoft))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(title): \(value)، \(note)"))
    }
}

// MARK: - أكثر الشاشات

private struct AdminUsageScreensCard: View {
    let screens: [AppUsageEngagement.Screen]
    private static let cap = 10

    var body: some View {
        let total = max(1, screens.reduce(0) { $0 + $1.opens })
        AdminSectionCard(title: L10n.t("أكثر الشاشات", "Top screens"), spacing: 0) {
            AdminRowsCardBody {
                ForEach(Array(screens.prefix(Self.cap))) { screen in
                    let pct = DSGaugeText.share(screen.opens, of: total) ?? 0
                    AdminInfoRow(icon: AppUsageScreen.icon(screen.screen), tint: DS.Color.primary,
                                 title: AppUsageScreen.title(screen.screen),
                                 subtitle: L10n.t("\(DSGaugeText.percent(pct)) من الجلسات", "\(DSGaugeText.percent(pct)) of sessions"),
                                 trailing: AnyView(AdminRowValue(text: "\(screen.opens)")))
                }
            }
            Text(L10n.t("كل جلسة تُحسب للشاشة التي أخذت أطول وقت فيها",
                        "Each session counts for the screen it spent the longest on"))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Spacing.xs)
        }
    }
}

// MARK: - أكثر الأعضاء استخداماً

private struct AdminUsageMembersCard: View {
    let members: [AppUsageEngagement.Member]
    @EnvironmentObject private var memberVM: MemberViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAll = false
    @State private var sheet: AdminMemberSheetContext?
    /// الصفوف الظاهرة قبل «الكل»
    private static let collapsedCount = 5

    var body: some View {
        // السابق/التالي في ورقة العضو: الأعضاء الموجودون في الشجرة بترتيب القائمة
        let ids = members.compactMap(\.memberId).filter { memberVM.member(byId: $0) != nil }
        let shown = showAll ? members : Array(members.prefix(Self.collapsedCount))
        AdminSectionCard(title: L10n.t("أكثر الأعضاء استخداماً", "Most active members"), link: link, spacing: 0) {
            AdminRowsCardBody {
                ForEach(shown) { item in
                    let member = item.memberId.flatMap { memberVM.member(byId: $0) }
                    AdminUsageMemberRow(item: item, member: member, open: opener(member, ids: ids))
                }
            }
        }
        .dsTallBox(item: $sheet) { context in
            AdminMemberSheet(ids: context.ids, start: context.start)
        }
    }

    /// يفتح ورقة العضو على قائمة الأعضاء (nil = ليس في الشجرة)
    private func opener(_ member: FamilyMember?, ids: [UUID]) -> (() -> Void)? {
        guard let member, let start = ids.firstIndex(of: member.id) else { return nil }
        return { sheet = AdminMemberSheetContext(ids: ids, start: start) }
    }

    private var link: AdminPageLink? {
        guard members.count > Self.collapsedCount else { return nil }
        return AdminPageLink(title: showAll ? L10n.t("أقل", "Less") : L10n.t("الكل (\(members.count))", "All (\(members.count))"),
                             tap: .action {
                                 withAnimation(reduceMotion ? nil : DSMotion.expand) { showAll.toggle() }
                             })
    }
}

/// صفّ عضو: الصورة + الاسم + «أيام · جلسات · دقائق» (+ سهم إن كان في الشجرة)
private struct AdminUsageMemberRow: View {
    let item: AppUsageEngagement.Member
    let member: FamilyMember?
    let open: (() -> Void)?

    var body: some View {
        if let open {
            Button(action: open) { face }
                .buttonStyle(.plain)
        } else {
            face
        }
    }

    private var name: String {
        member?.shortFullName ?? item.name.map(PersonName.threeParts) ?? L10n.t("عضو", "Member")
    }

    private var detail: String {
        [SmsText.days(item.days), AdminUsageText.sessions(item.sessions), AdminUsageText.minutes(item.minutes)]
            .joined(separator: " · ")
    }

    private var face: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSMemberAvatar(name: name, avatarUrl: member?.avatarUrl, size: DS.Icon.row, roleColor: AppSection.admin.ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(name)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .dsNameLines()
                Text(verbatim: detail)
                    .dsFont(.footnote)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Spacing.xs)
            if open != nil { DSChevron() }
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(minHeight: DS.Icon.tapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - الرسم (أسلوب رسم KWT ٣٠ يوماً: أعمدة + خط بمقياس واحد، الأقدم في بداية السطر)

/// أعمدة يومية (+ خط اختياري) — رسم ساكن. اليوم بلا قيمة = أثر خافت
private struct AdminUsageBarsChart: View {
    let bars: [Int?]
    var line: [Int?] = []

    var body: some View {
        let top = max(1, (bars + line).compactMap { $0 }.max() ?? 1)
        // ٩٠ يوماً: الفراغ نصفه كي لا تختفي الأعمدة
        let gap = bars.count > 31 ? DS.Hub.chartBarGap / 2 : DS.Hub.chartBarGap
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(bars.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: DS.Hub.chartBarRadius, style: .continuous)
                        .fill((bars[i] ?? 0) > 0 ? DS.Color.primary : DS.Color.textTertiary.opacity(DS.Opacity.divider))
                        .frame(maxWidth: .infinity)
                        .frame(height: barHeight(bars[i], top: top))
                }
            }
            if line.contains(where: { $0 != nil }) {
                AdminUsageLineShape(values: line, top: top)
                    .stroke(DS.Color.accentLight, style: StrokeStyle(lineWidth: DS.Hub.chartLine, lineCap: .round, lineJoin: .round))
                    .flipsForRightToLeftLayoutDirection(true)
                if line.count <= 31 {
                    AdminUsageLineShape(values: line, top: top, dots: true)
                        .fill(DS.Color.accentLight)
                        .flipsForRightToLeftLayoutDirection(true)
                }
            }
        }
        .frame(height: DS.Hub.chartHeight)
    }

    private func barHeight(_ value: Int?, top: Int) -> CGFloat {
        guard let value, value > 0 else { return DS.Hub.chartLine }
        let usable = DS.Hub.chartHeight - DS.Hub.chartDot
        return max(DS.Hub.chartLine * 2, usable * CGFloat(value) / CGFloat(top))
    }
}

/// الخط بين الأيام المعروفة (أو نقطة على كل يوم) — بمقياس الأعمدة نفسه، موضع فيزيائي يقلبه الاتجاه
private struct AdminUsageLineShape: Shape {
    let values: [Int?]
    let top: Int
    var dots = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }
        let slot = rect.width / CGFloat(values.count)
        let usable = rect.height - DS.Hub.chartDot
        let points: [CGPoint] = values.enumerated().compactMap { i, v in
            guard let v else { return nil }
            return CGPoint(x: rect.minX + slot * (CGFloat(i) + 0.5),
                           y: rect.maxY - usable * CGFloat(v) / CGFloat(max(1, top)))
        }
        if dots {
            let r = DS.Hub.chartDot / 2
            for p in points { path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)) }
        } else if let first = points.first {
            path.move(to: first)
            for p in points.dropFirst() { path.addLine(to: p) }
        }
        return path
    }
}

/// طرفا المحور: أول يوم في الفترة … اليوم
private struct AdminUsageAxis: View {
    let firstDay: String?

    var body: some View {
        HStack {
            Text(SmsText.shortDay(firstDay ?? ""))
            Spacer(minLength: DS.Spacing.sm)
            Text(L10n.t("اليوم", "Today"))
        }
        .dsFont(.caption)
        .foregroundColor(DS.Color.textTertiary)
        .accessibilityHidden(true)
    }
}

/// مفتاح الرسم: العمود (+ الخط)
private struct AdminUsageLegend: View {
    let bar: String
    var line: String? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.md) { items }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) { items }
        }
        .dsFont(.caption)
        .foregroundColor(DS.Color.textSecondary)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var items: some View {
        HStack(spacing: DS.Spacing.xs) {
            RoundedRectangle(cornerRadius: DS.Hub.chartBarRadius, style: .continuous)
                .fill(DS.Color.primary)
                .frame(width: DS.Hub.chartSwatch, height: DS.Hub.chartSwatch)
            Text(verbatim: bar)
        }
        if let line {
            HStack(spacing: DS.Spacing.xs) {
                Capsule()
                    .fill(DS.Color.accentLight)
                    .frame(width: DS.Hub.chartSwatch * 2, height: DS.Hub.chartLine)
                Text(verbatim: line)
            }
        }
    }
}
