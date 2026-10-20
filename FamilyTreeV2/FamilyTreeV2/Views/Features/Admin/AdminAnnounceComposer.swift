import SwiftUI
import Supabase

// MARK: - «إعلان جديد» السريع (طلب المالك ٢٠٢٦-١٠-٢٠: «الاعلانات ابى زر سريع و خارجي… مختصر»، «قسّم الإعلانات يكون
// مختصر و ملموم»، «اربط قسم الاعلانات مع ارسال الاشعارات يكون في خيار» ← اختار «الاثنين مع بعض»)
//
// زرّ مكبّر الصوت في رأس «اليوم» و«إعلان جديد» في بطاقة «الإعلانات» يفتحان مربّعاً واحداً مختصراً: العنوان، النص، وخياران
// (☑ نشر كإعلان في الأخبار · ☑ إرسال إشعار للأعضاء — واحد على الأقل)، و«خيارات أكثر» مطويّة (الجمهور: الكل / دولة /
// أعضاء، والجدولة)، ثم «إرسال» بتأكيد قصير. لا منطق جديد:
//   • الخبر = `NewsViewModel.postNews(type: «إعلان»)` نفسه (مسار «خبر جديد»)، باسم «إدارة العائلة».
//   • الإشعار = `NotificationViewModel.sendNotification` / `scheduleNotification` بنوع `admin_broadcast` (صفحة «إشعار
//     للأعضاء» نفسها) — والدفع من مشغّل جدول الإشعارات على السيرفر كما هو.
// الإشعار المزدوج: نشر الخبر لا يُشعر الأعضاء (لا مشغّل على `news` غير `trg_content_force_pending`، ولا دالة طرفية)؛
// يُشعر الإدارة فقط بـ«منشور جديد». فمع الخيارين يصل الأعضاءَ إشعار واحد (الإعلان)، ويُترك تنبيه الإدارة حين يصلها الإعلان
// نفسه (الجمهور «الكل») — لا إشعاران لأحد. الصلاحية `canSendNotifications` (المالك والمدير — نشرهما مباشر)، وحارس السيرفر
// يبقى الحَكَم.

/// قراءة خفيفة لبطاقة «الإعلانات» (لا شيء جديد على السيرفر)
enum AdminAnnounceFetch {
    /// «معدل الصحة» نفسه في «وصول الإشعارات»: الرموز السليمة (أطول من ٢٠ حرفاً) من كل الأجهزة — nil إن تعذّر
    static func pushHealthPercent() async -> Int? {
        struct Row: Decodable { let token: String? }
        do {
            let rows: [Row] = try await SupabaseConfig.client
                .from("device_tokens").select("token").execute().value
            guard !rows.isEmpty else { return nil }
            let valid = rows.filter { ($0.token ?? "").count > 20 }.count
            return Int(Double(valid) / Double(rows.count) * 100)
        } catch {
            return nil
        }
    }

    /// لون نسبة الصحة — نفس عتبات «وصول الإشعارات» (٩٠ / ٧٠)
    nonisolated static func healthTint(_ rate: Int) -> Color {
        rate >= 90 ? DS.Color.success : (rate >= 70 ? DS.Color.warning : DS.Color.error)
    }
}

// MARK: - العرض: نافذة مستقلة (حارس المكدس)

/// يعرض المربّع في نافذة فوق كل شيء (مثل `DeathAnnouncementPresenter`) — فلا يحمل رأس «اليوم» ولا البطاقة أي مُعدِّل
/// عرض (`fullScreenCover`/تنبيه): «اليوم» على سقف مكدس الجوال، وكل مُعدِّل فيه يعمّقه
@MainActor
enum AdminAnnounceWindow {
    private static var window: UIWindow?
    private static weak var previousKey: UIWindow?

