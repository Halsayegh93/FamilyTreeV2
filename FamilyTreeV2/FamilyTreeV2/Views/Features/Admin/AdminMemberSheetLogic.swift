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

    /// يُضغط «التالي»/«السابق»؟ — لا في طرفي القائمة ولا بلا شريط، ولا أثناء أمر جارٍ (F4، V27: نتيجته تخصّ هذا العضو)
    static func canStep(next: Bool, position: Int, count: Int, busy: Bool = false) -> Bool {
        guard !busy, showsStepBar(count: count), position >= 0, position < count else { return false }
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

    // MARK: - «أ3 ملف موجز وأفعال» (الوحدة V2-3، اختيار المالك ٢٠٢٦-١١-٢٦)
    //   xcrun swiftc -o /private/tmp/claude-501/v2c-logic \
    //     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminMemberSheetLogic.swift tests/admin-redesign/V2c/main.swift \
    //     && /private/tmp/claude-501/v2c-logic

    /// أزرار الرأس الكحلي بترتيبها من الطرف البادئ
    enum HeaderAction: String, CaseIterable, Equatable {
        case fullProfile, tree, call, whatsapp
    }

    /// أزرار الرأس (حتى أربعة): «الملف الكامل» لمن يعدّل · «في الشجرة» لمن له عقدة في شجرة العائلة (لا مخفي ولا موقوف
    /// ولا ابن بنت — `isCountable`) · «اتصال» و«واتساب» للحيّ برقم ظاهر لهذا المشاهد فقط (`dsVisiblePhone`) — يُحذفان
    /// حين لا رقم، لا يُعتّمان أبداً
    static func headerActions(canEdit: Bool, inTree: Bool, isDeceased: Bool, visiblePhone: String?) -> [HeaderAction] {
        var list: [HeaderAction] = []
        if canEdit { list.append(.fullProfile) }
        if inTree { list.append(.tree) }
        if !isDeceased && canContact(visiblePhone) { list += [.call, .whatsapp] }
        return list
    }

    /// أعمدة صفّ الأزرار: أربعة دائماً (الأقل يبدأ من الطرف البادئ بعرض الربع)، وشبكة ٢×٢ من أحجام إمكانية الوصول
    static func actionColumns(accessibilitySize: Bool) -> Int {
        accessibilitySize ? 2 : 4
    }

    /// فهارس الأزرار صفاً صفاً (`actionColumns` في كل صفّ، والأخير قد ينقص)
    static func actionRows(count: Int, accessibilitySize: Bool) -> [[Int]] {
        guard count > 0 else { return [] }
        let columns = actionColumns(accessibilitySize: accessibilitySize)
        return stride(from: 0, to: count, by: columns).map { Array($0..<min($0 + columns, count)) }
    }

    /// رقاقات «أكمل الناقص» — نفس `rawValue` في `AdminMemberGap` و`AdminMemberProblem`
    enum Missing: String, CaseIterable, Equatable {
        case noBirth, noGender, noPhoto, deathIncomplete
        case orphan, noName, brokenParent, hidden, dupPhone
    }

    /// رقاقة لكل ناقص تحت الرأس: لمن يعدّل فقط، النواقص ثم مشكلات الشجرة بلا تكرار. «الصورة ناقصة» بلا رقاقة — بيتها صفّ
    /// «الصورة» (بلا صورة + «نبّهه يضيف صورة» + سهمه). فارغة = لا شيء تحت الرأس
    static func missingChips(gaps: [Missing], problems: [Missing], canEdit: Bool) -> [Missing] {
        guard canEdit else { return [] }
        var seen = Set<Missing>()
        return (gaps + problems).filter { $0 != .noPhoto && seen.insert($0).inserted }
    }

    /// قيمة الصفوف بالاسم الأول فقط (الاسم الكامل مرة واحدة في الرأس): الاسم الأول المحفوظ، وإلا أول كلمة من الكامل؛
    /// nil = بلا اسم («بدون اسم» اسم مؤقت لا اسم)
    static func firstName(_ first: String?, full: String?) -> String? {
        let placeholder = "بدون اسم"
        if let first = first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty, first != placeholder {
            return first
        }
        let whole = full?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !whole.isEmpty, whole != placeholder else { return nil }
        return whole.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    /// سطر «الأبناء»: أول أربعة أسماء أولى بفاصلة عربية، و«…» إن زادوا. nil بلا أبناء (الرقم ٠ يكفي)
    static func childrenLine(_ firstNames: [String], limit: Int = 4) -> String? {
        let names = firstNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        return names.prefix(limit).joined(separator: "، ") + (names.count > limit ? "…" : "")
    }

    // MARK: قفل ورقتك وورقة المالك

    /// العضو «غيرك»: لا المالك ولا أنت — وحده يقبل الإيقاف ومنع الرقم والحذف
    static func isOther(memberId: UUID, viewerId: UUID?, memberIsOwner: Bool) -> Bool {
        !memberIsOwner && memberId != viewerId
    }

    /// أوامر «الحساب» الثلاثة الخطرة: الصلاحية × «غيرك» (والمنع برقم صالح للملء فقط)
    struct AccountCommands: Equatable {
        let suspend: Bool
        let ban: Bool
        let delete: Bool
    }

    static func accountCommands(isOther: Bool, canFreeze: Bool, canBan: Bool, banPrefill: String?,
                                canDelete: Bool) -> AccountCommands {
        AccountCommands(suspend: canFreeze && isOther,
                        ban: canBan && isOther && banPrefill != nil,
                        delete: canDelete && isOther)
    }

    /// سطر القفل آخر الورقة: لماذا لا إيقاف ولا منع ولا حذف هنا
    enum LockNote: Equatable {
        /// «هذا حسابك، وأنت المالك: …»
        case selfOwner
        /// «هذا حسابك: …»
        case selfAccount
        /// «حساب المالك: …» (مالك آخر)
        case ownerAccount
    }

    // MARK: «في الشجرة» (F4، V33)

    /// العضو يُرسم في شجرة العائلة: سلسلة آبائه تصل إلى الرأس الأول وكلهم مرسومون (لا مخفي ولا موقوف ولا ابن بنت) —
    /// اليتيم وجذر ثانٍ ومن تحت أب مخفي لا «في الشجرة» (كان الضغط يطوي الشجرة على لا شيء). حلقة الآباء لا تعلّق
    static func reachable(_ id: UUID, root: UUID?, father: (UUID) -> UUID?, drawable: (UUID) -> Bool,
                          limit: Int = 300) -> Bool {
        guard let root else { return false }
        var current = id
        for _ in 0..<limit {
            guard drawable(current) else { return false }
            if current == root { return true }
            guard let next = father(current) else { return false }
            current = next
        }
        return false
    }

    // MARK: «إجراءات الإدارة» (F4 القسم A — «اهم شي نفصل الأمور الادارية عن الاعضاء»)

    /// أوامر الإدارة بترتيب بطاقتها، والحذف آخرها
    enum AdminItem: String, CaseIterable, Equatable {
        /// V3: «رقم الهاتف» (تعديل الرقم أو مسحه) — نُقل من «العضو» إلى هنا، أول البطاقة
        case phone
        /// «نبّهه يضيف صورة» / السطر المعلّق بـ«ذكّره الحين» و«إلغاء التنبيه» / «طلب تغيير الصورة»
        case photo
        /// «تسجيل في التطبيق»
        case register
        /// الأجهزة بـ«تسجيل خروج»
        case devices
        /// «إيقاف الحساب» / «رفع الإيقاف»
        case suspend
        /// «منع الرقم من التسجيل»
        case ban
        /// «حذف العضو نهائياً» — أحمر، آخر البطاقة
        case delete
    }

    struct AdminCard: Equatable {
        let items: [AdminItem]
    }

    /// بطاقة «إجراءات الإدارة» تحت معلومات العضو — nil = لا بطاقة: على ورقتك (يبقى سطر القفل)، أو لا أمر لك هنا.
    /// للمتوفى: طلب الصورة المفتوح (لإلغائه) والحذف فقط. V3: `phone` = صفّ «رقم الهاتف» أولاً (للحيّ)، و`requests` =
    /// شريط «طلبات عنه» يرسم البطاقة ولو بلا أمر
    static func adminCard(isSelf: Bool, living: Bool, photo: Bool, register: Bool, devices: Bool,
                          commands: AccountCommands, phone: Bool = false, requests: Bool = false) -> AdminCard? {
        guard !isSelf else { return nil }
        var items: [AdminItem] = []
        if living && phone { items.append(.phone) }
        if photo { items.append(.photo) }
        if living {
            if register { items.append(.register) }
            if devices { items.append(.devices) }
            if commands.suspend { items.append(.suspend) }
            if commands.ban { items.append(.ban) }
        }
        if commands.delete { items.append(.delete) }
        return items.isEmpty && !requests ? nil : AdminCard(items: items)
    }

    /// للحيّ فقط، ولمن يملك أمراً من أوامر الورقة (يعدّل أو يوقف أو يمنع أو يحذف) — غيره لا يحتاج شرحاً
    static func lockNote(memberId: UUID, viewerId: UUID?, memberIsOwner: Bool, isDeceased: Bool,
                         viewerCanAct: Bool) -> LockNote? {
        guard viewerCanAct, !isDeceased else { return nil }
        if memberId == viewerId { return memberIsOwner ? .selfOwner : .selfAccount }
        return memberIsOwner ? .ownerAccount : nil
    }
}
