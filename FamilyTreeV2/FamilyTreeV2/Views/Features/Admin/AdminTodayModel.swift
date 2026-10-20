import SwiftUI
import Supabase
import Combine

// MARK: - بيانات «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠ — الصفحة الأولى تجيب «وش يحتاجني الآن؟»)
//
// كل رقم هنا من بيانات محمّلة أصلاً في التطبيق (الطلبات، مسار الموافقات ٢، الرسائل، الأعضاء) أو من دوال
// قراءة موجودة على السيرفر (النشطون الآن، تقرير الموافقات، رصيد رسائل الدخول) — بلا أي دالة جديدة. ما لا
// يتوفّر لا يُرسم (لا أرقام مختلقة). مجال كل دور كما في «الوارد» (`AdminAllRequestsView.tabsForRole`).

/// عنصر ينتظر قراراً — صفّ في «يحتاج قرارك» ومصدر مهام «اليوم»
struct AdminDecisionItem: Identifiable {
    /// معرّف الصف في «الوارد» (للانضمام: معرّف العضو المعلّق)
    let id: UUID
    let typeTitle: String
    let icon: String
    let tint: Color
    let name: String
    let date: Date?
    let snapshot: ApprovalSnapshot?
    let waitingForMe: Bool
    let holderLabel: String?

    var isUrgent: Bool { snapshot?.isUrgent ?? false }
    var isLate: Bool { snapshot.map { $0.isLate || $0.isEscalated } ?? false }

    /// سطر الحالة: مرحلة المسار ومن عنده، وإلا عمر الطلب
    var subtitle: String {
        if let flow = snapshot {
            let stage: String
            switch flow.stage {
            case .review:  stage = L10n.t("مراجعة المختص", "Specialist review")
            case .info:    stage = L10n.t("بانتظار معلومات العضو", "Waiting for the member")
            case .approve: stage = L10n.t("ينتظر اعتماد المدير", "Awaiting manager approval")
            case .execute: stage = L10n.t("معتمد · للتنفيذ", "Approved · to carry out")
            }
            return [stage, holderLabel].compactMap { $0 }.joined(separator: " · ")
        }
        return AdminTodayText.since(date) ?? L10n.t("بانتظار المراجعة", "Awaiting review")
    }

    /// فعل المهمة حسب المرحلة: راجع / اعتمد / نفّذ
    var verb: String {
        switch snapshot?.stage {
        case .approve: return L10n.t("اعتمد", "Approve")
        case .execute: return L10n.t("نفّذ", "Carry out")
        default:       return L10n.t("راجع", "Review")
        }
    }

    /// ترتيب الأولوية: المستعجل ← المتأخر ← بانتظارك ← الأقدم
    var priorityRank: Int {
        if isUrgent { return 0 }
        if isLate { return 1 }
        if waitingForMe { return 2 }
        return 3
    }
}

/// أرقام رأس «اليوم» (بانتظارك · مستعجل · متأخر · رسائل) — نفس تعريف فلاتر «الوارد»
struct AdminTodayCounts: Equatable {
    var waiting = 0
    var urgent = 0
    var late = 0
    var unreadMessages = 0
    var pendingMessages = 0
    /// كل ما في «الوارد» لهذا الدور (= عدّاد «الكل» فيه)
    var inboxTotal = 0
}

/// إشارة من إشارات «حالة النظام» في رأس «اليوم» (كانت بطاقة «تنبيهات» ثم سطر نقاط ثم شريحة): الصيانة · الرصيد · المجدول ·
/// بلا إشعارات — صفّ في لوحة السطر بنقطة لون (أخضر سليم، كهرماني تنبيه، أحمر عاجل) وإجراء صغير يفتح بيتها الوحيد
struct AdminStatusPill: Identifiable, Equatable {
    enum Level { case ok, warn, urgent, unknown }
    enum Home: Hashable { case maintenance, sms, scheduled, devices }

    let home: Home
    /// عنوان الصفّ في اللوحة («الصيانة: مطفأة»، «الرصيد: 17 نقطة»، «مجدول: 1 اليوم»، «بلا إشعارات: 3 أجهزة»)
    let text: String
    /// السطر الثاني تحته («يكفي نحو 17 رمز دخول»، «لاحقاً 2»، «غير مسجّلة أو لم تُحدَّث منذ 30 يوماً»)
    let detail: String
    let level: Level
    /// العبارة في ملخّص السطر الصوتي حين تنبّه («الرصيد منخفض»، «3 أجهزة بلا إشعارات»)
    let issue: String
    /// ما يقرؤه القارئ الصوتي للصفّ: الحالة كاملة («وضع الصيانة مفعّل»، «رصيد رسائل رمز الدخول: 17 نقطة، منخفض»)
    let spoken: String

