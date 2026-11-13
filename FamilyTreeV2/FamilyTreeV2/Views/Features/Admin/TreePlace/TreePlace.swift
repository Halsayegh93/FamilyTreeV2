import SwiftUI

// MARK: - «مكانه في الشجرة» قبل التنفيذ (طلب المالك ٢٠٢٦-١١-١٣، الاختيار «ج» — نفسه في الآيفون والأندرويد)
//
// «أبي أي إجراء يصير قبل التنفيذ أشوف مكانه بالواقع بعدين أنفّذ»: كل طلب في «الوارد» (ومربّعا الربط) يخصّ شخصاً في
// الشجرة يعرض مقطعاً صغيراً حقيقياً حول المكان (الجد ← الأب ← الإخوة) والشخص بشكل التغيير، وسطر ملاحظة، وزرّ
// «افتح بالشجرة الكاملة» يفتح الشجرة الحقيقية نفسها على المكان. كله من بيانات محمّلة — لا كتابة ولا دوال جديدة.
// النموذج الواحد `TreePlace` (نفس الاسم في الأندرويد) ← `TreePlaceResolved` (المقطع والملاحظة) ← العرض.

/// أي شجرة: شجرة العائلة (الرجال) أو شجرة النساء (الآباء ملفات رجال، والبنات عقد نساء)
enum TreePlaceTree: Equatable {
    case men
    case women
}

/// التغيير الذي ينفّذه الطلب على الشخص
enum TreePlaceChange: Equatable {
    /// ليس في الشجرة بعد — يُرسم شبحاً بعد آخر أبناء الأب (`TreePlace.addFatherId`)
    case add(name: String, female: Bool)
    /// عقدة موجودة يُربط بها الحساب
    case link(UUID)
    /// أُضيف فعلاً وينتظر التأكيد (إضافة ابن)
    case added(UUID)
    case rename(UUID, newName: String)
    case birth(UUID, newBirth: String)
    case deceased(UUID, deathDate: String?)
    case photo(UUID, newPhotoUrl: String?)
    case delete(UUID)
    /// من تحت أبيه الحالي إلى تحت أب جديد — مقطعان «قبل» ثم «بعد»
    case moveFather(UUID, newFatherId: UUID)
    /// تعريف بالشخص فقط (الرقم، الخصوصية، طلب آخر…) — إطار ذهبي بلا شريحة
    case subject(UUID)
    /// زوجة من خارج العائلة: عقدة الزوج ومربّع شبح جنبه بلا خط
    case outsideWife(husbandId: UUID, name: String)

    /// الشخص المعني (nil = إضافة جديدة)
    var personId: UUID? {
        switch self {
        case .add: return nil
        case .link(let id), .added(let id), .delete(let id), .subject(let id): return id
        case .rename(let id, _), .birth(let id, _), .deceased(let id, _), .photo(let id, _): return id
        case .moveFather(let id, _): return id
        case .outsideWife(let id, _): return id
        }
    }
}

/// الزمن: `future` قبل التنفيذ («الوارد» ومربّعا الربط — §3/§4)، و`past` لما تمّ فعلاً (إشعارات الإدارة،
/// الطلبات المعالَجة المقبولة — §7/§8)
enum TreePlaceTense: Equatable {
    case future
    case past
}

/// مكان الطلب في الشجرة
struct TreePlace: Equatable {
    var tree: TreePlaceTree
    let change: TreePlaceChange
    /// أب الإضافة (`add`) — الباقي يُقرأ أبوه من الشجرة نفسها، فلا يتأخر عن آخر تعديل
    var addFatherId: UUID? = nil
    /// عنوان نوع الطلب — للمعاينة («طلب انضمام · محمد»)
    let kindLabel: String
    /// سطر خاص بدل الملاحظة المعتادة (أمّ من خارج العائلة، ابن بنت العائلة)
    var noteOverride: String? = nil
    /// قبل التنفيذ (الافتراضي) أو تمّ
    var tense: TreePlaceTense = .future
    /// طلب معالَج مرفوض (§8): المكان كما طُلب، والشخص رمادي باهت بإطار متقطّع و«رُفض» — لم يتغيّر شيء
    var rejected: Bool = false
    /// ما تمّ: القيمة قبل التغيير من سجلّه (الاسم/الميلاد/رابط الصورة) — بدونها يُرسم الشخص بحاله الآن
    var pastBefore: String? = nil
    /// ما تمّ من نقل: الأب السابق (الحالي في البيانات = الجديد)
    var oldFatherId: UUID? = nil
    /// المحذوف (العقدة لم تعد موجودة): اسمه المحفوظ وأبوه إن عُرف من السجلّ — `TreePlaceDeletedLookup`
    var goneName: String? = nil
    var goneFatherHint: UUID? = nil
    var goneFemale: Bool = false
    /// «طلب حذف من الشجرة» لزوجة من خارج العائلة: مربّعها بجانب الزوج بالأحمر («تُحذف»/«حُذفت»)
    var removing: Bool = false

    /// النتيجة على طلب معالَج: معلّق ← قبل التنفيذ، مقبول ← تمّ، مرفوض ← «رُفض»
    func outcome(status: String) -> TreePlace {
        var p = self
        switch status {
        case ApprovalStatus.approved.rawValue: p.tense = .past
        case ApprovalStatus.rejected.rawValue: p.rejected = true
        default: break
        }
        return p
    }

    /// لا مقطع: ما تمّ أو رُفض وشخصه لم يعد موجوداً ← «لم يعد في الشجرة.»، وغيره ← لا أب مسجّل
    func unresolvedNote(_ data: TreePlaceData) -> String {
        guard tense == .past || rejected else { return TreePlaceText.noFather }
        if let pid = change.personId, data.node(pid, in: tree) != nil { return TreePlaceText.noFather }
        // حُذف قبل أن يُحفظ مكانه (السجلّ من ٢٠٢٦-١١-١٣)
        if case .delete(let id) = change, data.deletedMissing.contains(id) { return TreePlaceText.goneUnknown }
        return TreePlaceText.gone
    }
}

/// الزرّ الرئيسي للمربّع نفسه — يتكرّر في المعاينة («ربط بالشجرة»، «موافقة»، «تنفيذ»…) ويشغّل نفس المعالج
struct TreePlacePrimary {
    let title: String
    var icon: String = "checkmark"
    let action: () -> Void
}

// MARK: - شكل العلامة (المقطع والشجرة الكاملة)

/// شكل الشخص بحسب التغيير — ذهبي للرجال، وردي للنساء، أحمر للحذف، رمادي للوفاة
struct TreePlaceMarkStyle: Equatable {
    enum Kind: Equatable {
        /// إطار متقطّع + تعبئة خفيفة (يُضاف، أُضيف، يُنقل)
        case ghost
        /// إطار صلب + هالة (يُربط)
        case halo
        /// إطار صلب فقط (تعريف، بعد التعديل)
        case ring
        /// رمادي (متوفى)
        case grey
        /// متقطّع أحمر (يُحذف)
        case danger
        /// طلب مرفوض: رمادي باهت بإطار متقطّع رمادي و«رُفض» (بلا ذهبي)
        case rejected
    }
    let kind: Kind
    let pill: String?
    let female: Bool

