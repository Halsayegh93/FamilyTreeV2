import Foundation

// MARK: - منطق «اليوم» الخالص (إعادة التصميم ٢٠٢٦-١١-٢٦ — spec C.1 وAutoplan note 4، الوحدة U7)
//
// ما يقرّره «اليوم» من الأرقام، بلا واجهة (Foundation فقط):
//  ١) **سطر التحية الذكي** تحت رأس التبويب: جملة واحدة بالأولوية — العاجل أولاً فيتّفق مع مربّع «الوارد»:
//     «طلبان عاجلان في الوارد» › «اليوم ذكرى وفاة فلان» › «لم يُعلَن بعد عن وفاة فلان» (المالك والمدير) › «5 طلبات بانتظار
//     قرارك» › «انضمّ 3 أعضاء هذا الأسبوع» › «ما في طلبات — يوم هادئ». السطر زرّ يفتح بيت حقيقته (`AdminTodayLink`)، والهادئ
//     لا يفتح شيئاً.
//  ٢) **كلمة كل مربّع قسم** (`AdminTileState`) بدل الشارات الحمراء، ومعها هبوط القسم حين تسمّي الكلمة شيئاً يُصفّى
//     («4 مشكلات في الشجرة» ← «العائلة» ثم قائمة «مشكلات» فوقها؛ «2 عاجل» ← «الوارد» على «عاجل»).
//     ترتيب كلمات «الوارد» من جدول الأدوار: `today.attention` (عاجل · بانتظارك · متأخر) ثم الرقم الرابع للدور
//     (`attention_fourth`: رسائل · بلاغات؛ «مشكلات الشجرة» يقولها مربّع «العائلة» نفسه فلا تتكرّر). حقيقتان على الأكثر.
//  حال المخزن (لا كلمة هادئة قبل وصول بياناتها، و«تعذّر التحميل» عند الفشل) يرسمها `AdminRowTile(health:)` — هنا الكلمة فقط.
//
// يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u7-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTileKit.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminCensusRings.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTodayLogic.swift tests/admin-redesign/U7/main.swift && /tmp/u7-logic

/// بيت يفتحه «اليوم» (يقابل `AdminArea` — هذا الملف بلا واجهة) + هبوطه
nonisolated struct AdminTodayLink: Hashable {
    nonisolated enum Home: Hashable { case inbox, family, occasions, metrics, team, app }

    var home: Home
    var landing: AdminLanding? = nil
}

/// الرقم الرابع في كلمات «الوارد» (`attention_fourth` في جدول الأدوار)
nonisolated enum AdminTodayFourth: Hashable {
    /// رسائل الأعضاء غير المقروءة (المالك والمدير — `inbox.messages`)
    case messages
    /// مشكلات الشجرة (المراقب) — بيتها مربّع «العائلة»، فلا تُكرَّر في «الوارد»
    case treeIssues
    /// البلاغات المفتوحة (المشرف)
    case reports
}

/// مستوى رصيد رسائل الدخول (نفس `SmsBalanceStore.Level`)
nonisolated enum AdminTodaySmsLevel: Hashable { case unknown, good, low, urgent }

/// كلمة مربّع + الهبوط الذي يفتح عليه
nonisolated struct AdminTodayWord: Hashable {
    var state: AdminTileState
    var landing: AdminLanding? = nil
}

/// سطر التحية الذكي: الجملة وما يفتحه (nil = يوم هادئ أو بيت لا يراه الدور)
nonisolated struct AdminSmartLine: Hashable {
    var text: String
    var link: AdminTodayLink? = nil
}