    var id: Home { home }
    /// تنبيه أو عاجل (يُعدّ في السطر)
    var isFlagged: Bool { level == .warn || level == .urgent }

    /// الإجراء الصغير في طرف الصفّ — يفتح بيت الإشارة
    var actionTitle: String {
        switch home {
        case .maintenance: return L10n.t("الإعدادات", "Settings")
        case .sms:         return L10n.t("اشحن", "Top up")
        case .scheduled:   return L10n.t("القادم", "Upcoming")
        case .devices:     return L10n.t("الأجهزة", "Devices")
        }
    }
}

/// ملخّص «حالة النظام» (اختيار المالك ٢٠٢٦-١٠-٢٠ بدل النقاط الأربع؛ سطر أسفل «يحتاج انتباهك» منذ الدفعة ٩): «✓ النظام
/// سليم» حين تسلم كلها، «⚠︎ تنبيه/تنبيهان/3 تنبيهات للنظام» حين ينبّه شيء (أحمر إن كان فيها عاجل)، و«حالة النظام» محايدة
/// ما دام شيء لم يُحمَّل
struct AdminSystemStatus: Equatable {
    enum Tone { case ok, warn, urgent, loading }

    let pills: [AdminStatusPill]

    var flagged: [AdminStatusPill] { pills.filter(\.isFlagged) }

    var tone: Tone {
        if pills.contains(where: { $0.level == .urgent }) { return .urgent }
        if !flagged.isEmpty { return .warn }
        return pills.allSatisfy { $0.level == .ok } ? .ok : .loading
    }

    /// عدد التنبيهات بالمعدود الصحيح («تنبيه»، «تنبيهان»، «3 تنبيهات»)
    private var alerts: String {
        let n = flagged.count
        return L10n.isArabic
            ? AdminTodayText.arabicCount(n, one: "تنبيه", two: "تنبيهان", few: "تنبيهات", many: "تنبيهاً", single: "تنبيه")
            : (n == 1 ? "1 alert" : "\(n) alerts")
    }

    /// نص السطر: «النظام سليم» · «تنبيهان للنظام» · «حالة النظام»
    var title: String {
        switch tone {
        case .ok:            return L10n.t("النظام سليم", "All systems OK")
        case .loading:       return L10n.t("حالة النظام", "System status")
        case .warn, .urgent: return L10n.isArabic ? "\(alerts) للنظام" : (flagged.count == 1 ? "1 system alert" : "\(flagged.count) system alerts")
        }
    }

    /// ما يقرؤه القارئ الصوتي للسطر: «حالة النظام: تنبيهان — الرصيد منخفض، 3 أجهزة بلا إشعارات»
    var spoken: String {
        let head = L10n.t("حالة النظام", "System status")
        switch tone {
        case .ok:      return "\(head): \(title)"
        case .loading: return L10n.t("\(head): لم يُحمَّل بعد", "\(head): not loaded yet")
        case .warn, .urgent:
            return "\(head): \(alerts) — " + flagged.map(\.issue).joined(separator: L10n.t("، ", ", "))
        }
    }
}

/// مهمة في «مهام اليوم» (لمسة من الاتجاه «ب»): مشتقة من حالة حقيقية، وتصير «منجزة» حين يُحلّ ما خلفها اليوم
struct AdminTodayTask: Identifiable, Equatable {
    enum Target: Equatable {
        case inbox(UUID), sms, deaths, announce(UUID), messages
    }

    let id: String
    let title: String
    let detail: String?
    /// «!!» للمتأخر والمنخفض، «!!!» للمستعجل والعاجل
    let marks: Int
    let source: String
    let sourceIcon: String
    /// شارة الأولوية بجانب المصدر («متأخر يومين»، «مستعجل»)
    var flag: String? = nil
    var flagIcon: String = "clock"
    var flagTint: Color = DS.Color.error
    let target: Target

    static func == (a: AdminTodayTask, b: AdminTodayTask) -> Bool {
        a.id == b.id && a.title == b.title && a.detail == b.detail && a.marks == b.marks && a.flag == b.flag
    }
}

/// صفّ في القائمة الموحّدة «يحتاج قرارك» (طلب المالك ٢٠٢٦-١٠-٢٠: «الأقسام فوق + قائمة وحدة») — تجمع قرارات اليوم
/// و«مهام اليوم» في صفّ واحد لكل طلب: ما عليك أنت = دائرة إنجاز (لمسة «ب»)، وما في مجالك عند غيرك = مربّع نوعه.
/// رصيد الرسائل (سطر الحالة في الرأس) والوفاة التي لم يُعلن عنها («إشعارات الإدارة») لا تتكرّر هنا.
struct AdminTodayEntry: Identifiable, Equatable {
    enum Target: Equatable { case inbox(UUID), messages }

