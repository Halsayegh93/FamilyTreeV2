import SwiftUI
import Combine

// MARK: - «رسائل رمز الدخول (KWT SMS)» (طلب المالك ٢٠٢٦-١٠-١٩ «نضيف قسم جديد تبع kwt-sms» — في «الفريق والأمان»)
//
// المالك فقط (`sms_admin_overview()` على السيرفر، و`team.sms` سقفه المالك). البيانات الحية `AdminSmsData.swift`.
// شكل الإدارة v2 «أ» (طلب المالك ٢٠٢٦-١١-٢٧ «ما عدلت اعدادات رسائل sms بالفريق و الامان»): صفحة داخلية `AdminPage`
//  • الرأس الكحلي: «‹ الفريق والأمان» · «رسائل رمز الدخول» · السطر الذهبي، وفيه بطل الصفحة: حلقة الرصيد الكبيرة على الكحلي
//    (النقاط في وسطها، كلمة حاله تحتها)، وبجانبها كم يكفي ومتى يخلص وآخر تحديث، ثم «شحن الرصيد» الذهبي (رابط الشحن الوحيد
//    `SmsBalanceStore.rechargeURL`) و«تحديث الرصيد الآن».
//  • ثم أقسام قصيرة بعناوين صغيرة بترتيب `SmsPageLogic.sections`: رموز الدخول المرسلة (اليوم · 7 أيام · 30 يوماً + هذه
//    الساعة) · آخر 30 يوماً (الرسم) · آخر الإرسالات (فحص الحالة) · إعدادات الإرسال (مكانها الوحيد — كانت صفحة من ⋯) ·
//    حماية رسائل الدخول · تنبيهات الرصيد · الأدوات · صفّ «طلبات رمز الدخول» (بعدد المريبة غير المقروءة) · «طريقة العمل» مطويّة.
//  • الإعدادات صفوف لا مربّعات، وتعديلها للمالك وحده — لغيره «للاطلاع فقط — التعديل للمالك» والقيم كلمات.
// كل النداءات والصلاحيات والنصوص كما كانت (`kwtsms-admin`، `updateSmsLimits`، `updateSmsAlerts`، `set_app_config`).
// حارس المكدس: كل قسم نوع مستقل خلف `AnyView` (`AdminSmsSections.swift`، `AdminSmsSettings.swift`، `AdminSmsLoginGuard.swift`).

extension SmsText {
    /// اسم الصفحة — ونصّ الرجوع من صفحاتها الفرعية
    static var pageTitle: String { L10n.t("رسائل رمز الدخول", "Sign-in code messages") }
}

/// ما يُفتح من أدوات الصفحة في مربّع
enum SmsToolBox: String, Identifiable {
    /// `sender` = مربّع تغيير «اسم المرسل» (المالك)
    case senders, coverage, validate, sender
    var id: String { rawValue }
}

/// نتيجة إجراء تظهر في نافذة صغيرة
struct SmsNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    /// بعد تغيير المرسل: زر «اختبار إرسال لرقمي» في النافذة نفسها
    var offersTest = false
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
            return SmsNotice(title: L10n.t("أُرسلت الرسالة التجريبية", "Test message sent"),
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
    /// نص الرجوع: «الفريق والأمان» من صفّها، و«اليوم» من تنبيهه أو نبضه
    var backTitle: String = AdminArea.team.title
    @ObservedObject private var store = SmsBalanceStore.shared
    @StateObject private var actions = SmsPageActions()
    @EnvironmentObject private var authVM: AuthViewModel
    /// من دفع الصفحة سمّى الرجوع (`adminBackTitle`) — يغلب الافتراضي كما في الرأس القديم
    @Environment(\.adminBackTitle) private var outerBack
    /// آخر جلب ناجح للنظرة في هذه الصفحة — «آخر تحديث» آخرها
    @State private var refreshedAt: Date?

    /// الصفحة لصاحبها (`canViewSystemSettings`)، والسيرفر رفض بلا بيانات = مقفولة
    private var canView: Bool {
        authVM.canViewSystemSettings && !(store.state == .denied && store.status == nil)
    }

    var body: some View {
        let sections = SmsPageLogic.sections(canView: canView, hasOverview: store.overview != nil)
        AdminPage(header: header, content: AnyView(SmsPageSections(sections: sections, store: store, actions: actions)),
                  updatedAt: refreshedAt)
            .refreshable { await reload(force: true) }
            .task { await reload(force: false) }
            .modifier(SmsPagePresentations(actions: actions))
            .debugStackProbe("AdminSmsView", limitKB: DebugStackLimit.page)
    }

    private var header: AdminPageHeader {
        AdminPageHeader(back: outerBack ?? backTitle,
                        title: SmsText.pageTitle,
                        subtitle: L10n.t("KWT SMS · رمز الدخول برسالة نصية", "KWT SMS · the sign-in code by text message"),
                        readOnly: canView && !authVM.canManageSettings,
                        accessory: canView ? AnyView(SmsBandHero(store: store, actions: actions)) : nil)
    }

    /// النظرة + طلبات رمز الدخول (عدد المريبة) + حماية رسائل الدخول — كل واحد وحده
    private func reload(force: Bool) async {
        guard authVM.canViewSystemSettings else { return }
        async let overview: Void = store.refresh(force: force)
        async let attempts: Void = SmsLoginAttemptsStore.shared.refresh(force: force)
        async let guardKeys: Void = SmsLoginGuardStore.shared.refresh()
        _ = await (overview, attempts, guardKeys)
        if store.state == .loaded { refreshedAt = Date() }
    }
}

