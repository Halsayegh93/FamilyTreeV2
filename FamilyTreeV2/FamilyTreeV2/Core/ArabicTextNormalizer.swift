import Foundation

// MARK: - ArabicTextNormalizer
// تطبيع النص العربي للبحث — إزالة التشكيل والتطويل والمحارف الخفية، توحيد الهمزات، تطبيع التاء المربوطة.
// المكان الواحد لكل مقارنة أسماء: البحث (`NameSearch` ← كل منتقيات الأشخاص)، و«اسم بنت» (`FamilyTreeMenOnly`)
// عبر `normalizeLetters`. فحصه: `tests/admin-redesign/M1` (و`G1`).

enum ArabicTextNormalizer {

    // MARK: - Public API

    /// تطبيع شامل للبحث: إزالة تشكيل + توحيد همزات + تطبيع تاء + حروف صغيرة
    static func normalizeForSearch(_ text: String) -> String {
        var result = text

        // 1. إزالة التشكيل (الحركات)
        result = removeTashkeel(result)

        // 2. توحيد أشكال الألف والهمزة
        result = normalizeHamza(result)

        // 3. تطبيع التاء المربوطة
        result = normalizeTaaMarbuta(result)

        // 4. توحيد الياء
        result = normalizeYaa(result)

        // 5. حروف صغيرة + إزالة diacritics للحروف اللاتينية
        result = result
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        return result
    }

    /// توحيد الحروف بلا تغيير حالة الأحرف اللاتينية: بلا تشكيل ولا تطويل ولا محارف خفية، أ/إ/آ/ٱ ← ا، ى ← ي،
    /// و«ة» في آخر الكلمة ← «ه» («سهيلة» = «سهيله»). المسافات تبقى كما هي
    static func normalizeLetters(_ text: String) -> String {
        let base = normalizeYaa(normalizeHamza(removeTashkeel(text)))
        guard base.contains("\u{0629}") else { return base }
        var chars = Array(base)
        for i in chars.indices where chars[i] == "\u{0629}" {
            let next: Character = i + 1 < chars.count ? chars[i + 1] : " "
            if !(next.isLetter || next.isNumber) { chars[i] = "\u{0647}" }
        }
        return String(chars)
    }

    // MARK: - Individual Normalizations

    /// إزالة التشكيل (الفتحة، الضمة، الكسرة، السكون، الشدة، التنوين) والتطويل والمحارف الخفية
    /// النطاق: U+064B–U+065F + U+0670 (ألف خنجرية) + U+0640 (تطويل «ـ») + U+06D6–U+06ED (علامات المصحف)
    /// + U+200B–U+200F و U+FEFF (محارف الاتجاه والعرض الصفري — تأتي ملتصقة بالأسماء المنسوخة)
    static func removeTashkeel(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0640, 0x064B...0x065F, 0x0670, 0x06D6...0x06ED, 0x200B...0x200F, 0xFEFF: continue
            default: out.append(scalar)
            }
        }
        return String(out)
    }

    /// توحيد الهمزات: أ إ آ ٱ → ا
    static func normalizeHamza(_ text: String) -> String {
        var result = text
        // أ (ألف مع همزة فوق) U+0623
        result = result.replacingOccurrences(of: "\u{0623}", with: "\u{0627}")
        // إ (ألف مع همزة تحت) U+0625
        result = result.replacingOccurrences(of: "\u{0625}", with: "\u{0627}")
        // آ (ألف مع مدة) U+0622
        result = result.replacingOccurrences(of: "\u{0622}", with: "\u{0627}")
        // ٱ (ألف وصلة) U+0671
        result = result.replacingOccurrences(of: "\u{0671}", with: "\u{0627}")
        return result
    }

    /// تطبيع التاء المربوطة: ة → ه
    static func normalizeTaaMarbuta(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{0629}", with: "\u{0647}")
    }

    /// توحيد الياء: ى (ألف مقصورة) → ي
    static func normalizeYaa(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{0649}", with: "\u{064A}")
    }
}