    /// لون الإطار والخط
    var tint: Color {
        switch kind {
        case .danger: return DS.Color.error
        case .rejected: return DS.Color.textTertiary
        case .grey: return DS.Color.deceased
        default: return female ? DS.Color.female : DS.Color.accentLight
        }
    }
    /// لون النص في عقدة الشبح
    var ink: Color {
        switch kind {
        case .danger: return DS.Color.error
        case .grey, .rejected: return DS.Color.textTertiary
        default: return female ? DS.Color.female : DS.Color.accent
        }
    }
    /// تعبئة الشريحة تحت النص الأبيض
    var pillFill: Color {
        switch kind {
        case .danger: return DS.Color.errorFill
        case .grey, .rejected: return DS.Color.deceasedFill
        default: return female ? DS.Color.femaleFill : DS.Color.goldFill
        }
    }
    var dashed: Bool { kind == .ghost || kind == .danger || kind == .rejected }
    /// الشخص نفسه باهت (المرفوض)
    var fadesPerson: Bool { kind == .rejected }
    var fillOpacity: Double {
        switch kind {
        case .ghost: return DS.Opacity.tintFillSoft
        case .danger: return 0.06
        case .grey: return DS.Opacity.tintFill
        default: return 0
        }
    }
}

// MARK: - البيانات (محمّلة مسبقاً — لا جلب ولا كتابة)

struct TreePlaceData {
    /// أعضاء شجرة العائلة (`memberVM.allMembers`)
    let men: [FamilyMember]
    /// شجرة النساء (`WomenStore.cache`) — الرجال فيها بنفس معرّفات ملفاتهم
    let women: [FamilyMember]
    /// أماكن المحذوفين من السجلّ (`TreePlaceDeletedLookup`) — يملؤها القسم بعد السؤال
    var deleted: [UUID: MemberDeletePlace] = [:]
    /// سُئل عنهم ولا سجلّ لهم
    var deletedMissing: Set<UUID> = []

    func man(_ id: UUID?) -> FamilyMember? {
        guard let id else { return nil }
        return men.first { $0.id == id }
    }

    func woman(_ id: UUID?) -> FamilyMember? {
        guard let id else { return nil }
        return women.first { $0.id == id }
    }

    /// العقدة في الشجرة المعنية — النساء: عقدتها أولاً ثم ملف الرجل
    func node(_ id: UUID?, in tree: TreePlaceTree) -> FamilyMember? {
        tree == .women ? (woman(id) ?? man(id)) : man(id)
    }

    /// الأب (رجل دائماً): ملفه في شجرة العائلة، وإلا مرآته في شجرة النساء
    func father(_ id: UUID?) -> FamilyMember? { man(id) ?? woman(id) }

    /// الإخوة بترتيب الشجرة نفسها: العائلة = من يُعرض فيها (`isCountable`) بترتيب العرض، والنساء = البنات بترتيبهن
    func children(of fatherId: UUID, in tree: TreePlaceTree) -> [FamilyMember] {
        switch tree {
        case .men:
            return men.filter { $0.fatherId == fatherId && $0.isCountable }.sortedForDisplay()
        case .women:
            return women.filter { $0.fatherId == fatherId && $0.isFemale && !$0.isHiddenFromTree }
                .sorted {
                    $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder
                        : $0.firstName.localizedCompare($1.firstName) == .orderedAscending
                }
        }
    }

    /// عدد الأبناء والبنات المرتبطين (الشجرتان، بلا تكرار المرايا)
    func childCount(of id: UUID) -> Int {
        let a = men.lazy.filter { $0.fatherId == id }.map(\.id)
        let b = women.lazy.filter { $0.fatherId == id }.map(\.id)
        return Set(a).union(b).count
    }
}

// MARK: - المقطع المحلول

/// كل ما يرسمه المقطع والمعاينة: الجد والأب والإخوة والشخص (قبل/بعد) والملاحظة والعلامة
struct TreePlaceResolved {
    enum Shape { case tree, beforeAfter, moveFather, outsideWife, rootOnly }

    let place: TreePlace
    let shape: Shape
    let female: Bool
    /// الشخص كما هو الآن (أو الشبح)
    let person: FamilyMember
    /// الشخص بعد التنفيذ (اسم/ميلاد/صورة/وفاة/نقل)
    let after: FamilyMember?
    let father: FamilyMember?
    let grandfather: FamilyMember?
    /// الإخوة بترتيب الشجرة، والشخص بينهم (الشبح آخرهم)
    let siblings: [FamilyMember]
    /// النقل: الأب الحالي وإخوته الحاليون
    let oldFather: FamilyMember?
    let oldGrandfather: FamilyMember?
    let oldSiblings: [FamilyMember]
    let note: String
    let noteIsDanger: Bool
    /// علامة الشخص في المقطع (قبل/بعد له شكله الخاص)
    let mark: TreePlaceMarkStyle
    /// علامته في الشجرة الكاملة (قبل ← بعد: «بعد التعديل»)
    let previewMark: TreePlaceMarkStyle
    /// اسم الزوجة من خارج العائلة (مربّع الشبح)
    let wifeName: String?

    /// معرّف الشبح في الرسم (لا وجود له في البيانات)
    static let ghostId = UUID(uuidString: "7E1A0000-0000-4000-8000-00000000A0D1")!

    var personFirstName: String { TreePlaceText.firstName(after ?? person) }
}

// MARK: - النصوص (العربية الرسمية — كما في المواصفة حرفياً)

enum TreePlaceText {
    static let sectionTitle = L10n.t("مكانه في الشجرة", "Place in the tree")
    static let openFull = L10n.t("افتح بالشجرة الكاملة", "Open in the full tree")
    static let noFather = L10n.t("لا يمكن تحديد مكانه في الشجرة — لا يوجد أب مسجّل.",
                                 "Can't place it in the tree — no father on record.")
    static let noMatch = L10n.t("لا يوجد اسم مطابق في الشجرة", "No matching name in the tree")
    static let gone = L10n.t("لم يعد في الشجرة.", "No longer in the tree.")
    static let goneUnknown = L10n.t("حُذف قبل حفظ الأماكن — لا يُعرف مكانه.", "Deleted before places were kept — its place is unknown.")
    static let rejectedNote = L10n.t("رُفض الطلب — لم يتغيّر شيء في الشجرة", "The request was rejected — nothing changed in the tree")
    static let rejectedPill = L10n.t("رُفض", "Rejected")
    static let backToNotice = L10n.t("العودة إلى الإشعار", "Back to the notification")
    static let pastBanner = L10n.t("هذا مكانه في الشجرة بعد التغيير", "This is its place in the tree after the change")
    static let previewTitle = L10n.t("معاينة في الشجرة", "Preview in the tree")
    static let previewBanner = L10n.t("هذا مكانه بعد التنفيذ — لا تتغيّر الشجرة قبل موافقتك",
                                      "This is its place after you carry it out — the tree doesn't change before you approve")
    static let previewHint = L10n.t("يمكنك التكبير والتنقّل في الشجرة", "You can zoom and move around the tree")
    static let backToRequest = L10n.t("العودة إلى الطلب", "Back to the request")
    static let afterEdit = L10n.t("بعد التعديل", "After the change")
    static let before = L10n.t("قبل", "Before")
    static let after = L10n.t("بعد", "After")
    static let grandfather = L10n.t("الجد", "Grandfather")
    static let father = L10n.t("الأب", "Father")
    static let herFather = L10n.t("أبوها", "Her father")
    static let outsideWifePill = L10n.t("زوجة من خارج العائلة", "Wife from outside the family")

    /// شريحة الزوجة المحذوفة: «تُحذف» قبل التنفيذ، «حُذفت» بعده
    static func wifeRemovalPill(_ place: TreePlace) -> String {
        place.tense == .past ? L10n.t("حُذفت", "Removed") : L10n.t("تُحذف", "Deleted")
    }

    static func firstName(_ m: FamilyMember) -> String {
        let first = m.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty { return first }
        let full = m.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? L10n.t("بدون اسم", "No name") : PersonName.firstUnit(full)
    }

    /// «X» = الاسم الأول + اسم أبيه («أحمد خالد»)
    static func pair(_ m: FamilyMember?, fatherOf: (UUID?) -> FamilyMember?) -> String {
        guard let m else { return "" }
        let own = firstName(m)
        guard let f = fatherOf(m.fatherId) else { return own }
        return own + " " + firstName(f)
    }

