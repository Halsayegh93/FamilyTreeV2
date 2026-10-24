import Foundation

// MARK: - «أسبوع المجالس»: منطق الترتيب الجديد (طلب المالك ٢٠٢٦-١٠-٢٤ «ابي ترتيب جديد للديوانيات»)
//
// المنطق وحده هنا بلا واجهة (الواجهة في `DiwaniyaBoard.swift`):
//  • `DiwaniyaSchedule` — يقرأ الموعد من البيانات: الأيام المهيكلة (وإلا من النص القديم) ووقت البداية والنهاية.
//  • `DiwaniyaTonight` — حال مجلس اليوم: مفتوح الآن / يبدأ بعد قليل / انتهى.
//  • `DiwaniyaOrganizer` — يرتّب القائمة: بانتظار الاعتماد ← الليلة ← الأيام القادمة بالترتيب (كل مجلس مرة
//    واحدة تحت أقرب موعد له) ← بلا موعد ثابت ← متوقفة. واختيار يوم من شريط الأسبوع = مجالس ذلك اليوم كلها.

/// مصدر الوقت للترتيب — `override` يثبّت لحظة للتجربة (لقطات الشاشة)
enum DiwaniyaClock {
    static var override: Date?
    static var now: Date { override ?? Date() }
}

// MARK: - أيام الأسبوع

/// أيام الأسبوع بترقيم نموذج الإضافة: ٠=السبت … ٦=الجمعة
enum DiwaniyaWeek {
    static let count = 7

    /// التقويم الميلادي بتوقيت الجهاز — مثل بقية التطبيق (لا يتأثر بتقويم هجري/بوذي في الإعدادات)
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .autoupdatingCurrent
        return c
    }()

    private static let names: [(ar: String, en: String)] = [
        ("السبت", "Saturday"), ("الأحد", "Sunday"), ("الإثنين", "Monday"), ("الثلاثاء", "Tuesday"),
        ("الأربعاء", "Wednesday"), ("الخميس", "Thursday"), ("الجمعة", "Friday"),
    ]
    /// الاسم المختصر لخانات شريط الأسبوع
    private static let shortNames: [(ar: String, en: String)] = [
        ("سبت", "Sat"), ("أحد", "Sun"), ("إثنين", "Mon"), ("ثلاثاء", "Tue"),
        ("أربعاء", "Wed"), ("خميس", "Thu"), ("جمعة", "Fri"),
    ]
    /// حرف اليوم — نفس دوائر نموذج الإضافة
    private static let letters: [(ar: String, en: String)] = [
        ("س", "S"), ("ح", "S"), ("ن", "M"), ("ث", "T"), ("ر", "W"), ("خ", "T"), ("ج", "F"),
    ]
    /// كتابات قديمة للأيام داخل نص الموعد (قبل عمود الأيام) — للقراءة فقط
    private static let legacySpellings: [Int: [String]] = [2: ["الاثنين"], 4: ["الاربعاء"]]

    static func wrap(_ i: Int) -> Int { ((i % count) + count) % count }
    static func name(_ i: Int) -> String { let n = names[wrap(i)]; return L10n.t(n.ar, n.en) }
    static func shortName(_ i: Int) -> String { let n = shortNames[wrap(i)]; return L10n.t(n.ar, n.en) }
    static func letter(_ i: Int) -> String { let n = letters[wrap(i)]; return L10n.t(n.ar, n.en) }

    /// رقم يوم التاريخ (٠=السبت) — في الميلادي: الأحد=١ … السبت=٧
    static func index(of date: Date) -> Int { calendar.component(.weekday, from: date) % count }

    /// دقائق التاريخ من منتصف الليل
    static func minutes(of date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// الأيام المذكورة في نص موعد قديم («كل الأحد - …»، «كل يوم») — نفس قراءة مربّع التعديل
    static func days(in text: String) -> [Int] {
        if text.contains("كل يوم") || text.contains("يومي") || text.localizedCaseInsensitiveContains("every day")
            || text.localizedCaseInsensitiveContains("daily") {
            return Array(0..<count)
        }
        return (0..<count).filter { i in
            let spellings = [names[i].ar, names[i].en] + (legacySpellings[i] ?? [])
            return spellings.contains { text.localizedCaseInsensitiveContains($0) }
        }
    }

    /// «24 أكتوبر» / «Oct 24» — بأرقام لاتينية مثل أوقات المواعيد
    static func shortDate(_ date: Date) -> String {
        let f = L10n.isArabic ? arDate : enDate
        return f.string(from: date)
    }

    /// «السبت 24 أكتوبر» / «Saturday, Oct 24»
    static func longDate(_ date: Date) -> String {
        L10n.isArabic ? "\(name(index(of: date))) \(arDate.string(from: date))"
                      : "\(name(index(of: date))), \(enDate.string(from: date))"
    }

    /// رقم اليوم في الشهر («24»)
    static func dayNumber(_ date: Date) -> String { "\(calendar.component(.day, from: date))" }

    private static let arDate: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "ar@numbers=latn")
        f.dateFormat = "d MMMM"
        return f
    }()

    private static let enDate: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        return f
    }()
}