    static func open(authVM: AuthViewModel, newsVM: NewsViewModel, notificationVM: NotificationViewModel,
                     memberVM: MemberViewModel) {
        guard window == nil, let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        previousKey = scene.windows.first(where: \.isKeyWindow)
        let root = DSCenterPanel(onBackgroundTap: nil, hugsContent: true) {
            AdminAnnounceComposer(onClose: { close() })
                .environmentObject(authVM)
                .environmentObject(newsVM)
                .environmentObject(notificationVM)
                .environmentObject(memberVM)
        }
        .environment(\.locale, LanguageManager.shared.locale)
        // نافذة مستقلّة لا تصلها بيئة التطبيق — لون القسم المختار (أزرار الإجراء)
        .dsSection(AppSection.current)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        let w = UIWindow(windowScene: scene)
        // تحت نافذة التنبيهات (.alert + 1) فيظهر التأكيد فوقه
        w.windowLevel = .alert
        w.backgroundColor = .clear
        w.overrideUserInterfaceStyle = DSPopupPresenter.appInterfaceStyle(in: scene)
        w.rootViewController = host
        w.makeKeyAndVisible()
        window = w
    }

    static func close() {
        guard let w = window else { return }
        window = nil
        UIView.animate(withDuration: 0.2, animations: { w.alpha = 0 }, completion: { _ in
            w.isHidden = true
            w.rootViewController = nil
            previousKey?.makeKey()
        })
    }
}

/// زرّ مكبّر الصوت الزجاجي في رأس «اليوم» (لمن يرسل للأعضاء فقط — يقرّر من يضعه)
struct AdminAnnounceLauncher: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @EnvironmentObject private var memberVM: MemberViewModel

    var body: some View {
        Button {
            AdminAnnounceWindow.open(authVM: authVM, newsVM: newsVM, notificationVM: notificationVM, memberVM: memberVM)
        } label: {
            AdminGlassCircle(symbol: "megaphone")
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(L10n.t("إعلان جديد", "New announcement"))
        .accessibilityHint(L10n.t("نشر في الأخبار وإشعار للأعضاء", "Post to News and notify members"))
    }
}

// MARK: - بطاقة «الإعلانات» المختصرة (داخل «المناسبات والإعلانات»)

/// بطاقة واحدة: «إعلان جديد» ثم أربع خلايا (٢×٢ بخطوط رفيعة): المجدولة · رسالة تحديث التطبيق · وصول الإشعارات ·
/// الخيارات الكاملة (صفحة «إشعار للأعضاء» القديمة كما هي). تحلّ محلّ بطاقتي «إرسال للأعضاء» و«هل يصلهم؟»
struct AdminAnnouncementsCard: View {
    /// صفوف الفهرس التي تعرضها هذه البطاقة (لا تتكرّر كبطاقات أدوات في القسم — والبحث يبقى يجدها)
    static let toolIds: Set<String> = ["ann.notify", "ann.update", "ann.scheduled", "ann.push"]

    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showScheduled = false
    @State private var health: Int? = nil

    private enum Target { case scheduled, update, reach, full }

    private struct Cell: Identifiable {
        let id: Target
        let icon: String
        let tint: Color
        let title: String
        let note: String
        var noteTint: Color = DS.Color.textTertiary
    }

    private var cells: [Cell] {
        let scheduled = notificationVM.scheduledNotifications.count
        return [
            Cell(id: .scheduled, icon: "clock.badge.checkmark.fill", tint: DS.Color.sea,
                 title: L10n.t("المجدولة", "Scheduled"),
                 note: scheduled > 0 ? L10n.t("\(scheduled) بانتظار وقتها", "\(scheduled) waiting")
                                     : L10n.t("لا شيء مجدول", "Nothing scheduled"),
                 noteTint: scheduled > 0 ? DS.Color.warning : DS.Color.textTertiary),
            Cell(id: .update, icon: "sparkles", tint: DS.Color.sea,
                 title: L10n.t("رسالة تحديث التطبيق", "App update message"),
                 note: L10n.t("المستجدات + إشعار", "Updates + a push")),
            Cell(id: .reach, icon: "bell.and.waves.left.and.right.fill", tint: DS.Color.info,
                 title: L10n.t("وصول الإشعارات", "Notification reach"),
                 note: health.map { L10n.t("\($0)٪ سليمة", "\($0)% healthy") } ?? "—",
                 noteTint: health.map(AdminAnnounceFetch.healthTint) ?? DS.Color.textTertiary),
            Cell(id: .full, icon: "slider.horizontal.3", tint: DS.Color.slate,
                 title: L10n.t("الخيارات الكاملة", "All options"),
                 note: L10n.t("صفحة «إشعار للأعضاء»", "The “Notify members” page"))
        ]
    }

