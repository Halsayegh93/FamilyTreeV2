import SwiftUI
import Supabase

// MARK: - «إعلان» — أول أنواع المنشئ الواحد «إنشاء» (`AdminCreateComposer.swift`)
//
// طلب المالك ٢٠٢٦-١٠-٢٠: «الاعلانات ابى زر سريع و خارجي… مختصر»، «اربط قسم الاعلانات مع ارسال الاشعارات يكون في خيار»
// ← اختار «الاثنين مع بعض». منذ الدفعة ب المربّع جزء من «ماذا تنشئ؟»: يفتحه «إنشاء» في رأس «المناسبات والإعلانات» (بيته)
// ومكبّر الصوت في رأس «اليوم» (طلب المالك).
//
// الدفعة ١١ (اختيار المالك «ثلاث أسئلة بس»): المربّع ثلاثة أسئلة وزرّ واحد يقول بالضبط ما سيحدث:
//   ١) «شنو تبي تقول؟» — النص (أسطر)، والعنوان اختياري خلف «＋ عنوان» (فارغ = «عائلة المحمدعلي») ومعه العناوين الجاهزة.
//   ٢) «لمن؟» — شرائح: الكل · دولة ⌄ (قائمة الدول بعدد أعضائها) · أعضاء ⌄ (المنتقي الموحّد `DSMemberPickerBox` باختيار
//      متعدّد). ومع «الكل» وحده: ☑ «ينشر بعد في الأخبار» (مفعّل افتراضياً) — الخبر يراه الجميع، فلا معنى له لمستلمين بعينهم.
//   ٣) «متى؟» — الحين · بكرة الصبح (٩:٠٠ بتوقيت الكويت) · اختر وقت ⌄ (تاريخ ووقت في المستقبل فقط).
//   الزرّ: «أرسل الحين ← 32 عضو» / «جدول بكرة 9:00 ص ← الكل» / «جدول الخميس 7:30 م ← الكويت (210)» — تأكيد قصير لـ«الكل» فقط.
// لا منطق جديد:
//   • الخبر = `NewsViewModel.postNews(type: «إعلان»)` نفسه (مسار «خبر جديد»)، باسم «إدارة العائلة».
//   • الإشعار = `NotificationViewModel.sendNotification` / `scheduleNotification` بنوع `admin_broadcast` — والدفع من
//     مشغّل جدول الإشعارات على السيرفر كما هو (`fanout_broadcast_notification` للكل، `dispatch_due_scheduled_notifications` للمجدول).
//   • تعديل المجدول (من «القادم») = نفس المربّع بالمسودّة → `updateScheduledNotification` (سياسة التعديل للمالك والمدير، والصف
//     ما زال «pending»).
// الإشعار المزدوج (الدفعة ب): نشر الخبر لا يُشعر الأعضاء (لا مشغّل على `news` غير `trg_content_force_pending`)؛ يُشعر الإدارة فقط
// بـ«منشور جديد»، ويُترك هذا التنبيه حين يصلها الإعلان نفسه (للكل) — لا إشعاران لأحد. الصلاحية `canSendNotifications` (المالك
// والمدير — نشرهما مباشر)، وحارس السيرفر يبقى الحَكَم.

/// زرّ مكبّر الصوت الزجاجي في رأس «اليوم» (لمن يرسل للأعضاء فقط — يقرّر من يضعه): المنشئ الواحد على «إعلان»
struct AdminAnnounceLauncher: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @EnvironmentObject private var memberVM: MemberViewModel

    var body: some View {
        Button {
            AdminCreateWindow.open(.announcement, authVM: authVM, newsVM: newsVM, notificationVM: notificationVM,
                                   memberVM: memberVM)
        } label: {
            AdminGlassCircle(symbol: "megaphone")
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(L10n.t("إعلان جديد", "New announcement"))
        .accessibilityHint(L10n.t("إشعار للأعضاء، وينشر بعد في الأخبار", "Notify members, and post to News too"))
    }
}

// MARK: - مشترك بين المنشئ و«القادم»

enum AdminAnnounceKit {
    /// العناوين الجاهزة (من صفحة «إشعار للأعضاء» المحذوفة) — أولها العنوان حين يُترك فارغاً
    static var presetTitles: [String] { RemoteSettings.strings("announce_preset_titles", [
        "عائلة المحمدعلي",
        "إعلان من الإدارة",
        "تذكير",
        "دعوة",
        "تهنئة",
        "تنبيه مهم"
    ]) }
    static var defaultTitle: String { presetTitles[0] }
    /// «بكرة الصبح» = الساعة ٩:٠٠ بتوقيت الكويت
    static let morningHour = 9
    private static let pinnedCountries = ["KW", "SA"]