// MARK: - الموعد

/// موعد المجلس كما تقرؤه القائمة: أيام الانعقاد ووقت البداية/النهاية (دقائق من منتصف الليل)
struct DiwaniyaSchedule: Hashable {
    /// مرتّبة بلا تكرار (٠=السبت)
    let days: [Int]
    let start: Int?
    let end: Int?
    /// نص الموعد إن لم تُفهم منه أيام (قديم أو حرّ: «حسب المناسبات»)
    let freeText: String?

    /// مجلس بوقت بداية فقط: نفترض أنه يمتد ٣ ساعات (لحساب «مفتوحة الآن»)
    static let assumedLength = 180
    private static let dayMinutes = 24 * 60

    init(_ d: Diwaniya) {
        let text = d.scheduleText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let structured = (d.scheduleDays ?? []).filter { (0..<DiwaniyaWeek.count).contains($0) }
        let days = structured.isEmpty ? DiwaniyaWeek.days(in: text) : structured
        self.days = Array(Set(days)).sorted()

        let times = Self.times(in: text)
        start = times.first
        if times.count > 1, let last = times.last, let first = times.first, last > first {
            end = last
        } else if let first = times.first {
            end = min(first + Self.assumedLength, Self.dayMinutes - 1)
        } else {
            end = nil
        }
        self.freeText = self.days.isEmpty && !text.isEmpty ? text : nil
        hasExplicitEnd = times.count > 1
    }

    /// النهاية مكتوبة في الموعد (لا مفترضة)
    let hasExplicitEnd: Bool

    var hasDays: Bool { !days.isEmpty }
    var isDaily: Bool { days.count == DiwaniyaWeek.count }

    /// «7:00 – 11:00 م» / «8:30 م» — nil بلا وقت
    var timeText: String? {
        guard let start else { return nil }
        if hasExplicitEnd, let end {
            return L10n.t("\(Self.clock(start)) – \(Self.clock(end)) \(Self.period(end).ar)",
                          "\(Self.clock(start)) – \(Self.clock(end)) \(Self.period(end).en)")
        }
        return Self.clockWithPeriod(start)
    }

    /// «كل يوم» / «السبت والخميس» / «الإثنين، الأربعاء والجمعة»
    var daysText: String? {
        guard hasDays else { return nil }
        if isDaily { return L10n.t("كل يوم", "Every day") }
        let list = days.map { DiwaniyaWeek.name($0) }
        guard list.count > 1, let last = list.last else { return list.first }
        let head = list.dropLast().joined(separator: L10n.t("، ", ", "))
        return L10n.t("\(head) و\(last)", "\(head) & \(last)")
    }