    struct Chip: Equatable {
        let text: String
        var icon: String? = nil
        let tint: Color
    }

    let id: String
    /// مهمة عليك (تصير «منجزة» حين يُحلّ ما خلفها) — وإلا طلب في مجالك بانتظار غيرك
    let isTask: Bool
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    var chip: Chip? = nil
    let target: Target
}

/// «إحصاء الأفراد» أعلى «اليوم» — نفس تعريفات بطاقة «أفراد العائلة» القديمة (قبل إعادة التصميم):
/// الرجال = شجرة العائلة بلا المعلّقين، النساء = إناث شجرة النساء (جدولها يضمّ مرايا الرجال)، الأفراد = مجموعهما؛
/// والحسابات المفعّلة = «فعّال» في «استخدام التطبيق» (رقم وجهاز — فعّال + خامل، تعريف المالك). nil = لم يُعرف بعد.
struct AdminMemberCounts: Equatable {
    var men: Int? = nil
    var menAlive: Int? = nil
    var women: Int? = nil
    var womenAlive: Int? = nil
    var accounts: Int? = nil
    /// كل الأحياء في «استخدام التطبيق» (مقام نسبة الحسابات)
    var living: Int? = nil
    /// مرشّحو «تحقق من الأحياء» (كبار السن بلا وفاة مسجّلة) — قبل استبعاد ما راجعه المستخدم «حي ✓» على جهازه.
    /// ما دام منهم من لم يُراجَع فأحياء الرجال والإجمالي «تقديري»
    var oldLiving: Set<UUID>? = nil

    var total: Int? {
        guard let men, let women else { return nil }
        return men + women
    }

    var totalAlive: Int? {
        guard let menAlive, let womenAlive else { return nil }
        return menAlive + womenAlive
    }

    var menDeceased: Int? { men.flatMap { m in menAlive.map { m - $0 } } }
    var womenDeceased: Int? { women.flatMap { w in womenAlive.map { w - $0 } } }
    var totalDeceased: Int? { total.flatMap { t in totalAlive.map { t - $0 } } }

    /// الرجال من أعضاء الشجرة المحمّلة
    @MainActor
    mutating func setMen(from all: [FamilyMember]) {
        guard !all.isEmpty else { return }
        var total = 0, alive = 0
        for m in all where m.role != .pending {
            total += 1
            if m.isDeceased != true { alive += 1 }
        }
        men = total
        menAlive = alive
        // نفس معيار شريحة «تحقق من الأحياء» (ومن له حساب دخول حيّ قطعاً — حين وصلت قوائم الحسابات)
        let accounts = AdminAccountsStore.shared
        oldLiving = Set(AdminLivingCheck.candidates(all, hasLogin: accounts.loaded ? { accounts.info($0) != nil } : nil).keys)
    }

    mutating func setWomen(_ rows: [FamilyMember]) {
        guard !rows.isEmpty else { return }
        let females = rows.filter(\.isFemale)
        women = females.count
        womenAlive = females.filter { $0.isDeceased != true }.count
    }

    mutating func setUsage(_ u: AppUsageStats?) {
        guard let u else { return }
        // «الأعضاء المسجّلون» = لهم حساب دخول (نفس شريحة «مسجّلون» في العائلة)
        accounts = u.active + u.idle + u.loginNoDevice
        living = u.active + u.idle + u.loginNoDevice + u.neverLogged + u.noPhone
    }

    /// أعداد البداية من آخر ما حُمّل (الشجرة، كاش شجرة النساء، آخر «استخدام التطبيق») — بلا طلب جديد
    @MainActor
    static func seeded(members: [FamilyMember]) -> AdminMemberCounts {
        var c = AdminMemberCounts()
        c.setMen(from: members)
        c.setWomen(WomenStore.cache)
        c.setUsage(AppUsageStats.cached)
        return c
    }
}

// MARK: - نصوص مشتركة

enum AdminTodayText {
    /// «صباح الخير» قبل الظهر، «مساء الخير» بعده
    static func greeting(_ date: Date = Date()) -> String {
        Calendar.current.component(.hour, from: date) < 12
            ? L10n.t("صباح الخير", "Good morning") : L10n.t("مساء الخير", "Good evening")
    }