    /// المستلمون المحتملون — نفس فلتر «إشعار للأعضاء»: بلا المعلّقين والمتوفّين والموقوفين
    static func activeMembers(_ all: [FamilyMember]) -> [FamilyMember] {
        all.filter { $0.role != .pending && !($0.isDeceased ?? false) && $0.status != .frozen }
    }

    static func iso(_ m: FamilyMember) -> String? {
        let phone = (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phone.isEmpty else { return nil }
        return KuwaitPhone.detectCountryAndLocal(phone).country.isoCode
    }

    /// الدول التي فيها أعضاء (الكويت والسعودية أولاً، ثم الأكثر)
    static func countries(_ active: [FamilyMember]) -> [(country: KuwaitPhone.Country, count: Int)] {
        var counts: [String: Int] = [:]
        for m in active { if let c = iso(m) { counts[c, default: 0] += 1 } }
        let pinned = pinnedCountries.compactMap { code in
            KuwaitPhone.supportedCountries.first { $0.isoCode == code }.flatMap { c in counts[code].map { (c, $0) } }
        }
        let others = KuwaitPhone.supportedCountries
            .filter { !pinnedCountries.contains($0.isoCode) }
            .compactMap { c in counts[c.isoCode].map { (c, $0) } }
            .sorted { $0.1 > $1.1 }
        return (pinned + others).map { (country: $0.0, count: $0.1) }
    }

    static func ids(in code: String, _ active: [FamilyMember]) -> [UUID] {
        active.filter { iso($0) == code }.map(\.id)
    }

    /// «الكويت» / «Kuwait» — بلا علم في الزرّ والشريحة والصفّ (العلم يقلب ترتيب السطر العربي)، ومعه في القائمة فقط
    static func countryName(_ c: KuwaitPhone.Country, flag: Bool = false) -> String {
        let name = L10n.isArabic ? c.nameArabic
            : (Locale(identifier: "en").localizedString(forRegionCode: c.isoCode) ?? c.isoCode)
        return flag ? "\(c.flag) \(name)" : name
    }

    /// «عضو واحد» · «عضوين» · «5 أعضاء» · «32 عضو»
    static func membersCount(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "1 member" : "\(n) members" }
        switch n {
        case 1:       return "عضو واحد"
        case 2:       return "عضوين"
        case 3...10:  return "\(n) أعضاء"
        default:      return "\(n) عضو"
        }
    }

    /// ملخّص المستلمين لصفّ مجدول: «الكل» · «الكويت (210)» حين يطابقون أعضاء دولة بالضبط · «32 عضو»
    static func audienceLabel(ids: [UUID]?, members: [FamilyMember]) -> String {
        guard let ids, !ids.isEmpty else { return L10n.t("الكل", "Everyone") }
        if let code = countryCode(matching: ids, members: members),
           let c = KuwaitPhone.supportedCountries.first(where: { $0.isoCode == code }) {
            return "\(countryName(c)) (\(ids.count))"
        }
        return membersCount(ids.count)
    }

    /// دولة مستلموها هم هؤلاء بالضبط — nil = أعضاء مختارون
    static func countryCode(matching ids: [UUID], members: [FamilyMember]) -> String? {
        let set = Set(ids)
        let active = activeMembers(members)
        for item in countries(active) where item.count == set.count {
            if Set(Self.ids(in: item.country.isoCode, active)) == set { return item.country.isoCode }
        }
        return nil
    }

    /// بكرة الساعة ٩:٠٠ صباحاً بتوقيت الكويت
    static func tomorrowMorning(from now: Date = Date()) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kuwait") ?? .current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        return cal.date(bySettingHour: morningHour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    /// كلمة اليوم: «اليوم» · «بكرة» · اسم اليوم خلال أسبوع · «5 نوفمبر»
    static func dayWord(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case ...0: return L10n.t("اليوم", "today")
        case 1:    return L10n.t("بكرة", "tomorrow")
        case 2..<DeceasedMemorial.weekDays:
            let f = DateFormatter()
            f.locale = LanguageManager.shared.locale
            f.dateFormat = "EEEE"
            return f.string(from: date)
        default:
            return AdminOccasionsText.shortDate(date)
        }
    }

    /// «بكرة 9:00 ص» / «الخميس 7:30 م»
    static func when(_ date: Date) -> String {
        "\(dayWord(date)) \(AdminOccasionsText.time(date))"
    }
}

// MARK: - المسودّة: ما يفتح به المربّع (جديد، أو تعديل إشعار مجدول)