    /// «8:30 م»
    static func clockWithPeriod(_ m: Int) -> String {
        L10n.t("\(clock(m)) \(period(m).ar)", "\(clock(m)) \(period(m).en)")
    }

    /// «8:30» بنظام ١٢ ساعة
    static func clock(_ m: Int) -> String {
        let h = (m / 60) % 12
        return String(format: "%d:%02d", h == 0 ? 12 : h, m % 60)
    }

    private static func period(_ m: Int) -> (ar: String, en: String) {
        m >= 12 * 60 ? ("م", "PM") : ("ص", "AM")
    }

    /// الأوقات في النص بالدقائق، بترتيب ورودها. أوقات النموذج مسائية (٦–١١ م)، فالساعة بلا «ص»/AM تُقرأ مساءً.
    private static func times(in text: String) -> [Int] {
        let digits = KuwaitPhone.normalizeDigits(text)
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,2})[:٫.](\d{2})"#) else { return [] }
        let range = NSRange(digits.startIndex..., in: digits)
        // «ص»/AM بعد الوقت مباشرة = صباحاً (ما لم يُذكر «م»/PM)
        func marked(_ pattern: String) -> Bool {
            (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?
                .firstMatch(in: digits, range: range) != nil
        }
        let morning = marked(#"\d\s*(ص|صباح|a\.?m\b)"#) && !marked(#"\d\s*(م|مساء|p\.?m\b)"#)
        return regex.matches(in: digits, range: range).compactMap { match -> Int? in
            guard let hr = Range(match.range(at: 1), in: digits), let mr = Range(match.range(at: 2), in: digits),
                  let h = Int(digits[hr]), let m = Int(digits[mr]), h <= 23, m < 60 else { return nil }
            let hour = h >= 12 || morning ? h % 24 : h + 12
            return hour * 60 + m
        }
    }
}

// MARK: - حال الليلة

/// حال مجلس اليوم بالنسبة للساعة الآن
enum DiwaniyaTonight: Hashable {
    /// مفتوح الآن — التقدّم ٠…١ ووقت الانتهاء
    case live(progress: Double, end: Int)
    /// يبدأ لاحقاً الليلة — بعد كم دقيقة
    case upcoming(start: Int, minutes: Int)
    /// انتهى الليلة
    case ended
    /// اليوم بلا وقت معروف
    case today

    /// ترتيب داخل «الليلة»: المفتوح، ثم القادم، ثم بلا وقت، ثم المنتهي
    var rank: Int {
        switch self {
        case .live: return 0
        case .upcoming: return 1
        case .today: return 2
        case .ended: return 3
        }
    }

    var isLive: Bool { if case .live = self { return true } else { return false } }
    var isEnded: Bool { self == .ended }

    static func of(_ s: DiwaniyaSchedule, weekday: Int, minute now: Int) -> DiwaniyaTonight? {
        guard s.days.contains(weekday) else { return nil }
        guard let start = s.start, let end = s.end else { return .today }
        if now < start { return .upcoming(start: start, minutes: start - now) }
        if now < end { return .live(progress: Double(now - start) / Double(max(end - start, 1)), end: end) }
        return .ended
    }
}

// MARK: - المجموعات

/// مجلس داخل مجموعة (قد يظهر نفسه في أكثر من يوم عند اختيار يوم من الشريط)
struct DiwaniyaEntry: Identifiable {
    let item: Diwaniya
    let schedule: DiwaniyaSchedule
    /// حال الليلة — لمجالس اليوم فقط
    let tonight: DiwaniyaTonight?
    let groupId: String
    var id: String { "\(groupId)/\(item.id.uuidString)" }
}

struct DiwaniyaGroup: Identifiable {
    enum Role: Hashable { case pending, day, unscheduled, closed }
    let id: String
    let role: Role
    let title: String
    /// طرف العنوان: التاريخ أو العدد
    let trailing: String?
    let icon: String
    /// بُعد اليوم عن اليوم (٠ = الليلة) — لمجموعات الأيام فقط
    let offset: Int?
    let entries: [DiwaniyaEntry]
}