/// المربّعات والنوافذ: الأدوات، تأكيد الاختبار، نتيجة الإجراء
private struct SmsPagePresentations: ViewModifier {
    @ObservedObject var actions: SmsPageActions

    func body(content: Content) -> some View {
        content
            .dsCenterBox(item: $actions.box) { kind in
                AnyView(SmsToolBoxView(kind: kind, actions: actions))
            }
            .dsAlert(L10n.t("إرسال رسالة تجريبية لرقمك؟", "Send a test message to your number?"),
                     isPresented: $actions.confirmTest, icon: "paperplane.fill") {
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
                Button(L10n.t("إرسال", "Send")) { actions.testSend() }
            } message: {
                Text(L10n.t("تُرسل رسالة تجريبية واحدة إلى رقم ملفك أنت فقط، وتخصم نقطة واحدة من الرصيد. مسموح مرة كل 10 دقائق.",
                            "One test message goes to your own profile number only and costs 1 point. Allowed once every 10 minutes."))
            }
            .dsAlert(actions.notice?.title ?? "", isPresented: Binding(
                get: { actions.notice != nil },
                set: { if !$0 { actions.notice = nil } }
            ), presenting: actions.notice) { notice in
                if notice.offersTest {
                    Button(L10n.t("لاحقاً", "Later"), role: .cancel) {}
                    Button(L10n.t("إرسال رسالة تجريبية إلى رقم المالك", "Send a test message to my number")) {
                        // بعد أن تُغلق هذه النافذة — ثم تأكيد الاختبار المعتاد (نقطة واحدة)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { actions.confirmTest = true }
                    }
                } else {
                    Button(L10n.t("حسناً", "OK"), role: .cancel) {}
                }
            } message: { notice in
                Text(notice.message)
            }
    }
}

// MARK: - الأقسام

/// الأقسام بترتيبها — كل قسم نوع مستقل خلف `AnyView` (حارس المكدس)، وبين القسمين ٢٤ (`DS.Hub.sectionGap`)
private struct SmsPageSections: View {
    let sections: [SmsPageLogic.Section]
    @ObservedObject var store: SmsBalanceStore
    @ObservedObject var actions: SmsPageActions

    var body: some View {
        if sections.isEmpty {
            AdminPageStateCard(.readOnly(L10n.t("رسائل رمز الدخول للمالك والمدير فقط.",
                                                "Sign-in code messages are for the owner and admins only.")))
        } else {
            VStack(alignment: .leading, spacing: DS.Hub.sectionGap) {
                ForEach(sections, id: \.self) { section($0) }
            }
        }
    }

    private func section(_ kind: SmsPageLogic.Section) -> AnyView {
        switch kind {
        case .sending:    return AnyView(SmsSendingSection(store: store))
        case .trend:      return store.overview.map { AnyView(SmsTrendSection(overview: $0)) } ?? AnyView(EmptyView())
        case .recent:     return store.overview.map { AnyView(SmsRecentCard(overview: $0, actions: actions)) } ?? AnyView(EmptyView())
        case .settings:   return AnyView(SmsSendingSettingsCard(overview: store.overview, actions: actions))
        case .protection: return AnyView(SmsLoginGuardCard())
        case .alerts:     return AnyView(SmsAlertsCard(alerts: store.overview?.alerts))
        case .tools:      return AnyView(SmsToolsSection(actions: actions))
        case .attempts:   return AnyView(SmsAttemptsDoorSection())
        case .how:        return AnyView(SmsHowItWorksCard(overview: store.overview))
        }
    }
}

