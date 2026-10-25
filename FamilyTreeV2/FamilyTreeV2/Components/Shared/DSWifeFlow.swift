import SwiftUI
import UIKit
import Supabase

// MARK: - «إضافة زوجة» الواحدة (طلب المالك ٢٠٢٦-١٠-٢٥)
//
// «مابي … المتزوجة … اقل من ١٨ … المولودة توه» + «ادمج ربط الزوجة مع اضافة زوجة … تحت ابيها … حتى في الملف الشخصي».
// مسار واحد في شجرة النساء (الإدارة · «عائلتي» · «طلب إضافة») وفي «حسابي»:
//   ١) من أين هي؟ — من العائلة، أو من خارجها
//   ٢) من العائلة: أبوها من الشجرة ← بناته المتاحات ← اختيارها زوجةً، أو «أضفها تحت أبيها» بالاسم
//   ٣) من خارج العائلة: مربّع الاسم الموجود عند كل مضيف
// المربّع للاختيار وحده — الكتابة عند المضيف بمساراته الموجودة (`WomenStore`، `add_or_link_self_relative`، الطلبات).

/// من تظهر في قوائم اختيار الزوجة — القواعد الواحدة لكل القوائم
enum WifeCandidateRules {
    // الرقمان من السيرفر (`app_config`، موافقة المالك ٢٠٢٦-١٠-٢٥ — يتغيّران بلا بناء تطبيق):
    //   • wife_candidate_min_age (عدد صحيح ١٢–٣٠، افتراضي ١٨): أقل عمر يظهر حين يُعرف تاريخ الميلاد
    //   • wife_candidate_recent_months (٠–٦٠، افتراضي ١٢): «المضافة حديثاً» خلال هذه الأشهر — ٠ = بلا هذه القاعدة
    // مفتاح غائب أو جلب فاشل = الافتراضي. الجلب يبدأ حين يُفتح مربّع الزوجة (`AppConfigValues`).
    static let minAgeKey = "wife_candidate_min_age"
    static let recentMonthsKey = "wife_candidate_recent_months"

    /// أقل عمر يظهر حين يُعرف تاريخ الميلاد
    static var minimumAge: Int { AppConfigValues.shared.int(minAgeKey, default: 18) }
    /// «المضافة حديثاً» = خلال آخر هذه الأشهر (٠ = لا تُستبعد)
    static var recentMonths: Int { AppConfigValues.shared.int(recentMonthsKey, default: 12) }

    /// تظهر مرشّحةً زوجةً؟
    /// ١) ليست متزوجة: لا زوج مرتبط بها، ولا «متزوجة» معلَّمة
    /// ٢) ليست دون ١٨ سنة — حين يُعرف ميلادها (مجهولة الميلاد لا يُحكم عليها بالعمر)
    /// ٣) ليست «مولودة حديثاً»: سجلّ بلا تاريخ ميلاد، أُضيف خلال آخر ١٢ شهراً، وله أب أو أم في الشجرة —
    ///    البنت الجديدة تُضاف تحت أبيها أو أمها بلا عمر غالباً (الزوجة والأم تُضافان بزوج فتسقطان بالقاعدة ١)
    static func isEligible(_ w: FamilyMember, now: Date = Date()) -> Bool {
        w.isFemale && w.isDeceased != true
            && !isMarried(w) && !isUnderAge(w, now: now) && !isRecentNewborn(w, now: now)
    }

    static func isMarried(_ w: FamilyMember) -> Bool { w.husbandId != nil || w.isMarried == true }

    static func isUnderAge(_ w: FamilyMember, now: Date) -> Bool {
        guard let years = age(w, now: now) else { return false }
        return years < minimumAge
    }

    static func isRecentNewborn(_ w: FamilyMember, now: Date) -> Bool {
        let months = recentMonths
        guard months > 0, birthDay(w.birthDate) == nil, w.fatherId != nil || w.motherId != nil,
              let added = timestamp(w.createdAt),
              let cutoff = calendar.date(byAdding: .month, value: -months, to: now) else { return false }
        return added > cutoff
    }

    /// العمر بالسنوات من تاريخ الميلاد — nil = غير معروف
    static func age(_ w: FamilyMember, now: Date = Date()) -> Int? {
        guard let born = birthDay(w.birthDate) else { return nil }
        return calendar.dateComponents([.year], from: born, to: now).year
    }

