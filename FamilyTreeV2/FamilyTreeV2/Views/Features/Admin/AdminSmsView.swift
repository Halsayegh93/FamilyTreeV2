import SwiftUI
import Combine

// MARK: - «رسائل الدخول · KWT SMS» (طلب المالك ٢٠٢٦-١٠-١٩ «نضيف قسم جديد تبع kwt-sms» — أول صفّ في «الدخول والأمان»)
//
// المالك والمدير فقط (نفس صلاحية `sms_admin_overview()` على السيرفر — غيرهما 42501). البيانات الحية منذ ٢٠٢٦-١٠-٢٠
// (`AdminSmsData.swift`): الرأس (الرصيد وحالته، يكفي كم رمز وكم يوم، تحديث حي، الشحن) ← الإرسال (اليوم/٧/٣٠،
// القبول، النقاط، عدّاد الساعة) ← آخر ٣٠ يوماً ← آخر الإرسالات (فحص الحالة) ← أدوات (اختبار المالك، فحص رقم،
// المرسلون، التغطية) ← التنبيهات (المالك يعدّل) ← الحدود ← الإعداد.
// حارس المكدس (تعطّل «اليوم» على الجوال ٢٠٢٦-١٠-٢٠): كل بطاقة نوع مستقل خلف `AnyView` — لا جسم واحد ضخم.

/// ما يُفتح من أدوات الصفحة في مربّع
enum SmsToolBox: String, Identifiable {
    case senders, coverage, validate
    var id: String { rawValue }
}

/// نتيجة إجراء تظهر في نافذة صغيرة
struct SmsNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

/// حالة إجراءات الصفحة: ما يعمل الآن، آخر نتيجة، والمربّع المفتوح
@MainActor
final class SmsPageActions: ObservableObject {
    @Published private(set) var busy: Set<String> = []
    @Published var notice: SmsNotice?
    @Published var box: SmsToolBox?
    @Published var confirmTest = false
    private var store: SmsBalanceStore { SmsBalanceStore.shared }

    func isBusy(_ key: String) -> Bool { busy.contains(key) }

    /// يشغّل إجراءً واحداً بمفتاحه (لا يتكرر وهو يعمل) ويعرض نتيجته أو خطأه بالعربي
    func run(_ key: String, _ work: @escaping () async throws -> SmsNotice?) {
        guard !busy.contains(key) else { return }
        busy.insert(key)
        Task {
            defer { busy.remove(key) }
            do {
                if let result = try await work() { notice = result }
            } catch let error as SmsAdminError {
                notice = SmsNotice(title: error.title, message: error.message)
            } catch {
                guard !ErrorHelper.isCancellation(error) else { return }
                let fallback = SmsAdminError(code: "network")
                notice = SmsNotice(title: fallback.title, message: fallback.message)
            }
        }
    }

    /// «تحديث الرصيد الآن» — رصيد حي من KWT (المالك والمدير)
    func refreshBalance() {
        run("balance") { [store] in
            try await store.refreshLiveBalance()
            return nil
        }
    }

    /// «اختبار إرسال لرقمي» — المالك فقط، لرقم ملفه، بعد التأكيد
    func testSend() {
        run("test") { [store] in
            let reply = try await store.call("test_send", as: SmsBalanceStore.TestSendReply.self)
            await store.refresh(force: true)
            if reply.testMode == true {
                return SmsNotice(title: L10n.t("تم الاختبار — وضع تجريبي", "Test done — test mode"),
                                 message: L10n.t("الحساب في الوضع التجريبي: قبل المزوّد الرسالة لكن لا تصل رسالة فعلية ولا تُخصم نقاط.",
                                                 "The account is in test mode: the provider accepted it, but no real message is sent and no points are charged."))
            }
            let points = reply.points.map { SmsText.number($0) } ?? "1"
            let balance = reply.balance.map { SmsBalanceText.points($0) }
            return SmsNotice(title: L10n.t("أُرسلت رسالة الاختبار", "Test message sent"),
                             message: balance.map { L10n.t("تصل رقمك خلال ثوانٍ. خُصم \(points) نقطة — الرصيد الآن \($0).",
                                                           "It reaches your number in seconds. \(points) point(s) charged — balance now \($0).") }
                                ?? L10n.t("تصل رقمك خلال ثوانٍ. خُصم \(points) نقطة.",
                                          "It reaches your number in seconds. \(points) point(s) charged."))
        }
    }