/// ملخّص الليلة لبطاقة الأسبوع
struct DiwaniyaTonightSummary {
    var live = 0
    var upcoming = 0
    var ended = 0
    /// أقرب وقت قادم الليلة
    var firstStart: Int?
    /// أقرب مجلس بعد الليلة: بُعده بالأيام ووقته
    var nextOffset: Int?
    var nextStart: Int?
}

/// يرتّب المجالس الظاهرة للمستخدم في «أسبوع المجالس» — لحظة واحدة (`now`) لكل الحسابات
struct DiwaniyaOrganizer {
    /// الظاهرة للمستخدم بعد فلتر النوع (المعتمدة + المعلّقة المسموح له برؤيتها)
    let items: [Diwaniya]
    let now: Date
    /// اليوم (٠=السبت) والدقيقة الآن
    let today: Int
    let minute: Int
    private let schedules: [UUID: DiwaniyaSchedule]

    init(items: [Diwaniya], now: Date) {
        self.items = items
        self.now = now
        today = DiwaniyaWeek.index(of: now)
        minute = DiwaniyaWeek.minutes(of: now)
        schedules = Dictionary(items.map { ($0.id, DiwaniyaSchedule($0)) }, uniquingKeysWith: { a, _ in a })
    }

    func schedule(_ d: Diwaniya) -> DiwaniyaSchedule { schedules[d.id] ?? DiwaniyaSchedule(d) }

    private static func isApproved(_ d: Diwaniya) -> Bool { d.approvalStatus == ApprovalStatus.approved.rawValue }
    private static func isPending(_ d: Diwaniya) -> Bool { d.approvalStatus == ApprovalStatus.pending.rawValue }

    /// المعتمدة المفتوحة — هي التي تُرتَّب في الأسبوع
    private var active: [Diwaniya] { items.filter { Self.isApproved($0) && $0.isClosed != true } }