    private static let ordinalsM = ["الأول", "الثاني", "الثالث", "الرابع", "الخامس", "السادس", "السابع", "الثامن", "التاسع", "العاشر"]
    private static let ordinalsF = ["الأولى", "الثانية", "الثالثة", "الرابعة", "الخامسة", "السادسة", "السابعة", "الثامنة", "التاسعة", "العاشرة"]
    private static let ordinalsEn = ["1st", "2nd", "3rd"]

    /// الترتيب بين الإخوة: الأول … العاشر، ثم «رقم 11»
    static func ordinal(_ n: Int, female: Bool) -> String {
        let list = female ? ordinalsF : ordinalsM
        let ar = (1...list.count).contains(n) ? list[n - 1] : "رقم \(n)"
        let en = n <= 3 && n >= 1 ? ordinalsEn[n - 1] : "\(n)th"
        return L10n.t(ar, en)
    }

    /// السنة من تاريخ (أول أربعة أرقام) — nil إن لم تكن سنة
    static func year(_ date: String?) -> String? {
        guard let d = date?.trimmingCharacters(in: .whitespacesAndNewlines), d.count >= 4 else { return nil }
        let y = String(d.prefix(4))
        return y.allSatisfy(\.isNumber) ? y : nil
    }

    static func deceasedPill(female: Bool, date: String?) -> String {
        let word = female ? L10n.t("متوفاة", "Deceased") : L10n.t("متوفى", "Deceased")
        return year(date).map { word + " " + $0 } ?? word
    }

    /// أول ما يختلف بين اسمين كاملين (كلمتان على الأكثر من كل طرف) — nil = متطابقان
    static func nameDiff(_ old: String, _ new: String) -> (old: String, new: String)? {
        let a = old.split(whereSeparator: \.isWhitespace).map(String.init)
        let b = new.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let i = (0..<max(a.count, b.count)).first(where: { $0 >= a.count || $0 >= b.count || a[$0] != b[$0] })
        else { return nil }
        let o = a.count > i ? a[i..<min(a.count, i + 2)].joined(separator: " ") : "—"
        let n = b.count > i ? b[i..<min(b.count, i + 2)].joined(separator: " ") : "—"
        return (o, n)
    }

    static func birthCaption(_ date: String?) -> String? {
        year(date).map { L10n.t("مواليد ", "Born ") + $0 }
    }
}

// MARK: - الحلّ: من الطلب إلى المقطع

extension TreePlace {
    /// يحلّ المكان من البيانات المحمّلة — nil = لا مقطع (`unresolvedNote`: لا أب مسجّل، أو «لم يعد في الشجرة.»)
    func resolve(_ data: TreePlaceData) -> TreePlaceResolved? {
        if rejected { return resolveRejected(data) }
        if tense == .past { return resolvePast(data) }
        return resolveFuture(data)
    }

    /// شبح للرسم فقط (لا وجود له في البيانات): يُضاف/أُضيف بلا عقدة، أو المحذوف
    fileprivate func ghost(_ name: String, female: Bool, fatherId: UUID?, first givenFirst: String? = nil,
                           sortOrder: Int = Int.max) -> FamilyMember {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = givenFirst.flatMap { $0.isEmpty ? nil : $0 } ?? PersonName.firstUnit(trimmed)
        return FamilyMember(id: TreePlaceResolved.ghostId, firstName: first.isEmpty ? trimmed : first, fullName: trimmed,
                            fatherId: fatherId, sortOrder: sortOrder, status: .active, gender: female ? "female" : "male")
    }

    /// الأب والجد و«X» وسطر «ابن «X»» والإخوة — مشترك بين الأزمنة
    fileprivate struct Frame {
        let father: FamilyMember?
        let grandfather: FamilyMember?
        let X: String
        let lineOf: String
        let fatherOf: (UUID?) -> FamilyMember?
        let siblingsWith: (FamilyMember, UUID?) -> [FamilyMember]
    }

    fileprivate func frame(female: Bool, fatherId: UUID?, data: TreePlaceData) -> Frame {
        let fatherOf: (UUID?) -> FamilyMember? = { data.man($0) ?? data.woman($0) }
        let father = fatherId.flatMap { data.father($0) }
        let X = TreePlaceText.pair(father, fatherOf: fatherOf)
        let son = female ? L10n.t("بنت", "Daughter of") : L10n.t("ابن", "Son of")
        let tree = self.tree
        return Frame(father: father, grandfather: father.flatMap { fatherOf($0.fatherId) }, X: X,
                     lineOf: X.isEmpty ? L10n.t("في رأس الشجرة", "At the top of the tree") : "\(son) «\(X)»",
                     fatherOf: fatherOf,
                     siblingsWith: { p, f in
                         guard let f else { return [p] }
                         var list = data.children(of: f, in: tree)
                         if let i = list.firstIndex(where: { $0.id == p.id }) { list[i] = p } else { list.append(p) }
                         // المحذوف من السجلّ: في مكانه بين إخوته الحاليين بترتيبه وقت الحذف
                         if p.id == TreePlaceResolved.ghostId && p.sortOrder != Int.max {
                             list = tree == .men ? list.sortedForDisplay() : list.sorted { $0.sortOrder < $1.sortOrder }
                         }
                         return list
                     })
    }

    // MARK: مرفوض (§8): المكان كما طُلب، والشخص رمادي باهت و«رُفض»

    private func resolveRejected(_ data: TreePlaceData) -> TreePlaceResolved? {
        let person: FamilyMember
        switch change {
        case .add(let name, let isFemale):
            person = ghost(name, female: isFemale, fatherId: addFatherId)
        default:
            guard let pid = change.personId, let node = data.node(pid, in: tree) else { return nil }
            person = node
        }
        let female = person.isFemale
        let f = frame(female: female, fatherId: person.fatherId, data: data)
        let mark = TreePlaceMarkStyle(kind: .rejected, pill: TreePlaceText.rejectedPill, female: female)
        if f.father == nil && person.id == TreePlaceResolved.ghostId { return nil }
        return TreePlaceResolved(place: self, shape: f.father == nil ? .rootOnly : .tree, female: female, person: person,
                                 after: nil, father: f.father, grandfather: f.grandfather,
                                 siblings: f.siblingsWith(person, person.fatherId),
                                 oldFather: nil, oldGrandfather: nil, oldSiblings: [],
                                 note: TreePlaceText.rejectedNote, noteIsDanger: false,
                                 mark: mark, previewMark: mark, wifeName: nil)
    }

    // MARK: ما تمّ (§7/§8): بصيغة الماضي

