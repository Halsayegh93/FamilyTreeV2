import Foundation

// MARK: - تصفية الألفاظ المسيئة قبل النشر (Guideline 1.2)
//
// الأخبار والمكتبة والمشاريع والديوانيات تمرّ بموافقة الإدارة قبل ظهورها،
// أما التعليقات فتُنشر فوراً — فتُفحص هنا أولاً ويُمنع إرسال التعليق الذي يحوي
// ألفاظاً بذيئة أو شتائم صريحة. القائمة محافظة عمداً (كلمات كاملة فقط) حتى لا
// تمنع كلاماً عادياً؛ البلاغ والحظر ومراجعة الإدارة تبقى خط الحماية الأساسي.

enum ObjectionableContentFilter {

    /// هل يحوي النص لفظاً مسيئاً صريحاً؟
    static func containsObjectionable(_ text: String) -> Bool {
        let normalized = ArabicTextNormalizer.normalizeForSearch(text)
            .replacingOccurrences(of: "\u{0640}", with: "")   // التطويل «ـ»
        let words = normalized.split { !$0.isLetter }.map(String.init)
        guard !words.isEmpty else { return false }

        for word in words {
            if blockedWords.contains(word) { return true }
            // «الـ» و«و» و«يا» الملتصقة بالكلمة (مثل: والشرموطه، ياعرص)
            for prefix in attachedPrefixes where word.hasPrefix(prefix) {
                let stem = String(word.dropFirst(prefix.count))
                if stem.count >= 3, blockedWords.contains(stem) { return true }
            }
        }

        let joined = " " + words.joined(separator: " ") + " "
        return blockedPhrases.contains { joined.contains(" \($0) ") }
    }

    // MARK: - القوائم (بعد التطبيع: بلا تشكيل، ة→ه، أ/إ/آ→ا، ى→ي، أحرف صغيرة)

    private static let attachedPrefixes = ["وال", "بال", "فال", "لل", "ال", "يا", "و"]

    private static let blockedWords: Set<String> = [
        // عربي
        "كس", "كسمك", "كسامك", "كسخت", "كسختك",
        "زب", "زبي", "زبك",
        "طيز", "طيزك", "طيزي",
        "نيك", "ينيك", "انيك", "نيكه", "منيك", "نياك",
        "منيوك", "منيوكه", "متناك", "متناكه",
        "شرموط", "شرموطه", "شراميط",
        "قحبه", "قحاب", "قحبات",
        "عاهره", "عواهر",
        "عرص", "معرص", "معرصه",   // لا «عرصه»: العرصة = الساحة (كلمة عادية)
        "ديوث",
        // English
        "fuck", "fucking", "fucker", "fucked", "motherfucker",
        "shit", "bullshit", "bitch", "bitches", "bastard", "asshole", "dickhead",
        "cunt", "pussy", "whore", "slut", "nigger", "nigga", "faggot", "retard"
    ]

    private static let blockedPhrases: [String] = [
        "كس امك", "كس اختك",
        "ابن الكلب", "ابن كلب", "بنت الكلب", "ولد الكلب", "يا كلب",
        "يلعن ابوك", "يلعن امك", "يلعن دينك", "يلعن ابو"
    ]
}
