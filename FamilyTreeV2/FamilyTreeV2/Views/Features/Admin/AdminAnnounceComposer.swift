import SwiftUI
import Supabase

// MARK: - «إعلان» — أول أنواع المنشئ الواحد «إنشاء» (`AdminCreateComposer.swift`)
//
// طلب المالك ٢٠٢٦-١٠-٢٠: «الاعلانات ابى زر سريع و خارجي… مختصر»، «اربط قسم الاعلانات مع ارسال الاشعارات يكون في خيار»
// ← اختار «الاثنين مع بعض». منذ الدفعة ب المربّع جزء من «ماذا تنشئ؟»: يفتحه «إنشاء» في رأس «المناسبات والإعلانات» (بيته)
// ومكبّر الصوت في رأس «اليوم» (طلب المالك).
//
// تبسيط ٢٠٢٦-١٠-٢٢ (موافقة المالك): شاشة واحدة بدل الأسئلة الثلاثة — النص، ثم «لمن» (الكل · دولة ⌄ · أعضاء ⌄ بالمنتقي
// الموحّد `DSMemberPickerBox`)، ثم «أرسل الآن / جدولة» (تاريخ ووقت في المستقبل حين تُجدول)، وزرّ واحد يقول ما سيحدث.
// العنوان خانة مكتوبة مسبقاً «عائلة المحمدعلي» وتتعدّل، والنص خانة أكبر (المالك ٢٠٢٦-١٠-٢٣)؛ والإعلان إشعار فقط — لا يُنشر في الأخبار.
// الإشعار = `NotificationViewModel.sendNotification` / `scheduleNotification` بنوع `admin_broadcast` — والدفع من مشغّل جدول
// الإشعارات على السيرفر كما هو. تعديل المجدول (من «الإشعارات المجدولة») = نفس الشاشة بالمسودّة → `updateScheduledNotification`.
// الصلاحية `canSendNotifications` (المالك والمدير)، وحارس السيرفر يبقى الحَكَم.

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
        .accessibilityLabel(L10n.t("إرسال إشعار", "Send a push"))
        .accessibilityHint(L10n.t("إشعار للأعضاء", "Notify members"))
    }
}

// MARK: - مشترك بين المنشئ و«القادم»

enum AdminAnnounceKit {
    /// العنوان الثابت لكل إعلان
    static let defaultTitle = "عائلة المحمدعلي"
    /// عناوين جاهزة تحت خانة العنوان (كما في «إرسال إشعار» القديمة — المالك ٢٠٢٦-١٠-٢٣ «وين اختيار اكثر من عنوان»)
    static let presetTitles = ["عائلة المحمدعلي", "إعلان من الإدارة", "تذكير", "دعوة", "تهنئة", "تنبيه مهم"]
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
    enum When: Hashable { case now, custom(Date) }

    var title = AdminAnnounceKit.defaultTitle
    var text = ""
    var audience: Audience = .all
    var when: When = .now
    /// تعديل إشعار مجدول — معرّف صفّه (nil = جديد)
    var editingId: UUID? = nil

    init(text: String = "", audience: Audience = .all, when: When = .now) {
        self.text = text
        self.audience = audience
        self.when = when
    }

    /// إشعار مجدول ← مسودّة تعديل: نصّه، مستلموه (دولة إن طابقوا أعضاءها بالضبط)، وموعده
    init(editing n: NotificationViewModel.ScheduledNotification, members: [FamilyMember]) {
        editingId = n.id
        let body = n.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { text = n.title } else { title = n.title; text = n.body }
        if let ids = n.targetMemberIds, !ids.isEmpty {
            audience = AdminAnnounceKit.countryCode(matching: ids, members: members).map { .country($0) } ?? .members(Set(ids))
        }
        when = .custom(n.scheduledDate ?? Date().addingTimeInterval(3600))
    }
}

// MARK: - المربّع

struct AdminAnnounceComposer: View {
    /// «ماذا تنشئ؟» — مربّعات الأنواع أعلى المربّع (من `AdminCreateRoot`)؛ nil = المربّع وحده
    var chooser: AnyView? = nil
    /// إغلاق المربّع (الإلغاء، أو «حسناً» بعد النجاح)
    let onClose: () -> Void

    @EnvironmentObject private var notificationVM: NotificationViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @Environment(\.dsSection) private var section
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum AudienceKind: Hashable { case all, country, members }
    private enum WhenKind: Hashable { case now, scheduled }
    /// «لمن» و«متى» بطاقتان جنب بعض — الضغط يفتح خياراتها تحتهما (واحدة فقط)، والثانية تبقى ملخّصاً
    private enum Panel: Hashable { case to, when }