    private func resolvePast(_ data: TreePlaceData) -> TreePlaceResolved? {
        var person: FamilyMember
        switch change {
        case .add(let name, let isFemale):
            // أُضيف فعلاً: عقدته تحت أبيه بالاسم نفسه (الأحدث)، وإلا شبح
            guard let fid = addFatherId else { return nil }
            let first = PersonName.firstUnit(name.trimmingCharacters(in: .whitespacesAndNewlines))
            person = data.children(of: fid, in: tree).last { TreePlaceText.firstName($0) == first }
                ?? ghost(name, female: isFemale, fatherId: fid)
        case .delete(let id):
            // العقدة لم تعد موجودة: شبح أحمر من سجلّ الأماكن (`TreePlaceDeletedLookup`) تحت أبيه بترتيبه — أو بجانب
            // زوجها (زوجة من خارج العائلة). بلا سجلّ (حُذف قبله) ← لا مقطع؛ وتعذّر السؤال ← الاسم والأب في الإشعار/الطلب
            if let node = data.node(id, in: tree) {
                person = node
            } else if let row = data.deleted[id] {
                if let fid = row.parentId, data.father(fid) != nil {
                    person = ghost(row.displayFullName, female: row.isFemale, fatherId: fid,
                                   first: row.displayFirstName, sortOrder: row.sortIndex)
                } else if let hid = row.husbandId, let husband = data.father(hid) {
                    return goneWife(row, husband: husband, data: data)
                } else {
                    return nil
                }
            } else if data.deletedMissing.contains(id) {
                return nil
            } else {
                guard let fid = goneFatherHint, data.father(fid) != nil,
                      !(goneName ?? "").trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                person = ghost(goneName ?? "", female: goneFemale, fatherId: fid)
            }
        default:
            guard let pid = change.personId, let node = data.node(pid, in: tree) else { return nil }
            person = node
        }
        let female = person.isFemale
        let f = frame(female: female, fatherId: person.fatherId, data: data)
        func mark(_ kind: TreePlaceMarkStyle.Kind, _ pill: String?) -> TreePlaceMarkStyle {
            TreePlaceMarkStyle(kind: kind, pill: pill, female: female)
        }
        if f.father == nil {
            guard case .subject = change, data.childCount(of: person.id) > 0 else { return nil }
            return TreePlaceResolved(place: self, shape: .rootOnly, female: female, person: person, after: nil,
                                     father: nil, grandfather: nil, siblings: [person],
                                     oldFather: nil, oldGrandfather: nil, oldSiblings: [],
                                     note: noteOverride ?? f.lineOf, noteIsDanger: false,
                                     mark: mark(.ring, nil), previewMark: mark(.ring, nil), wifeName: nil)
        }
        let siblings = f.siblingsWith(person, person.fatherId)
        let order = (siblings.firstIndex { $0.id == person.id } ?? siblings.count - 1) + 1
        let ord = TreePlaceText.ordinal(order, female: female)
        let X = f.X, lineOf = f.lineOf

        func make(shape: TreePlaceResolved.Shape = .tree, before: FamilyMember? = nil, after: FamilyMember? = nil,
                  sibs: [FamilyMember]? = nil, note: String, danger: Bool = false, mark m: TreePlaceMarkStyle,
                  preview: TreePlaceMarkStyle? = nil, oldFather: FamilyMember? = nil, oldSibs: [FamilyMember] = [],
                  wife: String? = nil) -> TreePlaceResolved {
            TreePlaceResolved(place: self, shape: shape, female: female, person: before ?? person, after: after,
                              father: f.father, grandfather: f.grandfather, siblings: sibs ?? siblings,
                              oldFather: oldFather, oldGrandfather: oldFather.flatMap { f.fatherOf($0.fatherId) },
                              oldSiblings: oldSibs, note: noteOverride ?? note, noteIsDanger: danger,
                              mark: m, previewMark: preview ?? m, wifeName: wife)
        }
        /// قبل ← بعد من السجلّ (`pastBefore`)، وبدونه الشخص بحاله الآن بإطار «بعد التعديل»
        func edited(after: FamilyMember, before: FamilyMember?, note: String) -> TreePlaceResolved {
            let afterPill = mark(.ring, TreePlaceText.afterEdit)
            guard let before else {
                return make(after: after, sibs: f.siblingsWith(after, person.fatherId), note: note, mark: afterPill)
            }
            return make(shape: .beforeAfter, before: before, after: after, note: note, mark: mark(.ring, nil), preview: afterPill)
        }
        let old = pastBefore?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasOld = !(old ?? "").isEmpty

        switch change {
        case .add, .added:
            let note = female
                ? L10n.t("أُضيفت بنتاً لـ «\(X)» — \(ord) بين أخواتها", "Added as a daughter of «\(X)» — \(ord) among her sisters")
                : L10n.t("أُضيف ابناً لـ «\(X)» — \(ord) بين إخوانه", "Added as a son of «\(X)» — \(ord) among his brothers")
            return make(note: note, mark: mark(.ghost, female ? L10n.t("أُضيفت", "Added") : L10n.t("أُضيف", "Added")))

        case .link:
            let note = tree == .women
                ? L10n.t("الاسم في شجرة النساء — رُبط حسابها به", "The name in the women's tree — her account was linked to it")
                : (female ? L10n.t("الاسم في الشجرة — رُبط حسابها به", "The name in the tree — her account was linked to it")
                          : L10n.t("الاسم في الشجرة — رُبط حسابه به", "The name in the tree — his account was linked to it"))
            return make(note: note, mark: mark(.halo, female ? L10n.t("رُبطت بحسابها", "Linked") : L10n.t("رُبط بحسابه", "Linked")))

        case .rename(_, let newName):
            let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            let after = n.isEmpty ? person
                : TreePlaceCopy.with(person, firstName: PersonName.firstUnit(n), fullName: n.contains(" ") ? n : person.fullName)
            let before = hasOld ? TreePlaceCopy.with(person, firstName: PersonName.firstUnit(old!),
                                                     fullName: old!.contains(" ") ? old! : person.fullName) : nil
            return edited(after: after, before: before,
                          note: L10n.t("\(lineOf) · تغيّر الاسم", "\(lineOf) · the name changed"))

        case .birth(_, let newBirth):
            let after = newBirth.isEmpty ? person : TreePlaceCopy.with(person, birthDate: newBirth)
            let before = hasOld ? TreePlaceCopy.with(person, birthDate: old!) : nil
            return edited(after: after, before: before,
                          note: L10n.t("\(lineOf) · تغيّر تاريخ الميلاد", "\(lineOf) · the birth date changed"))

        case .photo(_, let url):
            let after = url.map { TreePlaceCopy.with(person, avatarUrl: $0) } ?? person
            let before = hasOld ? TreePlaceCopy.with(person, avatarUrl: old!) : nil
            return edited(after: after, before: before,
                          note: L10n.t("\(lineOf) · تغيّرت الصورة", "\(lineOf) · the photo changed"))

        case .deceased(_, let date):
            let after = TreePlaceCopy.with(person, isDeceased: true, deathDate: date ?? person.deathDate)
            return make(after: after, sibs: f.siblingsWith(after, person.fatherId),
                        note: L10n.t("\(lineOf) · سُجّلت الوفاة", "\(lineOf) · the death was recorded"),
                        mark: mark(.grey, TreePlaceText.deceasedPill(female: female, date: date ?? person.deathDate)))

        case .delete(let id):
            // اسم الأب كما حفظه السجلّ وقت الحذف، وإلا من الشجرة
            let P = data.deleted[id]?.parentName.flatMap { $0.isEmpty ? nil : $0 } ?? X
            let note = female
                ? L10n.t("حُذفت من الشجرة — كانت بنت «\(P)»", "Removed from the tree — she was the daughter of «\(P)»")
                : L10n.t("حُذف من الشجرة — كان ابن «\(P)»", "Removed from the tree — he was the son of «\(P)»")
            return make(note: note, danger: true,
                        mark: mark(.danger, female ? L10n.t("حُذفت", "Removed") : L10n.t("حُذف", "Removed")))

        case .moveFather:
            // البيانات الآن: تحت الأب الجديد. الأب السابق من السجلّ (`oldFatherId`) — بدونه «نُقل إلى تحت «B»»
            let pill = female ? L10n.t("نُقلت", "Moved") : L10n.t("نُقل", "Moved")
            if let oid = oldFatherId, oid != person.fatherId, let oldFather = data.father(oid) {
                let A = TreePlaceText.pair(oldFather, fatherOf: f.fatherOf)
                let note = female
                    ? L10n.t("نُقلت من تحت «\(A)» إلى تحت «\(X)»", "Moved from under «\(A)» to under «\(X)»")
                    : L10n.t("نُقل من تحت «\(A)» إلى تحت «\(X)»", "Moved from under «\(A)» to under «\(X)»")
                return make(shape: .moveFather, note: note, mark: mark(.ghost, pill),
                            oldFather: oldFather, oldSibs: f.siblingsWith(person, oid))
            }
            let note = female ? L10n.t("نُقلت إلى تحت «\(X)»", "Moved to under «\(X)»")
                              : L10n.t("نُقل إلى تحت «\(X)»", "Moved to under «\(X)»")
            return make(note: note, mark: mark(.ghost, pill))

        case .subject:
            return make(note: lineOf, mark: mark(.ring, nil))

        case .outsideWife(_, let name):
            let H = TreePlaceText.pair(person, fatherOf: f.fatherOf)
            if removing {
                return make(shape: .outsideWife, sibs: [person],
                            note: L10n.t("حُذفت من الشجرة — كانت زوجة «\(H)»", "Removed from the tree — she was the wife of «\(H)»"),
                            danger: true, mark: mark(.ring, nil), wife: name)
            }
            return make(shape: .outsideWife, sibs: [person],
                        note: L10n.t("زوجة «\(H)» من خارج العائلة", "Wife of «\(H)» from outside the family"),
                        mark: mark(.ring, nil), wife: name)
        }
    }