nonisolated enum AdminTodayLogic {

    // MARK: سطر التحية الذكي

    /// ما يقرؤه سطر التحية — أسماء جاهزة (الاسم المختصر) وأعداد من نفس تعريفات المربّعات
    nonisolated struct SmartInput {
        /// ما زالت الأرقام الأولى تصل — السطر محجوز بلا نص (لا قفزة، ولا «يوم هادئ» كاذب)
        var loading = false
        /// العاجل في مجال الدور (مسار الموافقات) — ٠ لمن لا يرى أرقام «الوارد» (`today.attention`)
        var urgent = 0
        /// بانتظار قرارك (المسار مطفأ: كل ما في «الوارد» لدورك)
        var waiting = 0
        /// ذكرى وفاة اليوم
        var memorialToday: [String] = []
        /// وفيات حديثة لم يُعلن عنها (المالك والمدير — فارغة لغيرهما)
        var unannounced: [String] = []
        /// قُيّدوا هذا الأسبوع — nil لمن ليس مجاله الشجرة
        var joinedThisWeek: Int? = nil
        /// البيوت الظاهرة لدورك — سطر بيته مخفي يُقرأ ولا يفتح شيئاً
        var opens: Set<AdminTodayLink.Home> = [.inbox, .family, .occasions]
    }

    static func smartLine(_ input: SmartInput) -> AdminSmartLine? {
        guard !input.loading else { return nil }
        func link(_ home: AdminTodayLink.Home, _ landing: AdminLanding? = nil) -> AdminTodayLink? {
            input.opens.contains(home) ? AdminTodayLink(home: home, landing: landing) : nil
        }
        if input.urgent > 0 {
            return AdminSmartLine(text: urgentLine(input.urgent),
                                  link: link(.inbox, .inbox(AdminInboxLanding(status: .urgent))))
        }
        if let first = input.memorialToday.first {
            let text: String
            switch input.memorialToday.count {
            case 1:
                text = L10n.t("اليوم ذكرى وفاة \(first)", "Today is the anniversary of \(first)'s passing")
            case 2:
                let second = input.memorialToday[1]
                text = L10n.t("اليوم ذكرى وفاة \(first) و\(second)", "Today is the anniversary of \(first) and \(second)")
            default:
                let others = input.memorialToday.count - 1
                text = L10n.t("اليوم ذكرى وفاة \(first) و\(others) آخرين", "Today is the anniversary of \(first) and \(others) others")
            }
            return AdminSmartLine(text: text, link: link(.occasions, .occasions(.memorials)))
        }
        if let first = input.unannounced.first {
            let n = input.unannounced.count
            let text: String
            switch n {
            case 1:  text = L10n.t("لم يُعلَن بعد عن وفاة \(first)", "\(first)'s passing isn't announced yet")
            case 2:  text = L10n.t("وفاتان لم يُعلَن عنهما بعد", "2 deaths not announced yet")
            default:
                text = L10n.t("\(counted(n, one: "وفاة", two: "وفاتان", few: "وفيات", many: "وفاة", single: "وفاة")) لم يُعلَن عنها بعد",
                              "\(AdminNumberText.grouped(n)) deaths not announced yet")
            }
            return AdminSmartLine(text: text, link: link(.occasions, .occasions(.awaiting)))
        }
        if input.waiting > 0 {
            let n = input.waiting
            let text = L10n.isArabic
                ? "\(counted(n, one: "طلب واحد", two: "طلبان", few: "طلبات", many: "طلباً", single: "طلب")) بانتظار قرارك"
                : (n == 1 ? "1 request awaits your decision" : "\(AdminNumberText.grouped(n)) requests await your decision")
            return AdminSmartLine(text: text, link: link(.inbox, .inbox(AdminInboxLanding(status: .waiting))))
        }
        if let joined = input.joinedThisWeek, joined > 0 {
            let text = L10n.isArabic
                ? (joined == 1 ? "انضمّ عضو جديد هذا الأسبوع"
                    : "انضمّ \(counted(joined, one: "عضو", two: "عضوان", few: "أعضاء", many: "عضواً", single: "عضو")) هذا الأسبوع")
                : (joined == 1 ? "1 member joined this week" : "\(AdminNumberText.grouped(joined)) members joined this week")
            return AdminSmartLine(text: text, link: link(.family))
        }
        return AdminSmartLine(text: L10n.t("ما في طلبات — يوم هادئ", "No requests — a quiet day"), link: nil)
    }

    /// «طلب عاجل في الوارد» · «طلبان عاجلان في الوارد» · «3 طلبات عاجلة في الوارد» · «12 طلباً عاجلاً في الوارد»
    static func urgentLine(_ n: Int) -> String {
        guard L10n.isArabic else {
            return n == 1 ? "1 urgent request in the inbox" : "\(AdminNumberText.grouped(n)) urgent requests in the inbox"
        }
        let what = counted(n, one: "طلب عاجل", two: "طلبان عاجلان", few: "طلبات عاجلة", many: "طلباً عاجلاً",
                           single: "طلب عاجل")
        return "\(what) في الوارد"
    }

    // MARK: كلمات المربّعات

    /// «الوارد»: عاجل › بانتظارك › متأخر › الرقم الرابع للدور — أول حقيقتين غير صفريتين، والهبوط على فلتر الأولى.
    /// لا شيء = «لا جديد» ✓ (بعد وصول البيانات فقط — `AdminRowTile(health:)`)
    static func inboxWord(urgent: Int, waiting: Int, late: Int, fourth: AdminTodayFourth, fourthCount: Int) -> AdminTodayWord {
        var facts: [(state: AdminTileState, landing: AdminInboxLanding?)] = []
        if urgent > 0 {
            facts.append((.urgent(L10n.t("\(AdminNumberText.grouped(urgent)) عاجل", "\(AdminNumberText.grouped(urgent)) urgent")),
                          AdminInboxLanding(status: .urgent)))
        }
        if waiting > 0 {
            facts.append((.attention(""), AdminInboxLanding(status: .waiting)))   // نصّه بعد معرفة العدد
        }
        if late > 0 {
            facts.append((.attention(L10n.t("\(AdminNumberText.grouped(late)) متأخر", "\(AdminNumberText.grouped(late)) late")),
                          AdminInboxLanding(status: .late)))
        }
        if fourthCount > 0 {
            switch fourth {
            case .messages:
                // رسائل الأعضاء صفحتها خارج قائمة الطلبات — لا فلتر يُهبط عليه
                facts.append((.neutral(messagesText(fourthCount)), nil))
            case .reports:
                facts.append((.attention(reportsText(fourthCount)), AdminInboxLanding(kind: .reports)))
            case .treeIssues:
                break
            }
        }
        let shown = Array(facts.prefix(2))
        guard let first = shown.first else {
            return AdminTodayWord(state: .good(L10n.t("لا جديد", "Nothing new")))
        }
        // «5 بانتظار قرارك» وحدها، و«2 عاجل · 5 بانتظارك» مع غيرها (Autoplan decision 19)
        let states = shown.map { fact -> AdminTileState in
            guard fact.state.text.isEmpty else { return fact.state }
            let n = AdminNumberText.grouped(waiting)
            return .attention(shown.count == 1 ? L10n.t("\(n) بانتظار قرارك", "\(n) awaiting your decision")
                                               : L10n.t("\(n) بانتظارك", "\(n) waiting"))
        }
        return AdminTodayWord(state: AdminTileState.joined(states) ?? states[0], landing: first.landing.map { .inbox($0) })
    }

    /// «العائلة»: «4 مشكلات في الشجرة» ← «العائلة» وقائمة «مشكلات» فوقها، وإلا «سليمة» ✓
    static func familyWord(treeIssues: Int) -> AdminTodayWord {
        guard treeIssues > 0 else { return AdminTodayWord(state: .good(L10n.t("سليمة", "All good"))) }
        let text = L10n.isArabic
            ? counted(treeIssues, one: "مشكلة واحدة", two: "مشكلتان", few: "مشكلات", many: "مشكلة", single: "مشكلة") + " في الشجرة"
            : (treeIssues == 1 ? "1 tree problem" : "\(AdminNumberText.grouped(treeIssues)) tree problems")
        return AdminTodayWord(state: .attention(text), landing: .members(AdminMembersLanding(review: .problems)))
    }

    /// «المناسبات والإعلانات»: وفاة لم تُعلن (المالك والمدير) › مجدول اليوم › أقرب ذكرى خلال أسبوع › «لا شيء قريب».
    /// `nextMemorial` = متى الذكرى الأقرب («بعد 3 أيام»، «اليوم») حين تكون خلال أسبوع — nil غير ذلك
    static func occasionsWord(unannounced: Int, scheduledToday: Int, nextMemorial: String?) -> AdminTodayWord {
        if unannounced > 0 {
            let text: String
            if L10n.isArabic {
                switch unannounced {
                case 1:  text = "وفاة لم تُعلن"
                case 2:  text = "وفاتان لم تُعلنا"
                default: text = counted(unannounced, one: "وفاة", two: "وفاتان", few: "وفيات", many: "وفاة", single: "وفاة") + " لم تُعلن"
                }
            } else {
                text = unannounced == 1 ? "A death not announced" : "\(AdminNumberText.grouped(unannounced)) deaths not announced"
            }
            return AdminTodayWord(state: .attention(text), landing: .occasions(.awaiting))
        }
        if scheduledToday > 0 {
            let n = AdminNumberText.grouped(scheduledToday)
            return AdminTodayWord(state: .neutral(L10n.t("مجدول اليوم \(n)", "\(n) scheduled today")),
                                  landing: .occasions(.scheduled))
        }
        if let nextMemorial {
            return AdminTodayWord(state: .neutral(L10n.t("ذكرى \(nextMemorial)", "Memorial \(nextMemorial.lowercased())")),
                                  landing: .occasions(.memorials))
        }
        return AdminTodayWord(state: .neutral(L10n.t("لا شيء قريب", "Nothing coming up")))
    }

    /// «الإحصاءات»: «170 في التطبيق» ← قسم «في التطبيق» (عنوانه الرقم نفسه — T2). nil قبل وصول قوائم الحسابات
    static func metricsWord(inApp: Int?) -> AdminTodayWord? {
        guard let inApp else { return nil }
        let n = AdminNumberText.grouped(inApp)
        return AdminTodayWord(state: .neutral(L10n.t("\(n) في التطبيق", "\(n) in the app")), landing: .stats(.inApp))
    }

    /// «الفريق والأمان» (المالك): محاولات مريبة › الرصيد عاجل/منخفض › أجهزة لا تصلها الإشعارات › التسجيل متوقف › «سليم» ✓.
    /// `registrationOpen` nil = الإعدادات لم تصل (لا تُعدّ)
    static func teamWord(suspicious: Int, smsLevel: AdminTodaySmsLevel, devicesFailed: Int,
                         registrationOpen: Bool?) -> AdminTodayWord {
        if suspicious > 0 {
            let text = L10n.isArabic
                ? counted(suspicious, one: "محاولة مريبة", two: "محاولتان مريبتان", few: "محاولات مريبة", many: "محاولة مريبة",
                          single: "محاولة مريبة")
                : (suspicious == 1 ? "1 suspicious attempt" : "\(AdminNumberText.grouped(suspicious)) suspicious attempts")
            return AdminTodayWord(state: .urgent(text))
        }
        switch smsLevel {
        case .urgent: return AdminTodayWord(state: .urgent(L10n.t("الرصيد منخفض جداً", "Balance very low")))
        case .low:    return AdminTodayWord(state: .attention(L10n.t("الرصيد منخفض", "Balance low")))
        case .good, .unknown: break
        }
        if devicesFailed > 0 {
            let text: String
            if L10n.isArabic {
                switch devicesFailed {
                case 1:  text = "جهاز لا تصله الإشعارات"
                case 2:  text = "جهازان لا تصلهما الإشعارات"
                default: text = counted(devicesFailed, one: "جهاز", two: "جهازان", few: "أجهزة", many: "جهازاً", single: "جهاز")
                    + " لا تصلها الإشعارات"
                }
            } else {
                text = devicesFailed == 1 ? "1 device not reached" : "\(AdminNumberText.grouped(devicesFailed)) devices not reached"
            }
            return AdminTodayWord(state: .attention(text))
        }
        if registrationOpen == false {
            return AdminTodayWord(state: .attention(L10n.t("التسجيل متوقف", "Sign-ups stopped")))
        }
        return AdminTodayWord(state: .good(L10n.t("سليم", "All good")))
    }

    /// «التطبيق» (المالك): «الصيانة مفعّلة» › «الإشعارات موقوفة» › «يعمل للجميع» ✓
    static func appWord(maintenance: Bool, notificationsPaused: Bool) -> AdminTodayWord {
        if maintenance { return AdminTodayWord(state: .urgent(L10n.t("الصيانة مفعّلة", "Maintenance on"))) }
        if notificationsPaused { return AdminTodayWord(state: .attention(L10n.t("الإشعارات موقوفة", "Notifications paused"))) }
        return AdminTodayWord(state: .good(L10n.t("يعمل للجميع", "Open to everyone")))
    }

    // MARK: النصوص

    /// «رسالة جديدة» · «رسالتان جديدتان» · «7 رسائل جديدة» · «11 رسالة جديدة»
    static func messagesText(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "1 new message" : "\(AdminNumberText.grouped(n)) new messages" }
        return counted(n, one: "رسالة جديدة", two: "رسالتان جديدتان", few: "رسائل جديدة", many: "رسالة جديدة",
                       single: "رسالة جديدة")
    }

    /// «بلاغ» · «بلاغان» · «3 بلاغات» · «11 بلاغاً»
    static func reportsText(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "1 report" : "\(AdminNumberText.grouped(n)) reports" }
        return counted(n, one: "بلاغ واحد", two: "بلاغان", few: "بلاغات", many: "بلاغاً", single: "بلاغ")
    }

    /// العدد ومعدوده بالعربية — نفس قاعدة بطاقة «العائلة» (`AdminCensusText.counted`)
    static func counted(_ n: Int, one: String, two: String, few: String, many: String, single: String) -> String {
        AdminCensusText.counted(n, one: one, two: two, few: few, many: many, single: single)
    }
}
