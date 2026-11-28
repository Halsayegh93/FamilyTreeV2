import Foundation

// MARK: - «ظهور زوج البنت من خارج العائلة وأبنائها» — للإدارة ولابن البنت (قرار المالك ٢٠٢٦-١١-٢٨، الوحدة MV1)
//
// منطق خالص (Foundation فقط) يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/mv1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Profile/MotherVisibilityLogic.swift tests/admin-redesign/MV1/main.swift && /tmp/mv1-logic
//
//  ١) الإدارة (مالك، مدير، مراقب = `women_members_update`): مفتاحا «ظهور الزوج» و«ظهور الأبناء» في تفاصيل البنت التي
//     زوجها من خارج العائلة — كتابة مباشرة لـ `spouse_shown`/`children_shown` (`WomenStore.setVisibilityAsAdmin`).
//  ٢) ابن البنت / بنت البنت صاحب الحساب، وأمّه بلا حساب: المفتاحان في «حسابي ← الخصوصية» على أمّه
//     (`set_mother_visibility`، ترحيل 20261128120000). لأمّه حساب ← هي تقرّر، فلا يظهران.

nonisolated enum MotherVisibilityLogic {
    static var adminSpouseTitle: String { L10n.t("ظهور الزوج", "Husband shown") }
    static var adminChildrenTitle: String { L10n.t("ظهور الأبناء", "Children shown") }
    static var childSpouseTitle: String { L10n.t("ظهور الوالد بجانب الوالدة", "Father shown beside mother") }
    static var childChildrenTitle: String { L10n.t("ظهور الأبناء تحت الوالدة", "Children shown under mother") }

    /// الإدارة: بنت زوجها من خارج العائلة
    static func adminShowsToggles(canEdit: Bool, isFemale: Bool, husbandId: UUID?, outsideIds: Set<UUID>) -> Bool {
        guard canEdit, isFemale, let h = husbandId else { return false }
        return outsideIds.contains(h)
    }

    /// ابن البنت / بنت البنت: أمّه في الشجرة بلا حساب، وأبوه (أو زوج أمّه) من خارج العائلة
    static func childShowsToggles(motherId: UUID?, motherHasAccount: Bool, fatherId: UUID?,
                                  motherHusbandId: UUID?, outsideIds: Set<UUID>) -> Bool {
        guard motherId != nil, !motherHasAccount else { return false }
        if let f = fatherId, outsideIds.contains(f) { return true }
        if let h = motherHusbandId, outsideIds.contains(h) { return true }
        return false
    }

    /// الأصل مخفي (null)
    static func shown(_ value: Bool?) -> Bool { value == true }

    /// رسالة الخطأ بالعربية من `hint` السيرفر
    static func errorMessage(hint: String?) -> String {
        switch hint ?? "" {
        case "mother_has_account":
            return L10n.t("للوالدة حساب في التطبيق، والاختيار لها.", "Your mother has an account — the choice is hers.")
        case "no_mother":
            return L10n.t("الوالدة غير مسجّلة في الشجرة.", "Your mother isn't in the tree.")
        case "no_node":
            return L10n.t("لا توجد لك عقدة في شجرة النساء بعد.", "You don't have a node in the women's tree yet.")
        case "not_allowed":
            return L10n.t("حسابك غير مفعّل بعد.", "Your account isn't active yet.")
        default:
            return L10n.t("تعذّر الحفظ، يرجى المحاولة مرة أخرى.", "Couldn't save, please try again.")
        }
    }
}