    /// «الثلاثاء 20 أكتوبر» — ميلادي بالأرقام اللاتينية (نفس تواريخ التطبيق)
    static func dayLine(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: L10n.isArabic ? "ar_KW@numbers=latn" : "en_US")
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: date)
    }

    /// «منذ ٣ س» / «منذ يومين» — nil بلا تاريخ
    static func since(_ date: Date?) -> String? {
        guard let date else { return nil }
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 60 { return L10n.t("منذ \(max(minutes, 1)) د", "\(max(minutes, 1))m ago") }
        let hours = minutes / 60
        if hours < 24 { return L10n.t("منذ \(hours) س", "\(hours)h ago") }
        return L10n.t("منذ \(days(hours / 24))", "\(hours / 24)d ago")
    }

    /// «يوم» / «يومين» / «٣ أيام» / «١٢ يوماً»
    static func days(_ n: Int) -> String {
        switch n {
        case ...1:   return L10n.t("يوم", "1 day")
        case 2:      return L10n.t("يومين", "2 days")
        case 3...10: return L10n.t("\(n) أيام", "\(n) days")
        default:     return L10n.t("\(n) يوماً", "\(n) days")
        }
    }

    /// العدد ومعدوده بالعربية: ١ و٢ بلا رقم («جهاز»، «جهازان»)، ٣–١٠ جمع، ١١–٩٩ مفرد منصوب، وغيرها مفرد
    static func arabicCount(_ n: Int, one: String, two: String, few: String, many: String, single: String) -> String {
        if n == 1 { return one }
        if n == 2 { return two }
        switch n % 100 {
        case 3...10:  return "\(n) \(few)"
        case 11...99: return "\(n) \(many)"
        default:      return "\(n) \(single)"
        }
    }

    /// سطر «اليوم» الذكي تحت التحية (الدفعة ١٠): جملة واحدة من بيانات حقيقية بالأولوية — ذكرى وفاة اليوم › وفاة لم يُعلن عنها
    /// (المالك والمدير) › طلبات بانتظار قرارك (مجال الدور) › انضمّوا هذا الأسبوع (من مجاله الشجرة) › يوم هادئ. نبرة محترمة للوفاة
    /// بلا رموز. nil ما دام «اليوم» يحمّل
    static func smartLine(memorialToday: [FamilyMember], unannounced: [FamilyMember], waiting: Int,
                          joinedThisWeek: Int?, loading: Bool) -> String? {
        guard !loading else { return nil }
        if let first = memorialToday.first {
            let name = first.shortFullName
            switch memorialToday.count {
            case 1: return L10n.t("اليوم ذكرى وفاة \(name)", "Today is the anniversary of \(name)'s passing")
            case 2: return L10n.t("اليوم ذكرى وفاة \(name) و\(memorialToday[1].shortFullName)",
                                  "Today is the anniversary of \(name) and \(memorialToday[1].shortFullName)")
            default:
                let others = memorialToday.count - 1
                return L10n.t("اليوم ذكرى وفاة \(name) و\(others) آخرين",
                              "Today is the anniversary of \(name) and \(others) others")
            }
        }
        if let first = unannounced.first {
            switch unannounced.count {
            case 1: return L10n.t("لم يُعلَن بعد عن وفاة \(first.shortFullName)", "\(first.shortFullName)'s passing isn't announced yet")
            case 2: return L10n.t("وفاتان لم يُعلَن عنهما بعد", "2 deaths not announced yet")
            default:
                return L10n.t("\(arabicCount(unannounced.count, one: "وفاة", two: "وفاتان", few: "وفيات", many: "وفاة", single: "وفاة")) لم يُعلَن عنها بعد",
                              "\(unannounced.count) deaths not announced yet")
            }
        }
        if waiting > 0 {
            return L10n.isArabic
                ? "\(arabicCount(waiting, one: "طلب واحد", two: "طلبان", few: "طلبات", many: "طلباً", single: "طلب")) بانتظار قرارك"
                : (waiting == 1 ? "1 request awaits your decision" : "\(waiting) requests await your decision")
        }
        if let joined = joinedThisWeek, joined > 0 {
            return L10n.isArabic
                ? (joined == 1 ? "انضمّ عضو جديد هذا الأسبوع"
                    : "انضمّ \(arabicCount(joined, one: "عضو", two: "عضوان", few: "أعضاء", many: "عضواً", single: "عضو")) هذا الأسبوع")
                : (joined == 1 ? "1 member joined this week" : "\(joined) members joined this week")
        }
        return L10n.t("ما في طلبات — يوم هادئ", "No requests — a quiet day")
    }

    /// «متأخر يومين» — من بداية مرحلته
    static func late(_ flow: ApprovalSnapshot?) -> String {
        guard let since = flow?.stageSince ?? flow?.createdAt else { return L10n.t("متأخر", "Late") }
        let d = Int(Date().timeIntervalSince(since) / 86_400)
        if d < 1 { return L10n.t("متأخر", "Late") }
        return d == 1 ? L10n.t("متأخر يوماً", "Late 1 day") : L10n.t("متأخر \(days(d))", "Late \(days(d))")
    }
}