    /// اليوم (٠=السبت) بعد [offset] يوماً
    func weekday(atOffset offset: Int) -> Int { DiwaniyaWeek.wrap(today + offset) }
    /// كم يوماً حتى [weekday] (٠ = اليوم)
    func offset(of weekday: Int) -> Int { DiwaniyaWeek.wrap(weekday - today) }
    /// تاريخ اليوم بعد [offset] يوماً
    func date(atOffset offset: Int) -> Date {
        let cal = DiwaniyaWeek.calendar
        return cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) ?? now
    }

    /// عدد مجالس كل يوم (بالفهرس ٠=السبت) — للنقاط في شريط الأسبوع
    var dayCounts: [Int] {
        var counts = Array(repeating: 0, count: DiwaniyaWeek.count)
        for d in active { for day in schedule(d).days { counts[day] += 1 } }
        return counts
    }

    func tonight(_ d: Diwaniya) -> DiwaniyaTonight? {
        DiwaniyaTonight.of(schedule(d), weekday: today, minute: minute)
    }

    /// أقرب موعد قادم (٠…٧ أيام): اليوم إن لم ينتهِ بعد، وإلا أقرب يوم تالٍ (٧ = نفس اليوم الأسبوع القادم)
    private func nextOffset(_ s: DiwaniyaSchedule) -> Int? {
        guard s.hasDays else { return nil }
        for off in 0..<DiwaniyaWeek.count where s.days.contains(weekday(atOffset: off)) {
            if off == 0, DiwaniyaTonight.of(s, weekday: today, minute: minute)?.isEnded == true { continue }
            return off
        }
        return DiwaniyaWeek.count
    }

    var summary: DiwaniyaTonightSummary {
        var s = DiwaniyaTonightSummary()
        for d in active {
            let sch = schedule(d)
            switch DiwaniyaTonight.of(sch, weekday: today, minute: minute) {
            case .live?: s.live += 1
            case .upcoming(let start, _)?:
                s.upcoming += 1
                s.firstStart = min(s.firstStart ?? start, start)
            case .today?: s.upcoming += 1
            case .ended?: s.ended += 1
            case nil: break
            }
        }
        // أقرب مجلس بعد الليلة — لسطر «أقربها …» حين لا شيء الليلة
        for off in 1...DiwaniyaWeek.count {
            let day = weekday(atOffset: off)
            let starts = active.map { schedule($0) }.filter { $0.days.contains(day) }
            guard !starts.isEmpty else { continue }
            s.nextOffset = off
            s.nextStart = starts.compactMap(\.start).min()
            break
        }
        return s
    }

    /// المجموعات بالترتيب. [day] = يوم مختار من الشريط (مجالسه كلها)، nil = الأسبوع القادم كله.
    func groups(day: Int?) -> [DiwaniyaGroup] {
        if let day { return [dayGroup(offset: offset(of: day), entries: entriesMeeting(on: day))] }

        var result: [DiwaniyaGroup] = []
        // ١) بانتظار الاعتماد — أولاً (الإدارة تعتمد من هنا، وصاحبها يرى طلبه)
        let pending = items.filter { Self.isPending($0) }.sorted { $0.title < $1.title }
        if !pending.isEmpty {
            result.append(DiwaniyaGroup(id: "pending", role: .pending,
                                        title: L10n.t("بانتظار الاعتماد", "Awaiting approval"),
                                        trailing: "\(pending.count)", icon: "clock.badge.questionmark",
                                        offset: nil,
                                        entries: pending.map { entry($0, tonight: nil, group: "pending") }))
        }

        // ٢) الأيام بالترتيب من الليلة — كل مجلس مرة واحدة تحت أقرب موعد له
        var buckets: [Int: [Diwaniya]] = [:]
        var unscheduled: [Diwaniya] = []
        for d in active {
            if let off = nextOffset(schedule(d)) { buckets[off, default: []].append(d) } else { unscheduled.append(d) }
        }
        for off in 0...DiwaniyaWeek.count {
            guard let list = buckets[off], !list.isEmpty else { continue }
            let id = "day\(off)"
            result.append(dayGroup(offset: off, entries: sorted(list.map {
                entry($0, tonight: off == 0 ? tonight($0) : nil, group: id)
            })))
        }

        // ٣) بلا موعد ثابت
        if !unscheduled.isEmpty {
            result.append(DiwaniyaGroup(id: "unscheduled", role: .unscheduled,
                                        title: L10n.t("بلا موعد ثابت", "No fixed schedule"),
                                        trailing: "\(unscheduled.count)", icon: "calendar.badge.exclamationmark",
                                        offset: nil,
                                        entries: unscheduled.sorted { $0.title < $1.title }
                                            .map { entry($0, tonight: nil, group: "unscheduled") }))
        }

        // ٤) متوقفة حالياً — آخر القائمة
        let closed = items.filter { Self.isApproved($0) && $0.isClosed == true }.sorted { $0.title < $1.title }
        if !closed.isEmpty {
            result.append(DiwaniyaGroup(id: "closed", role: .closed,
                                        title: L10n.t("متوقفة حالياً", "Paused for now"),
                                        trailing: "\(closed.count)", icon: "pause.circle.fill",
                                        offset: nil,
                                        entries: closed.map { entry($0, tonight: nil, group: "closed") }))
        }
        return result
    }

    /// مجالس يوم من الشريط (المعتمدة المفتوحة التي تنعقد فيه) بترتيب الوقت
    private func entriesMeeting(on day: Int) -> [DiwaniyaEntry] {
        let off = offset(of: day)
        let id = "day\(off)"
        return sorted(active.filter { schedule($0).days.contains(day) }
            .map { entry($0, tonight: off == 0 ? tonight($0) : nil, group: id) })
    }

    private func entry(_ d: Diwaniya, tonight: DiwaniyaTonight?, group: String) -> DiwaniyaEntry {
        DiwaniyaEntry(item: d, schedule: schedule(d), tonight: tonight, groupId: group)
    }

    /// الليلة: المفتوح ثم القادم ثم بلا وقت ثم المنتهي؛ وبعدها بوقت البداية ثم الاسم
    private func sorted(_ list: [DiwaniyaEntry]) -> [DiwaniyaEntry] {
        list.sorted { a, b in
            let ra = a.tonight?.rank ?? 0, rb = b.tonight?.rank ?? 0
            if ra != rb { return ra < rb }
            let sa = a.schedule.start ?? Int.max, sb = b.schedule.start ?? Int.max
            if sa != sb { return sa < sb }
            return a.item.title < b.item.title
        }
    }

    private func dayGroup(offset off: Int, entries: [DiwaniyaEntry]) -> DiwaniyaGroup {
        let day = weekday(atOffset: off)
        let title: String
        switch off {
        case 0: title = L10n.t("الليلة", "Tonight")
        case 1: title = L10n.t("غداً", "Tomorrow")
        case DiwaniyaWeek.count: title = L10n.t("\(DiwaniyaWeek.name(day)) القادم", "Next \(DiwaniyaWeek.name(day))")
        default: title = DiwaniyaWeek.name(day)
        }
        // «الليلة» بلا تاريخ (هو في بطاقة الأسبوع فوقها)، و«غداً» بيومه وتاريخه، وغيرهما بالتاريخ
        let trailing: String?
        switch off {
        case 0: trailing = nil
        case 1: trailing = DiwaniyaWeek.longDate(date(atOffset: off))
        default: trailing = DiwaniyaWeek.shortDate(date(atOffset: off))
        }
        return DiwaniyaGroup(id: "day\(off)", role: .day, title: title, trailing: trailing,
                             icon: off == 0 ? "moon.stars.fill" : "calendar",
                             offset: off, entries: entries)
    }
}