    /// عمودان، وعمود واحد مع الخط الكبير جداً
    private var columns: Int { typeSize >= .xxxLarge ? 1 : 2 }

    var body: some View {
        let all = cells
        let rows = stride(from: 0, to: all.count, by: columns).map { Array(all[$0..<min($0 + columns, all.count)]) }
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminCardHeader(title: L10n.t("الإعلانات", "Announcements"))
            Button {
                AdminAnnounceWindow.open(authVM: authVM, newsVM: newsVM, notificationVM: notificationVM, memberVM: memberVM)
            } label: {
                AdminPillLabel(title: L10n.t("إعلان جديد", "New announcement"), icon: "megaphone.fill",
                               style: .navy, height: DS.Hub.pillHeightCard, fullWidth: true)
            }
            .buttonStyle(DSPressStyle())
            .accessibilityHint(L10n.t("نشر في الأخبار وإشعار للأعضاء", "Post to News and notify members"))
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                    if r > 0 { AdminRowDivider() }
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.element.id) { i, cell in
                            if i > 0 { AdminColumnDivider() }
                            link(cell)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
        .dsCenterBox(isPresented: $showScheduled) {
            ScheduledNotificationsSheet()
                .environmentObject(notificationVM)
                .environmentObject(memberVM)
        }
        .task { health = await AdminAnnounceFetch.pushHealthPercent() ?? health }
    }

    /// خلف `AnyView` — كل خلية نوع صغير (حارس المكدس)
    private func link(_ cell: Cell) -> AnyView {
        switch cell.id {
        case .scheduled:
            return AnyView(Button { showScheduled = true } label: { cellView(cell) }
                .buttonStyle(DSPressStyle()))
        default:
            return AnyView(NavigationLink {
                AdminLazyPage { Self.page(cell.id) }.adminBackTitle(AdminArea.occasions.title).adminArea(.occasions)
            } label: { cellView(cell) }
            .buttonStyle(DSPressStyle()))
        }
    }

    private func cellView(_ cell: Cell) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            AdminIconSquare(symbol: cell.icon, tint: cell.tint, side: DS.Hub.miniIcon,
                            radius: DS.Hub.miniIconRadius, glyph: DS.Glyph.md)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(cell.title)
                    .dsFont(.hubButton)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: cell.note)
                    .dsFont(.caption)
                    .monospacedDigit()
                    .foregroundColor(cell.noteTint.dsReadableGlyph)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Hub.miniCellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private static func page(_ target: Target) -> AnyView {
        switch target {
        case .update:    return AnyView(AdminMessagingHubView(startsWithUpdate: true))
        case .reach:     return AnyView(AdminPushHealthView())
        case .full, .scheduled: return AnyView(AdminMessagingHubView())
        }
    }
}

// MARK: - المربّع المختصر

struct AdminAnnounceComposer: View {
    /// إغلاق المربّع (الإلغاء، أو «حسناً» بعد «تم الإرسال»)
    let onClose: () -> Void

    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @Environment(\.dsSection) private var section

    enum Audience: Hashable { case all, country, members }

    @State private var title = ""
    @State private var text = ""
    @State private var publishNews = true
    @State private var sendNotice = true
    /// حاول إطفاء آخر خيار — تظهر «لازم يبقى خيار واحد»
    @State private var oneRequired = false
    @State private var moreOpen = false
    @State private var audience: Audience = .all
    @State private var country: String? = nil
    @State private var selected: Set<UUID> = []
    @State private var search = ""
    @State private var scheduleOn = false
    @State private var scheduledDate = Date().addingTimeInterval(3600)
    @State private var confirm = false
    @State private var isSending = false
    @State private var failure: String? = nil
    /// ملخّص ما أُرسل — «تم الإرسال» ثم يُغلق المربّع
    @State private var sent: String? = nil

