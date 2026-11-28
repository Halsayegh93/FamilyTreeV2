import Foundation

// MARK: - منطق «التطبيق» (إعادة التصميم ٢٠٢٦-١١-٢٦ — spec C.14، اختيار المالك «ب»، الوحدة U17)
//
// منطق خالص (Foundation فقط) يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u17-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminAppAreaLogic.swift tests/admin-redesign/U17/main.swift && /tmp/u17-logic
//
//  ١) ما يُكتب من الصفحة (`AdminAppSetting`) ومخزن كلٍّ منه: `app_settings` · `app_config` · محلي · أمر.
//  ٢) أيّ تغيير يسأل أولاً (spec A.14): تشغيل الصيانة، إيقاف إشعارات الجوال، إعادة ضبط العدّاد، استعادة الافتراضي —
//     وإطفاء الصيانة وإعادة الإشعارات بلا سؤال.
//  ٣) كلمات الحبّات («يعمل للجميع» / «متوقف للأعضاء»، «مطفأ» / «مفعّل»، «تعمل» / «موقوفة»، «اختياري» / «إجباري») —
//     تُرسم بعد وصول بياناتها فقط (`AdminStatePill(health:)`)، والفشل «تعذّر التحميل» لا كلمة هادئة (spec T1).
//  ٤) حال الحفظ (`AdminAppSaveState`): حفظ واحد في كل مرة (دوّارة صغيرة + الباقي معطّل)، والفشل يُرجع القيمة القديمة
//     ويترك سطر «لم يُحفظ. أعد المحاولة» تحت صفّه.

/// ما يُكتب من صفحة «التطبيق»: الإعدادات والأمران الأحمران
nonisolated enum AdminAppSetting: String, CaseIterable, Hashable {
    // حالة التطبيق
    case maintenance
    /// «إشعارات الجوال» = `notifications_paused` (القيمة = موقوفة)
    case pushPaused
    // ما يراه الأعضاء
    case language
    case diwaniyas
    case womenTree
    case projects
    case polls
    // قواعد الأعضاء
    case newsApproval
    /// «منع لقطة الشاشة في المكتبة» (`app_config.library_screen_protection`)
    case libraryShield
    /// «حدّ التعديلات الذاتية» — على السيرفر (`app_config.profile_edit_limit_enabled`، ترحيل 20261128160000)
    case selfEditLimit
    /// «إعادة ضبط العدّاد»
    case resetCounter
    // النظام
    /// «استعادة الإعدادات الافتراضية»
    case restoreDefaults

    /// أين يُحفظ
    enum Store: Hashable {
        /// صفّ `app_settings` (`AppSettingsViewModel.updateSetting`)
        case settings
        /// `app_config` (`set_app_config`)
        case config
        /// «حدّ التعديلات الذاتية»: `set_app_config` بقيمة bool (`ProfileEditCooldown.setLimitEnabled`)
        case editLimit
        /// أمر لا قيمة له (يسأل أولاً دائماً)
        case command
    }

    var store: Store {
        switch self {
        case .maintenance, .pushPaused, .language, .diwaniyas, .womenTree, .projects, .polls, .newsApproval:
            return .settings
        case .libraryShield:
            return .config
        case .selfEditLimit:
            return .editLimit
        case .resetCounter, .restoreDefaults:
            return .command
        }
    }

    /// مفتاح السيرفر — nil للمحلي والأوامر
    var serverKey: String? {
        switch self {
        case .maintenance:   return "maintenance_mode"
        case .pushPaused:    return "notifications_paused"
        case .language:      return "default_language"
        case .diwaniyas:     return "diwaniyas_enabled"
        case .womenTree:     return "women_tree_enabled"
        case .projects:      return "projects_enabled"
        case .polls:         return "polls_enabled"
        case .newsApproval:  return "news_requires_approval"
        case .libraryShield: return "library_screen_protection"
        case .selfEditLimit: return "profile_edit_limit_enabled"
        case .resetCounter, .restoreDefaults: return nil
        }
    }
}