    /// «فحص الحالة» لرسالة برقمها عند المزوّد — النتيجة تُحفظ على الإرسال نفسه
    func checkStatus(_ msgid: String) {
        run("status:\(msgid)") { [store] in
            let reply = try await store.call("status", msgid: msgid, as: SmsBalanceStore.StatusReply.self)
            await store.refresh(force: true)
            let text = SmsText.deliveryStatus(reply.status)
            return SmsNotice(title: L10n.t("حالة الرسالة", "Message status"),
                             message: text == reply.status ? text : "\(text) (\(reply.status))")
        }
    }
}

// MARK: - الصفحة

struct AdminSmsView: View {
    /// نص الرجوع: «الدخول والأمان» من صفّها، و«اليوم» من تنبيهه أو نبضه
    var backTitle: String = AdminArea.access.title
    @ObservedObject private var store = SmsBalanceStore.shared
    @StateObject private var actions = SmsPageActions()

    var body: some View {
        AdminHubPage {
            AnyView(SmsHeroHeader(backTitle: backTitle, store: store, actions: actions))
        } content: {
            AnyView(SmsPageContent(store: store, actions: actions))
        }
        .refreshable { await store.refresh(force: true) }
        .task { await store.refresh() }
        .modifier(SmsPagePresentations(actions: actions))
    }
}

/// المربّعات والنوافذ: الأدوات، تأكيد الاختبار، نتيجة الإجراء
private struct SmsPagePresentations: ViewModifier {
    @ObservedObject var actions: SmsPageActions

    func body(content: Content) -> some View {
        content
            .dsCenterBox(item: $actions.box) { kind in
                AnyView(SmsToolBoxView(kind: kind))
            }
            .dsAlert(L10n.t("إرسال رسالة اختبار لرقمك؟", "Send a test message to your number?"),
                     isPresented: $actions.confirmTest, icon: "paperplane.fill") {
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
                Button(L10n.t("أرسل الاختبار", "Send test")) { actions.testSend() }
            } message: {
                Text(L10n.t("تُرسل رسالة اختبار واحدة إلى رقم ملفك أنت فقط، وتخصم نقطة واحدة من الرصيد. مسموح مرة كل 10 دقائق.",
                            "One test message goes to your own profile number only and costs 1 point. Allowed once every 10 minutes."))
            }
            .dsAlert(actions.notice?.title ?? "", isPresented: Binding(
                get: { actions.notice != nil },
                set: { if !$0 { actions.notice = nil } }
            ), presenting: actions.notice) { _ in
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: { notice in
                Text(notice.message)
            }
    }
}

/// المحتوى تحت الرأس — كل بطاقة نوع مستقل (حارس المكدس)
private struct SmsPageContent: View {
    @ObservedObject var store: SmsBalanceStore
    @ObservedObject var actions: SmsPageActions
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        if !authVM.canViewSystemSettings || (store.state == .denied && store.status == nil) {
            DSNoteCard(L10n.t("صفحة رسائل الدخول للمالك والمدير فقط.", "Sign-in messages are for the owner and admins only."),
                       icon: "lock.fill", tint: DS.Color.warning)
        } else {
            VStack(spacing: DS.Hub.stackSpacing) {
                if let overview = store.overview {
                    AnyView(SmsNumbersCard(overview: overview))
                    AnyView(SmsTrendCard(overview: overview))
                    AnyView(SmsRecentCard(overview: overview, actions: actions))
                } else if store.state == .loading {
                    DSPageLoader(L10n.t("جاري جلب أرقام الرسائل…", "Loading message stats…"),
                                 size: DS.Icon.loaderArtInline, fillsSpace: false)
                } else if store.overviewFailed || store.state == .failed {
                    DSNoteCard(L10n.t("تعذّر جلب أرقام الرسائل الآن — اسحب للتحديث.",
                                      "Couldn't load message stats — pull to refresh."),
                               icon: "wifi.exclamationmark", tint: DS.Color.warning)
                }
                AnyView(SmsToolsCard(actions: actions, isOwner: authVM.isOwner))
                AnyView(SmsAlertsCard(alerts: store.overview?.alerts))
                AnyView(SmsLimitsCard(limits: store.overview?.limits ?? SmsOverview.Limits()))
                AnyView(SmsSetupCard())
            }
        }
    }
}

// MARK: - الرأس

private struct SmsHeroHeader: View {
    let backTitle: String
    @ObservedObject var store: SmsBalanceStore
    @ObservedObject var actions: SmsPageActions