/// عنوان القسم الصغير فوق بطاقته (٨ بينهما — `DS.Hub.sectionHeadingGap`)
struct SmsSection<Content: View>: View {
    let title: String
    var trailing: String? = nil
    var link: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: title, trailing: trailing, link: link)
            content()
        }
    }
}

// MARK: - الرأس: حلقة الرصيد على الكحلي

/// بطل الصفحة فوق الكحلي: الحلقة الكبيرة (النقاط في وسطها، كلمة الحال تحتها) وبجانبها كم يكفي ومتى يخلص وآخر تحديث،
/// ثم «شحن الرصيد» الذهبي (الإجراء الرئيسي) و«تحديث الرصيد الآن» الزجاجي. من أحجام إمكانية الوصول الحلقة فوق السطور
private struct SmsBandHero: View {
    @ObservedObject var store: SmsBalanceStore
    @ObservedObject var actions: SmsPageActions
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Hub.bandGap) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: DS.Spacing.md) { ring; facts }
                } else {
                    HStack(alignment: .center, spacing: DS.Spacing.lg) {
                        ring
                        facts.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            SmsBandButtons(actions: actions)
        }
    }

    private var level: SmsBalanceStore.Level { store.level }
    private var balance: Double? { store.status?.balance }
    private var health: AdminStoreHealth { store.adminHealth }

    /// الحلقة: الرصيد من ١٠٠ بلون حاله فوق مسار الكحلي، النقاط في وسطها تعدّ من الصفر، وكلمة الحال تحتها
    private var ring: some View {
        VStack(spacing: DS.Spacing.xs) {
            DSRingGauge(progress: SmsPageLogic.gaugeProgress(balance: balance), tint: level.bandRing,
                        size: DS.Ring.large, track: DS.Ring.bandTrack,
                        center: .count(balance.map { Int($0.rounded(.down)) }),
                        caption: L10n.t("نقطة من 100", "pts of 100"),
                        ink: DS.Color.headerTitle, captionInk: DS.Color.headerSubtitle,
                        spoken: balance.map { L10n.t("الرصيد \(SmsBalanceText.points($0)) نقطة", "Balance \(SmsBalanceText.points($0)) points") })
                .background(
                    // قبل الوصول ترسم الحلقة مسارها الفارغ (المصنوع للأبيض) — مسار الكحلي تحته فتبقى ظاهرة
                    Circle()
                        .stroke(DS.Ring.bandTrack, lineWidth: DS.Ring.large.line)
                        .opacity(balance == nil ? 1 : 0)
                        .accessibilityHidden(true)
                )
            stateWord
        }
        .fixedSize()
    }

    /// «● منخفض» بلون الحال — «—» قبل الوصول، و«تعذّر التحميل ↻» حين فشل بلا رصيد
    @ViewBuilder private var stateWord: some View {
        switch health.look {
        case .unknown:
            Button { Task { await store.refresh(force: true) } } label: {
                Label(AdminStoreHealthText.failed, systemImage: "arrow.clockwise")
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.headerSubtitle)
                    .frame(minHeight: DS.Icon.tapTarget)
            }
            .buttonStyle(DSPressStyle())
            .accessibilityHint(AdminStoreHealthText.retry)
        case .skeleton, .hidden:
            Text(verbatim: AdminStoreHealthText.placeholder)
                .dsFont(.hubRow)
                .foregroundColor(DS.Hub.lineZero)
        case .word, .staleWord:
            HStack(spacing: DS.Spacing.xsm) {
                Circle()
                    .fill(level.bandRing)
                    .frame(width: DS.Hub.bandPillDot, height: DS.Hub.bandPillDot)
                    .accessibilityHidden(true)
                Text(level.title)
                    .dsFont(.hubRow)
                    .foregroundColor(level.bandRing)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// كم يكفي · متى يخلص ومعدّله · آخر تحديث (أو «جارٍ جلب الرصيد…») · وضع تجريبي/تشغيل فعلي
    private var facts: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            if let balance {
                Text(verbatim: SmsBalanceText.enough(balance))
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.headerTitle)
                    .fixedSize(horizontal: false, vertical: true)
                if let pace = paceLine {
                    Text(verbatim: pace)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.headerSubtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if health.look == .skeleton {
                Text(L10n.t("جارٍ جلب الرصيد…", "Fetching the balance…"))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Hub.lineZero)
            } else {
                Text(SmsBalanceText.noReading)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.headerSubtitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if actions.isBusy("balance") {
                Text(L10n.t("جارٍ جلب الرصيد…", "Fetching the balance…"))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Hub.lineZero)
            } else if balance != nil, let updated = SmsBalanceText.updated(store.status?.at) {
                Text(updated)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Hub.lineZero)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let test = store.overview?.lastTestMode {
                AdminBandChip(text: test ? L10n.t("وضع تجريبي", "Test mode") : L10n.t("تشغيل فعلي", "Live"),
                              icon: test ? "flask.fill" : "dot.radiowaves.left.and.right",
                              tint: test ? DS.Hub.statusWarn : DS.Color.headerSubtitle)
            }
        }
    }

    /// «يخلص خلال 6 أيام تقريباً · معدّل يومي 3 نقاط»
    private var paceLine: String? {
        var parts: [String] = []
        if let days = store.overview?.daysLeft {
            parts.append(L10n.t("يخلص خلال \(SmsText.days(days)) تقريباً", "runs out in about \(SmsText.days(days))"))
        }
        if let avg = store.overview?.avgDailyPoints7d, avg > 0 {
            parts.append(L10n.t("معدّل يومي \(SmsText.number(avg)) نقطة", "\(SmsText.number(avg)) pts a day"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// «شحن الرصيد» الذهبي (الذهبي على الكحلي وحده) + «تحديث الرصيد الآن» الزجاجي — تحت بعض حين يضيق السطر
private struct SmsBandButtons: View {
    @ObservedObject var actions: SmsPageActions
    @Environment(\.openURL) private var openURL

    var body: some View {
        ViewThatFits(in: .horizontal) {
            AdminPillRow { recharge; refresh; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) { recharge; refresh }
        }
    }

    private var recharge: some View {
        AdminPillButton(title: L10n.t("شحن الرصيد", "Top up balance"), icon: "creditcard.fill", style: .gold) {
            openURL(SmsBalanceStore.rechargeURL)
        }
        .fixedSize()
        .accessibilityHint(L10n.t("يفتح صفحة شراء الرصيد في حساب KWT SMS", "Opens the KWT SMS buy-credits page"))
    }

    private var refresh: some View {
        let busy = actions.isBusy("balance")
        return AdminPillButton(title: busy ? L10n.t("جارٍ جلب الرصيد…", "Fetching balance…")
                                           : L10n.t("تحديث الرصيد الآن", "Refresh balance now"),
                               icon: busy ? "hourglass" : "arrow.triangle.2.circlepath", style: .glass) {
            actions.refreshBalance()
        }
        .fixedSize()
        .disabled(busy)
        .accessibilityHint(L10n.t("يسأل KWT SMS عن الرصيد الحالي ويحفظه", "Asks KWT SMS for the current balance and saves it"))
    }
}

// MARK: - رموز الدخول المرسلة: اليوم · 7 أيام · 30 يوماً

/// بطاقة واحدة: ثلاثة أعمدة بخطوط رفيعة بينها (العدد، الفترة، القبول بحلقة مصغّرة، النقاط)، ثم صفّ «هذه الساعة»
private struct SmsSendingSection: View {
    @ObservedObject var store: SmsBalanceStore

    var body: some View {
        SmsSection(title: L10n.t("رموز الدخول المرسلة", "Sign-in codes sent")) {
            if let overview = store.overview {
                AnyView(SmsTotalsCard(overview: overview))
            } else if store.state == .loading || store.state == .idle {
                AnyView(AdminPageStateCard(.loading(L10n.t("جاري جلب أرقام الرسائل…", "Loading message stats…"), rows: 2)))
            } else {
                AnyView(AdminPageStateCard(.error(L10n.t("تعذّر جلب أرقام الرسائل الآن", "Couldn't load message stats"),
                                                  message: L10n.t("اسحب للتحديث أو أعد المحاولة.", "Pull to refresh or retry."),
                                                  retry: { Task { await store.refresh(force: true) } })))
            }
        }
    }
}

private struct SmsTotalsCard: View {
    let overview: SmsOverview
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 0) {
                        column(L10n.t("اليوم", "Today"), overview.today)
                        AdminRowDivider()
                        column(L10n.t("7 أيام", "7 days"), overview.days7)
                        AdminRowDivider()
                        column(L10n.t("30 يوماً", "30 days"), overview.days30)
                    }
                } else {
                    HStack(alignment: .top, spacing: DS.Spacing.md) {
                        column(L10n.t("اليوم", "Today"), overview.today)
                        columnDivider
                        column(L10n.t("7 أيام", "7 days"), overview.days7)
                        columnDivider
                        column(L10n.t("30 يوماً", "30 days"), overview.days30)
                    }
                }
            }
            .padding(.bottom, DS.Spacing.sm)
            AdminRowDivider()
            SmsHourRow(count: overview.hourCount, cap: overview.hourCap)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private var columnDivider: some View {
        Rectangle()
            .fill(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke * 2))
            .frame(width: DS.Border.width / 2)
            .accessibilityHidden(true)
    }

    private func column(_ title: String, _ totals: SmsOverview.Totals) -> some View {
        SmsTotalsColumn(title: title, totals: totals)
    }
}