/// قيمة إعداد: مفتاح أو نصّ
nonisolated enum AdminAppValue: Hashable {
    case flag(Bool)
    case text(String)

    var flag: Bool? { if case .flag(let b) = self { return b } else { return nil } }
    var text: String? { if case .text(let s) = self { return s } else { return nil } }

    /// للسجل («DRY-RUN app_settings maintenance_mode=true»)
    var logText: String {
        switch self {
        case .flag(let b): return b ? "true" : "false"
        case .text(let s): return s
        }
    }
}

nonisolated enum AdminAppLogic {
    /// نغمة الحبّة (تُترجم إلى `AdminPillTone` في الواجهة)
    enum Tone: Hashable { case ok, off, warn, error }

    /// كلمة حبّة: النص والنغمة والرمز
    struct Word: Hashable {
        var text: String
        var tone: Tone
        var icon: String? = nil
    }

    // MARK: الرأس

    /// سطر الرأس تحت «التطبيق» (spec C.14)
    static var pageSubtitle: String {
        L10n.t("للمالك فقط. أي تغيير هنا يصل لكل الأعضاء.", "Owner only. Any change here reaches every member.")
    }

    /// «الإصدار 1.0.1 (51)» — الرقمان معزولان من اليسار فلا ينقلب ترتيبهما في السطر العربي
    static func versionLine(short: String, build: String?) -> String {
        let b = build?.trimmingCharacters(in: .whitespaces) ?? ""
        let number = b.isEmpty || b == short ? short : "\(short) (\(b))"
        return L10n.t("الإصدار \u{2066}\(number)\u{2069}", "Version \(number)")
    }

    // MARK: بطاقة «حالة التطبيق»

    /// حبّة الرأس: «يعمل للجميع ✓» أو «متوقف للأعضاء»
    static func statusWord(maintenanceOn: Bool) -> Word {
        maintenanceOn
            ? Word(text: L10n.t("متوقف للأعضاء", "Stopped for members"), tone: .error, icon: "pause.fill")
            : Word(text: L10n.t("يعمل للجميع", "Running for everyone"), tone: .ok, icon: "checkmark")
    }

    /// «وضع الصيانة»: «مفعّل» / «مطفأ»
    static func maintenanceWord(on: Bool) -> Word {
        on ? Word(text: L10n.t("مفعّل", "On"), tone: .error)
           : Word(text: L10n.t("مطفأ", "Off"), tone: .off)
    }

    /// «إشعارات الجوال»: «تعمل» / «موقوفة»
    static func pushWord(paused: Bool) -> Word {
        paused ? Word(text: L10n.t("موقوفة", "Paused"), tone: .warn)
               : Word(text: L10n.t("تعمل", "On"), tone: .ok)
    }

    /// سطر «إشعارات الجوال» تحت اسمها
    static func pushLine(paused: Bool) -> String {
        paused ? L10n.t("لا تصل الجوالات، وتبقى داخل التطبيق", "Phones don't get them; they stay inside the app")
               : L10n.t("تصل لكل الأعضاء", "Reach every member")
    }

    /// تلميح القارئ الصوتي على صفّ يغيّر حين يُضغط — «يسأل قبل التغيير» فقط حين يسأل فعلاً (spec A.7/A.14)
    static func maintenanceHint(on: Bool) -> String {
        on ? L10n.t("يطفئ الصيانة الحين", "Turns maintenance off now")
           : L10n.t("يسأل قبل التغيير", "Asks before changing")
    }

    static func pushHint(paused: Bool) -> String {
        paused ? L10n.t("يعيد الإشعارات الحين", "Turns notifications back on now")
               : L10n.t("يسأل قبل التغيير", "Asks before changing")
    }

    /// «فرض التحديث»: «اختياري» / «إجباري»
    static func forceUpdateWord(required: Bool) -> Word {
        required ? Word(text: L10n.t("إجباري", "Required"), tone: .warn)
                 : Word(text: L10n.t("اختياري", "Optional"), tone: .off)
    }

    /// إجباري حين تكون أيّ منصة على «إجباري من تاريخ» أو «إجباري فوراً» (قيم `AdminUpdatePlatform.Mode`)
    static func forceUpdateRequired(modes: [String]) -> Bool {
        modes.contains { $0 == "scheduled" || $0 == "forced" }
    }

    /// قبل ترحيل «فرض التحديث» الجديد: أقلّ إصدار مسموح (> ٠) أو طريقة الأندرويد القديمة = إجباري
    static func legacyForceRequired(iosMin: Int, androidMin: Int, legacyAndroid: Bool) -> Bool {
        iosMin > 0 || androidMin > 0 || legacyAndroid
    }

    /// «آخر إصدار في المتجر: آيفون 49 · أندرويد 31» (المنصة بلا رقم لا تُذكر)
    static func storeLine(ios: Int, android: Int) -> String {
        var parts: [String] = []
        if ios > 0 { parts.append(L10n.t("آيفون \(ios)", "iPhone \(ios)")) }
        if android > 0 { parts.append(L10n.t("أندرويد \(android)", "Android \(android)")) }
        guard !parts.isEmpty else { return L10n.t("آخر إصدار في المتجر لم يُحدَّد بعد", "Latest store build not set yet") }
        return L10n.t("آخر إصدار في المتجر: ", "Latest in the store: ") + parts.joined(separator: " · ")
    }

    /// قبل الترحيل: «أقل إصدار مسموح: آيفون بلا · أندرويد 31» (السطر السابق كما كان)
    static func legacyLine(iosMin: Int, androidMin: Int) -> String {
        func v(_ n: Int) -> String { n == 0 ? L10n.t("بلا", "off") : "\(n)" }
        return L10n.t("أقل إصدار مسموح: آيفون \(v(iosMin)) · أندرويد \(v(androidMin))",
                      "Minimum allowed: iPhone \(v(iosMin)) · Android \(v(androidMin))")
    }

    // MARK: التأكيد (spec A.14)

    /// ما يسأل قبل التنفيذ — العنوان سؤال بالفعل، وسطر ما يحدث، والزرّ يكرّر الفعل
    enum Confirm: String, Hashable, Identifiable, CaseIterable {
        case maintenanceOn, pushOff, resetCounter, restoreDefaults

        var id: String { rawValue }

        /// الإعداد والقيمة التي ينفّذها «نعم»
        var change: (setting: AdminAppSetting, value: AdminAppValue?) {
            switch self {
            case .maintenanceOn:   return (.maintenance, .flag(true))
            case .pushOff:         return (.pushPaused, .flag(true))
            case .resetCounter:    return (.resetCounter, nil)
            case .restoreDefaults: return (.restoreDefaults, nil)
            }
        }

        var title: String {
            switch self {
            case .maintenanceOn:   return L10n.t("تشغيل وضع الصيانة؟", "Turn on maintenance mode?")
            case .pushOff:         return L10n.t("إيقاف إشعارات الجوال؟", "Pause phone notifications?")
            case .resetCounter:    return L10n.t("إعادة ضبط العدّاد؟", "Reset the counter?")
            case .restoreDefaults: return L10n.t("استعادة الإعدادات الافتراضية؟", "Restore default settings?")
            }
        }

        var message: String {
            switch self {
            case .maintenanceOn:
                return L10n.t("يتوقف التطبيق لكل الأعضاء حتى تطفئه. الإدارة تدخل كالعادة.",
                              "The app stops for every member until you turn it off. Admins still get in.")
            case .pushOff:
                return L10n.t("لن تصل إشعارات الجوال لأي عضو حتى تعيدها. تبقى داخل التطبيق، ورسائل رمز الدخول لا تتأثر.",
                              "No member gets phone notifications until you turn them back on. They stay inside the app; sign-in code messages aren't affected.")
            case .resetCounter:
                return L10n.t("يُصفَّر عدّاد التعديلات الذاتية لكل الأعضاء على السيرفر، فيعود لكل عضو عدد التعديلات المباشرة كاملاً في كل حقل. لا يمكن التراجع.",
                              "Every member's self-edit counter is reset on the server, so each gets the full number of direct edits for every field again. This can't be undone.")
            case .restoreDefaults:
                return L10n.t("تظهر الأقسام كلها، وتُطفأ الصيانة، وتعمل الإشعارات، وتُعتمد الأخبار قبل نشرها، ويُفتح التسجيل، و3 أجهزة لكل عضو. لا يمكن التراجع.",
                              "Every section shows, maintenance turns off, notifications run, news needs approval, sign-up opens and each member gets 3 devices. This can't be undone.")
            }
        }

        /// زرّ التنفيذ (أحمر)
        var verb: String {
            switch self {
            case .maintenanceOn:   return L10n.t("شغّل الصيانة", "Turn on maintenance")
            case .pushOff:         return L10n.t("أوقف الإشعارات", "Pause notifications")
            case .resetCounter:    return L10n.t("أعد ضبط العدّاد", "Reset the counter")
            case .restoreDefaults: return L10n.t("استعادة الإعدادات", "Restore settings")
            }
        }
    }

    /// هل يسأل هذا التغيير قبل التنفيذ؟ تشغيل الصيانة وإيقاف الإشعارات والأمران الأحمران فقط — الرجوع بلا سؤال
    static func confirm(for setting: AdminAppSetting, to value: AdminAppValue?) -> Confirm? {
        switch (setting, value) {
        case (.maintenance, .flag(true)?): return .maintenanceOn
        case (.pushPaused, .flag(true)?):  return .pushOff
        case (.resetCounter, _):           return .resetCounter
        case (.restoreDefaults, _):        return .restoreDefaults
        default:                           return nil
        }
    }

    // MARK: ما يراه الأعضاء · قواعد الأعضاء

    /// لغات التطبيق الرسمية (`default_language`)
    static let languages: [(value: String, title: String)] = [("ar", "العربية"), ("en", "English")]

    static func languageTitle(_ code: String?) -> String {
        let c = code ?? "ar"
        return languages.first { $0.value == c }?.title ?? c
    }

    /// «منع لقطة الشاشة في المكتبة» (`library_screen_protection`) — الافتراضي «على الأعضاء فقط»
    static let shieldFallback = "members"

    static var shieldOptions: [(value: String, title: String)] {
        [("all", L10n.t("على الجميع", "Everyone")),
         ("members", L10n.t("على الأعضاء فقط", "Members only")),
         ("off", L10n.t("مطفأ", "Off"))]
    }

    static func shieldTitle(_ value: String?) -> String {
        let v = value ?? shieldFallback
        return shieldOptions.first { $0.value == v }?.title ?? v
    }

    /// المفتاح للاطلاع (لا يعدّل): كلمة «مفعّل» / «مطفأ» بدل المفتاح (spec A.12)
    static func onOffWord(_ on: Bool) -> Word {
        on ? Word(text: L10n.t("مفعّل", "On"), tone: .ok) : Word(text: L10n.t("مطفأ", "Off"), tone: .off)
    }

    // MARK: القوائم · النظام

    /// «14 فرعاً» بجانب «أسماء العوائل والفروع» — nil حين لا فرع مسمّى
    static func branchesValue(_ n: Int) -> String? {
        guard n > 0 else { return nil }
        guard L10n.isArabic else { return n == 1 ? "1 branch" : "\(n) branches" }
        switch n {
        case 1: return "فرع واحد"
        case 2: return "فرعان"
        default:
            switch n % 100 {
            case 3...10:  return "\(n) فروع"
            case 11...99: return "\(n) فرعاً"
            default:      return "\(n) فرع"
            }
        }
    }

    /// عدد «الأخطاء» في الفترة = مجموع المنصات (أخطاء مختلفة، لا مرات) — «1,204»
    static func errorsValue(totals: [Int]) -> String {
        AdminNumberText.grouped(totals.reduce(0, +))
    }

    /// «17 نوفمبر» (والسنة حين لا تكون هذه السنة) — أرقام لاتينية
    static func dayMonth(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let thisYear = calendar.component(.year, from: now)
        let day = c.day ?? 1
        let month = max(1, min(12, c.month ?? 1))
        let year = c.year ?? thisYear
        let arabic = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر",
                      "نوفمبر", "ديسمبر"]
        let english = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let name = L10n.isArabic ? arabic[month - 1] : english[month - 1]
        return year == thisYear ? "\(day) \(name)" : "\(day) \(name) \(year)"
    }

    // MARK: الحالات (spec A.12 + T1/T5)

    /// مخزن لم يُجلب هنا بعد وفي الذاكرة بياناته من صفحة أخرى: كلمة فوراً لا هيكل يومض قبل أول جلب
    static func seeded(_ health: AdminStoreHealth, hasData: Bool, now: Date = Date()) -> AdminStoreHealth {
        health == .idle && hasData ? .loaded(at: now) : health
    }

    /// الأداة (مفتاح، قائمة، صفّ حبّة) تعمل: يعدّل × وصلت قيمتها (ولو قديمة) × لا حفظ جارٍ
    static func controlEnabled(health: AdminStoreHealth, canEdit: Bool, busy: Bool) -> Bool {
        canEdit && health.hasData && !busy
    }

    /// تُرسم القيمة (لا هيكلاً): وصلت ولو قديمة — قبلها المفتاح هيكل معطّل لا قيمة افتراضية مضلِّلة
    static func showsValue(_ health: AdminStoreHealth) -> Bool { health.hasData }

    /// نجح الحفظ: لا خطأ، والقيمة بعد إعادة الجلب = المطلوبة (تحديث بصفر صفوف لا يُحسب نجاحاً)
    static func saveSucceeded(desired: AdminAppValue, after current: AdminAppValue, errored: Bool) -> Bool {
        !errored && desired == current
    }

    /// تحت الصفّ حين فشل الحفظ (الضغط يعيد المحاولة)
    static var failedLine: String { L10n.t("لم يُحفظ. أعد المحاولة", "Not saved. Try again") }

    /// للقارئ الصوتي حين فشل الحفظ
    static func failedAnnouncement(_ title: String) -> String {
        L10n.t("لم يُحفظ \(title). أعد المحاولة", "\(title) wasn't saved. Try again")
    }

    static var savingLabel: String { L10n.t("جارٍ الحفظ", "Saving") }
}