    /// العنوان الجاهز الأول في «إشعار للأعضاء» — العنوان حين يُترك فارغاً
    private static let defaultTitle = AdminNotificationsView.presetTitles.first ?? "عائلة المحمدعلي"
    private static let memberRowsLimit = 6

    private let tint = DS.Color.brandFill

    // MARK: مشتقات

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var noticeTitle: String { trimmed(title).isEmpty ? Self.defaultTitle : trimmed(title) }
    private var noticeBody: String { trimmed(text).isEmpty ? noticeTitle : trimmed(text) }

    /// نص الخبر: العنوان (إن كُتب) سطراً أول ثم النص
    private var newsContent: String {
        let t = trimmed(title)
        return t.isEmpty ? trimmed(text) : t + "\n" + trimmed(text)
    }

    /// المستلمون المحتملون — نفس فلتر «إشعار للأعضاء»: بلا المعلّقين والمتوفّين والمجمّدين
    private var activeMembers: [FamilyMember] {
        memberVM.allMembers.filter { $0.role != .pending && !($0.isDeceased ?? false) && $0.status != .frozen }
    }

    private func iso(_ m: FamilyMember) -> String? {
        let phone = trimmed(m.phoneNumber ?? "")
        guard !phone.isEmpty else { return nil }
        return KuwaitPhone.detectCountryAndLocal(phone).country.isoCode
    }

    /// الدول التي فيها أعضاء (الكويت والسعودية أولاً — كما في «إشعار للأعضاء»)
    private var countries: [(country: KuwaitPhone.Country, count: Int)] {
        var counts: [String: Int] = [:]
        for m in activeMembers { if let c = iso(m) { counts[c, default: 0] += 1 } }
        let pinned = ["KW", "SA"]
        let pinnedItems = pinned.compactMap { code in
            KuwaitPhone.supportedCountries.first { $0.isoCode == code }.map { ($0, counts[code] ?? 0) }
        }
        let others = KuwaitPhone.supportedCountries
            .filter { !pinned.contains($0.isoCode) }
            .compactMap { c in counts[c.isoCode].map { (c, $0) } }
            .sorted { $0.1 > $1.1 }
        return (pinnedItems + others).map { (country: $0.0, count: $0.1) }
    }

    /// nil = للجميع؛ قائمة فارغة = لا أحد (لا تتحوّل للجميع — ب-٩)
    private var targetIds: [UUID]? {
        switch audience {
        case .all:
            return nil
        case .country:
            guard let country else { return [] }
            return activeMembers.filter { iso($0) == country }.map(\.id)
        case .members:
            return Array(selected)
        }
    }

    private var audienceCount: Int { targetIds?.count ?? activeMembers.count }

    /// ما يمنع الإرسال (سطر تحت الخيارات) — nil = جاهز
    private var blocker: String? {
        if publishNews && trimmed(text).isEmpty {
            return L10n.t("اكتب نص الإعلان", "Write the announcement")
        }
        if sendNotice, let ids = targetIds, ids.isEmpty {
            return audience == .country ? L10n.t("اختر دولة فيها أعضاء", "Pick a country with members")
                                        : L10n.t("اختر عضواً واحداً على الأقل", "Pick at least one member")
        }
        return nil
    }

    private var canSubmit: Bool { (publishNews || sendNotice) && blocker == nil && !isSending }

    private var scheduledText: String {
        let f = DateFormatter()
        f.locale = LanguageManager.shared.locale
        f.dateFormat = L10n.isArabic ? "EEEE d MMMM • h:mm a" : "EEEE d MMM • h:mm a"
        return f.string(from: scheduledDate)
    }

    private var audienceText: String {
        switch targetIds {
        case nil:      return L10n.t("للجميع (\(audienceCount))", "everyone (\(audienceCount))")
        case let ids?: return L10n.t("لـ \(ids.count) عضو", "\(ids.count) members")
        }
    }

    // MARK: المربّع

