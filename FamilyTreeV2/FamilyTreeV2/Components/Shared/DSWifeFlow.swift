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
    /// المتوفّاة تظهر أيضاً بعلامة «متوفاة» (طلب المالك ٢٠٢٦-١١-٠٩ «حتى المتوفية»)
    static func isEligible(_ w: FamilyMember, now: Date = Date()) -> Bool {
        w.isFemale
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
    /// من السيرفر (`father_candidate_min_age`، ٣٥ — المالك ٢٠٢٦-١٠-٢٥ «خل اختيار الأب يكون ٣٥ فوق»)، وإلا ٣٥
    static let fatherMinAgeKey = "father_candidate_min_age"
    static var fatherMinimumAge: Int { AppConfigValues.shared.int(fatherMinAgeKey, default: 35) }
    /// أبو الأم أكبر من صاحب العقدة بهذا على الأقل (جدّه) — ٣٠
    static let motherFatherGap = 30

    /// يصلح أباً؟ المتوفّى يظهر دائماً. الحيّ: لا يظهر إلا إن عُرف ميلاده وكان دون الحد — بلا ميلاد أو مضاف حديثاً
    /// يظهر (المالك ٢٠٢٦-١٠-٢٥ «بس ما يكون مولود»). `childBorn`: ميلاد صاحب العقدة في مسار الأم —
    /// أبو الأم أكبر منه بالحد على الأقل حين يُعرف الميلادان
    static func canBeFather(_ m: FamilyMember, childBorn: Date? = nil, now: Date = Date()) -> Bool {
        if m.isDeceased == true { return true }
        let minAge = fatherMinimumAge
        if let years = age(m, now: now), years < minAge { return false }
        if let childBorn, let born = birthDay(m.birthDate),
           let gap = calendar.dateComponents([.year], from: born, to: childBorn).year, gap < motherFatherGap { return false }
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

    /// رجل فعلاً: الجنس «ذكر» صراحةً ولا زوج له (سجلّ أنثى محفوظ «ذكر» خطأً بزوج — «فاطمة» ٢٠٢٦-١٠-٢٥ — لا يظهر أباً،
    /// طلب المالك «ما يظهرون الإناث لي قائمة الأب»)
    static func isMan(_ m: FamilyMember) -> Bool {
        (m.gender ?? "").lowercased() == "male" && m.husbandId == nil
    }

    /// أعضاء شجرة العائلة (`profiles`) — يكتبها `MemberViewModel.allMembers`. رجال شجرة النساء من خارج العائلة
    /// (أزواج البنات من خارجها وأبناؤهم: «القلاف»، «بوشهري») ليسوا فيها، فلا يظهرون آباءً في «من العائلة»
    /// (طلب المالك ٢٠٢٦-١١-١٢). فارغة قبل التحميل = بلا هذا الشرط
    @MainActor static var familyMemberIds: Set<UUID> = []

    /// قائمتا الآباء محسوبتان مرة لكل (الشخص، العلاقة، عدد السجلات، الحد) — كانت تُحسب لآلاف الرجال مع كل حرف بحث
    @MainActor private static var fathersMemo: [String: [FamilyMember]] = [:]
    @MainActor static func cachedFathers(_ relation: DSWifeFlowBox.Relation, for personId: UUID, in people: [FamilyMember],
                                         showsHidden: Bool) -> [FamilyMember] {
        let family = familyMemberIds
        let key = "\(relation == .mother ? "m" : "w")-\(personId)-\(people.count)-\(showsHidden)-\(fatherMinimumAge)-\(family.count)"
        if let hit = fathersMemo[key] { return hit }
        var list = relation == .mother ? motherFathers(for: personId, in: people, showsHidden: showsHidden)
                                       : fathers(for: personId, in: people, showsHidden: showsHidden)
        if !family.isEmpty { list = list.filter { family.contains($0.id) } }
        if fathersMemo.count > 8 { fathersMemo.removeAll() }
        fathersMemo[key] = list
        return list
    }

    /// قائمة الآباء: رجال الشجرة بنسخهم في شجرة النساء (شرط دالة السيرفر وجدول البنات)، بلا محارم الزوج، بالاسم
    static func fathers(for husbandId: UUID, in people: [FamilyMember], showsHidden: Bool) -> [FamilyMember] {
        let blocked = blockedFathers(for: husbandId, in: people)
        return people
            .filter { m in
                isMan(m) && !blocked.contains(m.id) && canBeFather(m)
                    && (showsHidden || !m.isHiddenFromTree)
                    && !m.fullName.trimmingCharacters(in: .whitespaces).isEmpty
            }
            .sorted { $0.fullName.localizedCompare($1.fullName) == .orderedAscending }
    }

    /// بنات الأب (الأحياء والمتوفّيات — المالك ٢٠٢٦-١١-٠٩): المتاحات بترتيبهنّ، وعدد من أخفتهنّ القواعد (لسطر التوضيح)
    static func daughters(of fatherId: UUID, husbandId: UUID, in people: [FamilyMember], showsHidden: Bool,
                          now: Date = Date()) -> (eligible: [FamilyMember], hidden: Int) {
        let all = people.filter {
            $0.fatherId == fatherId && $0.isFemale && $0.id != husbandId
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
                isMan(m) && m.id != personId && m.id != personFather && canBeFather(m, childBorn: personBorn)
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

    /// طلب «الأب غير موجود» للإدارة: الاسم المكتوب ولمن (طلب المالك ٢٠٢٦-١٠-٢٥ «زر صغير إذا الأب غير موجود… تعديل
    /// عن طريق الإدارة») — الإدارة تضيفه أو تصلح ميلاده ثم تكمل الربط
    static func missingFatherPayload(typed: String, memberId: UUID, memberName: String,
                                     relation: DSWifeFlowBox.Relation) -> TreeEditPayload {
        let what = relation == .mother ? L10n.t("أم", "mother") : L10n.t("زوجة", "wife")
        let lines = [
            L10n.t("الأب غير موجود في قائمة «أبوها» (إضافة ", "Father not in the list (adding a ") + what + ")",
            L10n.t("الاسم المكتوب: ", "Typed name: ") + (typed.isEmpty ? L10n.t("(لم يُكتب)", "(none)") : typed),
            L10n.t("لـ: ", "For: ") + memberName,
            L10n.t("المطلوب: إضافة الأب في الشجرة أو تصحيح بياناته (الميلاد)، ثم ربط ال", "Needed: add the father or fix his birth date, then link the ") + what
        ]
        // «إضافة» بلا اسم ابن (`newMemberName` = nil) مثل طلبات ربط شجرة النساء — السيرفر يقبل «طلب آخر» لتعديلات الملف
        // الثلاثة فقط (`guard_admin_request_insert`)، والقبول هنا يدوي من الإدارة
        return TreeEditPayload.make(action: .add, targetMemberId: memberId.uuidString, targetMemberName: memberName,
                                    parentMemberId: memberId.uuidString, parentMemberName: memberName,
                                    notes: (lines + [L10n.t("التنفيذ يدوي: تضيف الإدارة الأب أو تصلحه ثم تكمل الربط، ثم يُقبل الطلب.",
                                                            "Manual: the admins add or fix the father, link, then approve.")])
                                        .joined(separator: "\n"))
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
    /// «ج» (اختيار المالك ٢٠٢٦-١١-١٢): مربّع واحد — «من العائلة | من خارج العائلة»، بحث الأب وبناته تنفتح تحته،
    /// وسطر «سيُرسل: …» بالاسم كاملاً. «الأب غير موجود؟» خطوة ثانية كما كانت
    private enum Step: Equatable { case pick, missingFather }

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
    /// «الأب غير موجود؟» — طلب للإدارة بالاسم المكتوب (nil = لا زرّ، مثل الإدارة التي تصلح بنفسها)
    var onFatherMissing: ((String) -> Void)? = nil
    let onCancel: () -> Void

    @State private var step: Step
    @State private var search = ""
    /// البحث المؤجَّل قليلاً — الكتابة سلسة مع ٢٥٠٠ رجل
    @State private var settledSearch = ""
    /// الأب المفتوحة بناته تحته
    @State private var openFatherId: UUID? = nil
    /// المضيف سأل «من أين؟» قبل المربّع (حسابي) — بلا شريحتي المصدر
    private let asksSourceBefore: Bool
    @State private var selectedId: UUID? = nil
    @State private var addingNew = false
    @State private var newName = ""
    /// «متوفّاة» للبنت الجديدة تحت أبيها — يظهر فقط حين يمرّر المضيف `addsDeceased` (الإدارة)
    @State private var newDeceased = false
    /// إضافة البنت الجديدة متوفّاةً (طلب المالك ٢٠٢٦-١١-٠٧) — nil = بلا خيار «متوفّاة» كما كان
    private var onAddDeceasedUnderFather: ((_ name: String, _ father: FamilyMember) -> Void)? = nil
    /// القوائم تُعاد حين تصل أرقام السيرفر
    @ObservedObject private var config = AppConfigValues.shared

    init(mode: Mode, relation: Relation = .wife, husbandId: UUID, personFatherId: UUID? = nil,
         husbandName: String, subtitle: String? = nil, people: [FamilyMember],
         isLoading: Bool = false, showsHidden: Bool = false, startsAtFather: Bool = false,
         isBusy: Bool = false, error: String? = nil, onOutside: (() -> Void)? = nil,
         onLink: @escaping (_ daughter: FamilyMember, _ father: FamilyMember) -> Void,
         onAddUnderFather: @escaping (_ name: String, _ father: FamilyMember) -> Void,
         onFatherMissing: ((String) -> Void)? = nil,
         onCancel: @escaping () -> Void) {
        self.onFatherMissing = onFatherMissing
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
        // المضيف الذي سأل «من أين؟» قبل المربّع (حسابي) — بلا شريحتي المصدر
        asksSourceBefore = startsAtFather || onOutside == nil
        _step = State(initialValue: .pick)
    }

    var body: some View {
        Group {
            // كل خطوة مربّع كامل بحدود `AnyView` — لا يتراكم عمق الأنواع فوق التفاصيل (مكدس الآيفون)
            switch step {
            case .pick: AnyView(pickStep)
            case .missingFather: AnyView(missingFatherStep)
            }
        }
        .task(id: search) {
            if !search.isEmpty { try? await Task.sleep(nanoseconds: 150_000_000) }
            guard !Task.isCancelled else { return }
            settledSearch = search
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

    /// يُظهر «متوفّاة» في «أضفها تحت أبيها»، والإضافة بها تمرّ من هنا بدل `onAddUnderFather`
    func addsDeceased(_ handler: @escaping (_ name: String, _ father: FamilyMember) -> Void) -> Self {
        var copy = self
        copy.onAddDeceasedUnderFather = handler
        return copy
    }

    private func go(_ next: Step) {
        selectedId = nil; addingNew = false; newName = ""; newDeceased = false; search = ""; openFatherId = nil
        step = next
    }

    private func shownName(_ m: FamilyMember) -> String { m.fullName.isEmpty ? m.firstName : m.displayFullName }
    private func firstName(_ m: FamilyMember) -> String { m.firstName.isEmpty ? m.fullName : m.firstName }

    // MARK: المربّع الواحد («ج»)

    private var pickStep: some View {
        let father = openFatherId.flatMap { id in people.first { $0.id == id } }
        let list = father.map { daughterList(of: $0.id) } ?? (eligible: [], hidden: 0)
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
            if !asksSourceBefore {
                // «من خارج العائلة» = مربّع الاسم الموجود عند المضيف
                DSSegmentedSwitch(options: [
                    DSSegmentOption(id: 0, title: L10n.t("من العائلة", "From the family"), icon: "tree.fill"),
                    DSSegmentOption(id: 1, title: L10n.t("من خارج العائلة", "From outside"), icon: "person.crop.circle.badge.plus")
                ], selection: Binding(get: { 0 }, set: { v in if v == 1 { onOutside?() } }), size: .regular)
            }
            DSComposerSection(title: L10n.t("أبوها في الشجرة", "Her father in the tree"), icon: "tree.fill",
                              tint: DS.Color.male, index: 0) {
                VStack(spacing: DS.Spacing.sm) {
                    DSComposerField(icon: "magnifyingglass",
                                    label: L10n.t("اسم الأب", "Father's name"),
                                    placeholder: L10n.t("اكتب اسم أبيها", "Type her father's name"),
                                    text: $search)
                    fatherResults
                    if onFatherMissing != nil && !isLoading {
                        Button {
                            let typed = search.trimmingCharacters(in: .whitespaces)
                            go(.missingFather); newName = typed
                        } label: {
                            Text(L10n.t("الأب غير موجود؟", "Father not listed?"))
                                .dsFont(.footnote)
                                .underline()
                                .foregroundColor(DS.Color.textSecondary)
                                .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let father, let line = summaryLine(father: father, eligible: list.eligible) {
                DSNoteCard(line, icon: request ? "paperplane.fill" : "link", tint: DS.Color.female)
            }
            if let error {
                DSNoteCard(error, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
    }

    /// نتائج الأب: لا أسماء قبل الكتابة، وأول ٨ مطابقات — كل أب ينفتح تحته بناته
    @ViewBuilder
    private var fatherResults: some View {
        let query = settledSearch.trimmingCharacters(in: .whitespaces)
        if isLoading {
            DSPageLoader(L10n.t("جارٍ التحميل…", "Loading…"), fillsSpace: false)
        } else if query.isEmpty {
            Text(L10n.t("ابدأ باسمه الأول ثم اسم أبيه — مثل «علي حسين».",
                        "Start with his first name, then his father's — e.g. «Ali Hussain»."))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            let candidates = WifeCandidateRules.cachedFathers(relation, for: husbandId, in: people, showsHidden: showsHidden)
            // من له بنات في الشجرة أولاً (بترتيب المطابقة)، ثم الباقي — أول ٨
            let fathersOfDaughters = Set(people.lazy.filter { $0.isFemale }.compactMap(\.fatherId))
            let all = NameSearch.filter(candidates, query: query, fromFirstName: true) {
                $0.fullName.isEmpty ? $0.firstName : $0.fullName
            }
            let matches = Array((all.filter { fathersOfDaughters.contains($0.id) }
                                 + all.filter { !fathersOfDaughters.contains($0.id) }).prefix(8))
            if matches.isEmpty {
                DSEmptyView(L10n.t("لم يُعثر على اسم مطابق", "No matching name"),
                            icon: "person.fill.questionmark", style: .inline)
            } else {
                ForEach(matches) { f in fatherCard(f) }
            }
        }
    }

    /// الأب: اسمه كاملاً و«بناته المتاحات · N» — الضغط يفتح بناته تحته (واحد مفتوح فقط)
    private func fatherCard(_ f: FamilyMember) -> some View {
        let isOpen = openFatherId == f.id
        let list = daughterList(of: f.id)
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(DS.Anim.snappy) {
                    openFatherId = isOpen ? nil : f.id
                    selectedId = nil; addingNew = false; newName = ""; newDeceased = false
                }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    DSFieldIcon(name: "person.fill", tint: DS.Color.male)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(shownName(f))
                            .dsFieldFont(.memberName)
                            .foregroundColor(DS.Color.fieldValue)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L10n.t("بناته المتاحات · \(list.eligible.count)", "Available daughters · \(list.eligible.count)"))
                            .dsFont(.caption)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .dsGlyph(DS.Glyph.sm, weight: .semibold)
                        .foregroundColor(DS.Color.textTertiary)
                }
                .frame(minHeight: DSBox.fieldMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityAddTraits(isOpen ? [.isButton, .isSelected] : .isButton)
            if isOpen {
                daughtersSection(list, father: f)
                if addingNew { nameSection(f) }
            }
        }
        .dsRowBox()
    }

    /// «سيُرسل: فاطمة علي حسين … زوجةً لجعفر …» — الاسم المختار كاملاً بنسب أبيها
    private func summaryLine(father: FamilyMember, eligible: [FamilyMember]) -> String? {
        let first: String
        if addingNew {
            guard !trimmedName.isEmpty else { return nil }
            first = trimmedName
        } else if let d = eligible.first(where: { $0.id == selectedId }) {
            first = shownName(d)
        } else {
            return nil
        }
        let fatherFull = shownName(father)
        let words = first.split(separator: " ")
        let full = words.count <= fatherFull.split(separator: " ").count ? "\(words.first ?? "") \(fatherFull)" : first
        let lead = mode == .request ? L10n.t("سيُرسل: ", "Will send: ") : L10n.t("سيُربط: ", "Will link: ")
        // «لك» في «حسابي»، وإلا اسم صاحب العقدة (لا سطر العنوان الفرعي)
        let target = mode == .selfFamily ? L10n.t("لك", "for you") : L10n.t("لـ", "of ") + husbandName
        return lead + full + " " + asWord + " " + target
    }

    // MARK: «الأب غير موجود؟» — اسمه الرباعي للإدارة

    /// الاسم الرباعي: أربع كلمات على الأقل (يُعدّ «عبد» مع ما بعده كلمة — نفس قاعدة البحث)
    private var fatherNameIsFull: Bool { NameSearch.words(trimmedName).count >= 4 }

    private var missingFatherStep: some View {
        DSComposer(
            title: L10n.t("الأب غير موجود", "Father not listed"),
            subtitle: forLine,
            icon: "person.fill.questionmark",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("إرسال للإدارة", "Send to the admins"),
            actionIcon: "paperplane.fill",
            cancelTitle: L10n.t("رجوع", "Back"),
            canSubmit: fatherNameIsFull,
            isBusy: isBusy,
            note: L10n.t("تضيف الإدارة الأب في الشجرة أو تصلح بياناته، ثم تكمل الربط.",
                         "The admins add the father or fix his details, then complete the link."),
            hasUnsavedChanges: !trimmedName.isEmpty,
            onSubmit: { if fatherNameIsFull { onFatherMissing?(trimmedName) } },
            onCancel: { go(.pick) }
        ) {
            DSComposerSection(title: L10n.t("اسم الأب", "Father's name"), icon: "person.fill", tint: DS.Color.primary, index: 0) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    DSComposerField(icon: "person.text.rectangle",
                                    label: L10n.t("الاسم الرباعي للأب", "Father's four-part name"),
                                    placeholder: L10n.t("مثل: علي حسين محمد حسن", "e.g. Ali Hussain Mohammad Hasan"),
                                    text: $newName)
                    Text(fatherNameIsFull || trimmedName.isEmpty
                         ? L10n.t("اكتب اسمه الرباعي كاملاً — أربعة أسماء على الأقل.", "Write his full four-part name.")
                         : L10n.t("الاسم ناقص — يلزم أربعة أسماء.", "Incomplete — four names needed."))
                        .dsFont(.footnote)
                        .foregroundColor(fatherNameIsFull || trimmedName.isEmpty ? DS.Color.textTertiary : DS.Color.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: البنات

    /// بنات الأب المتاحات زوجةً (أو أمّاً) ومن لا تظهر — القواعد الواحدة `WifeCandidateRules`
    private func daughterList(of fatherId: UUID) -> (eligible: [FamilyMember], hidden: Int) {
        isMother
            ? WifeCandidateRules.motherDaughters(of: fatherId, personId: husbandId, personFatherId: personFatherId,
                                                 in: people, showsHidden: showsHidden)
            : WifeCandidateRules.daughters(of: fatherId, husbandId: husbandId, in: people, showsHidden: showsHidden)
    }

    /// البنات المتاحات (اختيار واحد)، وسطر يوضّح من لا تظهر، ثم «أضفها تحت أبيها»
    private func daughtersSection(_ list: (eligible: [FamilyMember], hidden: Int), father: FamilyMember?) -> some View {
        DSComposerSection(title: L10n.t("بناته", "His daughters"), icon: "figure.stand.dress", tint: DS.Color.female,
                          trailing: list.eligible.isEmpty ? nil : "\(list.eligible.count)", index: 1) {
            VStack(spacing: DS.Spacing.sm) {
                // «لا بنات متاحات» تختفي حين يختار «إضافة بنت غير موجودة» (طلب المالك ٢٠٢٦-١١-٠٨)
                if list.eligible.isEmpty && !addingNew {
                    DSEmptyView(L10n.t("لا بنات متاحات له في الشجرة", "No available daughters in the tree"),
                                icon: "person.fill.questionmark", style: .inline)
                }
                ForEach(Array(list.eligible.enumerated()), id: \.element.id) { i, d in
                    WifeDaughterRow(name: firstName(d), age: WifeCandidateRules.age(d), deceased: d.isDeceased == true,
                                    isSelected: selectedId == d.id && !addingNew) {
                        withAnimation(DS.Anim.snappy) { selectedId = d.id; addingNew = false; newName = ""; newDeceased = false }
                    }
                    .dsEntrance(delay: DSMotion.staggerDelay(i + 2, base: DSMotion.sectionsAfterHeader),
                                y: DSMotion.rise, scale: DSMotion.riseScale)
                }
                if list.hidden > 0 && !addingNew {
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
                // زرّ إضافة واضح (طلب المالك ٢٠٢٦-١١-٠٨ «شكل واضح ان زر اضافة بنت غير موجودة تحت الاب»)
                WifeFlowOption(title: L10n.t("إضافة بنت غير موجودة", "Add a daughter who isn't listed"),
                               hint: father.map { L10n.t("بنت جديدة تحت أبيها \(firstName($0))", "A new daughter under \(firstName($0))") }
                                   ?? L10n.t("بنت جديدة تحت أبيها", "A new daughter under her father"),
                               icon: "plus", tint: DSMemberKit.addTint, isSelected: addingNew, dashed: !addingNew) {
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
                                label: L10n.t("اسم البنت الأول", "Daughter's first name"),
                                placeholder: L10n.t("اكتب اسمها الأول فقط — يُكمَل باسم أبيها", "Her first name only — her father's name is added"),
                                text: $newName)
                if onAddDeceasedUnderFather != nil {
                    // الحالة — الاختيار الموحّد (طلب المالك ٢٠٢٦-١١-١٠)، وسطر يؤكّد «متوفّاة»
                    DSMenuTile(icon: "leaf.fill", label: L10n.t("الحالة", "Status"), options: [
                        DSChoiceOption(id: false, title: L10n.t("على قيد الحياة", "Alive"), icon: "heart.fill"),
                        DSChoiceOption(id: true, title: L10n.t("متوفّاة", "Deceased"), icon: "leaf.fill")
                    ], selection: $newDeceased.animation(DS.Anim.snappy))
                    if newDeceased {
                        Text(L10n.t("تُضاف متوفّاة — تظهر تحت صورتها «متوفية» في الشجرة", "Added as deceased — marked in the tree"))
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
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
            if newDeceased, let addDeceased = onAddDeceasedUnderFather {
                addDeceased(trimmedName, father)
            } else {
                onAddUnderFather(trimmedName, father)
            }
        } else if let d = eligible.first(where: { $0.id == selectedId }) {
            onLink(d, father)
        }
    }
}

// MARK: - أجزاء المربّع

/// خيار بحجم بطاقة الإجراء (`DSActionTile`): قرص بلون النوع ورمز أبيض، العنوان وسطر يشرحه، وسهم
struct WifeFlowOption: View {
    let title: String
    let hint: String
    let icon: String
    let tint: Color
    var isSelected: Bool = false
    /// إطار متقطّع — زرّ «إضافة» واضح قبل اختياره
    var dashed: Bool = false
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
                                        style: StrokeStyle(lineWidth: isSelected || dashed ? DS.Border.widthBold : DS.Border.width,
                                                           dash: dashed ? [DS.Spacing.xsm, DS.Spacing.xs] : [])))
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
    var deceased: Bool = false
    let isSelected: Bool
    let action: () -> Void

    /// السطر تحت الاسم: «متوفاة» للمتوفّاة (بلا عمر — العمر حتى اليوم لا معنى له)، وإلا العمر إن عُرف
    private var detail: String? {
        if deceased { return L10n.t("متوفاة", "Deceased") }
        return age.map { L10n.t("\($0) سنة", "\($0) yrs") }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "person.fill", tint: DS.Color.female)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(name)
                        .dsFieldFont(.memberName)
                        .foregroundColor(DS.Color.fieldValue)
                    if let detail {
                        Text(detail)
                            .dsFont(.caption)
                            .foregroundColor(deceased ? DS.Color.deceased : DS.Color.textTertiary)
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
        .accessibilityLabel(detail.map { "\(name)، \($0)" } ?? name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