/// حال الحفظ في الصفحة: حفظ واحد في كل مرة (دوّارة صغيرة على صاحبه، والباقي معطّل حتى ينتهي)، والفاشل يبقى معلَّماً
/// بسطر «لم يُحفظ. أعد المحاولة» حتى ينجح أو يُحفظ من جديد
nonisolated struct AdminAppSaveState: Equatable {
    private(set) var saving: AdminAppSetting? = nil
    private(set) var failed: Set<AdminAppSetting> = []

    /// حفظ جارٍ (كل الأدوات معطّلة)
    var isBusy: Bool { saving != nil }

    func isSaving(_ s: AdminAppSetting) -> Bool { saving == s }
    func hasFailed(_ s: AdminAppSetting) -> Bool { failed.contains(s) }

    /// يبدأ حفظاً — false حين يجري غيره (لا يُبدأ ثانٍ)
    mutating func begin(_ s: AdminAppSetting) -> Bool {
        guard saving == nil else { return false }
        saving = s
        failed.remove(s)
        return true
    }

    /// انتهى حفظ صاحبه: نجح = يُمسح علَمه، فشل = يبقى سطر «لم يُحفظ»
    mutating func finish(_ s: AdminAppSetting, success: Bool) {
        guard saving == s else { return }
        saving = nil
        if success { failed.remove(s) } else { failed.insert(s) }
    }
}
