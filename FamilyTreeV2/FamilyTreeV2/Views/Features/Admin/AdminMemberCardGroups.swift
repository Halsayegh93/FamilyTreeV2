import SwiftUI

// MARK: - «العضو» في كرت العضو v3 «ب»: ثلاث مجموعات تنطوي (الوحدة V3، اختيار المالك ٢٠٢٦-١١-٢٦)
//
// «البيانات» · «العائلة» · «الحساب» — كل مجموعة بطاقة `AdminSectionCard(isOpen:subtitle:)`: العنوان وسطر ملخّصها تحته
// دائماً («ميلاد 27/12/1963 · ذكر · السيرة غير مسجّل»)، مفتوحة أول مرة، والاختيار يُحفظ لكل مشاهد (UserDefaults —
// `AdminMemberCardLogic.storageKey`). المجموعة التي فيها طلب أو صفّ «تحت التعديل» لا تنطوي («فيها طلب، لا تنطوي»).
// كل صفّ (`AdminMemberFactRow`): مربّع ملوّن، العنوان (وشارة صلته)، القيمة أو «غير مسجّل»، و‹ إلى مربّع تعديله؛
// والصفّ الذي سيغيّره طلب معلّق عليه شارة «طلب» تقفز إلى الطلب في «إجراءات الإدارة».
// «الحساب» حقائق فقط (الهاتف كما يرجعه السيرفر، «مسجّل ✓»، آخر دخول) — أوامر الرقم في «إجراءات الإدارة».
// حارس المكدس: كل مجموعة نوع مستقل، والورقة تضعها خلف `AnyView`.

typealias AdminCardRow = AdminMemberCardLogic.Row
typealias AdminCardGroup = AdminMemberCardLogic.Group

/// ما تفعله الصفوف — كلها تمرّ بالورقة (الصلاحيات والتجربة `dryRun` هناك)
struct AdminMemberCardHandlers {
    let openBox: (AdminMemberBox) -> Void
    let openTall: (AdminMemberTallBox) -> Void
    let openFamily: (AdminMemberFamilyBox) -> Void
    /// شارة «طلب» ← الطلب في «إجراءات الإدارة»
    let jumpToRequest: (AdminCardRow) -> Void
    /// مفتاح «الظهور»: true = أخفِه (يسأل أولاً)، false = أظهِره
    let setHidden: (Bool) -> Void
}

// MARK: - ذاكرة المجموعات (لكل مشاهد)

@MainActor
enum AdminMemberGroupMemory {
    static func stored(_ group: AdminCardGroup, viewer: UUID?) -> Bool? {
        UserDefaults.standard.object(forKey: AdminMemberCardLogic.storageKey(group, viewer: viewer)) as? Bool
    }

    static func remember(_ open: Bool, _ group: AdminCardGroup, viewer: UUID?) {
        UserDefaults.standard.set(open, forKey: AdminMemberCardLogic.storageKey(group, viewer: viewer))
    }
}

// MARK: - بطاقة المجموعة

struct AdminMemberGroupCard<Rows: View>: View {
    let group: AdminCardGroup
    let summary: String
    let requestRows: Set<AdminCardRow>
    let pendingRows: Set<AdminCardRow>
    let viewer: UUID?
    let rows: () -> Rows
    /// الاختيار المحفوظ يُقرأ قبل أول رسم — لا ومضة «مفتوحة ثم مطويّة»
    @State private var stored: Bool?

    init(group: AdminCardGroup, summary: String, requestRows: Set<AdminCardRow>, pendingRows: Set<AdminCardRow>,
         viewer: UUID?, @ViewBuilder rows: @escaping () -> Rows) {
        self.group = group
        self.summary = summary
        self.requestRows = requestRows
        self.pendingRows = pendingRows
        self.viewer = viewer
        self.rows = rows
        _stored = State(initialValue: AdminMemberGroupMemory.stored(group, viewer: viewer))
    }

    static func title(_ group: AdminCardGroup) -> String {
        switch group {
        case .data: return L10n.t("البيانات", "Details")
        case .family: return L10n.t("العائلة", "Family")
        case .account: return L10n.t("الحساب", "Account")
        }
    }

    private var locked: Bool {
        AdminMemberCardLogic.locked(group, requestRows: requestRows, pendingRows: pendingRows)
    }

    /// مفتاح الطيّ لمن ينطوي فقط — المقفولة بلا مفتاح
    private var canFold: Bool {
        AdminMemberCardLogic.canFold(group, requestRows: requestRows, pendingRows: pendingRows)
    }

