import Foundation

// MARK: - «نبّهه يضيف صورة» + التذكير — المنطق الخالص (الوحدة P1، طلب المالك ٢٠٢٦-١١-٢٦)
//
// «اذا حساب مسجل و مو حاط صورة بملفه … نحط زر ينبهه يحط صورة شخصية» · «ابى تذكير طلب اضافة صورة شخصية» ·
// «مابي التنبيه يكون بشكل يومي كل ما يدخل التطبيق».
// السيرفر: 20261126180000_photo_add_request (request_photo_change بلا سبب لمن لا صورة له، request_photo_add_all،
// photo_requests_remind_tick يومياً 18:00 الكويت). هذا الملف Foundation فقط — يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /private/tmp/claude-501/p1-logic \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/PhotoNudgeLogic.swift tests/admin-redesign/P1/main.swift \
//     && /private/tmp/claude-501/p1-logic
// الواجهات: PhotoNudgeViews.swift (صفّ ورقة العضو، قائمة «مسجّلون بلا صورة»، إعدادات المالك) و`PhotoReminderGate`.

nonisolated enum PhotoNudgeLogic {
    /// مفاتيح `app_config` (يعدّلها المالك من «التطبيق» ← «قواعد الأعضاء»)
    static let remindDaysKey = "photo_request_remind_days"
    static let maxRemindersKey = "photo_request_max_reminders"
    /// افتراضي السيرفر حين يغيب المفتاح (قبل الترحيل)
    static let defaultRemindDays = 3
    static let defaultMaxReminders = 3
    /// حدود المفتاحين على السيرفر
    static let remindDaysRange = 0...30
    static let maxRemindersRange = 0...10
    /// «ذكّره الحين» يختفي دقيقة بعد كل إشعار (السيرفر لا يعيد الإشعار قبلها)
    static let remindCooldown: TimeInterval = 60
    /// «نبّههم كلهم» يتخطّى من نُبّه خلال هذه الأيام (نفس السيرفر)
    static let bulkSkipDays = 7

    // MARK: المدخلات

    /// من ينظر: صلاحية الدور × «يعدّل» القسم
    struct Viewer: Equatable {
        let id: UUID?
        /// المالك/المدير/المراقب (`canEditMembers`) × «يعدّل» «العائلة»
        let canEdit: Bool
        let isOwner: Bool
        /// «نبّههم كلهم» — المالك والمدير (`isAdmin`) × «يعدّل» «العائلة»
        let canBulk: Bool
        /// F4 (S-4): يقرأ `photo_change_requests` (RLS: المالك والمدير والمراقب) — غيره يرى «—» لا «لم يُنبَّه بعد»
        var canReadStatus: Bool = true
    }

    /// العضو كما تراه الإدارة
    struct Member: Equatable {
        let id: UUID
        let isDeceased: Bool
        /// له حساب دخول (`AdminAccountsStore`)
        let hasLogin: Bool
        let hasPhoto: Bool
        let isFemale: Bool
        let isOwner: Bool
        /// الحالة «مفعّل» وليس «معلّق» (لا موقوف ولا محذوف)
        let isActive: Bool
    }

    /// الطلب المفتوح كما يُقرأ (الأعمدة الجديدة nil على السيرفر القديم)
    struct Open: Equatable {
        let notifiedAt: Date?
        let requestedAt: Date?
        let remindersSent: Int?
        let reason: String
        let hidePhoto: Bool

        /// آخر إشعار وصله
        var lastNotice: Date? { notifiedAt ?? requestedAt }
    }

    // MARK: الصورة

    /// صورة = `avatar_url` أو `photo_url` غير فارغ (نفس السيرفر)
    static func hasPhoto(avatar: String?, photo: String?) -> Bool {
        [avatar, photo].contains { !($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: من يرى الزرّ

    /// شروط الطلب المشتركة (= `canRequestPhotoChange` القديمة بلا شرط الصورة): عضو مسجّل حيّ، ليس أنت، والمالك لا يُطلب
    /// منه إلا من مالك
    static func canAct(_ viewer: Viewer, _ m: Member) -> Bool {
        viewer.canEdit && !m.isDeceased && m.hasLogin && m.id != viewer.id && (!m.isOwner || viewer.isOwner)
    }

    /// «نبّهه يضيف صورة»: بلا صورة، وليس أنثى (لا صور للإناث — السيرفر يفرّغها ويرفض `female_no_photo`)، ومفعّل: مسار «أضف»
    /// يرفض الموقوف والمعلّق (`account_frozen`، 20261126200000 V12 — تدقيق الكرت ٢٠٢٦-١١-٢٧: كان الزرّ يظهر ويُرفض)
    static func canNudge(_ viewer: Viewer, _ m: Member) -> Bool {
        canAct(viewer, m) && !m.hasPhoto && !m.isFemale && m.isActive
    }

    /// «طلب تغيير الصورة» (المربّع بالسبب): له صورة
    static func canAskChange(_ viewer: Viewer, _ m: Member) -> Bool {
        canAct(viewer, m) && m.hasPhoto
    }

    /// F4 (V10): «إلغاء التنبيه» — لا على ورقتك (طلب الإدارة لك لا تلغيه بنفسك). يبقى للمتوفى ولمن فقد حسابه (طلبه
    /// المفتوح يُغلق من هنا)، وعلى ورقة المالك كما كان (السيرفر يسمح للطاقم)
    static func canCancel(_ viewer: Viewer, _ m: Member) -> Bool {
        viewer.canEdit && m.id != viewer.id
    }

    // MARK: حالات الصفّ

    enum Row: Equatable {
        /// لا صفّ
        case hidden
        /// «نبّهه يضيف صورة»
        case nudge
        /// «طلب تغيير الصورة» — يفتح مربّع السبب
        case askChange
        /// طلب مفتوح: السطر و«ذكّره الحين» و«إلغاء التنبيه»
        case pending(Pending)
    }

    struct Pending: Equatable {
        /// طلب «أضف» (لا صورة الآن) أم «غيّر»
        let isAdd: Bool
        /// «نُبّه قبل 5 أيام · ذُكّر 1 من 3 · بانتظار صورته»
        let line: String
        /// السبب (طلب التغيير فقط) — nil = لا سطر
        let reason: String?
        /// «ذكّره الحين» ظاهر
        let canRemind: Bool
        /// متى يعود «ذكّره الحين» (بعد دقيقة من آخر إشعار) — nil = ظاهر أو لا يعود
        let remindAt: Date?
        /// «إلغاء التنبيه» ظاهر
        let canCancel: Bool
    }

    static func row(viewer: Viewer, member m: Member, open: Open?, maxReminders: Int,
                    now: Date = Date(), calendar: Calendar = .current) -> Row {
        guard viewer.canEdit else { return .hidden }
        if let open {
            // F4 (V24): المتوفى بطلب مفتوح (قبل ترحيل 20261126200000 الذي يغلقه) — السطر و«إلغاء التنبيه» بلا تذكير
            let eligible = !m.isDeceased && (m.hasPhoto ? canAskChange(viewer, m) : canNudge(viewer, m))
            let ready = canRemindNow(open, now: now)
            let reason = open.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return .pending(Pending(
                isAdd: !m.hasPhoto,
                line: pendingLine(open, isAdd: !m.hasPhoto, maxReminders: maxReminders, now: now, calendar: calendar),
                reason: m.hasPhoto && !reason.isEmpty ? reason : nil,
                canRemind: eligible && ready,
                remindAt: eligible && !ready ? open.lastNotice.map { $0.addingTimeInterval(remindCooldown) } : nil,
                canCancel: canCancel(viewer, m)))
        }
        guard !m.isDeceased else { return .hidden }
        if m.hasPhoto { return canAskChange(viewer, m) ? .askChange : .hidden }
        return canNudge(viewer, m) ? .nudge : .hidden
    }

    /// السيرفر يعيد الإشعار بعد دقيقة من آخره — قبلها «ذكّره الحين» مخفي
    static func canRemindNow(_ open: Open, now: Date) -> Bool {
        guard let last = open.lastNotice else { return true }
        return now.timeIntervalSince(last) >= remindCooldown
    }

    // MARK: النصوص

    /// أيام تقويمية بين آخر إشعار واليوم
    static func daysSince(_ date: Date, now: Date, calendar: Calendar = .current) -> Int {
        let from = calendar.startOfDay(for: date)
        let to = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    /// «نُبّه اليوم» · «نُبّه أمس» · «نُبّه قبل يومين» · «نُبّه قبل 5 أيام» · «نُبّه قبل 12 يوماً»
    static func notifiedText(days: Int) -> String {
        switch days {
        case ..<1: return L10n.t("نُبّه اليوم", "Notified today")
        case 1:    return L10n.t("نُبّه أمس", "Notified yesterday")
        case 2:    return L10n.t("نُبّه قبل يومين", "Notified 2 days ago")
        case 3...10: return L10n.t("نُبّه قبل \(days) أيام", "Notified \(days) days ago")
        default:   return L10n.t("نُبّه قبل \(days) يوماً", "Notified \(days) days ago")
        }
    }

    /// «ذُكّر 1 من 3» — nil بلا تذكير بعد أو على السيرفر القديم؛ «ذُكّر 4» إن تجاوز الحدّ (تذكير يدوي) أو الحدّ صفر
    static func remindersText(sent: Int?, max maxReminders: Int) -> String? {
        guard let sent, sent > 0 else { return nil }
        if maxReminders > 0 && sent <= maxReminders {
            return L10n.t("ذُكّر \(sent) من \(maxReminders)", "Reminded \(sent) of \(maxReminders)")
        }
        return L10n.t("ذُكّر \(sent)", "Reminded \(sent)")
    }

    /// «بانتظار صورته» / «بانتظار صورته الجديدة»
    static func waitingText(isAdd: Bool) -> String {
        isAdd ? L10n.t("بانتظار صورته", "Waiting for a photo") : L10n.t("بانتظار صورته الجديدة", "Waiting for a new photo")
    }

    /// سطر ورقة العضو: «نُبّه قبل 5 أيام · ذُكّر 1 من 3 · بانتظار صورته»
    static func pendingLine(_ open: Open, isAdd: Bool, maxReminders: Int, now: Date, calendar: Calendar = .current) -> String {
        var parts = [shortLine(open, maxReminders: maxReminders, now: now, calendar: calendar)]
        parts.append(waitingText(isAdd: isAdd))
        return parts.joined(separator: " · ")
    }

    /// سطر قائمة «مسجّلون بلا صورة»: «نُبّه قبل 5 أيام · ذُكّر 1 من 3» (بلا طلب: «لم يُنبَّه بعد»)
    static func shortLine(_ open: Open?, maxReminders: Int, now: Date, calendar: Calendar = .current) -> String {
        guard let open else { return L10n.t("لم يُنبَّه بعد", "Not notified yet") }
        var parts: [String] = []
        if let last = open.lastNotice {
            parts.append(notifiedText(days: daysSince(last, now: now, calendar: calendar)))
        } else {
            parts.append(L10n.t("نُبّه", "Notified"))
        }
        if let reminders = remindersText(sent: open.remindersSent, max: maxReminders) { parts.append(reminders) }
        return parts.joined(separator: " · ")
    }

    /// «يصله إشعار، ثم تذكير كل 3 أيام حتى 3 مرات» — شرح صفّ «نبّهه» من إعداد المالك
    static func nudgeExplanation(remindDays: Int, maxReminders: Int) -> String {
        guard remindDays > 0, maxReminders > 0 else {
            return L10n.t("يصله إشعار يطلب منه إضافة صورته", "They get a notification asking for a photo")
        }
        let every = everyDaysText(remindDays)
        let times = timesText(maxReminders)
        return L10n.t("يصله إشعار، ثم تذكير \(every) \(times)", "They get a notification, then a reminder \(every), \(times)")
    }

    // MARK: العدد والمعدود (F4، V32) — «كل يومين» لا «كل 2 أيام»، «14 يوماً» لا «14 أيام»

    private static let days = AdminCountForms(one: "يوم", two: "يومين", few: "أيام", many: "يوماً", single: "يوم")

    /// «كل يوم» · «كل يومين» · «كل 3 أيام» · «كل 11 يوماً»
    static func everyDaysText(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "every day" : "every \(n) days" }
        return "كل \(days.text(n))"
    }

    /// «بعد يوم» · «بعد يومين» · «بعد 7 أيام» · «بعد 14 يوماً» · «بعد 100 يوم» (معدّل «تنبيه الصورة»)
    static func afterDaysText(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "after 1 day" : "after \(n) days" }
        return "بعد \(days.text(n))"
    }

    /// «مرة واحدة» · «حتى مرتين» · «حتى 3 مرات» · «حتى 11 مرة»
    static func timesText(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "once" : "up to \(n) times" }
        if n == 1 { return "مرة واحدة" }
        return "حتى " + AdminCountForms(one: "مرة", two: "مرتين", few: "مرات", many: "مرة", single: "مرة").text(n)
    }

    /// «تذكير واحد» · «حتى تذكيرين» · «حتى 5 تذكيرات» · «حتى 11 تذكيراً» (معدّل «حدّ التذكيرات»)
    static func remindersLimitText(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "1 reminder" : "Up to \(n) reminders" }
        if n == 1 { return "تذكير واحد" }
        return "حتى " + AdminCountForms(one: "تذكير", two: "تذكيرين", few: "تذكيرات", many: "تذكيراً", single: "تذكير").text(n)
    }

    /// سطر صفّ القائمة: «—» قبل وصول الطلبات ولمن لا يقرؤها (المشرف — RLS يرجع لا شيء فكان يقول «لم يُنبَّه بعد»)
    static func listLine(_ open: Open?, known: Bool, viewer: Viewer, maxReminders: Int, now: Date,
                         calendar: Calendar = .current) -> String {
        guard known, viewer.canReadStatus else { return "—" }
        return shortLine(open, maxReminders: maxReminders, now: now, calendar: calendar)
    }

    // MARK: «ذكّره الحين» الصادق (F4، V15) والبيانات القديمة (V11)

    /// السيرفر لا يعيد الإشعار خلال دقيقة من آخره ولا يخطئ — النجاح = تغيّر notified_at (قبل وبعد من السيرفر نفسه، فلا
    /// أثر لفرق ساعة الجهاز). بلا قراءة بعده: نصدّق قبول السيرفر
    static func reminderLanded(before: Date?, after: Date?) -> Bool {
        guard let after else { return true }
        guard let before else { return true }
        return after > before
    }

    static var tooSoonText: String { L10n.t("أُرسل له قبل أقل من دقيقة", "Sent to them less than a minute ago") }
    /// «نبّهه» رُفض لأن له صورة الآن (السيرفر يطلب سبباً لمن له صورة) — البيانات عندنا قديمة
    static var staleText: String { L10n.t("أضاف صورته — حدّثنا البيانات", "They added a photo — the data is refreshed") }

    enum Failure: Equatable {
        /// له صورة الآن: حدّث العضو وقل `staleText`
        case stale
        case message(String)
    }

    /// رسالة رفض السيرفر حسب `hint` — `nudging`: «نبّهه»/«ذكّره» بلا سبب
    static func failure(hint: String?, missingFunction: Bool, nudging: Bool, cancelling: Bool = false) -> Failure {
        if missingFunction { return .message(L10n.t("هذه الميزة تحتاج تحديث السيرفر.", "This feature needs a server update.")) }
        switch hint {
        case "bad_reason" where nudging:
            return .stale
        case "photo_pending":
            return .message(L10n.t("أرسل صورته وهي بانتظار الموافقة — راجعها من «الوارد».",
                                   "They sent a photo that awaits approval — review it in the Inbox."))
        case "account_frozen":
            return .message(L10n.t("حسابه موقوف أو غير مفعّل — لا يصله التنبيه.",
                                   "Their account is suspended or not active — the notice won't reach them."))
        case "female_no_photo":
            return .message(L10n.t("لا صور للإناث في التطبيق.", "Women's profiles don't have photos in the app."))
        case "not_allowed":
            return .message(L10n.t("هذا الإجراء للمالك والمدير والمراقب فقط.", "Only the owner, admins and monitors can do this."))
        case "no_account":
            return .message(L10n.t("ليس لهذا العضو حساب في التطبيق.", "This member has no app account."))
        case "deceased":
            return .message(L10n.t("لا يُرسل الطلب إلى عضو متوفى.", "The request can't be sent for a deceased member."))
        case "member_not_found":
            return .message(L10n.t("العضو غير موجود.", "Member not found."))
        case "own_profile":
            return .message(L10n.t("لا يُرسل الطلب إلى نفسك — غيّر صورتك من «حسابي».",
                                   "You can't send this to yourself — change your photo in My Account."))
        case "owner_protected":
            return .message(L10n.t("لا يُرسل هذا الطلب إلى المالك.", "This request can't be sent to the owner."))
        case "bad_reason":
            return .message(L10n.t("يرجى كتابة السبب (حتى ٢٠٠ حرف).", "Please enter the reason (up to 200 characters)."))
        default:
            return .message(cancelling
                ? L10n.t("تعذّر إلغاء الطلب. تحقق من الاتصال ثم حاول مرة أخرى.", "Couldn't cancel the request. Check your connection and try again.")
                : L10n.t("تعذّر إرسال الطلب. تحقق من الاتصال ثم حاول مرة أخرى.", "Couldn't send the request. Check your connection and try again."))
        }
    }

    // MARK: الدمج بعد الجلب (F4، V31)

    /// نتيجة جلب كل المفتوح مدموجةً مع ما كُتب محلياً بعد بدء الجلب: العضو الذي نُبّه أو أُلغي تنبيهه أثناءه يبقى كما
    /// كتبناه (موجوداً أو غائباً)، والباقي من الجلب (ما أُغلق في مكان آخر يختفي)
    static func merged<V>(fetched: [UUID: V], current: [UUID: V], writtenSince: Set<UUID>) -> [UUID: V] {
        var out = fetched
        for id in writtenSince { out[id] = current[id] }
        return out
    }

    // MARK: قائمة «مسجّلون بلا صورة» (نفس قاعدة السيرفر في `request_photo_add_all`)

    /// عضو مسجّل حيّ مفعّل بلا صورة، ليس أنثى، ليس أنت، والمالك لا يظهر إلا للمالك
    static func isListed(_ m: Member, viewerId: UUID?, viewerIsOwner: Bool) -> Bool {
        m.hasLogin && !m.isDeceased && m.isActive && !m.isFemale && !m.hasPhoto && m.id != viewerId
            && (!m.isOwner || viewerIsOwner)
    }

    /// له حساب لقاعدة القائمة: في قوائم الاستخدام (`AdminAccountsStore`)، أو — لمن تستبعده عمداً: أبناء البنات (لا يُعدّون في
    /// أرقام العائلة) — في قراءة الدخول الإضافية (`AdminAccountsStore.outsideSeen`: حساب دخول أو جهاز) وله رقم، كما يشترط
    /// السيرفر (`private.photo_nudge_listed` بعد 20261127100000 — بلاغ المالك ٢٠٢٦-١١-٢٧)
    static func listLogin(inUsage: Bool, outsideLogin: Bool, hasPhone: Bool) -> Bool {
        inUsage || (outsideLogin && hasPhone)
    }

    /// نُبّه خلال ٧ أيام — «نبّههم كلهم» يتخطّاه
    static func notifiedRecently(_ open: Open?, now: Date) -> Bool {
        guard let last = open?.lastNotice else { return false }
        return now.timeIntervalSince(last) < Double(bulkSkipDays) * 86_400
    }

    /// كم يصله «نبّههم كلهم» من القائمة
    static func bulkCount(listed: [UUID], open: [UUID: Open], now: Date) -> Int {
        listed.filter { !notifiedRecently(open[$0], now: now) }.count
    }

    /// «عضو واحد» · «عضوين» · «5 عضو» (كتابة المالك)
    static func membersText(_ n: Int) -> String {
        switch n {
        case 1:  return L10n.t("عضو واحد", "1 member")
        case 2:  return L10n.t("عضوين", "2 members")
        default: return L10n.t("\(n) عضو", "\(n) members")
        }
    }

    static func bulkButtonTitle(_ n: Int) -> String { L10n.t("نبّههم كلهم (\(n))", "Notify them all (\(n))") }
    static func bulkConfirmMessage(_ n: Int) -> String {
        n == 1 ? L10n.t("يوصل إشعار لعضو واحد", "1 member will be notified")
               : L10n.t("يوصل إشعار لـ \(membersText(n))", "\(membersText(n)) will be notified")
    }
    static func bulkResult(_ n: Int) -> String {
        n == 0 ? L10n.t("لا أحد يحتاج تنبيهاً الآن", "Nobody needs a notice right now")
               : L10n.t("نُبّه \(membersText(n))", "Notified \(membersText(n))")
    }

    // MARK: جانب العضو — مرة لكل إشعار

    enum MemberBox: Equatable { case add, change }

    /// مربّع العضو: «أضف صورتك الشخصية» بلا صورة، و«يرجى تغيير صورتك» بصورة
    static func memberBox(hasPhoto: Bool) -> MemberBox { hasPhoto ? .change : .add }

    /// ما يُحفظ لكل حساب على الجهاز: معرّف الطلب + وقت آخر إشعار (يتغيّر مع كل تذكير)
    static func seenToken(requestId: UUID, notifiedAtRaw: String?, requestedAtRaw: String?) -> String {
        "\(requestId.uuidString.lowercased())|\(notifiedAtRaw ?? requestedAtRaw ?? "")"
    }

    /// عند الفتح: يظهر المربّع إن كان هذا الإشعار لم يُرَ بعد. من الضغط على الإشعار: يظهر دائماً
    static func showsRequestBox(token: String, seen: String?, fromTap: Bool) -> Bool {
        fromTap || token != seen
    }

    /// «يوم» للمقارنة («2026-11-26») بتقويم الجهاز
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// «كمّل ملفك بصورة» لا يظهر في يوم ظهر فيه مربّع طلب الإدارة
    static func generalPopupAllowed(requestBoxDay: String?, today: String) -> Bool {
        requestBoxDay != today
    }

    /// «كمّل ملفك بصورة»: لم يظهر بعد، أو مضت المدة منذ آخر ظهور (أي إغلاق يؤجّله — يُحفظ وقت الظهور)
    static func generalPopupDue(lastShown: Date?, days: Int, now: Date, calendar: Calendar = .current) -> Bool {
        guard days > 0 else { return false }
        guard let lastShown else { return true }
        guard let due = calendar.date(byAdding: .day, value: days, to: lastShown) else { return false }
        return now >= due
    }
}
