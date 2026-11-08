import Foundation

/// ملاحظات كل إصدار — تُعبّأ تلقائياً في شاشة «تحديثات التطبيق» عند النشر،
/// فيصل الأعضاء في «المستجدات» وصفاً لما تغيّر في التطبيق (طلب المالك).
/// المفتاح = رقم البناء (CFBundleVersion). أضف مدخلاً جديداً مع كل إصدار.
enum AppReleaseNotes {
    static let byBuild: [String: (ar: String, en: String)] = [
        "50": (
            ar: """
            • إضافة الأبناء أسهل، وتذكير لطيف بإضافة صورتك.
            • ربط حسابك بالشجرة أوضح، مع إصلاح ظهور الاقتراحات.
            • رمز الدخول: تركيز تلقائي ورسائل أوضح عند ضعف الاتصال.
            • «ذكرى الراحلين» ومجلدات في مكتبة العائلة.
            • تصميم إعلانات المناسبات أسهل، بنماذج تتحدّث من السيرفر.
            • تحسينات وإصلاحات في الإشعارات والشاشات.
            """,
            en: """
            • Adding children is easier, with a gentle reminder to add your photo.
            • Linking your account to the tree is clearer, and suggestions show again.
            • Login code: automatic focus and clearer messages on weak connections.
            • «In memory» and folders in the Family Library.
            • Designing occasion announcements is easier, with templates updated from the server.
            • Improvements and fixes in notifications and screens.
            """
        ),
        "43": (
            ar: """
            • هوية ألوان جديدة رسمية (كحلي وذهبي) وأزرار بتصميم iOS 27.
            • الرئيسية: رجوع مربّعي الشجرة والديوانيات، ترحيب أوضح، وبطاقة أخبار أنعم.
            • علامة ⓘ بجانب الجرس: معلومات التطبيق ورقم الإصدار.
            • الأخبار: اسحب الخبر لليمين للحذف أو الإبلاغ، وزر إضافة مبسّط.
            • مكتبة العائلة والمشاريع: واجهة أبسط بلا تصنيفات.
            • الاسم الأخير يطابق العائلة المختارة في كل التطبيق.
            • تعديل الملف: الحفظ أعلى الشاشة، وبعد ٣ تعديلات يُرسل التعديل لموافقة الإدارة.
            • شجرة النساء: الإناث بالوردي، والمتوفّاة بوردي أغمق.
            • في كل النوافذ: الحفظ/الإضافة يميناً والإغلاق يساراً.
            """,
            en: """
            • A new formal color identity (navy & gold) with iOS 27–style buttons.
            • Home: the Tree and Diwaniyas tiles are back, a clearer greeting, and a smoother news card.
            • ⓘ next to the bell: app info and version.
            • News: swipe a post right to delete or report, and a simpler add button.
            • Family Library & Projects: simpler screens without categories.
            • Your last name now matches your chosen family everywhere.
            • Edit profile: Save is at the top; after 3 edits, changes go to the admins for approval.
            • Women's tree: women in pink, deceased in a darker pink.
            • In every sheet: Save/Add on the right, Close on the left.
            """
        ),
    ]

    static var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    static var currentVersionLabel: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return currentBuild.isEmpty ? v : "\(v) (\(currentBuild))"
    }

    /// ملاحظات الإصدار الحالي بلغة الواجهة، أو nil إن لم تُكتب بعد
    static var current: String? {
        guard let notes = byBuild[currentBuild] else { return nil }
        return L10n.isArabic ? notes.ar : notes.en
    }
}