// MARK: - المصدر

@MainActor
enum AdminTodayFeed {

    /// مجال الدور — نفس `tabsForRole` في «الوارد»
    private struct Scope {
        let tree: Bool
        let content: Bool
        let photos: Bool
    }

    private static func scope(_ authVM: AuthViewModel, workflowOn: Bool) -> Scope {
        if authVM.isAdmin { return Scope(tree: true, content: true, photos: true) }
        if authVM.currentUser?.role == .supervisor { return Scope(tree: false, content: true, photos: true) }
        return Scope(tree: true, content: false, photos: workflowOn)
    }

    /// لقطات المسار في مجال الدور (المشرف: البلاغات، المراقب: الباقي)
    static func scopedSnapshots(authVM: AuthViewModel, adminRequestVM: AdminRequestViewModel) -> [ApprovalSnapshot] {
        let all = adminRequestVM.allApprovalSnapshots
        if authVM.isAdmin { return all }
        if authVM.currentUser?.role == .supervisor {
            return all.filter { ApprovalWorkflow.specialistRole(for: $0.requestType) == .supervisor }
        }
        return all.filter { ApprovalWorkflow.specialistRole(for: $0.requestType) == .monitor }
    }

    // MARK: يحتاج قرارك

    static func decisionItems(authVM: AuthViewModel, memberVM: MemberViewModel, newsVM: NewsViewModel,
                              adminRequestVM: AdminRequestViewModel, diwaniyaVM: DiwaniyasViewModel,
                              projectsVM: ProjectsViewModel) -> [AdminDecisionItem] {
        let flowOn = adminRequestVM.approvalsWorkflowOn
        let s = scope(authVM, workflowOn: flowOn)
        var items: [AdminDecisionItem] = []

        func item(id: UUID, _ title: String, _ icon: String, _ tint: Color, name: String, date: Date?) {
            let flow = adminRequestVM.approvalSnapshot(forRowId: id)
            items.append(AdminDecisionItem(
                id: id, typeTitle: title, icon: icon, tint: tint, name: name, date: date, snapshot: flow,
                waitingForMe: flow.map(adminRequestVM.isApprovalWaitingForMe) ?? false,
                holderLabel: flow.flatMap(adminRequestVM.approvalHolderLabel)))
        }
        /// الاسم الأول واسم الأب («عبدالله فيصل») — الصفّ سطر واحد
        func name(_ m: FamilyMember?) -> String {
            guard let m else { return L10n.t("عضو", "Member") }
            return m.fullName.split(separator: " ").prefix(2).joined(separator: " ")
        }
        let date = ApprovalWorkflow.date

        if s.tree {
            for m in memberVM.allMembers where m.role == .pending {
                item(id: m.id, L10n.t("طلب انضمام", "Join request"), "person.badge.plus", DS.Color.info,
                     name: name(m), date: date(m.createdAt))
            }
            for r in adminRequestVM.treeEditRequests {
                let action = r.treeEditPayload?.resolvedAction ?? .other
                item(id: r.id, L10n.t("الشجرة · \(action.arabicLabel)", "Tree · \(action.englishLabel)"),
                     action.iconName, DS.Color.palm, name: name(r.member), date: date(r.createdAt))
            }
            for r in adminRequestVM.deceasedRequests {
                item(id: r.id, L10n.t("تسجيل وفاة", "Death report"), NewsTypeHelper.icon(for: "وفاة"),
                     DS.Color.slate, name: name(r.member), date: date(r.createdAt))
            }
            for r in adminRequestVM.childAddRequests {
                item(id: r.id, L10n.t("إضافة ابن", "Add child"), "person.badge.plus", DS.Color.info,
                     name: name(r.member), date: date(r.createdAt))
            }
            for r in adminRequestVM.phoneChangeRequests {
                item(id: r.id, L10n.t("تعديل رقم", "Phone change"), "phone.fill", DS.Color.palm,
                     name: name(r.member), date: date(r.createdAt))
            }
            for r in adminRequestVM.nameChangeRequests {
                let family = r.requestType == RequestType.familyChange.rawValue
                item(id: r.id, family ? L10n.t("تغيير العائلة", "Family change") : L10n.t("تغيير اسم", "Name change"),
                     "character.cursor.ibeam", DS.Color.info, name: name(r.member), date: date(r.createdAt))
            }
        }
        if s.photos {
            for r in adminRequestVM.photoSuggestionRequests {
                item(id: r.id, L10n.t("اقتراح صورة", "Photo suggestion"), "photo.fill", DS.Color.sadu,
                     name: name(r.member), date: date(r.createdAt))
            }
        }
        if s.content {
            for r in adminRequestVM.newsReportRequests {
                item(id: r.id, L10n.t("بلاغ", "Report"), "exclamationmark.bubble.fill", DS.Color.error,
                     name: name(r.member), date: date(r.createdAt))
            }
            for p in newsVM.pendingNewsRequests {
                let preview = p.content.trimmingCharacters(in: .whitespacesAndNewlines)
                item(id: p.id, L10n.t("خبر", "News"), "newspaper.fill", DS.Color.accent,
                     name: preview.isEmpty ? p.author_name : String(preview.prefix(40)), date: p.timestamp)
            }
            for d in diwaniyaVM.pendingDiwaniyas {
                item(id: d.id, L10n.t("ديوانية", "Diwaniya"), "tent.fill", DS.Color.palm, name: d.title, date: nil)
            }
            for p in projectsVM.pendingProjects {
                item(id: p.id, L10n.t("مشروع", "Project"), "briefcase.fill", DS.Color.accent,
                     name: p.title, date: date(p.createdAt))
            }
        }

        return items.sorted { a, b in
            if a.priorityRank != b.priorityRank { return a.priorityRank < b.priorityRank }
            return (a.date ?? .distantFuture) < (b.date ?? .distantFuture)
        }
    }