    private var lockTag: String? {
        guard locked else { return nil }
        let hasRequest = requestRows.contains { $0.group == group }
        return hasRequest ? L10n.t("فيها طلب، لا تنطوي", "Has a request — stays open")
                          : L10n.t("تحت التعديل، لا تنطوي", "Saving — stays open")
    }

    var body: some View {
        let open = Binding<Bool>(
            get: { AdminMemberCardLogic.isOpen(stored: stored, locked: locked) },
            set: { value in
                stored = value
                AdminMemberGroupMemory.remember(value, group, viewer: viewer)
            })
        AdminSectionCard(title: Self.title(group), tag: lockTag, isOpen: canFold ? open : nil, subtitle: summary) {
            AdminRowsCardBody { rows() }
        }
    }
}

// MARK: - شارة الصلة (تحت عنوان الصفّ)

struct AdminMemberTag: Equatable {
    enum Tone { case family, outside, daughterSon, neutral }
    let text: String
    var tone: Tone = .neutral

    static func lineage(_ l: AdminMemberCardLogic.Lineage, text: String? = nil) -> AdminMemberTag {
        let words = text ?? AdminMemberCardFamily.title(l)
        switch l {
        case .family: return AdminMemberTag(text: words, tone: .family)
        case .daughterSon: return AdminMemberTag(text: words, tone: .daughterSon)
        case .outsideHusband, .outsideWife: return AdminMemberTag(text: words, tone: .outside)
        }
    }
}

struct AdminMemberTagPill: View {
    let tag: AdminMemberTag

    private var ink: Color {
        switch tag.tone {
        case .family: return DS.Color.palm
        case .outside: return DS.Color.accent
        case .daughterSon: return DS.Color.female
        case .neutral: return DS.Color.textSecondary
        }
    }

    var body: some View {
        Text(verbatim: tag.text)
            .dsFont(.caption)
            .foregroundColor(ink)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs)
            .background(Capsule().fill(ink.opacity(DS.Opacity.tintFill)))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// «طلب» — شارة صغيرة على الصفّ الذي سيغيّره طلب معلّق؛ الضغط يقفز إلى الطلب
struct AdminMemberRequestBadge: View {
    let jump: () -> Void