    /// زوجة من خارج العائلة حُذفت: الزوج ومربّعها الأحمر بجانبه (شجرة العائلة — خانتها المحجوزة)
    private func goneWife(_ row: MemberDeletePlace, husband: FamilyMember, data: TreePlaceData) -> TreePlaceResolved {
        var p = self
        p.tree = .men
        p.removing = true
        let fatherOf: (UUID?) -> FamilyMember? = { data.man($0) ?? data.woman($0) }
        let father = fatherOf(husband.fatherId)
        let H = TreePlaceText.pair(husband, fatherOf: fatherOf)
        let mark = TreePlaceMarkStyle(kind: .ring, pill: nil, female: false)
        return TreePlaceResolved(place: p, shape: .outsideWife, female: true, person: husband, after: nil,
                                 father: father, grandfather: father.flatMap { fatherOf($0.fatherId) }, siblings: [husband],
                                 oldFather: nil, oldGrandfather: nil, oldSiblings: [],
                                 note: L10n.t("حُذفت من الشجرة — كانت زوجة «\(H)»", "Removed from the tree — she was the wife of «\(H)»"),
                                 noteIsDanger: true, mark: mark, previewMark: mark, wifeName: row.displayFirstName)
    }

    // MARK: قبل التنفيذ (§3/§4 — المرحلة الأولى كما هي)

    private func resolveFuture(_ data: TreePlaceData) -> TreePlaceResolved? {
        let fatherOf: (UUID?) -> FamilyMember? = { data.man($0) ?? data.woman($0) }
        let fatherWord: (Bool) -> String = { female in female ? L10n.t("بنت", "Daughter of") : L10n.t("ابن", "Son of") }

        // الشخص قبل التنفيذ (أو الشبح) وأبوه
        var person: FamilyMember
        var female: Bool
        var fatherId: UUID?
        switch change {
        case .add(let name, let isFemale):
            let first = PersonName.firstUnit(name.trimmingCharacters(in: .whitespacesAndNewlines))
            female = isFemale
            fatherId = addFatherId
            person = FamilyMember(id: TreePlaceResolved.ghostId, firstName: first.isEmpty ? name : first, fullName: name,
                                  fatherId: addFatherId, sortOrder: Int.max, status: .active,
                                  gender: isFemale ? "female" : "male")
        default:
            guard let pid = change.personId, let node = data.node(pid, in: tree) else { return nil }
            person = node
            female = node.isFemale
            fatherId = node.fatherId
        }

        let father = fatherId.flatMap { data.father($0) }
        let grandfather = father.flatMap { fatherOf($0.fatherId) }
        let X = TreePlaceText.pair(father, fatherOf: fatherOf)
        let son = fatherWord(female)
        let lineOf = X.isEmpty ? L10n.t("في رأس الشجرة", "At the top of the tree") : "\(son) «\(X)»"

        // الإخوة بترتيب الشجرة والشخص بينهم (الشبح آخرهم)
        func siblingsWith(_ p: FamilyMember, under f: UUID?) -> [FamilyMember] {
            guard let f else { return [p] }
            var list = data.children(of: f, in: tree)
            if let i = list.firstIndex(where: { $0.id == p.id }) {
                list[i] = p
            } else {
                list.append(p)
            }
            return list
        }

        func mark(_ kind: TreePlaceMarkStyle.Kind, _ pill: String?) -> TreePlaceMarkStyle {
            TreePlaceMarkStyle(kind: kind, pill: pill, female: female)
        }

        // بلا أب: الرأس نفسه يُعرض (تعريف) وما سواه لا يُحدَّد
        if father == nil {
            guard case .subject = change, data.childCount(of: person.id) > 0 else { return nil }
            return TreePlaceResolved(place: self, shape: .rootOnly, female: female, person: person, after: nil,
                                     father: nil, grandfather: nil, siblings: [person],
                                     oldFather: nil, oldGrandfather: nil, oldSiblings: [],
                                     note: noteOverride ?? lineOf, noteIsDanger: false,
                                     mark: mark(.ring, nil), previewMark: mark(.ring, nil), wifeName: nil)
        }

        let siblings = siblingsWith(person, under: fatherId)
        let order = (siblings.firstIndex { $0.id == person.id } ?? siblings.count - 1) + 1
        let ord = TreePlaceText.ordinal(order, female: female)

        func make(shape: TreePlaceResolved.Shape = .tree, after: FamilyMember? = nil, sibs: [FamilyMember]? = nil,
                  note: String, danger: Bool = false, mark m: TreePlaceMarkStyle,
                  preview: TreePlaceMarkStyle? = nil, oldFather: FamilyMember? = nil, oldSibs: [FamilyMember] = [],
                  wife: String? = nil, father f: FamilyMember? = nil, grandfather g: FamilyMember? = nil) -> TreePlaceResolved {
            TreePlaceResolved(place: self, shape: shape, female: female, person: person, after: after,
                              father: f ?? father, grandfather: g ?? grandfather, siblings: sibs ?? siblings,
                              oldFather: oldFather, oldGrandfather: oldFather.flatMap { fatherOf($0.fatherId) },
                              oldSiblings: oldSibs, note: noteOverride ?? note, noteIsDanger: danger,
                              mark: m, previewMark: preview ?? m, wifeName: wife)
        }

        let afterPill = mark(.ring, TreePlaceText.afterEdit)
        switch change {
        case .add:
            let note = female
                ? L10n.t("تُضاف بنتاً لـ «\(X)» — \(ord) بين أخواتها", "Added as a daughter of «\(X)» — \(ord) among her sisters")
                : L10n.t("يُضاف ابناً لـ «\(X)» — \(ord) بين إخوانه", "Added as a son of «\(X)» — \(ord) among his brothers")
            return make(note: note, mark: mark(.ghost, female ? L10n.t("تُضاف", "Added") : L10n.t("يُضاف", "Added")))

        case .link:
            let note = tree == .women
                ? L10n.t("الاسم موجود في شجرة النساء — يُربط حسابها به ولا يُضاف اسم جديد",
                         "The name is in the women's tree — her account is linked to it; no new name is added")
                : L10n.t("الاسم موجود في الشجرة — يُربط حسابه به ولا يُضاف اسم جديد",
                         "The name is in the tree — the account is linked to it; no new name is added")
            return make(note: note, mark: mark(.halo, female ? L10n.t("تُربط بحسابها", "Linked") : L10n.t("يُربط بحسابه", "Linked")))

        case .added:
            let note = female
                ? L10n.t("أُضيفت بنتاً لـ «\(X)» — \(ord) بين أخواتها", "Added as a daughter of «\(X)» — \(ord) among her sisters")
                : L10n.t("أُضيف ابناً لـ «\(X)» — \(ord) بين إخوانه", "Added as a son of «\(X)» — \(ord) among his brothers")
            return make(note: note, mark: mark(.ghost, female ? L10n.t("أُضيفت", "Added") : L10n.t("أُضيف", "Added")))

        case .rename(_, let newName):
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            let after = TreePlaceCopy.with(person, firstName: PersonName.firstUnit(trimmed), fullName: trimmed)
            let n = data.childCount(of: person.id)
            var note = female
                ? L10n.t("\(lineOf) · يتحدّث اسمها الكامل", "\(lineOf) · her full name is updated")
                : L10n.t("\(lineOf) · يتحدّث اسمه الكامل", "\(lineOf) · his full name is updated")
            if n > 0 {
                note += female ? L10n.t(" واسم أبنائها (\(n))", " and her children's (\(n))")
                               : L10n.t(" واسم أبنائه (\(n))", " and his children's (\(n))")
            }
            return make(shape: .beforeAfter, after: after, note: note, mark: mark(.ring, nil), preview: afterPill)

        case .birth(_, let newBirth):
            let after = TreePlaceCopy.with(person, birthDate: newBirth)
            return make(shape: .beforeAfter, after: after,
                        note: L10n.t("\(lineOf) · يتغيّر تاريخ الميلاد فقط", "\(lineOf) · only the birth date changes"),
                        mark: mark(.ring, nil), preview: afterPill)

        case .photo(_, let url):
            let after = TreePlaceCopy.with(person, avatarUrl: url)
            let note = female
                ? L10n.t("\(lineOf) · تتغيّر صورتها في الشجرة", "\(lineOf) · her photo in the tree changes")
                : L10n.t("\(lineOf) · تتغيّر صورته في الشجرة", "\(lineOf) · his photo in the tree changes")
            return make(shape: .beforeAfter, after: after, note: note, mark: mark(.ring, nil), preview: afterPill)

        case .deceased(_, let date):
            let after = TreePlaceCopy.with(person, isDeceased: true, deathDate: date ?? person.deathDate)
            let note = female
                ? L10n.t("\(lineOf) · تظهر في الشجرة متوفاة", "\(lineOf) · shown in the tree as deceased")
                : L10n.t("\(lineOf) · يظهر في الشجرة متوفى", "\(lineOf) · shown in the tree as deceased")
            return make(after: after, sibs: siblingsWith(after, under: fatherId), note: note,
                        mark: mark(.grey, TreePlaceText.deceasedPill(female: female, date: date ?? person.deathDate)))

        case .delete:
            let n = data.childCount(of: person.id)
            let note: String
            if n > 0 {
                note = female
                    ? L10n.t("لها \(n) أبناء مرتبطون — لا تُحذف قبل نقلهم", "She has \(n) linked children — she can't be deleted before they're moved")
                    : L10n.t("له \(n) أبناء مرتبطون — لا يُحذف قبل نقلهم", "He has \(n) linked children — he can't be deleted before they're moved")
            } else {
                note = female
                    ? L10n.t("\(lineOf) · تُحذف من الشجرة", "\(lineOf) · removed from the tree")
                    : L10n.t("\(lineOf) · يُحذف من الشجرة", "\(lineOf) · removed from the tree")
            }
            return make(note: note, danger: true, mark: mark(.danger, female ? L10n.t("تُحذف", "Deleted") : L10n.t("يُحذف", "Deleted")))

        case .moveFather(_, let newFatherId):
            guard let newFather = data.father(newFatherId) else { return nil }
            let after = TreePlaceCopy.with(person, fatherId: newFatherId, sortOrder: Int.max)
            let A = X, B = TreePlaceText.pair(newFather, fatherOf: fatherOf)
            let note = female
                ? L10n.t("تُنقل من تحت «\(A)» إلى تحت «\(B)» — يتحدّث اسمها الكامل", "Moved from under «\(A)» to under «\(B)» — her full name is updated")
                : L10n.t("يُنقل من تحت «\(A)» إلى تحت «\(B)» — يتحدّث اسمه الكامل", "Moved from under «\(A)» to under «\(B)» — his full name is updated")
            let pill = female ? L10n.t("تُنقل", "Moved") : L10n.t("يُنقل", "Moved")
            return make(shape: .moveFather, after: after, sibs: siblingsWith(after, under: newFatherId), note: note,
                        mark: mark(.ghost, pill), oldFather: father, oldSibs: siblings,
                        father: newFather, grandfather: fatherOf(newFather.fatherId))

        case .subject:
            return make(note: lineOf, mark: mark(.ring, nil))

        case .outsideWife(_, let name):
            let H = TreePlaceText.pair(person, fatherOf: fatherOf)
            if removing {
                return make(shape: .outsideWife, sibs: [person],
                            note: L10n.t("زوجة «\(H)» من خارج العائلة · تُحذف من الشجرة",
                                         "Wife of «\(H)» from outside the family · removed from the tree"),
                            danger: true, mark: mark(.ring, nil), wife: name)
            }
            return make(shape: .outsideWife, sibs: [person],
                        note: L10n.t("زوجة «\(H)» من خارج العائلة", "Wife of «\(H)» from outside the family"),
                        mark: mark(.ring, nil), wife: name)
        }
    }
}