    var body: some View {
        AdminBandHeader(backTitle: backTitle,
                        title: L10n.t("رسائل الدخول", "Sign-in messages"),
                        subtitle: L10n.t("KWT SMS · رموز الدخول برسالة نصية", "KWT SMS · sign-in codes by text message"),
                        bottomPadding: DS.Spacing.xl) {
            AdminGlassButton(symbol: "arrow.clockwise", label: L10n.t("تحديث الصفحة", "Refresh page")) {
                Task { await store.refresh(force: true) }
            }
        } accessory: {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                SmsBalanceBlock(store: store)
                SmsHeroButtons(actions: actions)
            }
            .padding(.top, DS.Spacing.md)
        }
    }
}

/// الرصيد الكبير وحالته وكم يكفي، والمقياس نصف الدائري
private struct SmsBalanceBlock: View {
    @ObservedObject var store: SmsBalanceStore

    var body: some View {
        let level = store.level
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.sm) {
                    Text(L10n.t("الرصيد · \(level.title)", "Balance · \(level.title)"))
                        .dsFont(.sectionTitle)
                        .foregroundColor(DS.Hub.onBandMuted)
                    if let test = store.overview?.lastTestMode {
                        AdminBandChip(text: test ? L10n.t("وضع تجريبي", "Test mode") : L10n.t("تشغيل فعلي", "Live"),
                                      icon: test ? "flask.fill" : "dot.radiowaves.left.and.right",
                                      tint: test ? DS.Hub.kpiLate : DS.Hub.rolePillInk)
                    }
                }
                if let balance = store.status?.balance {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                        Text(SmsBalanceText.points(balance))
                            .dsFont(.hubBalance)
                            .monospacedDigit()
                            .foregroundColor(level.bandTint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(L10n.t("نقطة", "pts"))
                            .dsFont(.headline)
                            .foregroundColor(level.bandTint)
                    }
                    Text(verbatim: enoughLine(balance))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Hub.onBandMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let updated = SmsBalanceText.updated(store.status?.at) {
                        Text(updated)
                            .dsFont(.footnote)
                            .foregroundColor(DS.Hub.onBandMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if store.state == .loading {
                    Text(verbatim: "—")
                        .dsFont(.hubBalance)
                        .foregroundColor(DS.Color.textOnPrimary)
                } else {
                    Text(SmsBalanceText.noReading)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Spacing.xs)
                }
            }
            Spacer(minLength: 0)
            if let balance = store.status?.balance {
                SmsBalanceGauge(progress: balance / SmsBalanceStore.gaugeReference, tint: level.bandTint)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// «يكفي نحو ١٧ رمز دخول · نحو ٦ أيام بمعدّل الأسبوع»
    private func enoughLine(_ balance: Double) -> String {
        var parts = [SmsBalanceText.enough(balance)]
        if let days = store.overview?.daysLeft {
            parts.append(L10n.t("يخلص خلال \(SmsText.days(days)) تقريباً", "runs out in about \(SmsText.days(days))"))
        }
        return parts.joined(separator: " · ")
    }
}

/// «اشحن الرصيد» + «تحديث الرصيد الآن» — عمود واحد إن كبر الخط
private struct SmsHeroButtons: View {
    @ObservedObject var actions: SmsPageActions
    @Environment(\.openURL) private var openURL

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.sm) {
                recharge
                refresh
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                recharge
                refresh
            }
        }
    }

    private var recharge: some View {
        Button { openURL(SmsBalanceStore.rechargeURL) } label: {
            AdminPillLabel(title: L10n.t("اشحن الرصيد", "Top up balance"), icon: "creditcard.fill",
                           style: .gold, height: DS.Hub.pillHeightCard)
                .fixedSize()
        }
        .buttonStyle(DSPressStyle())
        .accessibilityHint(L10n.t("يفتح صفحة شراء الرصيد في حساب KWT SMS", "Opens the KWT SMS buy-credits page"))
    }

    private var refresh: some View {
        let busy = actions.isBusy("balance")
        return Button { actions.refreshBalance() } label: {
            AdminPillLabel(title: busy ? L10n.t("جارٍ جلب الرصيد…", "Fetching balance…")
                                       : L10n.t("تحديث الرصيد الآن", "Refresh balance now"),
                           icon: busy ? "hourglass" : "arrow.triangle.2.circlepath",
                           style: .glass, height: DS.Hub.pillHeightCard)
                .fixedSize()
        }
        .buttonStyle(DSPressStyle())
        .disabled(busy)
        .accessibilityHint(L10n.t("يسأل KWT SMS عن الرصيد الحالي ويحفظه", "Asks KWT SMS for the current balance and saves it"))
    }
}