    // MARK: الآباء والبنات

    /// أقل عمر للأب في قائمة «أبوها» (طلب المالك ٢٠٢٦-١٠-٢٥ «لازم تراعي عمر الأب… المولود حديثاً شلون يكون أب؟»).
    /// من السيرفر إن وُجد المفتاح `father_candidate_min_age`، وإلا ٣٠
    static let fatherMinAgeKey = "father_candidate_min_age"
    static var fatherMinimumAge: Int { AppConfigValues.shared.int(fatherMinAgeKey, default: 30) }

    /// يصلح أباً؟ المتوفّى يظهر دائماً. الحيّ: لا يظهر إن عُرف عمره وكان دون الحد، ولا إن كان «مضافاً حديثاً»
    /// بلا تاريخ ميلاد تحت أب (نفس قاعدة البنت الجديدة). `childBorn`: ميلاد صاحب العقدة في مسار الأم —
    /// أبو الأم أكبر منه بالحد على الأقل حين يُعرف الميلادان
    static func canBeFather(_ m: FamilyMember, childBorn: Date? = nil, now: Date = Date()) -> Bool {
        if m.isDeceased == true { return true }
        let minAge = fatherMinimumAge
        if let years = age(m, now: now), years < minAge { return false }
        if isRecentNewborn(m, now: now) { return false }
        if let childBorn, let born = birthDay(m.birthDate),
           let gap = calendar.dateComponents([.year], from: born, to: childBorn).year, gap < minAge { return false }
        return true
    }

    /// آباء لا تُعرض بناتهم لهذا الرجل (محارمه): هو نفسه، وأبوه وأجداده (أخواته وعمّاته)، وذكور ذرّية أبيه —
    /// إخوته وأبناؤه وأحفادهم (بنات إخوته وبناته وحفيداته). بلا أب معروف: ذرّيته هو
    static func blockedFathers(for husbandId: UUID, in people: [FamilyMember]) -> Set<UUID> {
        var fatherOf: [UUID: UUID] = [:]
        var sonsOf: [UUID: [UUID]] = [:]
        for p in people where !p.isFemale {
            guard let f = p.fatherId else { continue }
            fatherOf[p.id] = f
            sonsOf[f, default: []].append(p.id)
        }
        var blocked: Set<UUID> = [husbandId]
        var up = fatherOf[husbandId]
        while let a = up, blocked.insert(a).inserted { up = fatherOf[a] }
        var seen: Set<UUID> = []
        var stack = [fatherOf[husbandId] ?? husbandId]
        while let node = stack.popLast() {
            for son in sonsOf[node] ?? [] where seen.insert(son).inserted {
                blocked.insert(son)
                stack.append(son)
            }
        }
        return blocked
    }

    /// قائمة الآباء: رجال الشجرة بنسخهم في شجرة النساء (شرط دالة السيرفر وجدول البنات)، بلا محارم الزوج، بالاسم
    static func fathers(for husbandId: UUID, in people: [FamilyMember], showsHidden: Bool) -> [FamilyMember] {
        let blocked = blockedFathers(for: husbandId, in: people)
        return people
            .filter { m in
                !m.isFemale && !blocked.contains(m.id) && canBeFather(m)
                    && (showsHidden || !m.isHiddenFromTree)
                    && !m.fullName.trimmingCharacters(in: .whitespaces).isEmpty
            }
            .sorted { $0.fullName.localizedCompare($1.fullName) == .orderedAscending }
    }