    var body: some View {
        Button(action: jump) {
            HStack(spacing: DS.Spacing.xxs) {
                Text(L10n.t("طلب", "Request"))
                    .dsFont(.caption)
                Image(systemName: "tray")
                    .dsGlyph(DS.Glyph.xs, weight: .semibold)
            }
            .foregroundColor(DS.Color.accent)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs)
            .background(Capsule().fill(DS.Color.accentLight.opacity(DS.Opacity.tintFill)))
            .overlay(Capsule().strokeBorder(DS.Color.accentLight.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(Text(L10n.t("طلب معلّق", "Pending request")))
        .accessibilityHint(Text(L10n.t("يقفز إلى الطلب في إجراءات الإدارة", "Jumps to the request in admin actions")))
    }
}

// MARK: - صفّ الحقيقة

/// `[مربّع ٣٠ ملوّن][العنوان / سطر / شارة الصلة] … [«طلب»][مصغّرة][القيمة أو «غير مسجّل»][‹]`. القيمة الغائبة تُكتب
/// «غير مسجّل» دائماً (لا فراغ)، و«تحت التعديل» بدوّارة صغيرة أثناء الحفظ. من أحجام إمكانية الوصول القيمة تحت العنوان
struct AdminMemberFactRow: View {
    let icon: String
    var tint: Color = DS.Color.primary
    let title: String
    var subtitle: String? = nil
    var tag: AdminMemberTag? = nil
    /// nil = «غير مسجّل»
    var value: String? = nil
    /// القيمة الغائبة بعد كلمة مؤنثة: «غير مسجّلة» (الأم، الزوجة، الصورة، السيرة، الوفاة، الصلة بالعائلة)
    var feminine: Bool = false
    /// بلا قيمة أصلاً (مفتاح، حبّة) — لا «غير مسجّل»
    var hidesValue: Bool = false
    var valueIsNumber: Bool = false
    var thumbnail: String? = nil
    var hasRequest: Bool = false
    var pending: Bool = false
    var accessory: AnyView? = nil
    /// يفتح مربّع تعديله (بسهم) — nil = للاطلاع
    var action: (() -> Void)? = nil
    var actionHint: String = ""
    var jump: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    private var stacked: Bool { typeSize.isAccessibilitySize }
    private var shownValue: String? {
        hidesValue ? nil : AdminMemberCardLogic.value(value, arabic: L10n.isArabic, feminine: feminine)
    }
    private var missing: Bool { (value ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(AdminRowPressStyle())
                    .accessibilityHint(Text(actionHint))
            } else {
                content
            }
        }
        .accessibilityElement(children: accessory == nil ? .combine : .contain)
        .modifier(AdminMemberJumpAction(jump: hasRequest ? jump : nil))
    }

    private var content: some View {
        HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: icon, tint: tint, filled: true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if pending {
                    HStack(spacing: DS.Spacing.xs) {
                        ProgressView().scaleEffect(DS.Spinner.chipScale)
                        Text(L10n.t("تحت التعديل", "Saving…"))
                            .dsFont(.subtitle)
                            .foregroundColor(DS.Color.warning)
                    }
                } else if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let tag { AdminMemberTagPill(tag: tag) }
                if stacked, let shownValue { valueText(shownValue) }
            }
            Spacer(minLength: DS.Spacing.sm)
            if hasRequest, let jump {
                AdminMemberRequestBadge(jump: jump)
            }
            if let thumbnail, let url = URL(string: thumbnail) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(tint.opacity(DS.Opacity.tintFill))
                }
                .frame(width: DS.Icon.section, height: DS.Icon.section)
                .clipShape(Circle())
                .accessibilityHidden(true)
            }
            if !stacked, let shownValue { valueText(shownValue) }
            if let accessory { accessory }
            if action != nil { DSChevron() }
        }
        .padding(.vertical, DS.Spacing.xsm)
        .frame(minHeight: (subtitle != nil || tag != nil || stacked) ? DS.Hub.rowMinHeightTwoLines : DS.Hub.rowMinHeight)
        .contentShape(Rectangle())
    }

    private func valueText(_ text: String) -> some View {
        Text(verbatim: text)
            .dsFont(.body)
            .monospacedDigit()
            .foregroundColor(missing ? DS.Color.textTertiary : DS.Color.textSecondary)
            .lineLimit(stacked ? 3 : 1)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.layoutDirection, valueIsNumber ? .leftToRight : LanguageManager.shared.layoutDirection)
    }
}

/// للقارئ الصوتي: «افتح الطلب» على الصفّ الذي عليه شارة «طلب» (الشارة نفسها زرّ داخل الصفّ)
private struct AdminMemberJumpAction: ViewModifier {
    let jump: (() -> Void)?

    func body(content: Content) -> some View {
        if let jump {
            content.accessibilityAction(named: Text(L10n.t("افتح الطلب", "Open the request")), jump)
        } else {
            content
        }
    }
}

// MARK: - «البيانات»

struct AdminMemberDataGroup: View {
    let member: FamilyMember
    let isProfile: Bool
    let canEdit: Bool
    /// ح٢: «الجنس» أمر عائلة (نقل بين الشجرتين) — مقفول على ورقتك؛ بقية «البيانات» بـ`canEdit`
    let familyAdmin: Bool
    let requestRows: Set<AdminCardRow>
    let pendingRows: Set<AdminCardRow>
    let viewer: UUID?
    let handlers: AdminMemberCardHandlers

    private var m: FamilyMember { member }
    /// تعديل البيانات من هنا لملفات شجرة الرجال فقط — عقدة شجرة النساء تُعدَّل من شجرتها
    private var edits: Bool { canEdit && isProfile }

    private var genderText: String? {
        switch (m.gender ?? "").lowercased() {
        case "male": return L10n.t("ذكر", "Male")
        case "female": return L10n.t("أنثى", "Female")
        default: return nil
        }
    }

    private var birth: String? { AdminMemberSheetFacts.dayText(m.birthDate) }

    private var age: String? {
        guard m.isDeceased != true, let years = WifeCandidateRules.age(m), years >= 0 else { return nil }
        return L10n.isArabic
            ? AdminTodayText.arabicCount(years, one: "سنة واحدة", two: "سنتان", few: "سنوات", many: "سنة", single: "سنة")
            : "Age \(years)"
    }

    private var death: String? {
        if m.deathDateUnknown == true { return L10n.t("غير معروف", "Unknown") }
        return AdminMemberSheetFacts.dayText(m.deathDate)
    }

    private var hasPhoto: Bool { PhotoNudgeLogic.hasPhoto(avatar: m.avatarUrl, photo: m.photoURL) }

