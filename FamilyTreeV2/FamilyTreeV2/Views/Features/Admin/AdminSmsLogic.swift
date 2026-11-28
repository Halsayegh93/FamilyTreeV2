import Foundation

// MARK: - منطق «طلبات رمز الدخول» و«رسائل رمز الدخول» الخالص (طلبا المالك ٢٠٢٦-١١-٢٧، الوحدة S1)
//
// ١) «محاولة مريبة — شنو اسوي؟»: على كل رقم مريب في `SmsAttemptsListPage` (وأعلى الصفحة) سطر يقول المعنى، و«لمن الرقم؟»
//    (`find_profiles_by_phone` + اسم الشجرة، وحساب الدخول من `last_sign_in_at` في `sms_login_attempts`)، وأزرار ظاهرة:
//    «اتصال» · «امنع الرقم من التسجيل» (نداء صفحة «التسجيل والمنع» نفسه `authVM.banPhone`) · «تم الاطلاع» (قراءة تنبيهات
//    `sms_suspicious` لهذا الرقم — نصّ التنبيه ينتهي بالرقم: كاملاً للمالك «+965 99887766»، مخفياً للمدير «+965 9988••66»؛
//    تنبيه «تقفل رقم» بلا رقم يُقرأ مع «تم الاطلاع على الكل»).
// ٢) صفحة «رسائل رمز الدخول (KWT SMS)» بشكل الإدارة v2 «أ»: الأقسام بترتيبها، الأدوات لكل دور، قفل الإعدادات، حلقة الرصيد.
//
// يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/s1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminSmsLogic.swift tests/admin-redesign/S1/main.swift \
//     && /private/tmp/claude-501/s1-logic