/// مقياس نصف دائري للرصيد (٠…١ من مرجع ١٠٠ نقطة) — رسم ساكن
struct SmsBalanceGauge: View {
    let progress: Double
    var tint: Color

    var body: some View {
        let p = min(max(progress, 0), 1)
        ZStack(alignment: .bottom) {
            ZStack {
                ArcShape(fraction: 1)
                    .stroke(DS.Hub.glassLine, style: StrokeStyle(lineWidth: DS.Hub.gaugeLine, lineCap: .round))
                ArcShape(fraction: p)
                    .stroke(tint, style: StrokeStyle(lineWidth: DS.Hub.gaugeLine, lineCap: .round))
            }
            // يمتلئ من بداية السطر (اليمين في العربية)
            .scaleEffect(x: L10n.isArabic ? -1 : 1, y: 1)
            Text(L10n.t("من 100", "of 100"))
                .dsFont(.caption)
                .foregroundColor(DS.Hub.onBandMuted)
                .padding(.bottom, DS.Spacing.xxs)
        }
        .frame(width: DS.Hub.gaugeWidth, height: DS.Hub.gaugeHeight)
        .accessibilityHidden(true)
    }

    /// قوس نصف دائرة من اليسار إلى اليمين (موضع فيزيائي ثابت)
    private struct ArcShape: Shape {
        var fraction: Double
        func path(in rect: CGRect) -> Path {
            let inset = DS.Hub.gaugeLine / 2
            let radius = min(rect.width / 2, rect.height) - inset
            let center = CGPoint(x: rect.midX, y: rect.maxY - inset)
            var path = Path()
            path.addArc(center: center, radius: radius, startAngle: .degrees(180),
                        endAngle: .degrees(180 + 180 * fraction), clockwise: false)
            return path
        }
    }
}

// MARK: - الإرسال (اليوم / ٧ / ٣٠)

private struct SmsNumbersCard: View {
    let overview: SmsOverview
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            AdminCardHeader(title: L10n.t("الإرسال", "Sending"))
            if typeSize.isAccessibilitySize {
                VStack(spacing: DS.Spacing.sm) { tiles }
            } else {
                HStack(alignment: .top, spacing: DS.Spacing.sm) { tiles }
            }
            SmsOutcomeBar(totals: overview.days30)
            VStack(alignment: .leading, spacing: 0) {
                SmsKVRow(icon: "chart.line.downtrend.xyaxis", label: L10n.t("معدّل الاستهلاك اليومي (7 أيام)", "Daily use (7-day average)"),
                         value: L10n.t("\(SmsText.number(overview.avgDailyPoints7d)) نقطة", "\(SmsText.number(overview.avgDailyPoints7d)) pts"))
                if let days = overview.daysLeft {
                    AdminRowDivider()
                    SmsKVRow(icon: "calendar", label: L10n.t("يكفي الرصيد تقريباً", "Balance lasts about"),
                             value: SmsText.days(days))
                }
                AdminRowDivider()
                SmsHourRow(count: overview.hourCount, cap: overview.hourCap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    @ViewBuilder private var tiles: some View {
        SmsTotalsTile(title: L10n.t("اليوم", "Today"), totals: overview.today)
        SmsTotalsTile(title: L10n.t("7 أيام", "7 days"), totals: overview.days7)
        SmsTotalsTile(title: L10n.t("30 يوماً", "30 days"), totals: overview.days30)
    }
}

/// مربّع فترة: عدد رموز الدخول، نسبة القبول، النقاط
private struct SmsTotalsTile: View {
    let title: String
    let totals: SmsOverview.Totals

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(verbatim: "\(totals.sends)")
                .dsFont(.hubPulse)
                .monospacedDigit()
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textSecondary)
            Text(verbatim: acceptance)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: points)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Hub.kpiPadding)
        .background(RoundedRectangle(cornerRadius: DS.Hub.kpiRadius, style: .continuous).fill(DS.Color.cardBackgroundSoft))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("\(title): \(totals.sends) رمز دخول، \(acceptance)، \(points)",
                                   "\(title): \(totals.sends) codes, \(acceptance), \(points)"))
    }

    /// «قبول 98%»
    private var acceptance: String {
        let pct = totals.acceptancePct.map { SmsText.percent($0) } ?? "—"
        return L10n.t("قبول \(pct)", "\(pct) accepted")
    }

    /// «12 نقطة»
    private var points: String {
        L10n.t("\(SmsText.number(totals.points)) نقطة", "\(SmsText.number(totals.points)) pts")
    }
}