/// نسخة من العضو بقيم «بعد التنفيذ» — للرسم فقط
enum TreePlaceCopy {
    static func with(_ m: FamilyMember, firstName: String? = nil, fullName: String? = nil, birthDate: String? = nil,
                     isDeceased: Bool? = nil, deathDate: String? = nil, avatarUrl: String?? = nil,
                     fatherId: UUID? = nil, sortOrder: Int? = nil) -> FamilyMember {
        var copy = FamilyMember(
            id: m.id, firstName: firstName ?? m.firstName, fullName: fullName ?? m.fullName,
            familyName: m.familyName, phoneNumber: m.phoneNumber, birthDate: birthDate ?? m.birthDate,
            deathDate: deathDate ?? m.deathDate, isDeceased: isDeceased ?? m.isDeceased, role: m.role,
            fatherId: fatherId ?? m.fatherId, motherId: m.motherId, husbandId: m.husbandId,
            photoURL: avatarUrl != nil ? nil : m.photoURL,
            isPhoneHidden: m.isPhoneHidden, isBirthDateHidden: m.isBirthDateHidden, badgeEnabled: m.badgeEnabled,
            isHiddenFromTree: m.isHiddenFromTree, sortOrder: sortOrder ?? m.sortOrder, bio: m.bio, status: m.status,
            avatarUrl: avatarUrl ?? m.avatarUrl, coverUrl: m.coverUrl, isMarried: m.isMarried, gender: m.gender,
            createdAt: m.createdAt, registrationPlatform: m.registrationPlatform, username: m.username, email: m.email)
        copy.deathDateUnknown = m.deathDateUnknown
        copy.isPhotoHidden = m.isPhotoHidden
        return copy
    }
}

// MARK: - من كل نوع طلب إلى مكانه (دالة لكل نوع — نفسها في الأندرويد)

extension TreePlace {
    /// انضمام (حساب رجل): المطابق المختار ← «يُربط بحسابه»
    static func join(match: FamilyMember) -> TreePlace {
        TreePlace(tree: .men, change: .link(match.id), kindLabel: L10n.t("طلب انضمام", "Join request"))
    }

    /// «إضافة ابن»: الابن أُضيف وينتظر التأكيد (`new_value` = معرّفه)
    static func childAdd(_ r: AdminRequest, kindLabel: String) -> TreePlace? {
        guard let id = r.newValue.flatMap(UUID.init(uuidString:)) else { return nil }
        return TreePlace(tree: .men, change: .added(id), kindLabel: kindLabel)
    }