nonisolated enum SmsSuspiciousLogic {

    // MARK: النصوص

    /// سطر المعنى على كل رقم مريب
    static var meaningLine: String {
        L10n.t("طلب هذا الرقم رمز الدخول 5 مرات أو أكثر خلال ساعة",
               "This number asked for a sign-in code 5 or more times within an hour")
    }

    /// سطر المعنى أعلى الصفحة
    static var pageMeaning: String {
        L10n.t("الرقم المريب: طلب رمز الدخول 5 مرات أو أكثر خلال ساعة.",
               "A suspicious number asked for a sign-in code 5 or more times within an hour.")
    }

    /// ماذا يفعل المالك — تحت سطر المعنى أعلى الصفحة
    static var pageAdvice: String {
        L10n.t("لكل رقم تحت: اعرف لمن هو، ثم اتصل به أو امنعه من التسجيل، أو اضغط «تم الاطلاع».",
               "For each number below: see whose it is, then call or block it, or tap “Seen”.")
    }

    /// «تنبيه جديد» · «تنبيهان جديدان» · «3 تنبيهات جديدة» · «11 تنبيهاً جديداً» · «100 تنبيه جديد»
    static func unreadWord(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "1 new alert" : "\(AdminNumberText.grouped(n)) new alerts" }
        return AdminCountForms(one: "تنبيه جديد", two: "تنبيهان جديدان", few: "تنبيهات جديدة",
                               many: "تنبيهاً جديداً", single: "تنبيه جديد").text(n)
    }

    // MARK: ربط التنبيه برقمه

    /// رقم كويتي ٨ خانات: أول ٤ وآخر ٢ (ما يبقى ظاهراً في المخفي)، والكامل إن عُرف
    struct PhoneKey: Hashable {
        let first4: String
        let last2: String
        let full: String?
    }

    /// آخر النصّ: «+965 99887766» (المالك) أو «+965 9988••66» (المدير) — تنبيه «تقفل رقم» بلا رقم = nil
    static func key(noticeBody body: String) -> PhoneKey? {
        tailKey(body)
    }

    /// صفّ المحاولة: من `phone_e164` (المالك) وإلا من الرقم الظاهر (المخفي للمدير)
    static func key(phoneE164: String?, shown: String) -> PhoneKey? {
        if let e164 = phoneE164 {
            let digits = e164.filter(\.isASCIIDigitChar)
            if digits.count == 11, digits.hasPrefix("965") { return fullKey(String(digits.dropFirst(3))) }
        }
        return tailKey(shown)
    }

    /// الكاملان يتطابقان بالكامل؛ وإن كان أحدهما مخفياً فبالظاهر منه
    static func sameNumber(_ a: PhoneKey, _ b: PhoneKey) -> Bool {
        if let fa = a.full, let fb = b.full { return fa == fb }
        return a.first4 == b.first4 && a.last2 == b.last2
    }

    /// تنبيه «محاولات دخول مريبة» واحد كما يقرؤه المنطق
    struct Notice: Hashable {
        let id: UUID
        let body: String
        let read: Bool
    }

    /// غير المقروء من تنبيهات هذا الرقم — «تم الاطلاع» على صفّه
    static func relatedUnreadIds(_ notices: [Notice], phoneE164: String?, shown: String) -> Set<UUID> {
        guard let mine = key(phoneE164: phoneE164, shown: shown) else { return [] }
        return Set(notices.filter { n in
            guard !n.read, let theirs = key(noticeBody: n.body) else { return false }
            return sameNumber(mine, theirs)
        }.map(\.id))
    }

    /// كل غير المقروء — «تم الاطلاع على الكل» (ومعه تنبيه «تقفل رقم» الذي لا رقم فيه)
    static func unreadIds(_ notices: [Notice]) -> Set<UUID> {
        Set(notices.filter { !$0.read }.map(\.id))
    }

    private static func fullKey(_ local8: String) -> PhoneKey? {
        guard local8.count == 8, local8.allSatisfy(\.isASCIIDigitChar) else { return nil }
        return PhoneKey(first4: String(local8.prefix(4)), last2: String(local8.suffix(2)), full: local8)
    }

    /// يقرأ آخر النص بعد «+965»: ٨ خانات، أو ٤ خانات «••» خانتان
    private static func tailKey(_ text: String) -> PhoneKey? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "+965", options: .backwards) else { return nil }
        let tail = trimmed[range.upperBound...].filter { !$0.isWhitespace && !$0.isBidiMark }
        if let full = fullKey(String(tail)) { return full }
        let parts = tail.components(separatedBy: "••")
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
              (parts[0] + parts[1]).allSatisfy(\.isASCIIDigitChar) else { return nil }
        return PhoneKey(first4: parts[0], last2: parts[1], full: nil)
    }

    // MARK: لمن الرقم؟

    /// ملف يحمل الرقم (`find_profiles_by_phone`: المعرّف والدور والحالة) واسمه من الشجرة
    struct Match: Hashable {
        let id: UUID
        let role: String?
        let status: String?
        let name: String?

        var hasName: Bool { !(name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// حال صاحب الرقم بالمسمّيات الرسمية
    enum Standing: Equatable { case registered, noAccount, pendingJoin, frozen }

    enum Owner: Equatable {
        /// `others` = ملفات أخرى بنفس الرقم
        case member(name: String, standing: Standing, others: Int)
        /// حساب دخول بلا ملف، أو ملف بلا اسم — لم يكمل التسجيل
        case namelessAccount
        /// لا ملف ولا حساب
        case nobody
    }

    /// - matches: نتيجة البحث بالرقم
    /// - attemptProfile: ملف المحاولة نفسها (`sms_login_attempts.profile_id`) — يُضاف إن لم يكن بين النتائج
    /// - hasAccount: للرقم حساب دخول دخل به (`last_sign_in_at`)
    static func owner(matches: [Match], attemptProfile: Match?, hasAccount: Bool) -> Owner {
        var all = matches
        if let extra = attemptProfile, !all.contains(where: { $0.id == extra.id }) { all.append(extra) }
        guard !all.isEmpty else { return hasAccount ? .namelessAccount : .nobody }
        let ordered = all.filter(\.hasName).sorted { rank($0) < rank($1) }
        guard let best = ordered.first, let name = best.name?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .namelessAccount
        }
        let standing: Standing
        if best.status == "frozen" {
            standing = .frozen
        } else if best.role == "pending" {
            standing = .pendingJoin
        } else {
            standing = hasAccount ? .registered : .noAccount
        }
        return .member(name: name, standing: standing, others: all.count - 1)
    }

    /// الملف المفعّل قبل المعلّق والموقوف (الترتيب الثابت لما سواه)
    private static func rank(_ m: Match) -> Int {
        if m.status == "frozen" { return 2 }
        if m.role == "pending" { return 1 }
        return 0
    }

    static func standingText(_ s: Standing) -> String {
        switch s {
        case .registered:  return L10n.t("عضو مسجّل", "Registered member")
        case .noAccount:   return L10n.t("بلا حساب", "No account")
        case .pendingJoin: return L10n.t("طلب انضمام قيد المراجعة", "Join request under review")
        case .frozen:      return L10n.t("حساب موقوف", "Stopped account")
        }
    }

    /// السطر الأول: الاسم، أو الحالة حين لا اسم
    static func ownerTitle(_ o: Owner) -> String {
        switch o {
        case .member(let name, _, _): return name
        case .namelessAccount:        return L10n.t("حساب بلا اسم — لم يكمل التسجيل", "Account without a name — sign-up not finished")
        case .nobody:                 return L10n.t("ليس رقماً لأحد في العائلة", "Not anyone's number in the family")
        }
    }

    /// السطر الثاني للعضو: حاله (+ من يشاركه الرقم)
    static func ownerDetail(_ o: Owner) -> String? {
        guard case .member(_, let standing, let others) = o else { return nil }
        let base = standingText(standing)
        guard others > 0 else { return base }
        let more: String
        if L10n.isArabic {
            let forms = AdminCountForms(one: "وعضو آخر بنفس الرقم", two: "وعضوان آخران بنفس الرقم",
                                        few: "أعضاء آخرون بنفس الرقم", many: "عضواً آخر بنفس الرقم",
                                        single: "عضو آخر بنفس الرقم")
            more = others <= 2 ? forms.text(others) : "و" + forms.text(others)
        } else {
            more = others == 1 ? "and 1 other with this number" : "and \(others) others with this number"
        }
        return "\(base) · \(more)"
    }

    /// رقم أحد المالكين — لا يُعرض منعه أبداً
    static func isOwnersNumber(matches: [Match]) -> Bool {
        matches.contains { $0.role == "owner" }
    }

    // MARK: الأزرار

    /// «تم الاطلاع»: زرّ بعدد تنبيهات الرقم غير المقروءة، أو حال «تم الاطلاع ✓»
    enum SeenState: Equatable { case button(count: Int), done }
    /// «امنع الرقم من التسجيل»: مخفي، متاح، أو «ممنوع من التسجيل» من قبل
    enum BanState: Equatable { case hidden, available, alreadyBanned }

    struct Actions: Equatable {
        var call: Bool
        var ban: BanState
        var seen: SeenState
    }

    /// - phoneE164: الرقم كاملاً (المالك) — بلا رقم لا اتصال ولا منع
    /// - canCall: للرقم رابط اتصال
    /// - canBan: `canManageBannedPhones` × «يعدّل» في الجدول
    static func actions(phoneE164: String?, canCall: Bool, canBan: Bool, isBanned: Bool, ownersNumber: Bool,
                        relatedUnread: Int) -> Actions {
        let hasNumber = phoneE164 != nil
        let ban: BanState
        if !hasNumber || !canBan || ownersNumber {
            ban = .hidden
        } else {
            ban = isBanned ? .alreadyBanned : .available
        }
        return Actions(call: hasNumber && canCall, ban: ban,
                       seen: relatedUnread > 0 ? .button(count: relatedUnread) : .done)
    }

    // MARK: أعلى الصفحة

    enum Banner: Equatable {
        case none
        /// اطّلع على كل التنبيهات، وفي الفترة أرقام مريبة
        case quiet(suspicious: Int)
        /// تنبيهات لم تُقرأ — «تم الاطلاع على الكل»
        case unread(Int)
    }

    static func banner(unread: Int, suspiciousInPeriod: Int) -> Banner {
        if unread > 0 { return .unread(unread) }
        return suspiciousInPeriod > 0 ? .quiet(suspicious: suspiciousInPeriod) : .none
    }

    // MARK: تأكيد المنع

    /// ما سيحدث بالضبط (المنع يوقف حساب من يحمل الرقم — `freeze_member_on_ban`)، وأين يُرفع
    static func banMessage(phone: String, owner: Owner?) -> String {
        let base = L10n.t("لن يستطيع صاحب الرقم \(phone) التسجيل أو الدخول إلى التطبيق. ترفع المنع متى شئت من «التسجيل والمنع».",
                          "The owner of \(phone) won't be able to sign up or sign in. You can lift it any time in “Sign-up and blocking”.")
        guard case .member(let name, _, _)? = owner else { return base }
        return L10n.t("هذا رقم \(name)، ويُوقَف حسابه أيضاً. ", "This is \(name)'s number; their account is stopped too. ") + base
    }

    /// السبب المحفوظ مع المنع (يظهر تحت الرقم في «الأرقام الممنوعة من التسجيل»)
    static var banReason: String { L10n.t("محاولات دخول مريبة", "Suspicious sign-in attempts") }
}

// MARK: - صفحة «رسائل رمز الدخول» v2

nonisolated enum SmsPageLogic {
    /// أقسام الصفحة بترتيبها (طلب المالك ٢٠٢٦-١١-٢٧ «ما عدلت اعدادات رسائل sms»)
    enum Section: String, CaseIterable {
        /// اليوم · 7 أيام · 30 يوماً + هذه الساعة
        case sending
        /// رسم آخر ٣٠ يوماً
        case trend
        /// آخر الإرسالات
        case recent
        /// إعدادات الإرسال (المكان الوحيد)
        case settings
        /// حماية رسائل الدخول
        case protection
        /// تنبيهات الرصيد
        case alerts
        /// الأدوات
        case tools
        /// صفّ «طلبات رمز الدخول»
        case attempts
        /// «طريقة العمل» مطويّة
        case how
    }

    /// لغير المالك لا أقسام (بطاقة القفل)؛ بلا النظرة ينتظر الرسم وآخر الإرسالات وتبقى البقية بقيمها المحفوظة
    static func sections(canView: Bool, hasOverview: Bool) -> [Section] {
        guard canView else { return [] }
        return Section.allCases.filter { hasOverview || ($0 != .trend && $0 != .recent) }
    }

    enum Tool: String { case testSend, validate }

    /// الرسالة التجريبية للمالك وحده (`test_send`)، والتحقق من رقم للجميع
    static func tools(isOwner: Bool) -> [Tool] {
        isOwner ? [.testSend, .validate] : [.validate]
    }

    /// الحدود تُعدَّل بعد معرفة القيم الحالية فقط، وعلى سيرفر فيه أعمدتها، وللمالك
    static func settingsEditable(canManageSettings: Bool, limitsEditable: Bool?) -> Bool {
        canManageSettings && limitsEditable == true
    }

    /// مرجع حلقة الرصيد («من 100»)
    static let gaugeReference: Double = 100

    /// الحلقة: الرصيد من ١٠٠، بين ٠ و١ — nil = لا قراءة
    static func gaugeProgress(balance: Double?) -> Double? {
        balance.map { min(1, max(0, $0 / gaugeReference)) }
    }

    /// حبّة صفّ «طلبات رمز الدخول»: «2 جديدة» حين توجد تنبيهات مريبة لم تُقرأ
    static func attemptsValue(unread: Int) -> String? {
        guard unread > 0 else { return nil }
        return L10n.t("\(AdminNumberText.grouped(unread)) جديدة", "\(AdminNumberText.grouped(unread)) new")
    }
}

private extension Character {
    nonisolated var isASCIIDigitChar: Bool { ("0"..."9").contains(self) }
    /// علامات اتجاه النص (العزل والتضمين) التي قد تحيط بالرقم في سطر عربي
    nonisolated var isBidiMark: Bool {
        unicodeScalars.allSatisfy { (0x2066...0x2069).contains($0.value) || (0x200E...0x200F).contains($0.value)
            || (0x202A...0x202E).contains($0.value) }
    }
}