/// شريط النتائج لآخر ٣٠ يوماً: مقبول · فشل · غير معروف (+ التجريبية)
private struct SmsOutcomeBar: View {
    let totals: SmsOverview.Totals

    var body: some View {
        if totals.sends > 0 || totals.testSends > 0 {
            VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
                DSDistributionBar(segments: [
                    .init(id: "ok", value: totals.accepted, tint: DS.Color.success),
                    .init(id: "unknown", value: totals.unknown, tint: DS.Color.warning),
                    .init(id: "failed", value: totals.failed, tint: DS.Color.error)
                ], height: DS.Hub.meterHeight)
                Text(verbatim: legend)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.t("آخر 30 يوماً: \(legend)", "Last 30 days: \(legend)"))
        }
    }

    private var legend: String {
        var parts = [L10n.t("مقبول \(totals.accepted)", "\(totals.accepted) accepted"),
                     L10n.t("فشل \(totals.failed)", "\(totals.failed) failed"),
                     L10n.t("غير معروف \(totals.unknown)", "\(totals.unknown) unknown")]
        if totals.testSends > 0 {
            parts.append(L10n.t("تجريبي \(totals.testSends)", "\(totals.testSends) test"))
        }
        return L10n.t("آخر 30 يوماً: ", "Last 30 days: ") + parts.joined(separator: " · ")
    }
}

/// «هذه الساعة: ١٢ من ١٠٠» بشريط
private struct SmsHourRow: View {
    let count: Int
    let cap: Int

    var body: some View {
        let share = cap > 0 ? Double(count) / Double(cap) : 0
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            SmsKVRow(icon: "gauge.with.dots.needle.33percent", label: L10n.t("هذه الساعة (للجميع)", "This hour (everyone)"),
                     value: L10n.t("\(count) من \(cap)", "\(count) of \(cap)"))
            AdminMeter(progress: share, tint: share >= 0.8 ? DS.Color.error : share >= 0.5 ? DS.Color.warning : DS.Color.success)
                .padding(.bottom, DS.Spacing.sm)
        }
    }
}

// MARK: - آخر ٣٠ يوماً

private struct SmsTrendCard: View {
    let overview: SmsOverview

    var body: some View {
        let series = overview.series()
        let maxSends = max(1, series.map(\.sends).max() ?? 0)
        let total = series.reduce(0) { $0 + $1.sends }
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminCardHeader(title: L10n.t("آخر 30 يوماً", "Last 30 days"))
            if total == 0 && !series.contains(where: { $0.balance != nil }) {
                Text(L10n.t("لا إرسال خلال آخر 30 يوماً بعد — يمتلئ الرسم مع أول رموز الدخول.",
                            "No sends in the last 30 days yet — the chart fills with the first sign-in codes."))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SmsTrendChart(series: series, maxSends: maxSends)
                    .frame(height: DS.Hub.chartHeight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.t("آخر 30 يوماً: \(total) رمز دخول، أعلى يوم \(maxSends)",
                                               "Last 30 days: \(total) codes, busiest day \(maxSends)"))
                HStack {
                    Text(SmsText.shortDay(series.first?.day ?? ""))
                    Spacer(minLength: DS.Spacing.sm)
                    Text(L10n.t("اليوم", "Today"))
                }
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)
                SmsTrendLegend(maxSends: maxSends)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }
}