    // MARK: الأرقام

    static func counts(authVM: AuthViewModel, adminRequestVM: AdminRequestViewModel,
                       items: [AdminDecisionItem], inboxTotal: Int) -> AdminTodayCounts {
        var c = AdminTodayCounts()
        c.unreadMessages = adminRequestVM.unreadContactMessagesCount
        c.pendingMessages = adminRequestVM.pendingContactMessagesCount
        c.inboxTotal = inboxTotal
        if adminRequestVM.approvalsWorkflowOn {
            let flows = scopedSnapshots(authVM: authVM, adminRequestVM: adminRequestVM)
            c.waiting = flows.filter(adminRequestVM.isApprovalWaitingForMe).count
            c.urgent = flows.filter(\.isUrgent).count
            c.late = flows.filter { $0.isLate || $0.isEscalated }.count
        } else {
            // المسار مطفأ: كل طلب في مجالك بانتظارك (بلا مستعجل ولا متأخر)
            c.waiting = items.count
        }
        return c
    }

    // MARK: مهام اليوم

    static func tasks(authVM: AuthViewModel, adminRequestVM: AdminRequestViewModel, items: [AdminDecisionItem],
                      sms: SmsBalanceStore, unannounced: [FamilyMember]) -> [AdminTodayTask] {
        var tasks: [AdminTodayTask] = []

        // رصيد رسائل الدخول (المالك والمدير)
        if authVM.canViewSystemSettings, let balance = sms.status?.balance, sms.needsTopUp {
            let urgent = sms.level == .urgent
            tasks.append(AdminTodayTask(
                id: "sms-balance",
                title: L10n.t("شحن رصيد رسائل الدخول", "Top up the sign-in SMS balance"),
                detail: L10n.t("بقي \(SmsBalanceText.points(balance)) نقطة · \(SmsBalanceText.enough(balance))",
                               "\(SmsBalanceText.points(balance)) points left · \(SmsBalanceText.enough(balance))"),
                marks: urgent ? 3 : 2,
                source: AdminArea.team.title, sourceIcon: "lock.shield.fill",
                target: .sms))
        }

        // ما ينتظر قرارك: بانتظارك أولاً (والمسار مطفأ: كل طلبات مجالك)
        let flowOn = adminRequestVM.approvalsWorkflowOn
        for item in items where (flowOn ? (item.waitingForMe || (item.snapshot == nil && authVM.isAdmin)) : true) {
            var task = AdminTodayTask(
                id: "req-\(item.id.uuidString)",
                title: "\(item.verb) \(item.typeTitle) · \(item.name)",
                detail: item.subtitle,
                marks: item.isUrgent ? 3 : item.isLate ? 2 : 0,
                source: AdminArea.inbox.title, sourceIcon: "tray.fill",
                target: .inbox(item.id))
            if item.isUrgent {
                task.flag = L10n.t("عاجل", "Urgent")
                task.flagIcon = "flame"
                task.flagTint = DS.Color.error
            } else if item.isLate {
                task.flag = AdminTodayText.late(item.snapshot)
                task.flagTint = DS.Color.error
            }
            tasks.append(task)
        }

        // وفاة لم يُعلن عنها (المالك والمدير)
        if authVM.isAdmin {
            for m in unannounced {
                tasks.append(AdminTodayTask(
                    id: "death-\(m.id.uuidString)",
                    title: L10n.t("أعلن وفاة \(m.shortFullName)", "Announce \(m.shortFullName)'s death"),
                    detail: L10n.t("سُجّلت وفاته ولم يُعلن عنها", "Recorded but not announced"),
                    marks: 0, source: AdminArea.occasions.title, sourceIcon: "calendar.badge.clock",
                    target: .announce(m.id)))
            }
        }

        // رسائل لم يُتعامل معها
        let pending = adminRequestVM.contactMessages
            .filter { $0.status == ApprovalStatus.pending.rawValue }
            .sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
        for msg in pending {
            let category = ContactCategoryInfo.from(raw: ContactParser.category(of: msg)).title
            tasks.append(AdminTodayTask(
                id: "msg-\(msg.id.uuidString)",
                title: L10n.t("رُدّ على رسالة \(msg.member?.shortFullName ?? "عضو")",
                              "Reply to \(msg.member?.shortFullName ?? "a member")"),
                detail: [category, AdminTodayText.since(ContactParser.date(msg.createdAt))]
                    .compactMap { $0 }.joined(separator: " · "),
                marks: 0, source: L10n.t("الرسائل", "Messages"), sourceIcon: "bubble.left.fill",
                target: .messages))
        }
        return tasks
    }

