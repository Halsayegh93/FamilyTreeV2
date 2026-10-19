import SwiftUI
import Supabase
import Combine

// MARK: - «رسائل الدخول · KWT SMS» (طلب المالك ٢٠٢٦-١٠-١٩ «نضيف قسم جديد تبع kwt-sms» — أول صفّ في «الدخول والأمان»)
//
// المالك والمدير فقط (نفس صلاحية `sms_balance_status()` على السيرفر — غيرهما 42501).
// بلا أي عمل سيرفر جديد: الرصيد = آخر `balance_after` من إرسال مقبول حقيقي (الجدول يُحذف ما قبل يومين، فقد لا
// توجد قراءة)، والباقي حقائق ثابتة من دوال السيرفر نفسها (المرسل، التغطية، النص، الحدود، عتبات التنبيه).
// الإحصاءات المفصّلة (٧/٣٠ يوماً، نسبة الوصول، آخر الإرسالات، الرصيد الحي، اختبار الإرسال) تحتاج عمل سيرفر
// (IA.md «عمل السيرفر المطلوب») — تظهر مكانها ملاحظة واحدة، بلا أرقام مختلقة.

/// آخر رصيد معروف لرسائل الدخول — مشترك بين «اليوم» وصفحة KWT SMS
@MainActor
final class SmsBalanceStore: ObservableObject {
    static let shared = SmsBalanceStore()

    /// ما تُرجعه `sms_balance_status()`
    struct Status: Equatable {
        /// nil = لا قراءة حديثة (لا إرسال مقبول خلال آخر يومين)
        var balance: Double?
        var at: Date?
    }

    enum LoadState: Equatable { case idle, loading, loaded, denied, failed }

    /// نفس عتبات تنبيه السيرفر (`finish_kwtsms_send`): منخفض تحت ٥٠، عاجل تحت ١٠
    static let lowThreshold: Double = 50
    static let urgentThreshold: Double = 10
    /// مرجع مقياس الرصيد في رأس الصفحة («من ١٠٠»)
    static let gaugeReference: Double = 100
    /// صفحة شحن الرصيد عند المزوّد
    static let rechargeURL = URL(string: "https://www.kwtsms.com/")!

    @Published var status: Status?
    @Published private(set) var state: LoadState = .idle
    private var lastFetch: Date?

    enum Level { case unknown, good, low, urgent }

    var level: Level {
        guard let balance = status?.balance else { return .unknown }
        if balance < Self.urgentThreshold { return .urgent }
        if balance < Self.lowThreshold { return .low }
        return .good
    }

    /// المالك والمدير فقط — ولا يُكرَّر الطلب خلال دقيقة إلا بالسحب للتحديث
    func refresh(force: Bool = false) async {
        if !force, let last = lastFetch, Date().timeIntervalSince(last) < 60 { return }
        lastFetch = Date()
        state = .loading
        nonisolated struct Row: Decodable {
            let balance: Double?
            let at: String?
        }
        do {
            let row: Row = try await SupabaseConfig.client.rpc("sms_balance_status").execute().value
            status = Status(balance: row.balance, at: ApprovalWorkflow.date(row.at))
            state = .loaded
        } catch {
            guard !ErrorHelper.isCancellation(error) else { state = .idle; return }
            let pg = error as? PostgrestError
            state = pg?.code == "42501" ? .denied : .failed
            Log.warning("[KWT SMS] تعذّر جلب الرصيد: \(error.localizedDescription)")
        }
    }
}

extension SmsBalanceStore.Level {
    var title: String {
        switch self {
        case .unknown: return L10n.t("لا قراءة", "No reading")
        case .good:    return L10n.t("جيد", "Good")
        case .low:     return L10n.t("منخفض", "Low")
        case .urgent:  return L10n.t("عاجل", "Urgent")
        }
    }

    /// لون المعنى: جيد أخضر، منخفض تحذير، عاجل خطأ
    var tint: Color {
        switch self {
        case .unknown: return DS.Color.textTertiary
        case .good:    return DS.Color.success
        case .low:     return DS.Color.warning
        case .urgent:  return DS.Color.error
        }
    }