// MARK: - الاعتماد من القسم نفسه

extension DiwaniyasViewModel {
    /// اعتماد من زرّ البطاقة في القسم: بيانات الطلب تصل لإشعار صاحبه (الاعتماد يقرؤها من المعلّقة)،
    /// والبطاقة تنتقل فوراً لمكانها في الأسبوع ثم يُحدَّث من السيرفر
    /// true = أُرسل الاعتماد (لحظة «تم الاعتماد»)؛ بلا صلاحية أو اتصال يتولّى الاعتماد نفسه السبب كما هو
    @discardableResult
    func approveFromSection(_ d: Diwaniya, adminId: UUID) async -> Bool {
        guard authVM?.isAdmin == true, NetworkMonitor.shared.isConnected else {
            await approveDiwaniya(id: d.id, adminId: adminId)
            return false
        }
        if !pendingDiwaniyas.contains(where: { $0.id == d.id }) { pendingDiwaniyas.append(d) }
        if let i = diwaniyas.firstIndex(where: { $0.id == d.id }) {
            diwaniyas[i].approvalStatus = ApprovalStatus.approved.rawValue
        }
        // يُحدِّث المعلّقة والقائمة من السيرفر بعد التنفيذ
        await approveDiwaniya(id: d.id, adminId: adminId)
        return true
    }

    /// رفض من البطاقة: نفس رفض «طلبات المراجعة» (حذف الطلب وإشعار صاحبه)، والبطاقة تختفي فوراً.
    /// لو فشل الرفض يظهر تنبيه الخطأ، و«إعادة المحاولة» فيه تعيد القائمة من السيرفر.
    func rejectFromSection(_ d: Diwaniya) async {
        guard authVM?.isAdmin == true else { return }
        if !pendingDiwaniyas.contains(where: { $0.id == d.id }) { pendingDiwaniyas.append(d) }
        diwaniyas.removeAll { $0.id == d.id }
        await rejectDiwaniya(id: d.id)
    }
}