    // MARK: القائمة الموحّدة «يحتاج قرارك»

    /// يدمج القرارات والمهام: صفّ واحد لكل طلب (المهمة «راجع انضمام · فلان» بدل تكرارها تحت القرار)، ثم رسائل
    /// الأعضاء. رصيد الرسائل (سطر الحالة) والوفيات غير المعلنة («إشعارات الإدارة») لها بيتها وزرّها هناك. الترتيب: المستعجل ←
    /// المتأخر ← ما عليك ← ما عند غيرك، ثم بترتيب الوصول.
    static func entries(items: [AdminDecisionItem], tasks: [AdminTodayTask]) -> [AdminTodayEntry] {
        var taskById: [String: AdminTodayTask] = [:]
        for task in tasks { taskById[task.id] = task }
        var ranked: [(rank: Int, entry: AdminTodayEntry)] = []

        for item in items {
            let task = taskById["req-\(item.id.uuidString)"]
            let chip: AdminTodayEntry.Chip?
            if item.isUrgent {
                chip = .init(text: L10n.t("عاجل", "Urgent"), icon: "flame.fill", tint: DS.Color.warning)
            } else if item.isLate {
                chip = .init(text: AdminTodayText.late(item.snapshot), icon: "clock", tint: DS.Color.error)
            } else if item.snapshot != nil {
                chip = AdminTodayText.since(item.date).map { .init(text: $0, tint: DS.Color.textTertiary) }
            } else {
                chip = nil // بلا مسار: سطر الحالة نفسه «منذ…» — لا تكرار
            }
            let rank = item.isUrgent ? 0 : item.isLate ? 1 : task != nil ? 2 : 3
            ranked.append((rank, AdminTodayEntry(
                id: "req-\(item.id.uuidString)", isTask: task != nil, icon: item.icon, tint: item.tint,
                title: task?.title ?? (item.typeTitle + " · " + item.name),
                subtitle: item.subtitle, chip: chip, target: .inbox(item.id))))
        }
        for task in tasks where task.target == .messages {
            ranked.append((2, AdminTodayEntry(
                id: task.id, isTask: true, icon: task.sourceIcon, tint: DS.Color.sea,
                title: task.title, subtitle: task.detail ?? "", target: .messages)))
        }
        return ranked.enumerated()
            .sorted { $0.element.rank != $1.element.rank ? $0.element.rank < $1.element.rank : $0.offset < $1.offset }
            .map(\.element.entry)
    }
}

// MARK: - ذاكرة مهام اليوم

