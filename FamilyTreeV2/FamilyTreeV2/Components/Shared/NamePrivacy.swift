import Foundation

// MARK: - خصوصية قوائم الأسماء للعضو العادي (طلب المالك ٢٠٢٦-١١-١٤)
//
// «قوائم الأسماء اللي تظهر للعضو العادي أبيها متشددة أكثر… ما أبيها تظهر كلها، أبي يكون على الاسم اللي يكتبه
// من اسمين أو ٣ أسماء… وحتى في تسجيل البيانات الإناث». القاعدة الواحدة لكل منتقٍ وبحث يراه غير الإدارة:
// لا اسم يظهر قبل أن يُكتب عدد كافٍ من أجزاء الاسم (الافتراضي ٢)، والنتائج قليلة. الإدارة (`canModerate`) كما كانت.
// العدد من السيرفر: `app_config.member_name_search_min_parts` (٢–٥) — يتغيّر بلا بناء.

@MainActor
enum NamePrivacy {
    /// غير الإدارة (يُضبط مع `AuthViewModel.currentUser`؛ قبل الدخول — التسجيل — متشدّد)
    static var isStrict = true

    /// أقل عدد من أجزاء الاسم قبل ظهور أي نتيجة
    static var minParts: Int {
        min(5, max(2, AppConfigValues.shared.int("member_name_search_min_parts", default: 2)))
    }

    /// أقصى ما يُعرض من النتائج للعضو العادي
    static let maxResults = 10

    /// هل المكتوب محدّد بما يكفي لعرض أسماء
    static func isSpecific(_ query: String) -> Bool {
        NameSearch.words(query).count >= minParts
    }

    /// الإرشاد قبل اكتمال الاسم
    static var hint: String {
        minParts == 2
            ? L10n.t("اكتب الاسم الأول واسم الأب على الأقل", "Type at least the first name and the father's name")
            : L10n.t("اكتب \(minParts) أسماء متتالية على الأقل", "Type at least \(minParts) consecutive name parts")
    }
}
