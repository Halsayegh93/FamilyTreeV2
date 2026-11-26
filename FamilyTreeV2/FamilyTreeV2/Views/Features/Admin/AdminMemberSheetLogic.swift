import Foundation

// MARK: - منطق ورقة العضو البحت (إعادة تصميم الإدارة ٢٠٢٦-١١-٢٦، الوحدة U13)
//
// Foundation فقط — يُفحص بلا محاكي:
//   xcrun swiftc -o /private/tmp/claude-501/u13-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMemberSheetLogic.swift tests/admin-redesign/U13/main.swift \
//     && /private/tmp/claude-501/u13-logic
// ما هنا: موضع الورقة في قائمتها وشريط «السابق · 3 من 123 · التالي» (يختفي بلا قائمة)، والرقم الذي يُملأ في صفحة
// «التسجيل والمنع» (spec C.10/T4: مطبَّع، لا رقم مخفي أبداً، ولا يُرسل وحده — الإرسال بيد المالك في تلك الصفحة).

nonisolated enum AdminMemberSheetLogic {
    /// بداية الورقة داخل قائمتها — فهرس خارج المدى يُقصّ (قائمة فارغة = ٠)
    static func clampedStart(_ start: Int, count: Int) -> Int {
        min(max(0, start), max(0, count - 1))
    }

    /// شريط «السابق · 3 من 123 · التالي» فقط حين فُتحت الورقة من قائمة: معرّف واحد (البحث، إشعار، مربّع طلب) = بلا شريط
    static func showsStepBar(count: Int) -> Bool {
        count > 1
    }

    /// يُضغط «التالي»/«السابق»؟ — لا في طرفي القائمة ولا بلا شريط
    static func canStep(next: Bool, position: Int, count: Int) -> Bool {
        guard showsStepBar(count: count), position >= 0, position < count else { return false }
        return next ? position < count - 1 : position > 0
    }

    /// الموضع بعد الضغط (يبقى مكانه في الطرف)
    static func stepped(next: Bool, position: Int, count: Int) -> Int {
        guard canStep(next: next, position: position, count: count) else { return position }
        return position + (next ? 1 : -1)
    }

    /// «3 من 123»: الأول = الموضع + ١
    static func counter(position: Int, count: Int) -> (current: Int, total: Int) {
        (clampedStart(position, count: count) + 1, max(count, 0))
    }

    /// رقم وصل مخفياً من السيرفر («+965 •••• 4417»، «*****1234») أو فيه حروف — لا يصلح للاتصال ولا للمنع.
    /// المسموح: الأرقام (لاتينية وعربية) و«+» والمسافة والشرطة والقوسان وعلامات الاتجاه
    static func isMasked(_ raw: String) -> Bool {
        let allowed: Set<Character> = ["+", " ", "-", "(", ")", "\u{200E}", "\u{200F}", "\u{202A}", "\u{202C}", "\u{2066}", "\u{2069}"]
        return raw.contains { !($0.isNumber || allowed.contains($0)) }
    }

    /// الرقم الذي يُملأ في صفحة «التسجيل والمنع» من صفّ «منع الرقم من التسجيل»: nil للفارغ أو المخفي أو ما لا يصير رقماً
    /// صالحاً. `normalize` = `KuwaitPhone.normalizedForStorage` بعد `detectCountryAndLocal` (في التطبيق) — ٨ أرقام كويتية
    /// أو «+رمز…». لا يُرسل شيء من هنا: الصفحة تفتح مربّع المنع مملوءاً والمالك يضغط «منع»
    static func banPrefill(_ raw: String?, normalize: (String) -> String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isMasked(trimmed), trimmed.contains(where: \.isNumber) else { return nil }
        guard let out = normalize(trimmed)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !out.isEmpty, !isMasked(out) else { return nil }
        return out
    }

    /// يُعرض «اتصال»/«واتساب»؟ — رقم ظاهر لهذا المشاهد وغير مخفي من السيرفر
    static func canContact(_ visiblePhone: String?) -> Bool {
        guard let phone = visiblePhone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty else { return false }
        return !isMasked(phone) && phone.contains(where: \.isNumber)
    }
}
