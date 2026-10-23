import SwiftUI
import Combine

// MARK: - «رسائل رمز الدخول (KWT SMS)» (طلب المالك ٢٠٢٦-١٠-١٩ «نضيف قسم جديد تبع kwt-sms» — في «الفريق والأمان»)
//
// المالك والمدير فقط (نفس صلاحية `sms_admin_overview()` على السيرفر — غيرهما 42501). البيانات الحية منذ ٢٠٢٦-١٠-٢٠
// (`AdminSmsData.swift`): الرأس (الرصيد وحالته، يكفي كم رمز وكم يوم، تحديث حي، الشحن) ← الإرسال (اليوم/٧/٣٠،
// القبول، النقاط، عدّاد الساعة) ← طلبات رمز الدخول (`AdminSmsAttempts.swift`) ← آخر ٣٠ يوماً ← آخر الإرسالات (فحص الحالة) ←
// الأدوات (رسالة تجريبية للمالك، التحقق من رقم) ← إعدادات الإرسال (الحدود، اسم المرسل، الدول المتاحة، نص الرسالة —
// `AdminSmsSettings.swift`، المكان الوحيد لتعديلها) ← تنبيهات الرصيد ← طريقة العمل (مطويّة).
// تبسيط ٢٠٢٦-١٠-٢٢ (موافقة المالك): الصفحة = بطاقة الرصيد والإرسال الواحدة (الحلقة + الشحن/التحديث + اليوم/٧/٣٠ + هذه
// الساعة) ← طلبات رمز الدخول (المشبوهة + أحدث ٣ ثم «الكل») ← «آخر 30 يوماً» مطويّة ← آخر الإرسالات. «إعدادات الإرسال»
// (ومعها تنبيهات الرصيد) و«طريقة العمل» صفحتان من قائمة ⋯ في الرأس مع الأدوات.
// الدفعة ج (٢٠٢٦-١٠-٢٠): كل معلومة مرة واحدة — حُذفت بطاقتا «الحدود» و«الإعداد» وصفّا «المرسلون/التغطية» في الأدوات، وصفّا
// «الحدود/التنبيهات» في «طريقة العمل» (كانت أزواجاً مكررة).
// حارس المكدس (تعطّل «اليوم» على الجوال ٢٠٢٦-١٠-٢٠): كل بطاقة نوع مستقل خلف `AnyView` — لا جسم واحد ضخم.

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
    /// صفحتا قائمة ⋯: «إعدادات الإرسال» و«طريقة العمل»
    @Published var showsSettings = false
    @Published var showsHow = false
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
    @Environment(\.adminArea) private var area

    var body: some View {
        AdminHubPage {
            AnyView(SmsHeroHeader(backTitle: backTitle, actions: actions))
        } content: {
            AnyView(SmsPageContent(store: store, actions: actions))
        }
        .refreshable {
            async let overview: Void = store.refresh(force: true)
            async let attempts: Void = SmsLoginAttemptsStore.shared.refresh(force: true)
            _ = await (overview, attempts)
        }
        .task { await store.refresh() }
        .modifier(SmsPagePresentations(actions: actions))
        .navigationDestination(isPresented: $actions.showsSettings) {
            AdminLazyPage { [area] in AnyView(SmsSettingsPage().adminArea(area)) }
        }
        .navigationDestination(isPresented: $actions.showsHow) {
            AdminLazyPage { [area] in AnyView(SmsHowItWorksPage().adminArea(area)) }
        }
    }
}

/// صفحة «إعدادات الإرسال» (من ⋯): الحدود، اسم المرسل، الدول، نص الرسالة، وتنبيهات الرصيد — المالك يعدّل، المدير يقرأ
struct SmsSettingsPage: View {
    @ObservedObject private var store = SmsBalanceStore.shared
    @StateObject private var actions = SmsPageActions()
    @EnvironmentObject private var authVM: AuthViewModel

    var body: some View {
        AdminHubPage {
            AdminBandHeader(backTitle: SmsText.pageTitle, title: L10n.t("إعدادات الإرسال", "Sending settings"),
                            subtitle: L10n.t("الحدود · اسم المرسل · تنبيهات الرصيد", "Limits · sender name · balance alerts"))
        } content: {
            if authVM.canViewSystemSettings {
                AnyView(SmsSendingSettingsCard(overview: store.overview, actions: actions))
            } else {
                DSNoteCard(L10n.t("رسائل رمز الدخول للمالك والمدير فقط.", "Sign-in code messages are for the owner and admins only."),
                           icon: "lock.fill", tint: DS.Color.warning)
            }
        }
        .refreshable { await store.refresh(force: true) }
        .task { await store.refresh() }
        .modifier(SmsPagePresentations(actions: actions))
    }
}

/// صفحة «طريقة العمل» (من ⋯): المسار، ما يُحفظ، رمز الدخول (وتحذير لوحة KWT)، من يرى ماذا
struct SmsHowItWorksPage: View {
    @ObservedObject private var store = SmsBalanceStore.shared
    @EnvironmentObject private var authVM: AuthViewModel