    /// لون الرقم الكبير فوق الكحلي
    var bandTint: Color {
        switch self {
        case .unknown: return DS.Color.textOnPrimary
        case .good:    return DS.Hub.kpiMine
        case .low:     return DS.Hub.kpiLate
        case .urgent:  return DS.Hub.kpiHot
        }
    }
}

/// نصوص الرصيد المشتركة (اليوم + الصفحة)
enum SmsBalanceText {
    static func points(_ balance: Double) -> String { "\(Int(balance.rounded(.down)))" }

    /// «يكفي ~١٧ رمز دخول» — كل رسالة دخول بنقطة واحدة (٥٣ حرفاً)
    static func enough(_ balance: Double) -> String {
        let n = Int(balance.rounded(.down))
        return L10n.t("يكفي نحو \(n) رمز دخول", "Enough for about \(n) sign-in codes")
    }

    /// «آخر قراءة منذ ساعتين»
    static func updated(_ date: Date?) -> String? {
        guard let date else { return nil }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        f.unitsStyle = .full
        return L10n.t("آخر قراءة \(f.localizedString(for: date, relativeTo: Date()))",
                      "Last reading \(f.localizedString(for: date, relativeTo: Date()))")
    }

    static let noReading = L10n.t("لا توجد قراءة حديثة — يتحدّث مع أول رسالة دخول",
                                  "No recent reading — updates with the next sign-in code")
}

// MARK: - الصفحة