    /// طلب تعديل الشجرة بإجرائه
    static func treeEdit(_ r: AdminRequest, action: TreeEditAction, kindLabel: String, data: TreePlaceData) -> TreePlace? {
        let p = r.treeEditPayload
        let target = p?.targetMemberId.flatMap(UUID.init(uuidString:)) ?? r.memberId
        // عقدة في شجرة النساء (لا ملف رجل بمعرّفها) ← شجرة النساء
        let tree: TreePlaceTree = data.man(target) == nil && data.woman(target) != nil ? .women : .men
        switch action {
        case .add:
            // طلب من شجرة النساء (زوجة/أم/بنت): الاسم ولمن من أسطر الملاحظات
            if let notes = p?.notes, let lines = WomenTreeRequestLines(notes) {
                if let w = lines.woman(in: data.women) {
                    return TreePlace(tree: .women, change: .subject(w.id), kindLabel: kindLabel)
                }
                switch lines.relation {
                case .wife:
                    return TreePlace(tree: .men, change: .outsideWife(husbandId: r.requesterId, name: lines.name),
                                     kindLabel: kindLabel)
                case .mother:
                    return TreePlace(tree: .men, change: .subject(r.requesterId), kindLabel: kindLabel,
                                     noteOverride: L10n.t("أمّ من خارج العائلة: \(lines.name)", "Mother from outside the family: \(lines.name)"))
                case nil:
                    guard let f = p?.parentMemberId.flatMap(UUID.init(uuidString:)), data.man(f) != nil else { return nil }
                    return TreePlace(tree: .women, change: .add(name: lines.name, female: true), addFatherId: f,
                                     kindLabel: kindLabel)
                }
            }
            let name = (p?.newMemberName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return TreePlace(tree: .men, change: .add(name: name, female: false),
                             addFatherId: p?.parentMemberId.flatMap(UUID.init(uuidString:)), kindLabel: kindLabel)
        case .editName:
            guard let n = p?.newName, !n.trimmingCharacters(in: .whitespaces).isEmpty else {
                return TreePlace(tree: tree, change: .subject(target), kindLabel: kindLabel)
            }
            return TreePlace(tree: tree, change: .rename(target, newName: n), kindLabel: kindLabel)
        case .editBirth:
            guard let b = p?.newBirthDate ?? p?.newName, !b.isEmpty else {
                return TreePlace(tree: tree, change: .subject(target), kindLabel: kindLabel)
            }
            return TreePlace(tree: tree, change: .birth(target, newBirth: b), kindLabel: kindLabel)
        case .deceased, .addDeathDate:
            return TreePlace(tree: tree, change: .deceased(target, deathDate: p?.deathDate), kindLabel: kindLabel)
        case .addPhoto:
            return TreePlace(tree: tree, change: .photo(target, newPhotoUrl: p?.newPhotoUrl), kindLabel: kindLabel)
        case .delete:
            return TreePlace(tree: tree, change: .delete(target), kindLabel: kindLabel)
        case .editPhone, .other:
            return TreePlace(tree: tree, change: .subject(target), kindLabel: kindLabel)
        }
    }

    /// تغيير الاسم (`new_value` = الاسم الجديد)؛ تغيير العائلة تعريف فقط
    static func nameChange(_ r: AdminRequest, kindLabel: String) -> TreePlace {
        if r.requestType == RequestType.familyChange.rawValue {
            return TreePlace(tree: .men, change: .subject(r.memberId), kindLabel: kindLabel)
        }
        let n = (r.newValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return TreePlace(tree: .men, change: n.isEmpty ? .subject(r.memberId) : .rename(r.memberId, newName: n),
                         kindLabel: kindLabel)
    }

    /// بلاغ وفاة (التاريخ إن كان في `new_value`)
    static func deceasedReport(_ r: AdminRequest, kindLabel: String) -> TreePlace {
        let date = TreePlaceText.year(r.newValue) != nil ? r.newValue : nil
        return TreePlace(tree: .men, change: .deceased(r.memberId, deathDate: date), kindLabel: kindLabel)
    }

    /// صورة مقترحة (`new_value` = رابطها)
    static func photoSuggestion(_ r: AdminRequest, kindLabel: String) -> TreePlace {
        TreePlace(tree: .men, change: .photo(r.memberId, newPhotoUrl: r.newValue), kindLabel: kindLabel)
    }

    /// تعريف بالعضو (الرقم، تغيير العائلة، الخصوصية، حذف الحساب) — حساب المرأة: عقدتها في شجرة النساء
    static func subject(memberId: UUID, kindLabel: String, data: TreePlaceData) -> TreePlace {
        if let m = data.man(memberId), m.isWomanAccount, let node = WomenStore.node(forAccount: memberId) {
            return TreePlace(tree: .women, change: .subject(node.id), kindLabel: kindLabel)
        }
        return TreePlace(tree: .men, change: .subject(memberId), kindLabel: kindLabel)
    }

    /// «إضافة قريبة» (`relative_add`): موجودة ← تُربط، تحت أب ← تُضاف، والقديم (اسم فقط) ← زوجة من خارج العائلة / أم
    static func relativeAdd(_ r: AdminRequest, kindLabel: String) -> TreePlace? {
        guard let d = RelativeAddPayload.parse(r.details) else { return nil }
        let a = d.args
        let name = (a?.name ?? d.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let w = a?.womanId.flatMap(UUID.init(uuidString:)) {
            return TreePlace(tree: .women, change: .link(w), kindLabel: kindLabel)
        }
        if let f = a?.fatherId.flatMap(UUID.init(uuidString:)), !name.isEmpty {
            return TreePlace(tree: .women, change: .add(name: name, female: true), addFatherId: f, kindLabel: kindLabel)
        }
        let requester = d.requesterId.flatMap(UUID.init(uuidString:)) ?? r.requesterId
        let kind = a?.kind ?? d.kind ?? ""
        let rpc = d.rpc ?? ""
        if kind == "mother" || rpc.contains("mother") {
            return TreePlace(tree: .men, change: .subject(requester), kindLabel: kindLabel,
                             noteOverride: L10n.t("أمّ من خارج العائلة: \(name)", "Mother from outside the family: \(name)"))
        }
        guard !name.isEmpty else { return nil }
        return TreePlace(tree: .men, change: .outsideWife(husbandId: requester, name: name), kindLabel: kindLabel)
    }

    /// «طلب حذف من الشجرة» (`relative_remove`): الابن/البنت في مكانه «يُحذف»، والزوجة تحت أبيها أو بجانب زوجها
    static func relativeRemove(_ r: AdminRequest, kindLabel: String, data: TreePlaceData) -> TreePlace? {
        guard let d = RelativeRemoveDetails.parse(r.details),
              let target = d.targetId.flatMap(UUID.init(uuidString:)) ?? r.newValue.flatMap(UUID.init(uuidString:))
        else { return nil }
        let requester = d.requesterId.flatMap(UUID.init(uuidString:)) ?? r.requesterId
        if d.kind == "wife" {
            // بنت من العائلة: عقدتها تحت أبيها؛ من خارج العائلة (أو حُذفت/لم تُحمَّل بعد): بجانب زوجها
            if let w = data.woman(target), w.fatherId != nil {
                return TreePlace(tree: .women, change: .delete(target), kindLabel: kindLabel)
            }
            if r.status == ApprovalStatus.approved.rawValue {
                return TreePlace(tree: .women, change: .delete(target), kindLabel: kindLabel)
            }
            let name = data.woman(target)?.firstName ?? d.name ?? ""
            var p = TreePlace(tree: .men, change: .outsideWife(husbandId: requester, name: name), kindLabel: kindLabel)
            p.removing = true
            return p
        }
        let tree: TreePlaceTree = d.tree == "women" || (data.man(target) == nil && data.woman(target) != nil) ? .women : .men
        var p = TreePlace(tree: tree, change: .delete(target), kindLabel: kindLabel)
        p.goneName = d.name
        p.goneFatherHint = requester
        p.goneFemale = d.kind == "daughter"
        return p
    }

    /// «طلب نسب» (ابن بنت العائلة): أمّه في شجرة النساء
    static func lineage(_ r: AdminRequest, kindLabel: String, data: TreePlaceData) -> TreePlace? {
        guard let d = LineageRequestDetails.parse(r.details), let mid = d.motherId.flatMap(UUID.init(uuidString:)) else {
            return nil
        }
        let mother = data.woman(mid)
        let name = mother.map { TreePlaceText.pair($0, fatherOf: { data.man($0) ?? data.woman($0) }) } ?? (d.motherName ?? "")
        return TreePlace(tree: .women, change: .subject(mid), kindLabel: kindLabel,
                         noteOverride: L10n.t("ابن بنت العائلة «\(name)»", "Son of the family's daughter «\(name)»"))
    }
}

// MARK: - من الطلب نفسه أياً كان نوعه (إشعارات الطلبات §7، والمعالَجة §8) — نفس الدوال أعلاه

extension TreePlace {
    /// مكان أي طلب من نوعه وحمولته، بزمن نتيجته (معلّق ← قبل التنفيذ، مقبول ← تمّ، مرفوض ← «رُفض»).
    /// الانضمام/الربط المقبول: العقدة التي رُبط بها الحساب (ملفه في الشجرة، أو عقدته في شجرة النساء)
    static func fromRequest(_ r: AdminRequest, data: TreePlaceData) -> TreePlace? {
        let label = AdminTrailText.typeTitle(r)
        let base: TreePlace?
        switch r.requestType {
        case RequestType.treeEdit.rawValue:
            let action = r.treeEditPayload?.resolvedAction ?? .other
            base = treeEdit(r, action: action, kindLabel: label, data: data).map { place in
                var p = place
                // تعديل اسم تمّ: الاسم قبل التعديل كما حُفظ في الطلب
                if action == .editName { p.pastBefore = r.treeEditPayload?.targetMemberName }
                // حذف تمّ: الاسم المحفوظ في الطلب (العقدة لم تعد موجودة)
                if action == .delete { p.goneName = r.treeEditPayload?.targetMemberName }
                return p
            }
        case RequestType.childAdd.rawValue:
            base = childAdd(r, kindLabel: label)
        case RequestType.nameChange.rawValue, RequestType.familyChange.rawValue:
            base = nameChange(r, kindLabel: label)
        case RequestType.deceasedReport.rawValue:
            base = deceasedReport(r, kindLabel: label)
        case RequestType.photoSuggestion.rawValue:
            base = photoSuggestion(r, kindLabel: label)
        case RequestType.phoneChange.rawValue, RequestType.accountDelete.rawValue, RequestType.privacyRequest.rawValue:
            base = subject(memberId: r.memberId, kindLabel: label, data: data)
        case RequestType.relativeAdd.rawValue:
            base = relativeAdd(r, kindLabel: label)
        case RequestType.relativeRemove.rawValue:
            base = relativeRemove(r, kindLabel: label, data: data)
        case DaughterSons.requestType:
            base = lineage(r, kindLabel: label, data: data)
        case RequestType.joinRequest.rawValue, RequestType.linkRequest.rawValue:
            // قبل القرار المطابق يُختار في «الوارد»، والمرفوض حُذف ملفه — المقبول وحده له مكان
            guard r.status == ApprovalStatus.approved.rawValue else { return nil }
            if let w = WomenStore.node(forAccount: r.memberId) {
                base = TreePlace(tree: .women, change: .link(w.id), kindLabel: label)
            } else if let m = data.man(r.memberId), m.fatherId != nil {
                base = TreePlace(tree: .men, change: .link(m.id), kindLabel: label)
            } else {
                base = nil
            }
        default:
            base = nil
        }
        return base?.outcome(status: r.status)
    }

    /// إشعار تغيير تمّ (`details.action` add|edit|delete، `details.tree`، `details.subject`، `details.changes[]`) —
    /// بصيغة الماضي؛ عدّة حقول ← الأظهر في الشجرة: نقل › وفاة › اسم › صورة › ميلاد › تعريف. nil = لا يخصّ شخصاً
    static func notice(_ n: AppNotification) -> TreePlace? {
        let d = n.details
        let selfChild = d?.selfChild == true
        guard let action = selfChild ? "add" : d?.action, ["add", "edit", "delete"].contains(action),
              let id = d?.subject?.id.flatMap(UUID.init(uuidString:)) ?? n.subjectMemberId else { return nil }
        let tree: TreePlaceTree = d?.tree == "women" ? .women : .men
        let label = AdminNoticeText.eventTitle(n)
        let changes = d?.changes ?? []
        func entry(_ fields: [String]) -> AppNotification.NotificationDetails.ChangeEntry? {
            changes.first { fields.contains($0.field) }
        }
        let fatherEntry = entry(["father_id", "parent_id"])

        var p: TreePlace
        switch action {
        case "add":
            p = TreePlace(tree: tree, change: .added(id), kindLabel: label)
        case "delete":
            p = TreePlace(tree: tree, change: .delete(id), kindLabel: label)
            p.goneName = d?.subject?.name
            p.goneFatherHint = fatherEntry?.before.flatMap(UUID.init(uuidString:))
            p.goneFemale = tree == .women || entry(["gender"])?.before == "female"
        default:
            if let e = fatherEntry, let to = e.after.flatMap(UUID.init(uuidString:)) {
                p = TreePlace(tree: tree, change: .moveFather(id, newFatherId: to), kindLabel: label)
                p.oldFatherId = e.before.flatMap(UUID.init(uuidString:))
            } else if let e = entry(["is_deceased", "death_date"]),
                      e.field == "death_date" || ["true", "1", "نعم", "Yes"].contains(e.after ?? "") {
                let date = entry(["death_date"])?.after
                p = TreePlace(tree: tree, change: .deceased(id, deathDate: date), kindLabel: label)
            } else if let e = entry(["full_name", "first_name"]) {
                p = TreePlace(tree: tree, change: .rename(id, newName: e.after ?? ""), kindLabel: label)
                p.pastBefore = e.before
            } else if let e = entry(["avatar_url"]) {
                p = TreePlace(tree: tree, change: .photo(id, newPhotoUrl: e.afterUrl ?? e.after), kindLabel: label)
                p.pastBefore = e.beforeUrl ?? e.before
            } else if let e = entry(["birth_date"]) {
                p = TreePlace(tree: tree, change: .birth(id, newBirth: e.after ?? ""), kindLabel: label)
                p.pastBefore = e.before
            } else {
                p = TreePlace(tree: tree, change: .subject(id), kindLabel: label)
            }
        }
        p.tense = .past
        return p
    }
}

/// `details` لطلب `relative_add`: `kind`، `rpc`، `args{p_kind,p_father_id,p_woman_id,p_name}`، `requester_id`
nonisolated struct RelativeAddPayload: Decodable, Sendable {
    struct Args: Decodable, Sendable {
        let kind: String?
        let fatherId: String?
        let womanId: String?
        let name: String?
        enum CodingKeys: String, CodingKey {
            case kind = "p_kind", fatherId = "p_father_id", womanId = "p_woman_id", name = "p_name"
        }
    }
    let kind: String?
    let name: String?
    let rpc: String?
    let args: Args?
    let requesterId: String?

    enum CodingKeys: String, CodingKey {
        case kind, name, rpc, args
        case requesterId = "requester_id"
    }

    static func parse(_ details: String?) -> RelativeAddPayload? {
        guard let data = details?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RelativeAddPayload.self, from: data)
    }
}