    var body: some View {
        DSComposer(
            title: L10n.t("إعلان جديد", "New announcement"),
            subtitle: L10n.t("في الأخبار وإشعار للأعضاء — بخطوة واحدة", "To News and a push — in one step"),
            icon: "megaphone.fill",
            tint: tint,
            actionTitle: L10n.t("إرسال", "Send"),
            actionIcon: "paperplane.fill",
            canSubmit: canSubmit,
            isBusy: isSending,
            note: footnote,
            hasUnsavedChanges: !trimmed(title).isEmpty || !trimmed(text).isEmpty,
            onSubmit: { confirm = true },
            onCancel: { onClose() }
        ) {
            messageSection
            channelsSection
            if sendNotice {
                moreSection
            }
        }
        .dsAlert(scheduleOn && sendNotice ? L10n.t("تأكيد الإرسال والجدولة", "Confirm send & schedule")
                                          : L10n.t("تأكيد الإرسال", "Confirm send"),
                 isPresented: $confirm, icon: "paperplane.fill") {
            Button(L10n.t("إرسال", "Send"), role: sendNotice && targetIds == nil && !scheduleOn ? .destructive : nil) {
                Task { await send() }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(confirmText)
        }
        .dsAlert(L10n.t("تعذّر الإرسال", "Couldn't send"), isPresented: Binding(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
        )) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
        .dsAlert(L10n.t("تم الإرسال", "Sent"), isPresented: Binding(
            get: { sent != nil },
            set: { if !$0 { sent = nil } }
        ), moment: .success, icon: "megaphone.fill") {
            Button(L10n.t("حسناً", "OK"), role: .cancel) { onClose() }
        } message: {
            Text(sent ?? "")
        }
        .task {
            if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
        }
    }

    /// سطر فوق الأزرار: ما سيحدث بالضبط
    private var footnote: String? {
        if let blocker { return blocker }
        switch (publishNews, sendNotice) {
        case (true, true):
            return scheduleOn ? L10n.t("يُنشر الآن، ويصل الإشعار \(audienceText) في موعده",
                                       "Posts now; the push goes to \(audienceText) on schedule")
                              : L10n.t("يُنشر في الأخبار ويصل إشعار واحد \(audienceText)",
                                       "Posts to News and sends one push to \(audienceText)")
        case (true, false):
            return L10n.t("يظهر في الأخبار فقط — بلا إشعار", "Shows in News only — no push")
        case (false, true):
            return L10n.t("إشعار فقط \(audienceText) — لا يظهر في الأخبار", "Push only to \(audienceText) — not in News")
        default:
            return nil
        }
    }

    private var confirmText: String {
        var lines: [String] = []
        if publishNews {
            lines.append(L10n.t("يُنشر في الأخبار كإعلان باسم «إدارة العائلة».", "Posted to News as an announcement by “Family Admin”."))
        }
        if sendNotice {
            lines.append(scheduleOn
                ? L10n.t("ويُجدول إشعار \(audienceText) في \(scheduledText).", "A push to \(audienceText) is scheduled for \(scheduledText).")
                : L10n.t("ويصل إشعار \(audienceText) الآن.", "A push goes to \(audienceText) now."))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: الأقسام

    private var messageSection: some View {
        DSComposerSection(title: L10n.t("الإعلان", "Announcement"), icon: "megaphone.fill", tint: tint, index: 0) {
            DSComposerField(icon: "character.cursor.ibeam", label: L10n.t("العنوان", "Title"),
                            placeholder: Self.defaultTitle, text: $title, tint: tint, limit: 100)
            DSComposerField(icon: "text.alignright", label: L10n.t("النص", "Text"),
                            placeholder: L10n.t("اكتب الإعلان…", "Write the announcement…"),
                            text: $text, tint: tint, multiline: true, limit: 500)
        }
    }

    private var channelsSection: some View {
        DSComposerSection(title: L10n.t("أين يصل", "Where it goes"), icon: "paperplane.fill", tint: tint, index: 1) {
            optionRow(icon: "newspaper.fill", title: L10n.t("نشر كإعلان في الأخبار", "Post as an announcement in News"),
                      subtitle: L10n.t("يراه كل الأعضاء في الرئيسية", "Every member sees it on Home"),
                      isOn: newsOption)
            optionRow(icon: "bell.badge.fill", title: L10n.t("إرسال إشعار للأعضاء", "Notify members"),
                      subtitle: L10n.t("يصل لجوالاتهم الآن أو بموعد", "Reaches their phones now or on schedule"),
                      isOn: noticeOption)
            if oneRequired {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill").dsGlyph(DS.Glyph.sm)
                    Text(L10n.t("لازم يبقى خيار واحد على الأقل", "Keep at least one option on"))
                        .dsFont(.footnote)
                }
                .foregroundColor(DS.Color.warning.dsReadableGlyph)
                .transition(.opacity)
                .accessibilityAddTraits(.isStaticText)
            }
        }
    }

    /// مفتاحا الخيارين — كلٌّ يرفض أن يُطفأ وهو الأخير (واحد على الأقل يبقى)
    private var newsOption: Binding<Bool> {
        Binding(get: { publishNews }, set: { on in setOption(on, other: sendNotice) { publishNews = on } })
    }

    private var noticeOption: Binding<Bool> {
        Binding(get: { sendNotice }, set: { on in setOption(on, other: publishNews) { sendNotice = on } })
    }

    private func setOption(_ on: Bool, other: Bool, apply: () -> Void) {
        if !on && !other {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            withAnimation(DS.Anim.snappy) { oneRequired = true }
            return
        }
        withAnimation(DS.Anim.snappy) {
            oneRequired = false
            apply()
        }
    }

    private func optionRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: icon, tint: tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title)
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(DS.Color.primary.dsChrome(in: section))
        .dsRowBox()
    }