    /// بنات الأب الأحياء: المتاحات بترتيبهنّ، وعدد من أخفتهنّ القواعد (لسطر التوضيح)
    static func daughters(of fatherId: UUID, husbandId: UUID, in people: [FamilyMember], showsHidden: Bool,
                          now: Date = Date()) -> (eligible: [FamilyMember], hidden: Int) {
        let all = people.filter {
            $0.fatherId == fatherId && $0.isFemale && $0.isDeceased != true && $0.id != husbandId
                && (showsHidden || !$0.isHiddenFromTree)
                && !$0.firstName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let eligible = all.filter { isEligible($0, now: now) }.sorted { $0.sortOrder < $1.sortOrder }
        return (eligible, all.count - eligible.count)
    }

    /// آباء «الأم من العائلة»: رجال الشجرة عدا صاحب العقدة وأبيه (الأم ليست أخت أبيه في الشجرة)
    static func motherFathers(for personId: UUID, in people: [FamilyMember], showsHidden: Bool) -> [FamilyMember] {
        let person = people.first { $0.id == personId }
        let personFather = person?.fatherId
        let personBorn = person.flatMap { birthDay($0.birthDate) }
        return people
            .filter { m in
                !m.isFemale && m.id != personId && m.id != personFather && canBeFather(m, childBorn: personBorn)
                    && (showsHidden || !m.isHiddenFromTree)
                    && !m.fullName.trimmingCharacters(in: .whitespaces).isEmpty
            }
            .sorted { $0.fullName.localizedCompare($1.fullName) == .orderedAscending }
    }

    /// بنات الأب للأم: بلا زوج أو زوجها أبو صاحب العقدة (المتوفّاة تظهر — قد تكون الأم متوفّاة)، وعدد من سواهنّ
    static func motherDaughters(of fatherId: UUID, personId: UUID, personFatherId: UUID?, in people: [FamilyMember],
                                showsHidden: Bool) -> (eligible: [FamilyMember], hidden: Int) {
        let all = people.filter {
            $0.fatherId == fatherId && $0.isFemale && $0.id != personId
                && (showsHidden || !$0.isHiddenFromTree)
                && !$0.firstName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let eligible = all.filter { $0.husbandId == nil || ($0.husbandId != nil && $0.husbandId == personFatherId) }
            .sorted { $0.sortOrder < $1.sortOrder }
        return (eligible, all.count - eligible.count)
    }

    /// رسالة خطأ الكتابة في مسار الزوجة (رموز `add_or_link_self_relative`)، وإلا الرسالة العامة
    static func failureMessage(_ error: Error) -> String {
        switch (error as? PostgrestError)?.hint {
        case "already_married":
            return L10n.t("مرتبطة بزوج آخر — راجع الإدارة.", "She's linked to another husband — contact the admins.")
        case "not_daughter":
            return L10n.t("المختارة ليست من بنات هذا الأب.", "She isn't a daughter of this father.")
        case "no_father":
            return L10n.t("الأب غير موجود في الشجرة.", "The father isn't in the tree.")
        default:
            return WomenStore.failureMessage(error)
        }
    }

    // MARK: التواريخ

    private static let calendar = Calendar(identifier: .gregorian)
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let stampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let stampFormatterPlain = ISO8601DateFormatter()

    /// «yyyy-MM-dd»، أو السنة وحدها (آخر يومها — الأصغر عمراً، فلا تظهر من قد تكون دون ١٨)
    private static func birthDay(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.count >= 10, let d = dayFormatter.date(from: String(raw.prefix(10))) { return d }
        guard let r = raw.range(of: "\\d{4}", options: .regularExpression) else { return nil }
        return dayFormatter.date(from: String(raw[r]) + "-12-31")
    }

    /// وقت السيرفر (timestamptz بأجزاء الثانية أو بدونها، أو اليوم وحده)
    private static func timestamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return stampFormatter.date(from: raw) ?? stampFormatterPlain.date(from: raw)
            ?? (raw.count >= 10 ? dayFormatter.date(from: String(raw.prefix(10))) : nil)
    }
}

// MARK: - المربّع

/// مربّع «إضافة زوجة» بخطواته في مكانه: من أين ← الأب ← بناته (أو إضافتها تحته). الخطوة تتبدّل داخل المربّع نفسه
struct DSWifeFlowBox: View {
    /// آلية الكتابة عند المضيف — تغيّر العنوان وزرّ الإجراء فقط
    enum Mode { case direct, selfFamily, request }
    /// زوجة لهذا الرجل، أو أمّ لهذا الشخص (طلب المالك ٢٠٢٦-١٠-٢٥ «الأم نفس طريقة الزوجة»)
    enum Relation { case wife, mother }
    private enum Step: Equatable { case choice, father, daughters(UUID) }