/// عمود فترة: عدد رموز الدخول، اسم الفترة، القبول بحلقة مصغّرة، النقاط
private struct SmsTotalsColumn: View {
    let title: String
    let totals: SmsOverview.Totals

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            // العدد يعدّ مرة عند الظهور (`DSCountText`) — «تقليل الحركة»: ثابت
            DSCountText(value: totals.sends) { n in Text(verbatim: n.map(AdminNumberText.grouped) ?? "—") }
                .dsFont(.hubPulse)
                .monospacedDigit()
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textSecondary)
            HStack(spacing: DS.Spacing.xs) {
                if let pct = totals.acceptancePct {
                    DSRingValue(progress: pct / 100, tint: DS.Color.success)
                }
                Text(verbatim: acceptance)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, DS.Spacing.xxs)
            Text(verbatim: points)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.Spacing.xs)
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

/// «هذه الساعة (للجميع)» بحلقة مصغّرة بلون الحال و«12 من 100»
private struct SmsHourRow: View {
    let count: Int
    let cap: Int

    var body: some View {
        let share = cap > 0 ? Double(count) / Double(cap) : 0
        HStack(spacing: DS.Spacing.sm) {
            Text(L10n.t("هذه الساعة (للجميع)", "This hour (everyone)"))
                .dsFont(.body)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Spacing.sm)
            DSRingValue(progress: share,
                        tint: share >= 0.8 ? DS.Color.error : share >= 0.5 ? DS.Color.warning : DS.Color.success,
                        text: L10n.t("\(count) من \(cap)", "\(count) of \(cap)"))
        }
        .frame(minHeight: DS.Hub.rowMinHeight)
        .padding(.top, DS.Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - آخر ٣٠ يوماً

/// الرسم ظاهراً (كان مطويّاً): سطر النتائج، الأعمدة وخط الرصيد، المحور، المفتاح
private struct SmsTrendSection: View {
    let overview: SmsOverview

    /// مقبول · فشل · غير معروف (+ تجريبية)
    private func outcomeLine(_ t: SmsOverview.Totals) -> String {
        var parts = [L10n.t("مقبول \(t.accepted)", "\(t.accepted) accepted"),
                     L10n.t("فشل \(t.failed)", "\(t.failed) failed"),
                     L10n.t("غير معروف \(t.unknown)", "\(t.unknown) unknown")]
        if t.testSends > 0 { parts.append(L10n.t("تجريبي \(t.testSends)", "\(t.testSends) test")) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let series = overview.series()
        let maxSends = max(1, series.map(\.sends).max() ?? 0)
        let total = series.reduce(0) { $0 + $1.sends }
        SmsSection(title: L10n.t("آخر 30 يوماً", "Last 30 days")) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text(outcomeLine(overview.days30))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(L10n.t("آخر 30 يوماً: \(outcomeLine(overview.days30))", "Last 30 days: \(outcomeLine(overview.days30))"))
                if total == 0 && !series.contains(where: { $0.balance != nil }) {
                    Text(L10n.t("لا إرسال خلال آخر 30 يوماً بعد — يمتلئ الرسم مع أول رموز الدخول.",
                                "No sends in the last 30 days yet — the chart fills with the first sign-in codes."))
                        .dsFont(.subtitle)
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
