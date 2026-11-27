#if !ADMIN_LOGIC_TEST
import SwiftUI
#else
import Foundation
#endif

// MARK: - شجرة العائلة للرجال فقط (طلب المالك ٢٠٢٦-١١-٢٧ «لمن عضو يضيف انثى بالشجرة العائلة يطلعه تنبيه ان شجرة مخصصة للرجال»)
//
// مربّعات الإضافة في شجرة العائلة (`AddChildSheet` في «عائلتي» وتفاصيل العضو، و`AddSonByAdminSheet` للإدارة) كان فيها
// «أنثى» تُرسل البنت لشجرة النساء بصمت. الآن اختيار «أنثى» لا يُقبل: تنبيه «شجرة العائلة للرجال فقط» وزرّ يفتح «إضافة بنت»
// الموجود في شجرة النساء تحت الأب نفسه (`WomanDetailSheet(startsDaughterAdd:)` — مباشر للإدارة، «عائلتي» لعقدته، وطلب لغيره).
// القاعدة هنا خالصة تُفحص بلا محاكي (`tests/admin-redesign/G1/main.swift`)، والواجهة خلف `#if !ADMIN_LOGIC_TEST`.

nonisolated enum FamilyTreeMenOnly {
    /// ما يحدث لاختيار جنس في مربّع إضافة لشجرة العائلة
    enum Decision: Equatable {
        /// ذكر — يُضاف لشجرة العائلة كما كان
        case allow
        /// أنثى — تنبيه وزرّ «إضافة بنت في شجرة النساء» تحت الأب نفسه
        case redirectToWomenTree
        /// أنثى ولا مسار لها في شجرة النساء من هنا — تنبيه بـ«إلغاء» فقط
        case blockOnly
    }

    static func isFemale(_ gender: String?) -> Bool {
        (gender ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "female"
    }

    /// `hasWomenPath`: للأب عقدة في شجرة النساء ولمن يضيف آلية فيها (ليس حساباً غير مفعّل وشجرة النساء غير مقفولة)
    static func decision(gender: String?, hasWomenPath: Bool) -> Decision {
        guard isFemale(gender) else { return .allow }
        return hasWomenPath ? .redirectToWomenTree : .blockOnly
    }

    /// الجنس الذي يبقى في المربّع بعد الاختيار — «أنثى» لا تُقبل، فيبقى ما كان (وإن كان أنثى خطأً يرجع ذكراً)
    static func keptGender(picked: String, current: String) -> String {
        guard isFemale(picked) else { return picked }
        return isFemale(current) ? "male" : current
    }

    /// آخر حارس قبل الكتابة: لا تُكتب أنثى في شجرة العائلة من مربّعات الإضافة
    static func mayWriteToFamilyTree(gender: String?) -> Bool { !isFemale(gender) }

    /// الاسم الذي يُنقل لمربّع البنت (الاسم الأول المكتوب، بلا مسافات زائدة)
    static func carriedName(_ typed: String) -> String {
        typed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: اسم بنت في مربّع ابن — انتقال تلقائي (طلب المالك ٢٠٢٦-١١-٢٧ «عندما يطلب اضافة ابن باسم انثى… تنتقل تلقائيا
    // الى شجرة النساء»)
    //
    // القاعدة من البيانات وقت الإرسال (لا قائمة أسماء مكتوبة): الاسم الأول المكتوب بعد التطبيع «اسم بنت» إذا كان اسماً أول
    // لأنثى في شجرة النساء ولم يكن اسماً أول لأي ذكر (في شجرة العائلة أو العُقد المنعكسة للرجال في شجرة النساء).
    // الاسم غير المعروف لا يُخمَّن (يبقى ابناً)، و«ة» في آخره ليست قاعدة (حمزة، أسامة رجال).

    /// تخمين الاسم من بيانات الشجرتين
    enum NameGuess: Equatable { case female, male, unknown }

    /// أسماء الشجرتين بعد التطبيع — `female` بلا أي اسم مشترك مع الذكور
    struct NameBook: Equatable {
        let female: Set<String>
        let male: Set<String>
        static let empty = NameBook(female: [], male: [])
    }

    /// الكلمة الأولى بعد التطبيع: بلا مسافات زائدة، أ/إ/آ/ٱ ← ا، ى ← ي، ة في الآخر ← ه، بلا تطويل ولا تشكيل ولا محارف خفية
    static func normalizedFirstName(_ typed: String) -> String {
        // التطبيع الواحد (`ArabicTextNormalizer.normalizeLetters`، M1): المحارف الخفية والتطويل والتشكيل تُحذف قبل
        // التقطيع (قد تأتي ملتصقة بالمسافة)، والحروف تتوحّد كالبحث
        let cleaned = ArabicTextNormalizer.normalizeLetters(typed)
        guard let first = cleaned.split(whereSeparator: { $0.isWhitespace }).first else { return "" }
        return String(first).lowercased()
    }

    /// `women`: صفوف شجرة النساء (الاسم الأول، أنثى؟) · `men`: الأسماء الأولى لذكور شجرة العائلة
    static func nameBook(women: [(firstName: String, isFemale: Bool)], men: [String]) -> NameBook {
        var femaleRaw = Set<String>(), male = Set<String>()
        for w in women {
            let key = normalizedFirstName(w.firstName)
            guard !key.isEmpty else { continue }
            if w.isFemale { femaleRaw.insert(key) } else { male.insert(key) }
        }
        for m in men {
            let key = normalizedFirstName(m)
            if !key.isEmpty { male.insert(key) }
        }
        return NameBook(female: femaleRaw.subtracting(male), male: male)
    }

    static func guess(_ typed: String, book: NameBook) -> NameGuess {
        let key = normalizedFirstName(typed)
        if key.isEmpty { return .unknown }
        if book.female.contains(key) { return .female }
        if book.male.contains(key) { return .male }
        return .unknown
    }

    /// الأسماء المكتوبة التي تنتقل لشجرة النساء (بترتيبها، بلا تكرار) — ما أكّد المستخدم أنه ولد («هو ولد؟ ارجع») لا ينتقل
    static func namesToMove(_ typed: [String], book: NameBook, confirmedSons: Set<String>) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for raw in typed {
            let name = carriedName(raw)
            let key = normalizedFirstName(name)
            guard !key.isEmpty, guess(name, book: book) == .female,
                  !confirmedSons.contains(key), seen.insert(key).inserted else { continue }
            out.append(name)
        }
        return out
    }

    /// مفاتيح الأسماء التي أكّد أنها لأولاد
    static func sonKeys(_ names: [String]) -> Set<String> {
        Set(names.map(normalizedFirstName).filter { !$0.isEmpty })
    }

    /// «فاطمة» · «فاطمة» و«مريم» · «فاطمة»، «مريم» و«نورة»
    static func quotedList(_ names: [String]) -> String {
        let q = names.map { "«\($0)»" }
        guard q.count > 1 else { return q.first ?? "" }
        return q.dropLast().joined(separator: "، ") + " و" + q.last!
    }

    /// السطر أعلى مربّع البنت بعد الانتقال
    static func autoMoveNotice(_ names: [String]) -> String {
        names.count > 1
            ? text("انتقلنا لشجرة النساء لأن \(quotedList(names)) أسماء بنات",
                   "Moved to the women's tree because \(quotedList(names)) are girls' names")
            : text("انتقلنا لشجرة النساء لأن \(quotedList(names)) اسم بنت",
                   "Moved to the women's tree because \(quotedList(names)) is a girl's name")
    }

    /// الرجوع لمربّع الابن كما هو
    static func backTitle(count: Int) -> String {
        count > 1 ? text("هم أولاد؟ ارجع", "They're boys? Go back") : text("هو ولد؟ ارجع", "It's a boy? Go back")
    }

    /// بلا مسار في شجرة النساء: تنبيه بـ«هو ولد — أرسل» و«إلغاء»
    static func noPathTitle(_ names: [String]) -> String {
        names.count > 1 ? text("\(quotedList(names)) أسماء بنات", "\(quotedList(names)) are girls' names")
                        : text("\(quotedList(names)) اسم بنت", "\(quotedList(names)) is a girl's name")
    }
    static func sendAsSonTitle(count: Int) -> String {
        count > 1 ? text("أولاد — أرسل", "Boys — send") : text("هو ولد — أرسل", "It's a boy — send")
    }

    // MARK: تغيير جنس سجلّ موجود (K1، ٢٠٢٦-١١-٢٧)
    // السيرفر يرفض صار سجلّ `profiles` أنثى وله أب (`trg_zzzz_family_tree_men_only`، hint `family_tree_men_only`)،
    // وكان `updateMemberGender` يسجّل الفشل فقط فيبقى ذكراً بصمت. «أنثى» لمن له أب = النقل بين الشجرتين
    // (`move_child_gender`)، وأي فشل يُعرض برسالة السيرفر العربية.

    enum GenderChangeRoute: Equatable {
        /// لا تغيير
        case unchanged
        /// كتابة عمود الجنس فقط (ذكر، أو أنثى بلا أب)
        case plainUpdate
        /// أنثى ولها أب: نقل لشجرة النساء تحت أبيها (`move_child_gender`)
        case moveBetweenTrees
    }

    static func genderChangeRoute(to gender: String, current: String?, hasFather: Bool) -> GenderChangeRoute {
        if isFemale(gender) == isFemale(current ?? "male") { return .unchanged }
        return isFemale(gender) && hasFather ? .moveBetweenTrees : .plainUpdate
    }

    /// hint رفض السيرفر
    static let menOnlyHint = "family_tree_men_only"

    /// ما يُعرض حين يفشل حفظ الجنس: رسالة السيرفر إن كانت عربية، وإلا رسالة عامة
    static func genderFailureMessage(serverMessage: String?) -> String {
        if let msg = serverMessage, msg.range(of: "\\p{Arabic}", options: .regularExpression) != nil { return msg }
        return text("تعذّر حفظ الجنس. حاول مرة أخرى.", "Couldn't save the gender. Try again.")
    }

    // MARK: النصوص

    static var title: String { text("شجرة العائلة للرجال فقط", "The family tree is for men only") }
    static var message: String { text("البنات يُضفن في شجرة النساء تحت أبيهن.", "Daughters are added in the women's tree under their father.") }
    static var openTitle: String { text("إلى شجرة النساء", "To the women's tree") }
    static var cancelTitle: String { text("إلغاء", "Cancel") }
    static var noNodeMessage: String {
        text("تعذّر فتح الأب في شجرة النساء. افتح شجرة النساء وأضف البنت من «طلب تعديل» على أبيها.",
             "Couldn't open the father in the women's tree. Open the women's tree and add her from her father.")
    }

    private static func text(_ ar: String, _ en: String) -> String {
        #if ADMIN_LOGIC_TEST
        ar
        #else
        L10n.t(ar, en)
        #endif
    }
}


#if !ADMIN_LOGIC_TEST

// MARK: - التنبيه والانتقال لشجرة النساء

/// طلب فحص أسماء مربّع الابن عند «إرسال/إضافة» — كل ضغطة طلب جديد (`id`)
struct FamilyTreeNameCheck: Equatable {
    let id = UUID()
    let names: [String]
}

/// ما يصل لمربّع البنت في شجرة النساء بعد الانتقال التلقائي: السطر أعلاه و«هو ولد؟ ارجع»
struct WomenTreeAutoMove {
    let notice: String
    let backTitle: String
    let onBack: () -> Void
}

/// على مربّع الإضافة: التنبيه حين `isPresented`، ومنه «إضافة بنت في شجرة النساء» تفتح عقدة الأب في شجرة النساء على «أبناء»
/// بابنة (الاسم المكتوب مملوء). `onWomenTreeClosed` بعد إغلاق شجرة النساء (المربّع الأصلي يُغلق — طلبه انتقل هناك).
///
/// والانتقال التلقائي: `nameCheck` يُضبط عند الإرسال بأسماء المربّع — اسم بنت (`FamilyTreeMenOnly.namesToMove`) يفتح
/// «أبناء» في شجرة النساء بالاسم وسطر «انتقلنا لشجرة النساء…» و«هو ولد؟ ارجع» (يرجع لمربّع الابن كما هو ويقبل الاسم ابناً
/// في الإرسال التالي)؛ غير ذلك `onSon` (الإرسال كما كان). بلا مسار في شجرة النساء: تنبيه «اسم بنت» بـ«هو ولد — أرسل».
struct FamilyTreeMenOnlyGate: ViewModifier {
    @Binding var isPresented: Bool
    let father: FamilyMember
    let typedName: String
    @Binding var nameCheck: FamilyTreeNameCheck?
    var onSon: () -> Void = {}
    /// بعد إغلاق شجرة النساء من انتقال تلقائي — nil = `onWomenTreeClosed`
    var onMoved: (([String]) -> Void)? = nil
    var onWomenTreeClosed: () -> Void = {}

    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @ObservedObject private var lineage = LineageGateStore.shared
    @State private var node: FamilyMember? = nil
    @State private var women: [FamilyMember] = []
    @State private var loading = false
    @State private var showNoNode = false
    /// الأسماء المنقولة تلقائياً لشجرة النساء المفتوحة الآن (فارغة = فُتحت من تنبيه «أنثى»)
    @State private var movedNames: [String] = []
    /// ضغط «هو ولد؟ ارجع»
    @State private var backToSon = false
    /// أسماء أكّد أنها لأولاد — لا تنتقل مرة ثانية من هذا المربّع
    @State private var confirmedSons: Set<String> = []
    /// اسم بنت بلا مسار في شجرة النساء — تنبيه «هو ولد — أرسل»
    @State private var noPathNames: [String] = []

    /// غير المفعّل لا يضيف هناك (عرض فقط)، وشجرة النساء المقفولة لا تُفتح — يبقى التنبيه بـ«إلغاء»
    private var hasWomenPath: Bool {
        guard !lineage.isLocked(.womenTree), let me = authVM.currentUser else { return false }
        if authVM.canEditMembers { return true }
        if me.role == .pending { return false }
        if let s = me.status, s == .frozen || s == .deleted || s == .pending { return false }
        return true
    }

    func body(content: Content) -> some View {
        content
            .dsAlert(FamilyTreeMenOnly.title, isPresented: $isPresented, icon: "figure.stand.dress") {
                if FamilyTreeMenOnly.decision(gender: "female", hasWomenPath: hasWomenPath) == .redirectToWomenTree {
                    Button(FamilyTreeMenOnly.openTitle) { openWomenTree(moving: []) }
                }
                Button(FamilyTreeMenOnly.cancelTitle, role: .cancel) {}
            } message: {
                Text(FamilyTreeMenOnly.message)
            }
            .dsAlert(FamilyTreeMenOnly.title, isPresented: $showNoNode) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: {
                Text(FamilyTreeMenOnly.noNodeMessage)
            }
            .dsAlert(FamilyTreeMenOnly.noPathTitle(noPathNames),
                     isPresented: Binding(get: { !noPathNames.isEmpty }, set: { if !$0 { noPathNames = [] } }),
                     icon: "figure.stand.dress") {
                Button(FamilyTreeMenOnly.sendAsSonTitle(count: noPathNames.count)) {
                    confirmedSons.formUnion(FamilyTreeMenOnly.sonKeys(noPathNames))
                    noPathNames = []
                    // بعد خروج التنبيه — قد يفتح الإرسال تنبيهه هو
                    DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.panelOutDuration) { onSon() }
                }
                Button(FamilyTreeMenOnly.cancelTitle, role: .cancel) { noPathNames = [] }
            } message: {
                Text(FamilyTreeMenOnly.message)
            }
            .onChange(of: nameCheck) { check in
                guard let check else { return }
                nameCheck = nil
                runNameCheck(check.names)
            }
            .fullScreenCover(item: $node, onDismiss: womenTreeClosed) { n in
                WomanDetailSheet(
                    woman: n,
                    allWomen: women,
                    me: authVM.currentUser,
                    canEdit: authVM.canEditMembers,
                    canDelete: authVM.canDeleteMembers,
                    canAnnounceDeath: authVM.isAdmin,
                    canModerate: authVM.canModerate,
                    startsDaughterAdd: movedNames.isEmpty ? [FamilyTreeMenOnly.carriedName(typedName)] : movedNames,
                    autoMove: movedNames.isEmpty ? nil : WomenTreeAutoMove(
                        notice: FamilyTreeMenOnly.autoMoveNotice(movedNames),
                        backTitle: FamilyTreeMenOnly.backTitle(count: movedNames.count),
                        onBack: { backToSon = true })
                )
                .background(ClearPresentationBackground())
                .dsSection(.tree)
            }
            .transaction { t in if node != nil { t.disablesAnimations = true } }
    }

    /// أسماء المربّع عند الإرسال: اسم بنت ← شجرة النساء، وإلا الإرسال كما كان
    private func runNameCheck(_ names: [String]) {
        guard !loading else { return }
        Task {
            // الأسماء من آخر جلب لشجرة النساء — ولم تُفتح بعد: جلب واحد (قراءة الجدول نفسه)
            if WomenStore.cache.isEmpty { _ = try? await WomenStore.fetch() }
            let book = FamilyTreeMenOnly.nameBook(
                women: WomenStore.cache.map { (firstName: $0.firstName, isFemale: $0.isFemale) },
                men: memberVM.allMembers.filter { !$0.isFemale }.map(\.firstName))
            let girls = FamilyTreeMenOnly.namesToMove(names, book: book, confirmedSons: confirmedSons)
            guard !girls.isEmpty else { onSon(); return }
            guard hasWomenPath else { noPathNames = girls; return }
            openWomenTree(moving: girls)
        }
    }

    private func womenTreeClosed() {
        let moved = movedNames
        movedNames = []
        if backToSon {
            // «هو ولد؟ ارجع»: مربّع الابن كما هو، والاسم يُقبل ابناً في الإرسال التالي
            backToSon = false
            confirmedSons.formUnion(FamilyTreeMenOnly.sonKeys(moved))
            return
        }
        if !moved.isEmpty, let onMoved { onMoved(moved) } else { onWomenTreeClosed() }
    }

    /// عقدة الأب في شجرة النساء (الذكر بنفس معرّفه) — من الكاش، وإلا جلب واحد
    private func openWomenTree(moving names: [String]) {
        guard !loading else { return }
        loading = true
        let fatherId = father.id
        let editor = authVM.canEditMembers
        Task {
            defer { loading = false }
            var rows = WomenStore.cache
            if !rows.contains(where: { $0.id == fatherId }) {
                rows = (try? await WomenStore.fetch()) ?? rows
            }
            // المخفيّ يبقى للإدارة فقط — كما في شجرة النساء
            let visible = editor ? rows : rows.filter { !$0.isHiddenFromTree || $0.id == fatherId }
            guard let found = visible.first(where: { $0.id == fatherId }) else {
                // الانتقال التلقائي بلا عقدة: تنبيه «اسم بنت» بـ«هو ولد — أرسل»
                if names.isEmpty { showNoNode = true } else { noPathNames = names }
                return
            }
            women = visible
            movedNames = names
            backToSon = false
            // بعد خروج نافذة التنبيه
            let delay = names.isEmpty ? DSMotion.panelOutDuration : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { node = found }
        }
    }
}

extension View {
    /// تنبيه «شجرة العائلة للرجال فقط» وانتقال لـ«إضافة بنت» في شجرة النساء تحت `father`، والانتقال التلقائي لاسم بنت
    /// عند الإرسال (`nameCheck` ← `onSon` أو شجرة النساء)
    func familyTreeMenOnly(isPresented: Binding<Bool>, father: FamilyMember, typedName: String,
                           nameCheck: Binding<FamilyTreeNameCheck?> = .constant(nil),
                           onSon: @escaping () -> Void = {},
                           onMoved: (([String]) -> Void)? = nil,
                           onWomenTreeClosed: @escaping () -> Void = {}) -> some View {
        modifier(FamilyTreeMenOnlyGate(isPresented: isPresented, father: father, typedName: typedName,
                                       nameCheck: nameCheck, onSon: onSon, onMoved: onMoved,
                                       onWomenTreeClosed: onWomenTreeClosed))
    }
}

/// اختيار الجنس في مربّعات إضافة شجرة العائلة: «أنثى» لا تُقبل وتفتح التنبيه
extension Binding where Value == String {
    func menOnly(alert: Binding<Bool>) -> Binding<String> {
        Binding(get: { wrappedValue },
                set: { picked in
                    let kept = FamilyTreeMenOnly.keptGender(picked: picked, current: wrappedValue)
                    if kept != wrappedValue { wrappedValue = kept }
                    if FamilyTreeMenOnly.isFemale(picked) { alert.wrappedValue = true }
                })
    }
}
#endif