    let mode: Mode
    var relation: Relation = .wife
    /// الزوج (للزوجة) أو صاحب العقدة (للأم)
    let husbandId: UUID
    /// أبو صاحب العقدة (للأم): بناتٌ زوجُهنّ أبوه يظهرن أيضاً
    var personFatherId: UUID? = nil
    let husbandName: String
    /// السطر تحت العنوان — nil = اسم الزوج (مثل مربّع الإجراءات)
    var subtitle: String? = nil
    /// شجرة النساء كاملة (الرجال بنسخهم والنساء) — منها الآباء والبنات
    let people: [FamilyMember]
    var isLoading: Bool = false
    /// الإدارة ترى المخفيّين في الشجرة (بعلامتهم هناك) — غيرها لا
    var showsHidden: Bool = false
    var isBusy: Bool = false
    var error: String? = nil
    /// «من خارج العائلة» — مربّع الاسم عند المضيف (nil = المضيف سأل قبل المربّع)
    var onOutside: (() -> Void)? = nil
    let onLink: (_ daughter: FamilyMember, _ father: FamilyMember) -> Void
    let onAddUnderFather: (_ name: String, _ father: FamilyMember) -> Void
    let onCancel: () -> Void

    @State private var step: Step
    @State private var search = ""
    @State private var selectedId: UUID? = nil
    @State private var addingNew = false
    @State private var newName = ""
    /// القوائم تُعاد حين تصل أرقام السيرفر
    @ObservedObject private var config = AppConfigValues.shared

    init(mode: Mode, relation: Relation = .wife, husbandId: UUID, personFatherId: UUID? = nil,
         husbandName: String, subtitle: String? = nil, people: [FamilyMember],
         isLoading: Bool = false, showsHidden: Bool = false, startsAtFather: Bool = false,
         isBusy: Bool = false, error: String? = nil, onOutside: (() -> Void)? = nil,
         onLink: @escaping (_ daughter: FamilyMember, _ father: FamilyMember) -> Void,
         onAddUnderFather: @escaping (_ name: String, _ father: FamilyMember) -> Void,
         onCancel: @escaping () -> Void) {
        self.mode = mode
        self.relation = relation
        self.husbandId = husbandId
        self.personFatherId = personFatherId
        self.husbandName = husbandName
        self.subtitle = subtitle
        self.people = people
        self.isLoading = isLoading
        self.showsHidden = showsHidden
        self.isBusy = isBusy
        self.error = error
        self.onOutside = onOutside
        self.onLink = onLink
        self.onAddUnderFather = onAddUnderFather
        self.onCancel = onCancel
        // المضيف الذي سأل «من أين؟» قبل المربّع (حسابي) يبدأ بالأب
        _step = State(initialValue: startsAtFather || onOutside == nil ? .father : .choice)
    }

    var body: some View {
        Group {
            // كل خطوة مربّع كامل بحدود `AnyView` — لا يتراكم عمق الأنواع فوق التفاصيل (مكدس الآيفون)
            switch step {
            case .choice: AnyView(choiceStep)
            case .father: AnyView(fatherStep)
            case .daughters(let id): AnyView(daughtersStep(fatherId: id))
            }
        }
        // رقما القواعد من السيرفر (أقل عمر، «المضافة حديثاً») — جلب مرة كل ٥ دقائق على الأكثر
        .task { await config.refresh() }
    }

    // MARK: النصوص