/// ما ظهر من مهام اليوم — المهمة التي ظهرت اليوم ثم اختفى ما خلفها (حُلّ الطلب، شُحن الرصيد، أُعلنت الوفاة)
/// تُعرض «منجزة». لا تأشير يدوي: الدائرة حالة فقط. تُنسى مع بداية يوم جديد (مفتاح باليوم والمستخدم).
/// ويحمل آخر صفوف «يحتاج قرارك» لصفحة «عرض الكل» (تتحدّث معها وهي مفتوحة).
@MainActor
final class AdminTodayTaskStore: ObservableObject {
    struct Record: Codable, Identifiable, Equatable {
        let id: String
        var title: String
        var source: String
        var sourceIcon: String
        var doneAt: Date?
    }

    @Published private(set) var done: [Record] = []
    /// صفوف القائمة الموحّدة كاملة، وعدّاد «الوارد» — من «اليوم» بعد اكتمال التحميل
    @Published private(set) var entries: [AdminTodayEntry] = []
    @Published private(set) var inboxTotal = 0
    @Published private(set) var loaded = false
    private var records: [String: Record] = [:]
    private var key = ""

    func publish(entries list: [AdminTodayEntry], inboxTotal total: Int) {
        if list != entries { entries = list }
        if total != inboxTotal { inboxTotal = total }
        if !loaded { loaded = true }
    }

    private static func dayKey(user: UUID?, role: String) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "adminTodayTasks.\(user?.uuidString ?? "-").\(role).\(f.string(from: Date()))"
    }

    /// يُستدعى بعد اكتمال تحميل البيانات فقط — قبله تبدو كل المهام «محلولة»
    func sync(open: [AdminTodayTask], user: UUID?, role: String) {
        let k = Self.dayKey(user: user, role: role)
        if k != key {
            key = k
            if let data = UserDefaults.standard.data(forKey: k),
               let saved = try? JSONDecoder().decode([String: Record].self, from: data) {
                records = saved
            } else {
                records = [:]
            }
        }
        let openIds = Set(open.map(\.id))
        for task in open {
            records[task.id] = Record(id: task.id, title: task.title, source: task.source,
                                      sourceIcon: task.sourceIcon, doneAt: nil)
        }
        for (id, rec) in records where rec.doneAt == nil && !openIds.contains(id) {
            records[id]?.doneAt = Date()
        }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: k)
        }
        let list = records.values.filter { $0.doneAt != nil }.sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
        if list != done { done = list }
    }

    /// منجز اليوم المحفوظ لهذا المستخدم والدور — يقرؤه سطر «المنجز اليوم» آخر «الوارد» (كان «عرض المنجز» في «عرض الكل»)
    static func doneToday(user: UUID?, role: String) -> [Record] {
        guard let data = UserDefaults.standard.data(forKey: dayKey(user: user, role: role)),
              let saved = try? JSONDecoder().decode([String: Record].self, from: data) else { return [] }
        return saved.values.filter { $0.doneAt != nil }.sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }
}

// MARK: - قراءات إضافية من دوال موجودة (لا شيء جديد على السيرفر)

enum AdminTodayFetch {
    /// الوفيات المعلن عنها — nil إن تعذّر الجلب (فلا يظهر تنبيه «لم يُعلن عنها» خطأً)
    static func announcedDeathIds() async -> Set<UUID>? {
        struct Row: Decodable { let member_id: UUID }
        do {
            let rows: [Row] = try await SupabaseConfig.client
                .from("death_announcements").select("member_id").execute().value
            return Set(rows.map(\.member_id))
        } catch {
            return nil
        }
    }

    /// عدد من يستخدم التطبيق الآن (`get_active_members_now` — المالك والمدير)
    static func activeNowCount() async -> Int? {
        struct Row: Decodable { let member_id: UUID }
        do {
            let response = try await SupabaseConfig.client.rpc("get_active_members_now").execute()
            let rows = try JSONDecoder().decode([Row].self, from: response.data)
            return Set(rows.map(\.member_id)).count
        } catch {
            return nil
        }
    }

    /// المنجز هذا الأسبوع من «تقرير الموافقات» (نُفّذ + رُفض خلال ٧ أيام) — nil إن لم يتوفّر
    static func weeklyDone() async -> (executed: Int, rejected: Int)? {
        nonisolated struct Params: Encodable { let p_from: String; let p_to: String }
        let to = Date()
        guard let from = Calendar.current.date(byAdding: .day, value: -7, to: to) else { return nil }
        let iso = ISO8601DateFormatter()
        do {
            let report: ApprovalsReport = try await SupabaseConfig.client
                .rpc("approvals_report", params: Params(p_from: iso.string(from: from), p_to: iso.string(from: to)))
                .execute().value
            return (report.totals.executed, report.totals.rejected)
        } catch {
            return nil
        }
    }
}