    var body: some View {
        AdminHubPage {
            AdminBandHeader(backTitle: SmsText.pageTitle, title: L10n.t("طريقة العمل", "How it works"),
                            subtitle: L10n.t("المسار · ما يُحفظ · رمز الدخول · من يرى ماذا",
                                             "The path · what's kept · the sign-in code · who sees what"))
        } content: {
            if authVM.canViewSystemSettings {
                AnyView(SmsHowItWorksCard(overview: store.overview))
            } else {
                DSNoteCard(L10n.t("رسائل رمز الدخول للمالك والمدير فقط.", "Sign-in code messages are for the owner and admins only."),
                           icon: "lock.fill", tint: DS.Color.warning)
            }
        }
        .task { await store.refresh() }
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
                    Button(L10n.t("إرسال رسالة تجريبية لرقمي", "Send a test message to my number")) {
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

/// المحتوى تحت الرأس — كل بطاقة نوع مستقل (حارس المكدس)
private struct SmsPageContent: View {
    @ObservedObject var store: SmsBalanceStore
    @ObservedObject var actions: SmsPageActions
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        if !authVM.canViewSystemSettings || (store.state == .denied && store.status == nil) {
            DSNoteCard(L10n.t("رسائل رمز الدخول للمالك والمدير فقط.", "Sign-in code messages are for the owner and admins only."),
                       icon: "lock.fill", tint: DS.Color.warning)
        } else {
            VStack(spacing: DS.Hub.stackSpacing) {
                // الرصيد والإرسال في بطاقة واحدة (كانا رأساً كحلياً + بطاقة «الإرسال»)
                AnyView(SmsBalanceCard(store: store, actions: actions))
                // «طلبات رمز الدخول» — دالتها مستقلة عن النظرة، فتظهر ولو تعذّرت (AdminSmsAttempts.swift)
                AnyView(SmsAttemptsCard())
                if let overview = store.overview {
                    AnyView(SmsTrendCard(overview: overview))
                    AnyView(SmsRecentCard(overview: overview, actions: actions))
                }
            }
        }
    }
}

// MARK: - الرأس

private struct SmsHeroHeader: View {
    let backTitle: String
    @ObservedObject var actions: SmsPageActions
    @EnvironmentObject private var authVM: AuthViewModel

    var body: some View {
        AdminBandHeader(backTitle: backTitle,
                        title: SmsText.pageTitle,
                        subtitle: L10n.t("KWT SMS · رمز الدخول برسالة نصية", "KWT SMS · the sign-in code by text message")) {
            // ⋯: صفحتا «إعدادات الإرسال» و«طريقة العمل»، ثم الأدوات (رسالة تجريبية للمالك، فحص رقم)
            Menu {
                Button { actions.showsSettings = true } label: {
                    Label(L10n.t("إعدادات الإرسال", "Sending settings"), systemImage: "slider.horizontal.3")
                }
                Button { actions.showsHow = true } label: {
                    Label(L10n.t("طريقة العمل", "How it works"), systemImage: "info.circle")
                }
                Divider()
                if authVM.isOwner {
                    Button { actions.confirmTest = true } label: {
                        Label(L10n.t("إرسال رسالة تجريبية لرقمي", "Send a test message to my number"), systemImage: "paperplane.fill")
                    }
                    .disabled(actions.isBusy("test"))
                }
                Button { actions.box = .validate } label: {
                    Label(L10n.t("التحقق من رقم", "Check a number"), systemImage: "phone.fill")
                }
            } label: {
                AdminGlassCircle(symbol: "ellipsis")
            }
            .accessibilityLabel(L10n.t("المزيد", "More"))
        }
    }
}

// MARK: - الرصيد والإرسال (بطاقة واحدة)

/// الرصيد (الحلقة وحالته وكم يكفي) + الشحن/التحديث + اليوم/٧/٣٠ + هذه الساعة
private struct SmsBalanceCard: View {
    @ObservedObject var store: SmsBalanceStore
    @ObservedObject var actions: SmsPageActions
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SmsBalanceBlock(store: store)
            SmsHeroButtons(actions: actions)
            if let overview = store.overview {
                Group {
                    if typeSize.isAccessibilitySize {
                        VStack(spacing: DS.Spacing.sm) { tiles(overview) }
                    } else {
                        HStack(alignment: .top, spacing: DS.Spacing.sm) { tiles(overview) }
                    }
                }
                SmsHourRow(count: overview.hourCount, cap: overview.hourCap)
            } else if store.state == .loading {
                DSPageLoader(L10n.t("جاري جلب أرقام الرسائل…", "Loading message stats…"),
                             size: DS.Icon.loaderArtInline, fillsSpace: false)
            } else if store.overviewFailed || store.state == .failed {
                DSNoteCard(L10n.t("تعذّر جلب أرقام الرسائل الآن — اسحب للتحديث.",
                                  "Couldn't load message stats — pull to refresh."),
                           icon: "wifi.exclamationmark", tint: DS.Color.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    @ViewBuilder private func tiles(_ overview: SmsOverview) -> some View {
        SmsTotalsTile(title: L10n.t("اليوم", "Today"), totals: overview.today)
        SmsTotalsTile(title: L10n.t("7 أيام", "7 days"), totals: overview.days7)
        SmsTotalsTile(title: L10n.t("30 يوماً", "30 days"), totals: overview.days30)
    }
}

/// الرصيد وحالته وكم يكفي، والحلقة الكبيرة
private struct SmsBalanceBlock: View {
    @ObservedObject var store: SmsBalanceStore

    var body: some View {
        let level = store.level
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.sm) {
                    Text(L10n.t("الرصيد · \(level.title)", "Balance · \(level.title)"))
                        .dsFont(.headline)
                        .foregroundColor(DS.Color.textPrimary)
                    if let test = store.overview?.lastTestMode {
                        AdminValueChip(text: test ? L10n.t("وضع تجريبي", "Test mode") : L10n.t("تشغيل فعلي", "Live"),
                                       icon: test ? "flask.fill" : "dot.radiowaves.left.and.right",
                                       tint: test ? DS.Color.warning : DS.Color.success)
                    }
                }
                if let balance = store.status?.balance {
                    Text(verbatim: enoughLine(balance))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let updated = SmsBalanceText.updated(store.status?.at) {
                        Text(updated)
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if store.state == .loading {
                    Text(L10n.t("جارٍ جلب الرصيد…", "Fetching the balance…"))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                } else {
                    Text(SmsBalanceText.noReading)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Spacing.xs)
                }
            }
            Spacer(minLength: 0)
            // الحلقة الكبيرة الموحّدة: الرصيد من ١٠٠ نقطة بلون حاله، والنقاط في وسطها تعدّ من الصفر
            if store.status?.balance != nil || store.state == .loading {
                let balance = store.status?.balance
                DSRingGauge(progress: balance.map { min(1, $0 / SmsBalanceStore.gaugeReference) }, tint: level.tint,
                            size: DS.Ring.large,
                            center: .count(balance.map { Int($0.rounded(.down)) }),
                            caption: L10n.t("نقطة من 100", "pts of 100"),
                            spoken: balance.map { L10n.t("الرصيد \(SmsBalanceText.points($0)) نقطة", "Balance \(SmsBalanceText.points($0)) points") })
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// «يكفي نحو ١٧ رمز دخول · يخلص خلال ٦ أيام تقريباً · معدّل يومي ٣ نقاط»
    private func enoughLine(_ balance: Double) -> String {
        var parts = [SmsBalanceText.enough(balance)]
        if let days = store.overview?.daysLeft {
            parts.append(L10n.t("يخلص خلال \(SmsText.days(days)) تقريباً", "runs out in about \(SmsText.days(days))"))
        }
        if let avg = store.overview?.avgDailyPoints7d, avg > 0 {
            parts.append(L10n.t("معدّل يومي \(SmsText.number(avg)) نقطة", "\(SmsText.number(avg)) pts a day"))
        }
        return parts.joined(separator: " · ")
    }
}

/// «شحن الرصيد» + «تحديث الرصيد الآن» — عمود واحد إن كبر الخط
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
            AdminPillLabel(title: L10n.t("شحن الرصيد", "Top up balance"), icon: "creditcard.fill",
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
                           style: .soft, height: DS.Hub.pillHeightCard)
                .fixedSize()
        }
        .buttonStyle(DSPressStyle())
        .disabled(busy)
        .accessibilityHint(L10n.t("يسأل KWT SMS عن الرصيد الحالي ويحفظه", "Asks KWT SMS for the current balance and saves it"))
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
            // «قبول 98%» بحلقة مصغّرة موحّدة (الدفعة ١٠)
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

/// «هذه الساعة: ١٢ من ١٠٠» بشريط
private struct SmsHourRow: View {
    let count: Int
    let cap: Int

    var body: some View {
        let share = cap > 0 ? Double(count) / Double(cap) : 0
        // الحلقة المصغّرة الموحّدة (الدفعة ١٠، كانت شريطاً) بلون الحال كما كان
        SmsKVRow(icon: "gauge.with.dots.needle.33percent", label: L10n.t("هذه الساعة (للجميع)", "This hour (everyone)")) {
            DSRingValue(progress: share,
                        tint: share >= 0.8 ? DS.Color.error : share >= 0.5 ? DS.Color.warning : DS.Color.success,
                        text: L10n.t("\(count) من \(cap)", "\(count) of \(cap)"))
        }
    }
}

// MARK: - آخر ٣٠ يوماً

/// مطويّة افتراضياً: سطر «آخر 30 يوماً» وتحته سطر النتائج، والضغط يفتح الرسم
private struct SmsTrendCard: View {
    let overview: SmsOverview
    @State private var open = false

    /// مقبول · فشل · غير معروف (+ تجريبية) — سطر واحد بدل الحلقة المكررة
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
        AdminSectionCard(title: L10n.t("آخر 30 يوماً", "Last 30 days"), isOpen: $open,
                         summary: outcomeLine(overview.days30)) {
            Text(outcomeLine(overview.days30))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textSecondary)
                .accessibilityLabel(L10n.t("آخر 30 يوماً: \(outcomeLine(overview.days30))", "Last 30 days: \(outcomeLine(overview.days30))"))
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
