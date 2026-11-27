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

/// على مربّع الإضافة: التنبيه حين `isPresented`، ومنه «إضافة بنت في شجرة النساء» تفتح عقدة الأب في شجرة النساء على «أبناء»
/// بابنة (الاسم المكتوب مملوء). `onWomenTreeClosed` بعد إغلاق شجرة النساء (المربّع الأصلي يُغلق — طلبه انتقل هناك).
struct FamilyTreeMenOnlyGate: ViewModifier {
    @Binding var isPresented: Bool
    let father: FamilyMember
    let typedName: String
    var onWomenTreeClosed: () -> Void = {}

    @EnvironmentObject private var authVM: AuthViewModel
    @ObservedObject private var lineage = LineageGateStore.shared
    @State private var node: FamilyMember? = nil
    @State private var women: [FamilyMember] = []
    @State private var loading = false
    @State private var showNoNode = false

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
                    Button(FamilyTreeMenOnly.openTitle) { openWomenTree() }
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
            .fullScreenCover(item: $node, onDismiss: onWomenTreeClosed) { n in
                WomanDetailSheet(
                    woman: n,
                    allWomen: women,
                    me: authVM.currentUser,
                    canEdit: authVM.canEditMembers,
                    canDelete: authVM.canDeleteMembers,
                    canAnnounceDeath: authVM.isAdmin,
                    canModerate: authVM.canModerate,
                    startsDaughterAdd: FamilyTreeMenOnly.carriedName(typedName)
                )
                .background(ClearPresentationBackground())
                .dsSection(.tree)
            }
            .transaction { t in if node != nil { t.disablesAnimations = true } }
    }

    /// عقدة الأب في شجرة النساء (الذكر بنفس معرّفه) — من الكاش، وإلا جلب واحد
    private func openWomenTree() {
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
                showNoNode = true
                return
            }
            women = visible
            // بعد خروج نافذة التنبيه
            DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.panelOutDuration) { node = found }
        }
    }
}

extension View {
    /// تنبيه «شجرة العائلة للرجال فقط» وانتقال لـ«إضافة بنت» في شجرة النساء تحت `father`
    func familyTreeMenOnly(isPresented: Binding<Bool>, father: FamilyMember, typedName: String,
                           onWomenTreeClosed: @escaping () -> Void = {}) -> some View {
        modifier(FamilyTreeMenOnlyGate(isPresented: isPresented, father: father, typedName: typedName,
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