    private var isMother: Bool { relation == .mother }
    private var title: String {
        if isMother {
            return mode == .request ? L10n.t("طلب إضافة أم", "Request a mother") : L10n.t("إضافة أم", "Add mother")
        }
        return mode == .request ? L10n.t("طلب إضافة زوجة", "Request a wife") : L10n.t("إضافة زوجة", "Add wife")
    }
    private var headerIcon: String { isMother ? "figure.stand.dress" : "heart.fill" }
    /// «زوجةً» / «أمّاً» في الأزرار والشرح
    private var asWord: String { isMother ? L10n.t("أمّاً", "as mother") : L10n.t("زوجةً", "as wife") }
    /// السطر تحت العنوان: الزوج (مثل مربّع الإجراءات)، أو ما يمرّره المضيف
    private var forLine: String { subtitle ?? husbandName }
    private var requestNote: String? {
        mode == .request ? L10n.t("يُرسل للإدارة للمراجعة", "Sent to the administration for review") : nil
    }
    private var trimmedName: String { newName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func go(_ next: Step) {
        selectedId = nil; addingNew = false; newName = ""; search = ""
        step = next
    }

    private func shownName(_ m: FamilyMember) -> String { m.fullName.isEmpty ? m.firstName : m.displayFullName }
    private func firstName(_ m: FamilyMember) -> String { m.firstName.isEmpty ? m.fullName : m.firstName }

    // MARK: ١) من أين هي؟

    private var choiceStep: some View {
        DSComposer(
            title: title,
            subtitle: forLine,
            icon: headerIcon,
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            canSubmit: false,
            note: requestNote,
            onSubmit: {},
            onCancel: onCancel
        ) {
            DSComposerSection(title: isMother ? L10n.t("من أين الأم؟", "Where is she from?")
                                              : L10n.t("من أين الزوجة؟", "Where is she from?"), icon: "person.fill.questionmark",
                              tint: DS.Color.female, index: 0) {
                VStack(spacing: DS.Spacing.sm) {
                    // من العائلة = أخضر العائلة ورمز الشجرة، ومن خارجها = كحلي القسم (اسم يُكتب)
                    WifeFlowOption(title: L10n.t("من العائلة", "From the family"),
                                   hint: L10n.t("تختار أباها من الشجرة، ثم تختارها من بناته أو تضيفها تحته",
                                                "Pick her father in the tree, then pick her from his daughters or add her"),
                                   icon: "tree.fill", tint: DSMemberKit.addTint) { go(.father) }
                        .dsEntrance(delay: DSMotion.staggerDelay(1, base: DSMotion.sectionsAfterHeader),
                                    y: DSMotion.rise, scale: DSMotion.riseScale)
                    WifeFlowOption(title: L10n.t("من خارج العائلة", "From outside the family"),
                                   hint: L10n.t("تكتب اسمها فقط", "Just type her name"),
                                   icon: "person.crop.circle.badge.plus", tint: DS.Color.primary) { onOutside?() }
                        .dsEntrance(delay: DSMotion.staggerDelay(2, base: DSMotion.sectionsAfterHeader),
                                    y: DSMotion.rise, scale: DSMotion.riseScale)
                }
            }
        }
    }

    // MARK: ٢) الأب من الشجرة

    private var fatherStep: some View {
        DSMemberPickerBox(
            title: L10n.t("أبوها في الشجرة", "Her father in the tree"),
            subtitle: L10n.t("اختر أباها، ثم اخترها من بناته", "Pick her father, then pick her from his daughters"),
            icon: "tree.fill",
            candidates: isMother ? WifeCandidateRules.motherFathers(for: husbandId, in: people, showsHidden: showsHidden)
                                 : WifeCandidateRules.fathers(for: husbandId, in: people, showsHidden: showsHidden),
            search: $search,
            isLoading: isLoading,
            // لا أسماء قبل الكتابة (طلب المالك ٢٠٢٦-١٠-٢٥) — والمطابقة دقيقة (`NameSearch`)
            listsAllWhenEmpty: false,
            searchLabel: L10n.t("اسم الأب", "Father's name"),
            searchPlaceholder: L10n.t("اكتب اسم أبيها", "Type her father's name"),
            hintTitle: L10n.t("اكتب اسم أبيها", "Type her father's name"),
            hintMessage: L10n.t("تظهر الأسماء بعد الكتابة — كل كلمة تطابق بداية اسم بالترتيب.",
                                "Names appear as you type — each word matches the start of a name, in order."),
            emptyTitle: L10n.t("لا رجال في الشجرة بعد", "No men in the tree yet"),
            noMatchTitle: L10n.t("ما لقينا اسماً مطابقاً", "No matching name"),
            rowHint: L10n.t("عرض بناته", "Show his daughters"),
            onPick: { go(.daughters($0.id)) },
            onCancel: onCancel
        )
    }

    // MARK: ٣) بناته — أو «أضفها تحت أبيها»

    private func daughtersStep(fatherId: UUID) -> some View {
        let father = people.first { $0.id == fatherId }
        let list = isMother
            ? WifeCandidateRules.motherDaughters(of: fatherId, personId: husbandId, personFatherId: personFatherId,
                                                 in: people, showsHidden: showsHidden)
            : WifeCandidateRules.daughters(of: fatherId, husbandId: husbandId, in: people, showsHidden: showsHidden)
        let request = mode == .request
        let actionTitle = request ? L10n.t("إرسال الطلب", "Send request")
            : (addingNew ? L10n.t("إضافة وربط", "Add & link") : L10n.t("ربطها ", "Link ") + asWord)
        return DSComposer(
            title: title,
            subtitle: forLine,
            icon: headerIcon,
            tint: DS.Color.actionNavy,
            actionTitle: actionTitle,
            actionIcon: request ? "paperplane.fill" : (addingNew ? "plus" : "link"),
            canSubmit: father != nil && (addingNew ? !trimmedName.isEmpty : selectedId != nil),
            isBusy: isBusy,
            note: requestNote,
            hasUnsavedChanges: !trimmedName.isEmpty,
            onSubmit: { submit(father: father, eligible: list.eligible) },
            onCancel: onCancel
        ) {
            fatherSection(father)
            daughtersSection(list, father: father)
            if addingNew { nameSection(father) }
            if let error {
                DSNoteCard(error, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
    }

    /// الأب المختار + «تغيير» يرجع لقائمة الآباء
    private func fatherSection(_ father: FamilyMember?) -> some View {
        DSComposerSection(title: L10n.t("أبوها", "Her father"), icon: "person.fill", tint: DS.Color.male, index: 0) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "person.fill", tint: DS.Color.male)
                    .accessibilityHidden(true)
                // الاسم كاملاً على سطرين — هو ما يميّز الأب
                Text(father.map(shownName) ?? "")
                    .dsFieldFont(.memberName)
                    .foregroundColor(DS.Color.fieldValue)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                DSChipButton(L10n.t("تغيير", "Change"), icon: "arrow.uturn.backward",
                             tint: DS.Color.male, size: .small) { go(.father) }
            }
            .dsRowBox()
        }
    }

    /// البنات المتاحات (اختيار واحد)، وسطر يوضّح من لا تظهر، ثم «أضفها تحت أبيها»
    private func daughtersSection(_ list: (eligible: [FamilyMember], hidden: Int), father: FamilyMember?) -> some View {
        DSComposerSection(title: L10n.t("بناته", "His daughters"), icon: "figure.stand.dress", tint: DS.Color.female,
                          trailing: list.eligible.isEmpty ? nil : "\(list.eligible.count)", index: 1) {
            VStack(spacing: DS.Spacing.sm) {
                if list.eligible.isEmpty {
                    DSEmptyView(L10n.t("لا بنات متاحات له في الشجرة", "No available daughters in the tree"),
                                icon: "person.fill.questionmark", style: .inline)
                }
                ForEach(Array(list.eligible.enumerated()), id: \.element.id) { i, d in
                    WifeDaughterRow(name: firstName(d), age: WifeCandidateRules.age(d),
                                    isSelected: selectedId == d.id && !addingNew) {
                        withAnimation(DS.Anim.snappy) { selectedId = d.id; addingNew = false; newName = "" }
                    }
                    .dsEntrance(delay: DSMotion.staggerDelay(i + 2, base: DSMotion.sectionsAfterHeader),
                                y: DSMotion.rise, scale: DSMotion.riseScale)
                }
                if list.hidden > 0 {
                    // لماذا لا تظهر بعضهنّ — بلا أسماء
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                        Image(systemName: "eye.slash")
                            .dsGlyph(DS.Glyph.xs, weight: .semibold)
                            .accessibilityHidden(true)
                        Text(isMother ? L10n.t("لا تظهر \(list.hidden): المتزوجة بغير أبيه",
                                           "\(list.hidden) not shown: married to someone other than his father")
                                  : hiddenNote(list.hidden))
                            .dsFont(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundColor(DS.Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                WifeFlowOption(title: L10n.t("أضفها تحت أبيها", "Add her under her father"),
                               hint: L10n.t("إن لم تكن في القائمة — بنتاً جديدة له", "If she isn't listed — a new daughter of his"),
                               icon: "plus", tint: DSMemberKit.addTint, isSelected: addingNew) {
                    withAnimation(DS.Anim.snappy) { addingNew = true; selectedId = nil }
                }
            }
        }
    }

    /// «لا تظهر N: …» بالقواعد المفعّلة الآن (رقما السيرفر — «المضافة حديثاً» تُذكر ما دامت قاعدتها مفعّلة)
    private func hiddenNote(_ n: Int) -> String {
        let age = WifeCandidateRules.minimumAge
        return WifeCandidateRules.recentMonths > 0
            ? L10n.t("لا تظهر \(n): المتزوجة، ومن عمرها أقل من \(age)، والمضافة حديثاً بلا تاريخ ميلاد",
                     "\(n) not shown: married, under \(age), or newly added without a birth date")
            : L10n.t("لا تظهر \(n): المتزوجة، ومن عمرها أقل من \(age)",
                     "\(n) not shown: married or under \(age)")
    }

    /// اسمها — بنت جديدة لأبيها ثم زوجة (الاسم الأول؛ يُكمَل باسم أبيها)
    private func nameSection(_ father: FamilyMember?) -> some View {
        DSComposerSection(title: L10n.t("اسمها", "Her name"), icon: "person.fill", tint: DS.Color.female, index: 2) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                DSComposerField(icon: "person.fill",
                                label: L10n.t("الاسم الأول", "First name"),
                                placeholder: L10n.t("اسمها الأول", "Her first name"),
                                text: $newName)
                if let father {
                    Text(mode == .request
                         ? L10n.t("تضيفها الإدارة بنتاً لـ\(firstName(father)) ثم تربطها ", "The admins add her as \(firstName(father))'s daughter, then link her ") + asWord
                         : L10n.t("تُضاف بنتاً لـ\(firstName(father)) ثم تُربط ", "Added as \(firstName(father))'s daughter, then linked ") + asWord)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .transition(.opacity)
    }

    private func submit(father: FamilyMember?, eligible: [FamilyMember]) {
        guard let father, !isBusy else { return }
        if addingNew {
            guard !trimmedName.isEmpty else { return }
            onAddUnderFather(trimmedName, father)
        } else if let d = eligible.first(where: { $0.id == selectedId }) {
            onLink(d, father)
        }
    }
}

// MARK: - أجزاء المربّع

/// خيار بحجم بطاقة الإجراء (`DSActionTile`): قرص بلون النوع ورمز أبيض، العنوان وسطر يشرحه، وسهم
private struct WifeFlowOption: View {
    let title: String
    let hint: String
    let icon: String
    let tint: Color
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DSMemberKit.chipRadius, style: .continuous)
        Button {
            guard TapDebouncer.shared.canFire("WifeFlowOption_\(title)") else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(dsSymbol: icon)
                    .dsGlyph(DS.Glyph.md)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .frame(width: DS.Icon.row, height: DS.Icon.row)
                    .background(Circle().fill(tint.dsSolidFill))
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title)
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(hint)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .dsGlyph(DS.Glyph.xl, weight: .regular)
                        .foregroundColor(tint.dsReadableGlyph)
                } else {
                    DSChevron()
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: DSMemberKit.chipHeight)
            .background(shape.fill(LinearGradient(colors: [tint.opacity(DS.Opacity.tintFillStrong),
                                                           tint.opacity(DS.Opacity.tintFillSoft)],
                                                  startPoint: .leading, endPoint: .trailing)))
            .overlay(shape.strokeBorder(tint.opacity(isSelected ? DS.Opacity.selectedStroke : DS.Opacity.tintStroke),
                                        lineWidth: isSelected ? DS.Border.widthBold : DS.Border.width))
            .contentShape(shape)
        }
        .buttonStyle(DSPressStyle())
        // القارئ الصوتي: العنوان والشرح جملة واحدة (القرص والسهم زخرفة)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// صفّ بنت: قرص بلون الأنثى + الاسم الأول + العمر إن عُرف، ودائرة الاختيار
private struct WifeDaughterRow: View {
    let name: String
    let age: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "person.fill", tint: DS.Color.female)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(name)
                        .dsFieldFont(.memberName)
                        .foregroundColor(DS.Color.fieldValue)
                    if let age {
                        Text(L10n.t("\(age) سنة", "\(age) yrs"))
                            .dsFont(.caption)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .dsGlyph(DS.Glyph.xl, weight: .regular)
                    .foregroundColor(isSelected ? DS.Color.female : DS.Color.textTertiary)
            }
            .frame(minHeight: DSBox.fieldMinHeight)
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(age.map { L10n.t("\(name)، \($0) سنة", "\(name), \($0) years") } ?? name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
