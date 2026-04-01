import Foundation

// MARK: - ArabicTextNormalizer
// تطبيع النص العربي للبحث — إزالة التشكيل، توحيد الهمزات، تطبيع التاء المربوطة

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

    // MARK: - Individual Normalizations

    /// إزالة التشكيل (الفتحة، الضمة، الكسرة، السكون، الشدة، التنوين)
    /// النطاق: U+064B إلى U+065F + U+0670 (ألف خنجرية)
    static func removeTashkeel(_ text: String) -> String {
        text.unicodeScalars.filter { scalar in
            !(scalar.value >= 0x064B && scalar.value <= 0x065F) &&
            scalar.value != 0x0670 // ألف خنجرية
        }.map { String($0) }.joined()
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