    /// تعديل إشعار مجدول (nil = جديد)
    private let editingId: UUID?

    /// العنوان — مكتوب مسبقاً «عائلة المحمدعلي» ويتعدّل (المالك ٢٠٢٦-١٠-٢٣ «خل مساحة للنص و العنوان»)
    @State private var title: String
    /// «أخرى» في قائمة العنوان — خانة يكتب فيها عنواناً من عنده (المالك ٢٠٢٦-١٠-٢٣)
    @State private var customTitle: Bool
    @State private var text: String
    @State private var audience: AudienceKind
    @State private var country: String?
    @State private var selected: Set<UUID>
    @State private var when: WhenKind
    @State private var customDate: Date
    /// العجلة المفتوحة في الجدولة — nil = الاثنين مطويّان (المالك ٢٠٢٦-١٠-٢٣ «خلهم بشكل مخفي لمن ابي اغيرهم»)
    @State private var openWheel: DatePickerComponents? = nil
    @State private var openPanel: Panel? = nil
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
        _customTitle = State(initialValue: !AdminAnnounceKit.presetTitles.contains(draft.title))
        _text = State(initialValue: draft.text)
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
        case .custom(let date):
            _when = State(initialValue: .scheduled); _customDate = State(initialValue: date)
        }
    }

    private let tint = DS.Color.brandFill
    private var isEditing: Bool { editingId != nil }

    /// «جدولة» تبدأ بعد ساعة، على أقرب ربع ساعة
    private static func defaultCustomDate() -> Date {
        let quarter: TimeInterval = 15 * 60
        let base = Date().addingTimeInterval(3600)
        return Date(timeIntervalSinceReferenceDate: (base.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter)
    }

    // MARK: مشتقات

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// فارغ ← العنوان الثابت
    private var noticeTitle: String { trimmed(title).isEmpty ? AdminAnnounceKit.defaultTitle : trimmed(title) }
    private var noticeBody: String { trimmed(text) }

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

    /// موعد الإرسال — nil = الآن
    private var sendDate: Date? { when == .now ? nil : customDate }

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
        if when == .scheduled && customDate <= Date().addingTimeInterval(30) {
            return L10n.t("اختر وقتاً بعد الآن", "Pick a time after now")
        }
        return nil
    }

    /// نصّ الزرّ: بالضبط ما سيحدث
    /// فعل فقط — «لمن» و«متى» ظاهرتان في بطاقتيهما (المالك ٢٠٢٦-١٠-٢٣ «في تكرر بالوقت بمتى و بالارسال»)
    private func actionTitle(_ active: [FamilyMember]) -> String {
        if isEditing { return L10n.t("احفظ", "Save") }
        return sendDate == nil ? L10n.t("أرسل الآن", "Send now") : L10n.t("جدولة", "Schedule")
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
                : (chooser == nil ? L10n.t("إرسال إشعار", "Send a push") : L10n.t("ماذا تنشئ؟", "What to create?")),
            subtitle: isEditing ? L10n.t("يوصل في موعده الجديد", "Goes out at the new time")
                : L10n.t("عنوان ونص — للكل أو لدولة أو لأعضاء", "Title and text — everyone, a country or people"),
            icon: isEditing ? "clock.arrow.circlepath" : "megaphone.fill",
            tint: tint,
            actionTitle: actionTitle(active),
            actionIcon: sendDate == nil ? "paperplane.fill" : "clock.fill",
            canSubmit: blocker == nil && !isSending,
            isBusy: isSending,
            note: blocker,
            hasUnsavedChanges: !isEditing && !trimmed(text).isEmpty,
            // «إرسال» و«إلغاء» جنب بعض (المالك ٢٠٢٦-١٠-٢٣)
            actionFullRow: false,
            onSubmit: submit,
            onCancel: { onClose() }
        ) {
            if let chooser { chooser }
            AnyView(formSection(active))
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
        if let date = sendDate {
            return L10n.t("يوصل الإشعار لكل الأعضاء \(AdminAnnounceKit.when(date)).",
                          "The push reaches every member \(AdminAnnounceKit.when(date)).")
        }
        return L10n.t("يوصل الإشعار لكل الأعضاء الآن.", "The push reaches every member now.")
    }

    private var doneTitle: String {
        if isEditing { return L10n.t("تم الحفظ", "Saved") }
        return sendDate == nil ? L10n.t("تم الإرسال", "Sent") : L10n.t("تمت الجدولة", "Scheduled")
    }

    // MARK: الشاشة الواحدة: النص · لمن · أرسل الآن / جدولة

    private func formSection(_ active: [FamilyMember]) -> some View {
        DSComposerSection(title: L10n.t("الإشعار", "Push"), icon: "bell.badge.fill", tint: tint, index: 0) {
            AnyView(titlePresets)
            if customTitle {
                DSComposerField(icon: "pencil", label: L10n.t("عنوان آخر", "Other title"),
                                placeholder: L10n.t("اكتب العنوان…", "Write the title…"),
                                text: $title, tint: tint, limit: 60)
            }
            DSComposerField(icon: "text.alignright", label: L10n.t("النص", "Text"),
                            placeholder: L10n.t("اكتب الإشعار…", "Write the message…"),
                            text: $text, tint: tint, multiline: true, lines: 2...4, limit: 500)
            AnyView(toWhenBlock(active))
        }
    }

    /// العنوان نفسه قائمة منسدلة: العناوين الجاهزة + «أخرى…» تفتح خانة للكتابة
    private var titlePresets: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        let ink = tint.dsReadableGlyph
        return Menu {
            ForEach(AdminAnnounceKit.presetTitles, id: \.self) { preset in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(DS.Anim.snappy) { customTitle = false; title = preset }
                } label: {
                    if !customTitle && trimmed(title) == preset { Label(preset, systemImage: "checkmark") } else { Text(preset) }
                }
            }
            Divider()
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(DS.Anim.snappy) {
                    if !customTitle { title = "" }
                    customTitle = true
                }
            } label: {
                if customTitle { Label(L10n.t("أخرى…", "Other…"), systemImage: "checkmark") }
                else { Label(L10n.t("أخرى…", "Other…"), systemImage: "pencil") }
            }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "textformat", tint: tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.t("العنوان", "Title"))
                        .dsFieldFont(.caption)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(customTitle ? L10n.t("أخرى", "Other") : (trimmed(title).isEmpty ? AdminAnnounceKit.defaultTitle : trimmed(title)))
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Spacing.sm)
                Image(dsSymbol: "chevron.up.chevron.down")
                    .dsGlyph(DS.Glyph.sm)
                    .foregroundColor(ink)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: DSFieldMetrics.fieldHeight, alignment: .leading)
            .background(shape.fill(DS.Color.surface))
            .overlay(shape.strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke), lineWidth: DS.Border.width))
            .contentShape(shape)
        }
        .accessibilityLabel(L10n.t("العنوان", "Title"))
        .accessibilityValue(customTitle ? L10n.t("أخرى", "Other") : trimmed(title))
    }

    // MARK: لمن · متى — بطاقتان جنب بعض، وخيارات المفتوحة تحتهما

    private func toWhenBlock(_ active: [FamilyMember]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                summaryTile(.to, label: L10n.t("لمن", "To"), value: audienceLabel(active), tint: DS.Color.sea,
                            icon: audience == .all ? "person.3.fill" : (audience == .country ? "globe" : "person.crop.circle.badge.checkmark"))
                summaryTile(.when, label: L10n.t("متى", "When"),
                            value: when == .now ? L10n.t("الآن", "Now") : "\(Self.dayText(customDate)) · \(Self.timeText(customDate))",
                            tint: DS.Color.accent,
                            icon: when == .now ? "bolt.fill" : "calendar")
            }
            if openPanel == .to {
                audienceBlock(active).transition(.opacity)
            } else if openPanel == .when {
                whenBlock.transition(.opacity)
            }
        }
    }

    /// كل بطاقة بلونها للتمييز (المالك ٢٠٢٦-١٠-٢٣ «حط الوان على الازرار»): «لمن» بترولي · «متى» ذهبي
    private func summaryTile(_ panel: Panel, label: String, value: String, tint: Color, icon: String) -> some View {
        let isOpen = openPanel == panel
        let ink = tint.dsReadableGlyph
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(DS.Anim.snappy) { openPanel = isOpen ? nil : panel }
        } label: {
            HStack(alignment: .center, spacing: DS.Spacing.xs) {
                AdminIconSquare(symbol: icon, tint: tint, side: DS.Icon.row,
                                radius: DS.Hub.miniIconRadius, filled: true, glyph: DS.Glyph.sm)
                VStack(alignment: .leading, spacing: 0) {
                    Text(label).dsFont(.caption).foregroundColor(DS.Color.textTertiary)
                    Text(verbatim: value)
                        .dsFont(.chip)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(dsSymbol: "chevron.down")
                    .dsGlyph(DS.Glyph.xs)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .foregroundColor(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xsm)
            .frame(maxWidth: .infinity, minHeight: DSBox.chipHeight, alignment: .leading)
            .background(shape.fill(ink.opacity(isOpen ? DS.Opacity.tintFill : DS.Opacity.tintFillSoft)))
            .overlay(shape.strokeBorder(ink.opacity(isOpen ? DS.Opacity.selectedStroke : DS.Opacity.tintStroke),
                                        lineWidth: isOpen ? DS.Border.widthBold : DS.Border.width))
            .contentShape(shape)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(isOpen ? L10n.t("يطوي الخيارات", "Hides the options") : L10n.t("يعرض الخيارات", "Shows the options"))
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .dsFieldFont(.rowTitle)
            .foregroundColor(DS.Color.fieldLabel)
            .accessibilityAddTraits(.isHeader)
    }

    private func audienceBlock(_ active: [FamilyMember]) -> some View {
        let countries = AdminAnnounceKit.countries(active)
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
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

    // MARK: أرسل الآن / جدولة

    private var whenBlock: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            AdminChoiceRow {
                whenChip(.now, title: L10n.t("أرسل الآن", "Send now"), icon: "bolt.fill")
                whenChip(.scheduled, title: L10n.t("جدولة", "Schedule"), icon: "calendar", expands: true)
            }
            if when == .scheduled {
                customPicker
                    .transition(.opacity)
            }
        }
    }

    private func whenChip(_ kind: WhenKind, title: String, icon: String, expands: Bool = false) -> some View {
        Button {
            guard when != kind else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            if kind == .scheduled && customDate <= Date().addingTimeInterval(60) { customDate = Self.defaultCustomDate() }
            withAnimation(DS.Anim.snappy) { when = kind }
        } label: {
            AdminChoiceChip(title: title, icon: icon, isSelected: when == kind, expands: expands)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityAddTraits(when == kind ? .isSelected : [])
    }

    /// تاريخ ووقت في المستقبل فقط — مضغوط داخل المربّع (عمودي من أحجام إمكانية الوصول)
    private var customPicker: some View {
        // عجلة للتاريخ وعجلة للوقت، كل واحدة بسطرها (المالك ٢٠٢٦-١٠-٢٣ «خله التاريخ عجلة و حتى الوقت كل واحد سطر»)
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            wheel(L10n.t("التاريخ", "Date"), [.date], value: Self.dayText(customDate))
            AdminRowDivider()
            wheel(L10n.t("الوقت", "Time"), [.hourAndMinute], value: Self.timeText(customDate))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
    }

    /// سطر مطويّ (الاسم + القيمة)؛ الضغط يفتح عجلته تحته ويطوي الأخرى
    private func wheel(_ label: String, _ parts: DatePickerComponents, value: String) -> some View {
        let isOpen = openWheel == parts
        return VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(DS.Anim.snappy) { openWheel = isOpen ? nil : parts }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Text(label)
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                    Spacer(minLength: DS.Spacing.sm)
                    Text(verbatim: value)
                        .dsFieldFont(.rowTitle)
                        .monospacedDigit()
                        .foregroundColor(isOpen ? DS.Color.primary.dsChrome(in: section) : DS.Color.textPrimary)
                    Image(dsSymbol: "chevron.down")
                        .dsGlyph(DS.Glyph.sm)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .foregroundColor(DS.Color.textTertiary)
                }
                .frame(minHeight: DSBox.chipHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(value)
            if isOpen {
                DatePicker(label, selection: $customDate, in: Date()..., displayedComponents: parts)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .environment(\.locale, LanguageManager.shared.locale)
                    .transition(.opacity)
            }
        }
    }

    /// «السبت ٢٥ أكتوبر» · «٩:٠٠ ص» — بلغة التطبيق وتوقيت الجهاز
    private static func dayText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = LanguageManager.shared.locale
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f.string(from: d)
    }

    private static func timeText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = LanguageManager.shared.locale
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: d)
    }

    // MARK: الإرسال — المسارات الموجودة كما هي (إشعار فقط)

    private func send() async {
        let active = self.active
        guard blocker(active) == nil, !isSending else { return }
        isSending = true
        defer { isSending = false }
        let ids = targetIds(active)
        let to = audienceLabel(active)

        // تعديل إشعار مجدول: الصف نفسه (ما زال «pending»)؛ «الآن» = موعده الآن فترسله المهمة خلال دقيقة
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
            failure = L10n.t("تعذّر إرسال الإشعار. حاول مرة أخرى.", "Couldn't send the push. Try again.")
            return
        }
        // لحظة النجاح الموجودة (`dsAlert(…, moment: .success)`) + اهتزاز نجاح خفيف (الدفعة ١٠)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        done = sendDate.map { L10n.t("يوصل الإشعار \(AdminAnnounceKit.when($0)) ← \(to).", "The push goes \(AdminAnnounceKit.when($0)) → \(to).") }
            ?? L10n.t("وصل الإشعار ← \(to).", "Push sent → \(to).")
    }
}

// MARK: - شرائح الاختيار

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