struct AdminAnnounceDraft {
    enum Audience: Hashable { case all, country(String), members(Set<UUID>) }
    enum When: Hashable { case now, tomorrowMorning, custom(Date) }

    var title = ""
    var text = ""
    var audience: Audience = .all
    var when: When = .now
    /// ☑ «ينشر بعد في الأخبار» (مع «الكل» فقط)
    var publishNews = true
    /// تعديل إشعار مجدول — معرّف صفّه (nil = جديد)
    var editingId: UUID? = nil

    init(title: String = "", text: String = "", audience: Audience = .all, when: When = .now, publishNews: Bool = true) {
        self.title = title
        self.text = text
        self.audience = audience
        self.when = when
        self.publishNews = publishNews
    }

    /// إشعار مجدول ← مسودّة تعديل: نصّه وعنوانه، مستلموه (دولة إن طابقوا أعضاءها بالضبط)، وموعده
    init(editing n: NotificationViewModel.ScheduledNotification, members: [FamilyMember]) {
        editingId = n.id
        publishNews = false
        title = n.title == AdminAnnounceKit.defaultTitle ? "" : n.title
        text = n.body
        if let ids = n.targetMemberIds, !ids.isEmpty {
            audience = AdminAnnounceKit.countryCode(matching: ids, members: members).map { .country($0) } ?? .members(Set(ids))
        }
        if let date = n.scheduledDate {
            when = abs(date.timeIntervalSince(AdminAnnounceKit.tomorrowMorning())) < 60 ? .tomorrowMorning : .custom(date)
        } else {
            when = .custom(Date().addingTimeInterval(3600))
        }
    }
}

// MARK: - المربّع

struct AdminAnnounceComposer: View {
    /// «ماذا تنشئ؟» — مربّعات الأنواع أعلى المربّع (من `AdminCreateRoot`)؛ nil = المربّع وحده
    var chooser: AnyView? = nil
    /// إغلاق المربّع (الإلغاء، أو «حسناً» بعد النجاح)
    let onClose: () -> Void

    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @Environment(\.dsSection) private var section
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum AudienceKind: Hashable { case all, country, members }
    private enum WhenKind: Hashable { case now, tomorrow, custom }

    /// تعديل إشعار مجدول (nil = جديد)
    private let editingId: UUID?

    @State private var title: String
    @State private var text: String
    @State private var titleOpen: Bool
    @State private var audience: AudienceKind
    @State private var country: String?
    @State private var selected: Set<UUID>
    @State private var when: WhenKind
    @State private var customDate: Date
    @State private var publishNews: Bool
    /// المنتقي الموحّد مكان المربّع (اختيار «أعضاء») — وما كان محدّداً عند فتحه («إلغاء» يرجعه، وترتيبه ثابت)
    @State private var picking = false
    @State private var pickerSnapshot: Set<UUID> = []
    @State private var pickerSearch = ""
    @State private var confirm = false
    @State private var isSending = false
    @State private var failure: String? = nil
    /// ملخّص ما تمّ — ثم يُغلق المربّع
    @State private var done: String? = nil

    init(chooser: AnyView? = nil, draft: AdminAnnounceDraft = AdminAnnounceDraft(), onClose: @escaping () -> Void) {
        self.chooser = chooser
        self.onClose = onClose
        editingId = draft.editingId
        _title = State(initialValue: draft.title)
        _text = State(initialValue: draft.text)
        _titleOpen = State(initialValue: !draft.title.isEmpty)
        _publishNews = State(initialValue: draft.publishNews)
        switch draft.audience {
        case .all:
            _audience = State(initialValue: .all); _country = State(initialValue: nil); _selected = State(initialValue: [])
        case .country(let code):
            _audience = State(initialValue: .country); _country = State(initialValue: code); _selected = State(initialValue: [])
        case .members(let ids):
            _audience = State(initialValue: .members); _country = State(initialValue: nil); _selected = State(initialValue: ids)
        }
        switch draft.when {
        case .now:
            _when = State(initialValue: .now); _customDate = State(initialValue: Self.defaultCustomDate())
        case .tomorrowMorning:
            _when = State(initialValue: .tomorrow); _customDate = State(initialValue: Self.defaultCustomDate())
        case .custom(let date):
            _when = State(initialValue: .custom); _customDate = State(initialValue: date)
        }
    }

    private let tint = DS.Color.brandFill
    private var isEditing: Bool { editingId != nil }