/// أعمدة الإرسال اليومي + خط الرصيد (مقياس مستقل) — رسم ساكن، الأقدم في بداية السطر
private struct SmsTrendChart: View {
    let series: [SmsOverview.Day]
    let maxSends: Int

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: DS.Hub.chartBarGap) {
                ForEach(series, id: \.day) { day in
                    RoundedRectangle(cornerRadius: DS.Hub.chartBarRadius, style: .continuous)
                        .fill(day.sends > 0 ? DS.Color.primary.opacity(day.failed > 0 ? DS.Opacity.selectedStroke : 1)
                                            : DS.Color.textTertiary.opacity(DS.Opacity.divider))
                        .frame(maxWidth: .infinity)
                        .frame(height: barHeight(day))
                }
            }
            SmsBalanceLine(values: series.map(\.balance))
                .stroke(DS.Color.accentLight, style: StrokeStyle(lineWidth: DS.Hub.chartLine, lineCap: .round, lineJoin: .round))
                .flipsForRightToLeftLayoutDirection(true)
            SmsBalanceDots(values: series.map(\.balance))
                .fill(DS.Color.accentLight)
                .flipsForRightToLeftLayoutDirection(true)
        }
    }

    private func barHeight(_ day: SmsOverview.Day) -> CGFloat {
        guard day.sends > 0 else { return DS.Hub.chartLine }
        let usable = DS.Hub.chartHeight - DS.Hub.chartDot
        return max(DS.Hub.chartLine * 2, usable * CGFloat(day.sends) / CGFloat(maxSends))
    }
}

/// خط الرصيد بين الأيام المعروفة (الفارغة تُتخطّى) — موضع فيزيائي، يقلبه الاتجاه
private struct SmsBalanceLine: Shape {
    let values: [Double?]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = SmsChartGeometry.points(values, in: rect)
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        return path
    }
}

/// نقطة على كل يوم معروف الرصيد
private struct SmsBalanceDots: Shape {
    let values: [Double?]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = DS.Hub.chartDot / 2
        for p in SmsChartGeometry.points(values, in: rect) {
            path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        return path
    }
}

private enum SmsChartGeometry {
    /// مواضع الأيام المعروفة: الأفقي بمنتصف عمود اليوم، والعمودي من صفر إلى أعلى رصيد في الفترة
    static func points(_ values: [Double?], in rect: CGRect) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let top = max(1, values.compactMap { $0 }.max() ?? 1)
        let inset = DS.Hub.chartDot / 2
        let slot = rect.width / CGFloat(values.count)
        return values.enumerated().compactMap { i, v in
            guard let v else { return nil }
            let y = rect.maxY - inset - (rect.height - 2 * inset) * CGFloat(v / top)
            return CGPoint(x: rect.minX + slot * (CGFloat(i) + 0.5), y: y)
        }
    }
}

/// مفتاح الرسم: العمود = رموز الدخول اليومية، الخط = الرصيد
private struct SmsTrendLegend: View {
    let maxSends: Int

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
            Text(L10n.t("رموز الدخول يومياً (أعلى يوم \(maxSends))", "Codes per day (busiest \(maxSends))"))
        }
        HStack(spacing: DS.Spacing.xs) {
            Capsule()
                .fill(DS.Color.accentLight)
                .frame(width: DS.Hub.chartSwatch * 2, height: DS.Hub.chartLine)
            Text(L10n.t("الرصيد آخر اليوم", "Balance at day end"))
        }
    }
}

// MARK: - صفّ «اسم ← قيمة»

/// صفّ «اسم ← قيمة» مع ملاحظة اختيارية — مشترك بين بطاقات الصفحة
struct SmsKVRow<Trailing: View>: View {
    let icon: String
    let label: String
    var note: String? = nil
    var tint: Color = DS.Color.textTertiary
    /// false = الطرف عنصر تفاعلي مستقل (مبدّل) — لا يُدمج مع الاسم للقارئ الصوتي
    var combines: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.sm) {
                Image(dsSymbol: icon)
                    .dsGlyph(DS.Glyph.md, weight: .semibold)
                    .foregroundColor(tint.dsReadableGlyph)
                    .frame(width: DS.Icon.section)
                    .accessibilityHidden(true)
                Text(label)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DS.Spacing.sm)
                trailing()
            }
            if let note {
                Text(note)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, DS.Icon.section + DS.Spacing.sm)
            }
        }
        .padding(.vertical, DS.Spacing.sm + 1)
        .frame(minHeight: DS.Icon.tapTarget)
        .accessibilityElement(children: combines ? .combine : .contain)
    }
}

extension SmsKVRow where Trailing == SmsKVValue {
    init(icon: String, label: String, value: String, note: String? = nil, tint: Color = DS.Color.textTertiary) {
        self.init(icon: icon, label: label, note: note, tint: tint) { SmsKVValue(text: value) }
    }
}

/// قيمة الصفّ العريضة في الطرف
struct SmsKVValue: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .dsFont(.hubRow)
            .foregroundColor(DS.Color.textPrimary)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}