    // MARK: خيارات أكثر (للإشعار فقط)

    private var moreSection: some View {
        let summary = [audience == .all ? L10n.t("للجميع", "Everyone") : audienceText,
                       scheduleOn ? L10n.t("مجدول", "Scheduled") : L10n.t("الآن", "Now")]
            .joined(separator: " · ")
        return DSComposerSection(title: L10n.t("خيارات أكثر", "More options"), icon: "slider.horizontal.3",
                                 tint: tint, trailing: summary, index: 2, isOpen: $moreOpen) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                DSFieldLabel(text: L10n.t("الجمهور", "Audience"))
                DSSegmentedSwitch(options: [
                    DSSegmentOption(id: Audience.all, title: L10n.t("الكل", "All"), icon: "person.3.fill"),
                    DSSegmentOption(id: Audience.country, title: L10n.t("دولة", "Country"), icon: "globe"),
                    DSSegmentOption(id: Audience.members, title: L10n.t("أعضاء", "Members"), icon: "person.crop.circle.badge.checkmark")
                ], selection: $audience, size: .regular)
                switch audience {
                case .all:     EmptyView()
                case .country: AnyView(countryPicker)
                case .members: AnyView(memberPicker)
                }
                if publishNews {
                    Text(L10n.t("الجمهور للإشعار فقط — الإعلان في الأخبار يراه الجميع",
                                "Audience is for the push only — everyone sees the News post"))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            scheduleRow
        }
    }

    private var countryPicker: some View {
        let options = countries.map { item in
            DSFilterOption<String?>(id: item.country.isoCode,
                                    title: "\(item.country.flag) \(L10n.isArabic ? item.country.nameArabic : item.country.isoCode)",
                                    count: item.count)
        }
        return DSFilterChips(options: options, selection: $country, tint: tint)
    }