    /// «موجودة» · «بلا صورة» · «لا توجد صورة لهذا العضو»
    private var photoText: String {
        AdminMemberCardLogic.photoValue(hasPhoto: hasPhoto, unavailable: m.avatarUnavailable == true, arabic: L10n.isArabic)
    }

    private var thumbnail: String? {
        guard hasPhoto, !m.isFemale else { return nil }
        return [m.avatarUrl, m.photoURL].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }

    private var bioCount: Int { m.bio?.count ?? 0 }

    private var bioText: String? {
        guard bioCount > 0 else { return nil }
        return L10n.isArabic
            ? AdminTodayText.arabicCount(bioCount, one: "حدث واحد", two: "حدثان", few: "أحداث", many: "حدثاً", single: "حدث")
            : "\(bioCount) entries"
    }

    var summary: String {
        let ar = L10n.isArabic
        var parts: [String] = [
            AdminMemberCardLogic.part(birth.map { L10n.t("ميلاد \($0)", "Born \($0)") }, label: L10n.t("الميلاد", "Birth"), arabic: ar)
        ]
        if m.isDeceased == true {
            parts.append(AdminMemberCardLogic.part(death.map { L10n.t("وفاة \($0)", "Died \($0)") },
                                                   label: L10n.t("الوفاة", "Death"), arabic: ar, feminine: true))
        }
        parts.append(AdminMemberCardLogic.part(genderText, label: L10n.t("الجنس", "Gender"), arabic: ar))
        if !m.isFemale {
            // الملخّص والصفّ بكلمة واحدة: «صورة» · «بلا صورة» · «لا توجد صورة لهذا العضو»
            parts.append(hasPhoto ? L10n.t("صورة", "Photo") : photoText)
        }
        parts.append(AdminMemberCardLogic.part(bioCount > 0 ? L10n.t("سيرة", "Biography") : nil,
                                               label: L10n.t("السيرة", "Biography"), arabic: ar, feminine: true))
        return AdminMemberCardLogic.summary(parts)
    }

    private func jump(_ row: AdminCardRow) -> (() -> Void)? {
        requestRows.contains(row) ? { handlers.jumpToRequest(row) } : nil
    }

    var body: some View {
        AdminMemberGroupCard(group: .data, summary: summary, requestRows: requestRows, pendingRows: pendingRows,
                             viewer: viewer) {
            AdminMemberFactRow(icon: "textformat", tint: DS.Color.primary, title: L10n.t("الاسم", "Name"),
                               value: AdminMemberSheetLogic.firstName(m.firstName, full: m.fullName),
                               hasRequest: requestRows.contains(.name),
                               action: edits ? { handlers.openTall(.editAll(m)) } : nil,
                               actionHint: L10n.t("تعديل", "Edit"), jump: jump(.name))
            AdminMemberFactRow(icon: "calendar", tint: DS.Color.primary, title: L10n.t("الميلاد", "Birth"),
                               subtitle: age, value: birth, valueIsNumber: birth != nil,
                               hasRequest: requestRows.contains(.birth),
                               action: edits ? { handlers.openBox(.birth(m)) } : nil,
                               actionHint: birth == nil ? L10n.t("إضافة", "Add") : L10n.t("تعديل", "Edit"),
                               jump: jump(.birth))
            if m.isDeceased == true {
                let incomplete = AdminMemberFacts.deathIncomplete(m)
                AdminMemberFactRow(icon: "calendar.badge.clock", tint: DS.Color.deceased, title: L10n.t("الوفاة", "Death"),
                                   subtitle: incomplete ? AdminMemberGap.deathIncomplete.title : nil,
                                   value: death, feminine: true, valueIsNumber: death != nil && m.deathDateUnknown != true,
                                   hasRequest: requestRows.contains(.death),
                                   action: edits ? {
                                       handlers.openBox(AdminMemberFacts.isBlank(m.deathDate) || m.deathDateUnknown == true
                                                        ? .death(m) : .deathDate(m))
                                   } : nil,
                                   actionHint: incomplete ? L10n.t("استكمال", "Complete") : L10n.t("تعديل", "Edit"),
                                   jump: jump(.death))
            }
            // تغيير الجنس نقلٌ بين الشجرتين (`move_child_gender`) — مربّعه يسأل أولاً ويقول ما يبقى وما يُحذف
            AdminMemberFactRow(icon: "person", tint: DS.Color.slate, title: L10n.t("الجنس", "Gender"),
                               subtitle: L10n.t("التغيير ينقله بين الشجرتين، ويسأل أولاً",
                                                "Changing it moves them between the trees; asks first"),
                               value: genderText, hasRequest: requestRows.contains(.gender),
                               action: familyAdmin ? {
                                   if AdminMemberFacts.isBlank(m.gender) && isProfile { handlers.openBox(.gender(m)) }
                                   else { handlers.openFamily(.gender(m)) }
                               } : nil,
                               actionHint: L10n.t("تغيير", "Change"), jump: jump(.gender))
            // باب واحد للصورة: إضافة أو تبديل (لا صور للإناث في التطبيق — طلب المالك ٢٠٢٦-١١-٢٤)
            if !m.isFemale {
                AdminMemberFactRow(icon: "photo", tint: DS.Color.sadu, title: L10n.t("الصورة", "Photo"),
                                   value: photoText, thumbnail: thumbnail,
                                   hasRequest: requestRows.contains(.photo),
                                   action: edits ? { handlers.openBox(.photo(m)) } : nil,
                                   actionHint: hasPhoto ? L10n.t("تبديل", "Replace") : L10n.t("إضافة", "Add"),
                                   jump: jump(.photo))
            }
            AdminMemberFactRow(icon: "doc.text", tint: DS.Color.accent, title: L10n.t("السيرة", "Biography"),
                               value: bioText, feminine: true, hasRequest: requestRows.contains(.bio),
                               action: edits ? { handlers.openTall(.editAll(m)) } : nil,
                               actionHint: bioCount == 0 ? L10n.t("إضافة", "Add") : L10n.t("تعديل", "Edit"),
                               jump: jump(.bio))
        }
    }
}