    /// «اختر وقت» يبدأ بعد ساعة، على أقرب ربع ساعة
    private static func defaultCustomDate() -> Date {
        let quarter: TimeInterval = 15 * 60
        let base = Date().addingTimeInterval(3600)
        return Date(timeIntervalSinceReferenceDate: (base.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter)
    }

    // MARK: مشتقات

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var noticeTitle: String { trimmed(title).isEmpty ? AdminAnnounceKit.defaultTitle : trimmed(title) }
    private var noticeBody: String { trimmed(text).isEmpty ? noticeTitle : trimmed(text) }

    /// نص الخبر: العنوان (إن كُتب) سطراً أول ثم النص
    private var newsContent: String {
        let t = trimmed(title)
        return t.isEmpty ? trimmed(text) : t + "\n" + trimmed(text)
    }

    private var active: [FamilyMember] { AdminAnnounceKit.activeMembers(memberVM.allMembers) }

    /// nil = للجميع؛ قائمة فارغة = لا أحد (لا تتحوّل للجميع — ب-٩)
    private func targetIds(_ active: [FamilyMember]) -> [UUID]? {
        switch audience {
        case .all:     return nil
        case .country: return country.map { AdminAnnounceKit.ids(in: $0, active) } ?? []
        case .members: return Array(selected)
        }
    }

    /// «الكل» · «الكويت (210)» · «32 عضو»
    private func audienceLabel(_ active: [FamilyMember]) -> String {
        switch audience {
        case .all:
            return L10n.t("الكل", "Everyone")
        case .country:
            guard let country, let c = KuwaitPhone.supportedCountries.first(where: { $0.isoCode == country }) else {
                return L10n.t("دولة", "a country")
            }
            return "\(AdminAnnounceKit.countryName(c)) (\(AdminAnnounceKit.ids(in: country, active).count))"
        case .members:
            return AdminAnnounceKit.membersCount(selected.count)
        }
    }

    /// موعد الإرسال — nil = الحين
    private var sendDate: Date? {
        switch when {
        case .now:      return nil
        case .tomorrow: return AdminAnnounceKit.tomorrowMorning()
        case .custom:   return customDate
        }
    }

    /// ينشر في الأخبار — مع «الكل» فقط، وليس في تعديل المجدول (الخبر نُشر يوم أُنشئ)
    private var postsNews: Bool { audience == .all && publishNews && !isEditing }

    /// ما يمنع الإرسال (سطر فوق الزرّ) — nil = جاهز
    private func blocker(_ active: [FamilyMember]) -> String? {
        if trimmed(text).isEmpty { return L10n.t("اكتب نص الإشعار", "Write the message") }
        switch audience {
        case .all: break
        case .country:
            if country == nil { return L10n.t("اختر الدولة", "Pick the country") }
            if targetIds(active)?.isEmpty ?? false { return L10n.t("ما في أعضاء في هذي الدولة", "No members in this country") }
        case .members:
            if selected.isEmpty { return L10n.t("اختر عضواً واحداً على الأقل", "Pick at least one member") }
        }
        if when == .custom && customDate <= Date().addingTimeInterval(30) {
            return L10n.t("اختر وقتاً بعد الحين", "Pick a time after now")
        }
        return nil
    }

    /// نصّ الزرّ: بالضبط ما سيحدث
    private func actionTitle(_ active: [FamilyMember]) -> String {
        let to = audienceLabel(active)
        guard let date = sendDate else {
            return L10n.t("أرسل الحين ← \(to)", "Send now → \(to)")
        }
        let at = AdminAnnounceKit.when(date)
        return isEditing ? L10n.t("احفظ: \(at) ← \(to)", "Save: \(at) → \(to)")
                         : L10n.t("جدول \(at) ← \(to)", "Schedule \(at) → \(to)")
    }

    // MARK: المربّع

    var body: some View {
        Group {
            if picking {
                AnyView(memberPicker)
            } else {
                AnyView(composer)
            }
        }
        .dsAlert(confirmTitle, isPresented: $confirm, icon: sendDate == nil ? "paperplane.fill" : "clock.fill") {
            Button(confirmButton, role: sendDate == nil && !isEditing ? .destructive : nil) {
                Task { await send() }
            }
            Button(L10n.t("تراجع", "Back"), role: .cancel) {}
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
        .dsAlert(doneTitle, isPresented: Binding(
            get: { done != nil },
            set: { if !$0 { done = nil } }
        ), moment: .success, icon: sendDate == nil ? "megaphone.fill" : "clock.fill") {
            Button(L10n.t("حسناً", "OK"), role: .cancel) { onClose() }
        } message: {
            Text(done ?? "")
        }
        .task {
            if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() }
        }
    }

    private var composer: some View {
        let active = self.active
        let blocker = self.blocker(active)
        return DSComposer(
            title: isEditing ? L10n.t("تعديل الإشعار المجدول", "Edit scheduled push")
                : (chooser == nil ? L10n.t("إعلان جديد", "New announcement") : L10n.t("ماذا تنشئ؟", "What to create?")),
            subtitle: isEditing ? L10n.t("نفس الأسئلة — ويوصل في موعده الجديد", "Same questions — goes out at the new time")
                : L10n.t("شنو تقول، لمن، ومتى — وترسل", "What, to whom, and when — then send"),
            icon: isEditing ? "clock.arrow.circlepath" : "megaphone.fill",
            tint: tint,
            actionTitle: actionTitle(active),
            actionIcon: sendDate == nil ? "paperplane.fill" : "clock.fill",
            canSubmit: blocker == nil && !isSending,
            isBusy: isSending,
            note: blocker,
            hasUnsavedChanges: !isEditing && (!trimmed(title).isEmpty || !trimmed(text).isEmpty),
            actionFullRow: true,
            onSubmit: submit,
            onCancel: { onClose() }
        ) {
            if let chooser { chooser }
            AnyView(sayingSection)
            AnyView(audienceSection(active))
            AnyView(whenSection)
        }
    }

    /// تأكيد قصير لـ«الكل» فقط — غيرهم يُرسل مباشرة
    private func submit() {
        guard blocker(active) == nil, !isSending else { return }
        if audience == .all {
            confirm = true
        } else {
            Task { await send() }
        }
    }

    private var confirmTitle: String {
        if isEditing { return L10n.t("حفظ التعديل للكل؟", "Save for everyone?") }
        return sendDate == nil ? L10n.t("إرسال للكل؟", "Send to everyone?") : L10n.t("جدولة للكل؟", "Schedule for everyone?")
    }

    private var confirmButton: String {
        if isEditing { return L10n.t("احفظ", "Save") }
        return sendDate == nil ? L10n.t("أرسل", "Send") : L10n.t("جدول", "Schedule")
    }

    private var confirmText: String {
        var lines: [String] = []
        if let date = sendDate {
            lines.append(L10n.t("يوصل الإشعار لكل الأعضاء \(AdminAnnounceKit.when(date)).",
                                "The push reaches every member \(AdminAnnounceKit.when(date))."))
        } else {
            lines.append(L10n.t("يوصل الإشعار لكل الأعضاء الحين.", "The push reaches every member now."))
        }
        if postsNews {
            lines.append(L10n.t("وينشر الحين في الأخبار باسم «إدارة العائلة».", "And posts to News now as “Family Admin”."))
        }
        return lines.joined(separator: "\n")
    }

    private var doneTitle: String {
        if isEditing { return L10n.t("تم الحفظ", "Saved") }
        return sendDate == nil ? L10n.t("تم الإرسال", "Sent") : L10n.t("تمت الجدولة", "Scheduled")
    }

    // MARK: ١) شنو تبي تقول؟

    private var sayingSection: some View {
        DSComposerSection(title: L10n.t("شنو تبي تقول؟", "What do you want to say?"), icon: "text.bubble.fill",
                          tint: tint, index: 0) {
            DSComposerField(icon: "text.alignright", label: L10n.t("النص", "Text"),
                            placeholder: L10n.t("اكتب الإشعار…", "Write the message…"),
                            text: $text, tint: tint, multiline: true, limit: 500)
            if titleOpen {
                DSComposerField(icon: "character.cursor.ibeam", label: L10n.t("العنوان (اختياري)", "Title (optional)"),
                                placeholder: AdminAnnounceKit.defaultTitle, text: $title, tint: tint, limit: 100)
                presetTitlesRow
            } else {
                HStack(spacing: DS.Spacing.sm) {
                    Button {
                        withAnimation(DS.Anim.snappy) { titleOpen = true }
                    } label: {
                        DSAddChipLabel(icon: "plus", title: L10n.t("عنوان", "Title"))
                    }
                    .buttonStyle(DSPressStyle())
                    .accessibilityLabel(L10n.t("إضافة عنوان", "Add a title"))
                    Text(L10n.t("بدونه: «\(AdminAnnounceKit.defaultTitle)»", "Default: “\(AdminAnnounceKit.defaultTitle)”"))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// العناوين الجاهزة — ضغطة تضعها في «العنوان» (والمختار مميّز)
    private var presetTitlesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xs) {
                ForEach(AdminAnnounceKit.presetTitles, id: \.self) { preset in
                    DSChipButton(preset, isSelected: trimmed(title) == preset, size: .small) {
                        withAnimation(DS.Anim.quick) { title = trimmed(title) == preset ? "" : preset }
                    }
                }
            }
            .padding(.horizontal, DS.Border.width)
        }
        .accessibilityLabel(L10n.t("عناوين جاهزة", "Ready titles"))
    }

    // MARK: ٢) لمن؟

    private func audienceSection(_ active: [FamilyMember]) -> some View {
        let countries = AdminAnnounceKit.countries(active)
        return DSComposerSection(title: L10n.t("لمن؟", "To whom?"), icon: "person.2.fill", tint: tint, index: 1) {
            AdminChoiceRow {
                Button { pickAudience(.all) } label: {
                    AdminChoiceChip(title: L10n.t("الكل", "Everyone"), icon: "person.3.fill", isSelected: audience == .all)
                }
                .buttonStyle(DSPressStyle())
                .accessibilityAddTraits(audience == .all ? .isSelected : [])
                countryMenu(countries)
                Button { openPicker() } label: {
                    AdminChoiceChip(title: audience == .members && !selected.isEmpty
                                        ? AdminAnnounceKit.membersCount(selected.count) : L10n.t("أعضاء", "Members"),
                                    icon: "person.crop.circle.badge.checkmark", isSelected: audience == .members,
                                    expands: true)
                }
                .buttonStyle(DSPressStyle())
                .accessibilityAddTraits(audience == .members ? .isSelected : [])
                .accessibilityHint(L10n.t("يفتح قائمة الأعضاء — تقدر تختار أكثر من عضو", "Opens the member list — pick several"))
            }
            if audience == .all && !isEditing {
                newsCheckbox
                    .transition(.opacity)
            }
        }
    }

    /// «دولة ⌄» — قائمة أصلية بالدول التي فيها أعضاء وعدد كلٍّ منها، والمختارة بعلامة ✓
    private func countryMenu(_ countries: [(country: KuwaitPhone.Country, count: Int)]) -> some View {
        let chosen = audience == .country ? countries.first { $0.country.isoCode == country } : nil
        return Menu {
            Picker(selection: Binding(get: { audience == .country ? country : nil }, set: { code in
                guard let code else { return }
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(DS.Anim.snappy) {
                    country = code
                    audience = .country
                }
            })) {
                ForEach(countries, id: \.country.isoCode) { item in
                    Text(verbatim: "\(AdminAnnounceKit.countryName(item.country, flag: true)) (\(item.count))")
                        .tag(Optional(item.country.isoCode))
                }
            } label: {
                Text(L10n.t("الدولة", "Country"))
            }
            .pickerStyle(.inline)
        } label: {
            AdminChoiceChip(title: chosen.map { "\(AdminAnnounceKit.countryName($0.country)) (\($0.count))" }
                                ?? L10n.t("دولة", "Country"),
                            icon: chosen == nil ? "globe" : nil, isSelected: audience == .country, expands: true)
        }
        .disabled(countries.isEmpty)
        .accessibilityLabel(chosen.map { L10n.t("دولة: \(AdminAnnounceKit.countryName($0.country))", "Country: \(AdminAnnounceKit.countryName($0.country))") }
                            ?? L10n.t("دولة", "Country"))
        .accessibilityAddTraits(audience == .country ? .isSelected : [])
    }

    private func pickAudience(_ kind: AudienceKind) {
        guard audience != kind else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(DS.Anim.snappy) { audience = kind }
    }

    /// ☑ «ينشر بعد في الأخبار» — مع «الكل» فقط (الخبر يراه الجميع)
    private var newsCheckbox: some View {
        let ink = DS.Color.primary.dsChrome(in: section).dsReadableGlyph
        let sub = sendDate == nil ? L10n.t("يراه الكل في الرئيسية", "Everyone sees it on Home")
                                  : L10n.t("ينزل في الأخبار الحين، والإشعار في موعده", "Posts to News now; the push on schedule")
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(DS.Anim.quick) { publishNews.toggle() }
        } label: {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Image(systemName: publishNews ? "checkmark.square.fill" : "square")
                    .dsGlyph(DS.Glyph.xl, weight: .semibold)
                    .foregroundColor(publishNews ? ink : DS.Color.textTertiary)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(L10n.t("ينشر بعد في الأخبار", "Also post in News"))
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(sub)
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("ينشر بعد في الأخبار", "Also post in News"))
        .accessibilityValue(publishNews ? L10n.t("محدّد", "Checked") : L10n.t("غير محدّد", "Unchecked"))
        .accessibilityHint(sub)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: المنتقي الموحّد (اختيار متعدّد)

    private func openPicker() {
        UISelectionFeedbackGenerator().selectionChanged()
        pickerSnapshot = selected
        pickerSearch = ""
        withAnimation(DS.Anim.snappy) { picking = true }
    }

    private var memberPicker: some View {
        // المحدّدون عند الفتح أولاً — الترتيب ثابت أثناء الاختيار
        let pool = active
        let candidates = pool.filter { pickerSnapshot.contains($0.id) } + pool.filter { !pickerSnapshot.contains($0.id) }
        return DSMemberPickerBox(
            title: L10n.t("اختر المستلمين", "Pick recipients"),
            subtitle: selected.isEmpty ? L10n.t("اضغط على الأسماء — أكثر من عضو", "Tap names — pick several")
                                       : L10n.t("المحدّد: \(AdminAnnounceKit.membersCount(selected.count))",
                                                "Selected: \(AdminAnnounceKit.membersCount(selected.count))"),
            icon: "person.crop.circle.badge.checkmark",
            candidates: candidates,
            search: $pickerSearch,
            isLoading: memberVM.allMembers.isEmpty,
            selectedIds: selected,
            doneTitle: selected.isEmpty ? L10n.t("تم", "Done") : L10n.t("تم (\(selected.count))", "Done (\(selected.count))"),
            onDone: { closePicker(keep: true) },
            rowHint: L10n.t("يضيفه أو يزيله من المستلمين", "Adds or removes them"),
            tint: tint,
            onPick: { m in
                UISelectionFeedbackGenerator().selectionChanged()
                if selected.contains(m.id) { selected.remove(m.id) } else { selected.insert(m.id) }
            },
            onCancel: { closePicker(keep: false) }
        )
    }

    private func closePicker(keep: Bool) {
        if !keep { selected = pickerSnapshot }
        withAnimation(DS.Anim.snappy) {
            picking = false
            if !selected.isEmpty {
                audience = .members
            } else if audience == .members {
                audience = .all
            }
        }
    }

    // MARK: ٣) متى؟

    private var whenSection: some View {
        DSComposerSection(title: L10n.t("متى؟", "When?"), icon: "clock.fill", tint: tint, index: 2) {
            AdminChoiceRow {
                whenChip(.now, title: L10n.t("الحين", "Now"), icon: "bolt.fill")
                whenChip(.tomorrow, title: L10n.t("بكرة الصبح", "Tomorrow morning"), icon: "sunrise.fill")
                whenChip(.custom, title: L10n.t("اختر وقت", "Pick a time"), icon: "calendar", expands: true)
            }
            if when == .custom {
                customPicker
                    .transition(.opacity)
            }
        }
    }

    private func whenChip(_ kind: WhenKind, title: String, icon: String, expands: Bool = false) -> some View {
        Button {
            guard when != kind else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            if kind == .custom && customDate <= Date().addingTimeInterval(60) { customDate = Self.defaultCustomDate() }
            withAnimation(DS.Anim.snappy) { when = kind }
        } label: {
            AdminChoiceChip(title: title, icon: icon, isSelected: when == kind, expands: expands)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityAddTraits(when == kind ? .isSelected : [])
        .accessibilityHint(kind == .tomorrow
            ? L10n.t("الساعة 9:00 الصبح بتوقيت الكويت", "9:00 AM Kuwait time") : "")
    }

    /// تاريخ ووقت في المستقبل فقط — مضغوط داخل المربّع (عمودي من أحجام إمكانية الوصول)
    private var customPicker: some View {
        let picker = DatePicker(L10n.t("وقت الإرسال", "Send time"), selection: $customDate, in: Date()...,
                                displayedComponents: [.date, .hourAndMinute])
            .datePickerStyle(.compact)
            .tint(DS.Color.primary.dsChrome(in: section))
            .environment(\.locale, LanguageManager.shared.locale)
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(L10n.t("وقت الإرسال", "Send time"))
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                    picker.labelsHidden()
                }
            } else {
                picker
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.fieldLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
    }

    // MARK: الإرسال — المسارات الموجودة كما هي

    private func send() async {
        let active = self.active
        guard blocker(active) == nil, !isSending else { return }
        isSending = true
        defer { isSending = false }
        let ids = targetIds(active)
        let to = audienceLabel(active)

        // تعديل إشعار مجدول: الصف نفسه (ما زال «pending»)؛ «الحين» = موعده الآن فترسله المهمة خلال دقيقة
        if let editingId {
            let result = await notificationVM.updateScheduledNotification(editingId, title: noticeTitle, body: noticeBody,
                                                                          targetMemberIds: ids, scheduledFor: sendDate ?? Date())
            switch result {
            case .saved:
                await notificationVM.fetchScheduledNotifications()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                done = sendDate.map { L10n.t("يوصل الإشعار \(AdminAnnounceKit.when($0)) ← \(to).", "The push goes \(AdminAnnounceKit.when($0)) → \(to).") }
                    ?? L10n.t("يوصل الإشعار ← \(to) خلال دقيقة.", "The push goes → \(to) within a minute.")
            case .gone:
                await notificationVM.fetchScheduledNotifications()
                failure = L10n.t("هذا الإشعار أُرسل أو أُلغي قبل الحفظ.", "This push was already sent or cancelled.")
            case .failed:
                failure = L10n.t("تعذّر حفظ التعديل. حاول مرة أخرى.", "Couldn't save the change. Try again.")
            }
            return
        }

        var lines: [String] = []
        if postsNews {
            // تنبيه الإدارة «منشور جديد» يُترك حين يصلها الإعلان نفسه (للكل) — لا إشعاران
            let ok = await newsVM.postNews(content: newsContent, type: "إعلان", asAdminIdentity: true,
                                           notifyAdmins: ids != nil)
            guard ok else {
                failure = newsVM.newsPostErrorMessage ?? L10n.t("تعذّر نشر الإعلان. حاول مرة أخرى.", "Couldn't post. Try again.")
                return
            }
            lines.append(L10n.t("نُشر في الأخبار.", "Posted to News."))
        }

        let ok: Bool
        if let date = sendDate {
            ok = await notificationVM.scheduleNotification(title: noticeTitle, body: noticeBody, targetMemberIds: ids,
                                                           scheduledFor: date, kind: "admin_broadcast")
            if ok { await notificationVM.fetchScheduledNotifications() }
        } else {
            ok = await notificationVM.sendNotification(title: noticeTitle, body: noticeBody, targetMemberIds: ids,
                                                       kind: "admin_broadcast")
        }
        guard ok else {
            if postsNews {
                // الخبر نُشر — المحاولة التالية للإشعار وحده (لا خبر مكرّر)
                publishNews = false
                failure = L10n.t("نُشر في الأخبار، لكن تعذّر إرسال الإشعار. اضغط الزر لإعادة الإشعار وحده.",
                                 "Posted to News, but the push failed. Tap the button to retry the push only.")
            } else {
                failure = L10n.t("تعذّر إرسال الإشعار. حاول مرة أخرى.", "Couldn't send the push. Try again.")
            }
            return
        }
        lines.append(sendDate.map { L10n.t("يوصل الإشعار \(AdminAnnounceKit.when($0)) ← \(to).", "The push goes \(AdminAnnounceKit.when($0)) → \(to).") }
                     ?? L10n.t("وصل الإشعار ← \(to).", "Push sent → \(to)."))
        // لحظة النجاح الموجودة (`dsAlert(…, moment: .success)`) + اهتزاز نجاح خفيف (الدفعة ١٠)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        done = lines.joined(separator: "\n")
    }
}

// MARK: - شرائح الاختيار (الأسئلة الثلاثة)

/// شريحة اختيار بشكل `DSFilterChips` (المختار ممتلئ بتدرّج القسم، والباقي بإطار خفيف)، و⌄ لما يفتح قائمة أو منتقياً.
/// وجه فقط — يُلبس `Button` أو `Menu`
struct AdminChoiceChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    /// ⌄ بعد النص: يفتح قائمة/منتقياً/حقلاً
    var expands: Bool = false

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            if let icon {
                Image(dsSymbol: icon).dsGlyph(DS.Glyph.smCompact)
            }
            Text(title)
                .dsFont(.sectionTitle)
                .lineLimit(1)
            if expands {
                Image(systemName: "chevron.down")
                    .dsGlyph(DS.Glyph.xs, weight: .bold)
                    .opacity(0.8)
                    .accessibilityHidden(true)
            }
        }
        .foregroundColor(isSelected ? DS.Color.textOnPrimary : DS.Color.textSecondary)
        .padding(.horizontal, DSBox.chipPadding)
        .frame(minHeight: DSBox.chipHeight)
        .background {
            if isSelected {
                Capsule().fill(DSActionFill.style())
            } else {
                Capsule().strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width)
            }
        }
        // مساحة ضغط ٤٤ (حدّ أبل) والشكل كما هو
        .padding(.vertical, (DS.Icon.tapTarget - DSBox.chipHeight) / 2)
        .contentShape(Rectangle())
    }
}

/// صفّ الشرائح: أفقي إن اتّسع، وإلا عمودي (الخط الكبير جداً) — بلا تمرير أفقي يخفي خياراً
struct AdminChoiceRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.sm) { content() }
            VStack(alignment: .leading, spacing: 0) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