    private var memberPicker: some View {
        let q = ArabicTextNormalizer.normalizeForSearch(trimmed(search))
        let digits = trimmed(search).filter(\.isNumber)
        let pool = activeMembers
        let matches: [FamilyMember] = q.isEmpty
            ? pool.filter { selected.contains($0.id) }
            : pool.filter { m in
                ArabicTextNormalizer.normalizeForSearch(m.fullName).contains(q)
                    || (digits.count >= 3 && (m.phoneNumber ?? "").contains(digits))
            }
        return VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            DSSearchField(text: $search, placeholder: L10n.t("ابحث بالاسم أو الرقم", "Search name or number"), tint: tint)
            ForEach(Array(matches.prefix(Self.memberRowsLimit))) { m in
                memberRow(m)
            }
            if !selected.isEmpty {
                HStack(spacing: DS.Spacing.sm) {
                    DSStatusChip(text: L10n.t("\(selected.count) محدّد", "\(selected.count) selected"),
                                 icon: "checkmark.circle.fill", tint: tint)
                    Spacer(minLength: 0)
                    DSChipButton(L10n.t("إلغاء التحديد", "Clear"), icon: "xmark.circle.fill", tint: DS.Color.error,
                                 size: .small) {
                        selected.removeAll()
                    }
                }
            }
        }
    }

    private func memberRow(_ m: FamilyMember) -> some View {
        let isOn = selected.contains(m.id)
        return Button {
            if isOn { selected.remove(m.id) } else { selected.insert(m.id) }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Text(m.displayFullName)
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                    .dsNameLines()
                Spacer(minLength: 0)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .dsGlyph(DS.Glyph.xl, weight: .semibold)
                    .foregroundColor(isOn ? tint.dsReadableGlyph : DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// الجدولة: نفس `scheduleNotification` في «إشعار للأعضاء» (الخادم يرسل في الوقت ولو كان الجوال مقفولاً)
    private var scheduleRow: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            optionRow(icon: "clock.badge", title: L10n.t("جدولة الإشعار", "Schedule the push"),
                      subtitle: scheduleOn ? scheduledText : L10n.t("يُرسل الآن", "Sends now"),
                      isOn: $scheduleOn.animation(DS.Anim.snappy))
            if scheduleOn {
                DatePicker(L10n.t("وقت الإرسال", "Send time"), selection: $scheduledDate, in: Date()...,
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                    .tint(DS.Color.primary.dsChrome(in: section))
                    .environment(\.locale, LanguageManager.shared.locale)
                    .dsRowBox()
            }
        }
    }

    // MARK: الإرسال — المساران الموجودان كما هما

    private func send() async {
        guard canSubmit else { return }
        isSending = true
        defer { isSending = false }
        var done: [String] = []

        if publishNews {
            // تنبيه الإدارة «منشور جديد» يُترك حين يصلها الإعلان نفسه (للجميع) — لا إشعاران
            let ok = await newsVM.postNews(content: newsContent, type: "إعلان", asAdminIdentity: true,
                                           notifyAdmins: !(sendNotice && targetIds == nil))
            guard ok else {
                failure = newsVM.newsPostErrorMessage ?? L10n.t("تعذّر نشر الإعلان. حاول مرة أخرى.", "Couldn't post. Try again.")
                return
            }
            done.append(L10n.t("نُشر الإعلان في الأخبار.", "Posted to News."))
        }

        if sendNotice {
            let ids = targetIds
            let ok: Bool
            if scheduleOn {
                ok = await notificationVM.scheduleNotification(title: noticeTitle, body: noticeBody, targetMemberIds: ids,
                                                               scheduledFor: scheduledDate, kind: "admin_broadcast")
                if ok { await notificationVM.fetchScheduledNotifications() }
            } else {
                ok = await notificationVM.sendNotification(title: noticeTitle, body: noticeBody, targetMemberIds: ids,
                                                           kind: "admin_broadcast")
            }
            guard ok else {
                if publishNews {
                    // الخبر نُشر — المحاولة التالية للإشعار وحده (لا خبر مكرّر)
                    publishNews = false
                    failure = L10n.t("نُشر الإعلان في الأخبار، لكن تعذّر إرسال الإشعار. اضغط «إرسال» لإعادة الإشعار وحده.",
                                     "Posted to News, but the push failed. Tap Send to retry the push only.")
                } else {
                    failure = L10n.t("تعذّر إرسال الإشعار. حاول مرة أخرى.", "Couldn't send the push. Try again.")
                }
                return
            }
            done.append(scheduleOn ? L10n.t("جُدول الإشعار \(audienceText) في \(scheduledText).",
                                            "Push scheduled to \(audienceText) for \(scheduledText).")
                                   : L10n.t("وصل الإشعار \(audienceText).", "Push sent to \(audienceText)."))
        }
        sent = done.joined(separator: "\n")
    }
}