// MARK: - «الحساب» — حقائق فقط

struct AdminMemberAccountGroup: View {
    let member: FamilyMember
    let facts: AdminMemberSheetFacts
    let requestRows: Set<AdminCardRow>
    let pendingRows: Set<AdminCardRow>
    let viewer: UUID?
    let jumpToRequest: (AdminCardRow) -> Void
    /// الأجهزة للاطلاع (لمن يراها ولا يسجّل خروجها) — كما كانت في «الحساب»
    let devices: AnyView?

    private var phone: String { (member.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    /// م١٠: كلمة الرأس نفسها («بدون حساب») ثم «لم يسجّل الدخول بعد» — لا «غير مسجّل · آخر دخول غير مسجّل»
    var summary: String {
        AdminMemberCardLogic.accountSummary(statusWord: AdminMemberAccountSection.registerWord(facts.status),
                                            lastSeen: facts.account?.lastSeen.map(AdminMemberSheetFacts.dateText),
                                            hasAccount: facts.account != nil, female: member.isFemale,
                                            arabic: L10n.isArabic)
    }

    var body: some View {
        AdminMemberGroupCard(group: .account, summary: summary, requestRows: requestRows, pendingRows: pendingRows,
                             viewer: viewer) {
            // الرقم كما وصل من السيرفر (مخفياً لمن لا يراه) — تعديله ومسحه في «إجراءات الإدارة»
            AdminMemberFactRow(icon: "phone", tint: DS.Color.sea, title: L10n.t("الهاتف", "Phone"),
                               value: phone.isEmpty ? nil : KuwaitPhone.display(phone), valueIsNumber: !phone.isEmpty,
                               hasRequest: requestRows.contains(.phone), pending: pendingRows.contains(.phone),
                               jump: requestRows.contains(.phone) ? { jumpToRequest(.phone) } : nil)
            AdminMemberFactRow(icon: "iphone", tint: DS.Color.sea, title: L10n.t("التطبيق", "App"),
                               subtitle: AdminMemberAccountSection.registerNote(member: member, facts: facts),
                               hidesValue: true,
                               accessory: AnyView(AdminStatePill(title: AdminMemberAccountSection.registerWord(facts.status),
                                                                 tone: AdminMemberAccountSection.registerTone(facts.status),
                                                                 icon: facts.status == .registered ? "checkmark" : nil)))
            AdminMemberFactRow(icon: "clock", tint: DS.Color.sea, title: L10n.t("آخر دخول", "Last sign-in"),
                               subtitle: facts.usageLine,
                               value: facts.lastSeenText(female: member.isFemale),
                               valueIsNumber: facts.account?.lastSeen != nil)
            if let devices { devices }
        }
    }
}