struct AdminSmsView: View {
    /// نص الرجوع: «الدخول والأمان» من صفّها، و«اليوم» من تنبيهه أو نبضه
    var backTitle: String = AdminArea.access.title
    @EnvironmentObject var authVM: AuthViewModel
    @ObservedObject private var store = SmsBalanceStore.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        AdminHubPage {
            header
        } content: {
            if !authVM.canViewSystemSettings || (store.state == .denied && store.status == nil) {
                DSNoteCard(L10n.t("صفحة رسائل الدخول للمالك والمدير فقط.", "Sign-in messages are for the owner and admins only."),
                           icon: "lock.fill", tint: DS.Color.warning)
            } else {
                if store.state == .failed && store.status == nil {
                    DSNoteCard(L10n.t("تعذّر جلب الرصيد الآن — اسحب للتحديث أو اضغط زر التحديث.",
                                      "Couldn't load the balance — pull to refresh or tap refresh."),
                               icon: "wifi.exclamationmark", tint: DS.Color.warning)
                }
                DSNoteCard(L10n.t("إحصاءات الإرسال المفصّلة تحتاج تفعيلاً من السيرفر — بانتظار موافقة المالك",
                                  "Detailed sending stats need server work — awaiting the owner's approval"),
                           icon: "chart.bar.doc.horizontal", tint: DS.Color.info)
                limitsCard
                setupCard
                alertsCard
            }
        }
        .refreshable { await store.refresh(force: true) }
        .task { await store.refresh() }
    }

    // MARK: الرأس

    private var header: some View {
        AdminBandHeader(backTitle: backTitle,
                        title: L10n.t("رسائل الدخول", "Sign-in messages"),
                        subtitle: L10n.t("KWT SMS · رموز الدخول برسالة نصية", "KWT SMS · sign-in codes by text message"),
                        bottomPadding: DS.Spacing.xl) {
            AdminGlassButton(symbol: "arrow.clockwise", label: L10n.t("تحديث الرصيد", "Refresh balance")) {
                Task { await store.refresh(force: true) }
            }
        } accessory: {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                balanceBlock
                HStack(spacing: DS.Spacing.sm) {
                    Button { openURL(SmsBalanceStore.rechargeURL) } label: {
                        AdminPillLabel(title: L10n.t("اشحن الرصيد", "Top up balance"), icon: "creditcard.fill",
                                       style: .gold, height: DS.Hub.pillHeightCard)
                    }
                    .buttonStyle(DSPressStyle())
                    .accessibilityHint(L10n.t("يفتح موقع KWT SMS", "Opens the KWT SMS website"))
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, DS.Spacing.md)
        }
    }

    private var balanceBlock: some View {
        let level = store.level
        return HStack(alignment: .center, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(L10n.t("الرصيد · \(level.title)", "Balance · \(level.title)"))
                    .dsFont(.sectionTitle)
                    .foregroundColor(DS.Hub.onBandMuted)
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
                    Text([SmsBalanceText.enough(balance), SmsBalanceText.updated(store.status?.at)]
                            .compactMap { $0 }.joined(separator: " · "))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Hub.onBandMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else if store.state == .loading && store.status == nil {
                    Text("—")
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

    // MARK: البطاقات

    private var limitsCard: some View {
        AdminRowsCard(title: L10n.t("الحدود", "Limits"),
                      footnote: L10n.t("حدود ثابتة في السيرفر تحمي الرصيد من التكرار.",
                                       "Fixed server limits that protect the balance from repeats.")) {
            kv("clock.fill", L10n.t("بين رمزين لنفس الرقم", "Between two codes to one number"),
               L10n.t("دقيقة", "1 minute"))
            kv("phone.fill", L10n.t("لكل رقم بالساعة", "Per number per hour"), L10n.t("حتى 5", "Up to 5"))
            kv("person.3.fill", L10n.t("للجميع بالساعة", "Everyone per hour"), L10n.t("حتى 100", "Up to 100"))
            kv("speedometer", L10n.t("للجميع بالثانية", "Everyone per second"), L10n.t("حتى 5", "Up to 5"))
        }
    }

    private var setupCard: some View {
        AdminRowsCard(title: L10n.t("الإعداد", "Setup")) {
            kv("tag.fill", L10n.t("المرسل", "Sender"), L10n.t("KWT-SMS (مشترك)", "KWT-SMS (shared)"),
               note: L10n.t("مرسل مشترك: أبطأ قليلاً وقد لا يصل لأرقام حجب الإعلانات.",
                            "Shared sender: a bit slower and may miss numbers that block promotions."))
            kv("globe", L10n.t("التغطية", "Coverage"), L10n.t("الكويت فقط", "Kuwait only"),
               note: L10n.t("أرقام جوال الكويت (+965) التي تبدأ بـ 4 أو 5 أو 6 أو 9.",
                            "+965 mobile numbers starting with 4, 5, 6 or 9."))
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                kv("text.bubble.fill", L10n.t("نص الرسالة", "Message text"),
                   L10n.t("53 حرفاً · نقطة واحدة", "53 characters · 1 point"))
                Text("عائلة المحمدعلي: رمز الدخول 123456. لا تشاركه مع أحد.")
                    .dsFont(.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(DS.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .fill(DS.Color.cardBackgroundSoft))
                    .environment(\.layoutDirection, .rightToLeft)
                    .padding(.bottom, DS.Spacing.sm)
                    .accessibilityLabel(L10n.t("معاينة الرسالة", "Message preview"))
            }
        }
    }

    private var alertsCard: some View {
        AdminRowsCard(title: L10n.t("التنبيهات", "Alerts")) {
            kv("exclamationmark.triangle.fill", L10n.t("منخفض", "Low"),
               L10n.t("أقل من 50 · مرة كل 24 ساعة", "Below 50 · once a day"), tint: DS.Color.warning)
            kv("flame.fill", L10n.t("عاجل", "Urgent"),
               L10n.t("أقل من 10 · كل 12 ساعة", "Below 10 · every 12 hours"), tint: DS.Color.error)
            kv("person.2.fill", L10n.t("يستلمها", "Sent to"), L10n.t("المالك والمدراء", "Owner and admins"))
        }
    }

    /// صفّ «اسم ← قيمة» مع ملاحظة اختيارية
    private func kv(_ icon: String, _ label: String, _ value: String, note: String? = nil,
                    tint: Color = DS.Color.textTertiary) -> some View {
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
                Spacer(minLength: DS.Spacing.sm)
                Text(value)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityElement(children: .combine)
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
