import SwiftUI
import Darwin
import os

// MARK: - أدوات فحص لوحة الإدارة (T0، خطة إعادة تصميم الإدارة ٢٠٢٦-١١-٢٦) — DEBUG فقط
//
// أعلام التشغيل (تُقرأ من `ProcessInfo.arguments` مرة واحدة، ولا تُكتب في UserDefaults أبداً):
//   -tmpStackDepth                 مقياس مكدس الخيط الرئيسي: سطر لكل صفحة عليها `.debugStackProbe(…)`، وسطر لتبويب الإدارة
//   -tmpStackCheck                 + سطر لكل «فحص» `DebugAdminProbe.stackCheck(…) { … }` (كلفة بناء جسم واحد ≤ 64 ك.ب)
//   -tmpAdminRole owner|admin|monitor|supervisor   الدور المعروض (يُطبَّق في `AuthViewModel.currentUser`)
//   -tmpRoleMatrix '<json>'        جدول «مين يشوف وش» بدل قيمة السيرفر (نفس شكل `admin_role_matrix`)
//   -tmpFailStores sms,devices@20,…  فشل مصطنع لجلب المخزن؛ `@ثوانٍ` = يفشل بعد أول تحميل ناجح ومضيّ الثواني من الإقلاع
// قيمة غير معروفة = سطر «DEBUG-PROBE ERROR …». سطر إقلاع واحد بما هو مفعّل، وشارة DEBUG صغيرة أسفل الشاشة.
// مع -tmpAdminRole أو -tmpRoleMatrix كل كتابة تمرّ بـ`DebugAdminProbe.dryRun(…)` تُسجَّل «DRY-RUN» ويُصطنع نجاحها:
// السيرفر ما زال يجيب بالحساب الحقيقي (المالك)، فالتجربة تفحص ما يراه الدور لا ما يكتبه.
// في الإصدار (Release) لا يُبنى شيء من هذا: الدوال المتاحة للوحدات بدائل ثابتة (`false` / نفس العرض) يحذفها المترجم.

/// حدود المكدس بالكيلوبايت (الخطة: «اليوم» ≤ 720، تبويب الإدارة ≤ 800، الصفحات ≤ 600، الفحص الواحد ≤ 64)
nonisolated enum DebugStackLimit {
    static let today = 720
    static let tab = 800
    static let page = 600
    static let check = 64
}

nonisolated enum DebugAdminProbe {
    /// المخازن التي يُصطنع فشلها بـ`-tmpFailStores` — المالك: sms·devices·usage = T0، accounts = U11، notices = U18،
    /// inbox = U8، census = U7
    enum Store: String, CaseIterable {
        case sms, devices, accounts, usage, notices, inbox, census
    }
}

#if DEBUG

// MARK: - السجل (stdout غير مخزَّن + os_log) — لا `Log.error`: ذاك يبلّغ السيرفر (`AppDiagnostics`)

nonisolated enum DebugProbeLog {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FamilyTreeV2", category: "DebugProbe")

    static func line(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
        logger.notice("\(text, privacy: .public)")
    }

    static func error(_ text: String) {
        let full = "DEBUG-PROBE ERROR " + text
        FileHandle.standardOutput.write(Data((full + "\n").utf8))
        logger.error("\(full, privacy: .public)")
    }
}

// MARK: - DebugArgs: قراءة الأعلام مرة واحدة

nonisolated struct DebugArgs {
    static let roles = ["owner", "admin", "monitor", "supervisor"]
    static let flags = ["-tmpStackDepth", "-tmpStackCheck", "-tmpAdminRole", "-tmpRoleMatrix", "-tmpFailStores"]
    /// بادئات عائلة هذه الأدوات — علم يبدأ بها وليس منها = خطأ (الأعلام الأخرى `-tmpOffline…`… لا تُمسّ)
    static let families = ["-tmpStack", "-tmpAdmin", "-tmpRole", "-tmpFail"]

    var stackDepth = false
    var stackCheck = false
    /// الدور بعد الفحص (nil = لا تبديل أو قيمة خاطئة)
    var adminRole: String?
    var roleFlagPresent = false
    var roleMatrix: [String: Any]?
    var matrixFlagPresent = false
    /// المخزن ← ثوانٍ (0 = يفشل من أول جلب)
    var failStores: [DebugAdminProbe.Store: Double] = [:]
    var errors: [String] = []

    static let current = DebugArgs(ProcessInfo.processInfo.arguments)
    /// لحظة أول قراءة (الإقلاع عملياً) — مرجع `@ثوانٍ`
    static let launchUptime = ProcessInfo.processInfo.systemUptime

    /// الكتابة تجريبية ما دام علم الدور أو الجدول موجوداً — ولو كانت قيمته خاطئة (الأحوط)
    var isDryRun: Bool { roleFlagPresent || matrixFlagPresent }
    var anyActive: Bool {
        stackDepth || stackCheck || roleFlagPresent || matrixFlagPresent || !failStores.isEmpty || !errors.isEmpty
    }

    init(_ args: [String]) {
        var i = 1
        /// القيمة بعد العلم إن لم تكن علماً آخر
        func next() -> String? {
            guard i + 1 < args.count else { return nil }
            let v = args[i + 1]
            if v.hasPrefix("-"), Double(v) == nil { return nil }
            i += 1
            return v
        }
        func bool(_ flag: String) -> Bool {
            guard let v = next() else { return true }
            switch v.lowercased() {
            case "1", "yes", "true": return true
            case "0", "no", "false": return false
            default:
                errors.append("unknown value \"\(v)\" for \(flag) (use YES|NO or nothing)")
                return false
            }
        }
        while i < args.count {
            let a = args[i]
            switch a {
            case "-tmpStackDepth":
                stackDepth = bool(a)
            case "-tmpStackCheck":
                stackCheck = bool(a)
            case "-tmpAdminRole":
                roleFlagPresent = true
                guard let v = next() else {
                    errors.append("-tmpAdminRole needs a value (\(Self.roles.joined(separator: "|")))")
                    break
                }
                if Self.roles.contains(v) { adminRole = v } else {
                    errors.append("unknown value \"\(v)\" for -tmpAdminRole (use \(Self.roles.joined(separator: "|")))")
                }
            case "-tmpRoleMatrix":
                matrixFlagPresent = true
                guard let v = next() else { errors.append("-tmpRoleMatrix needs a JSON object"); break }
                if let obj = (try? JSONSerialization.jsonObject(with: Data(v.utf8))) as? [String: Any] {
                    roleMatrix = obj
                } else {
                    errors.append("unknown value for -tmpRoleMatrix: not a JSON object: \(v)")
                }
            case "-tmpFailStores":
                guard let v = next() else { errors.append("-tmpFailStores needs a list (sms,devices@20,…)"); break }
                parseFailStores(v)
            default:
                if Self.families.contains(where: { a.hasPrefix($0) }) {
                    errors.append("unknown flag \(a) (known: \(Self.flags.joined(separator: " ")))")
                }
            }
            i += 1
        }
    }

    private mutating func parseFailStores(_ list: String) {
        let names = DebugAdminProbe.Store.allCases.map(\.rawValue).joined(separator: ",")
        let items = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if items.isEmpty { errors.append("unknown value \"\(list)\" for -tmpFailStores (use \(names)[@seconds])") }
        for item in items {
            let parts = item.split(separator: "@", maxSplits: 1).map(String.init)
            guard let store = DebugAdminProbe.Store(rawValue: parts[0]) else {
                errors.append("unknown value \"\(parts[0])\" for -tmpFailStores (use \(names)[@seconds])")
                continue
            }
            var delay = 0.0
            if parts.count == 2 {
                guard let s = Double(parts[1]), s >= 0 else {
                    errors.append("unknown value \"@\(parts[1])\" for -tmpFailStores \(store.rawValue) (use @seconds, e.g. @20)")
                    continue
                }
                delay = s
            }
            failStores[store] = delay
        }
    }

    /// «role=monitor · matrix · fail=sms,devices@20 · stack=depth+check · DRY-RUN»
    var summary: String {
        var parts: [String] = []
        if roleFlagPresent { parts.append("role=\(adminRole ?? "INVALID")") }
        if matrixFlagPresent { parts.append(roleMatrix == nil ? "matrix=INVALID" : "matrix=\(roleMatrix!.keys.sorted().joined(separator: "+"))") }
        if !failStores.isEmpty {
            let list = DebugAdminProbe.Store.allCases.compactMap { s -> String? in
                guard let d = failStores[s] else { return nil }
                return d > 0 ? "\(s.rawValue)@\(Int(d))" : s.rawValue
            }
            parts.append("fail=" + list.joined(separator: ","))
        }
        if stackDepth || stackCheck {
            parts.append("stack=" + [stackDepth ? "depth" : nil, stackCheck ? "check" : nil].compactMap { $0 }.joined(separator: "+"))
        }
        if isDryRun { parts.append("DRY-RUN") }
        if !errors.isEmpty { parts.append("ERRORS=\(errors.count)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - مقياس المكدس: «طلاء» الجزء غير المستعمل من مكدس الخيط الرئيسي بنمط ثابت، ثم البحث عن أعمق كلمة تغيّرت
// (علامة الماء العليا). يُستدعى على الخيط الرئيسي فقط. الطلاء دائماً تحت إطار الدالة الحالية بهامش، فلا يمسّ مكدساً حياً.

nonisolated final class DebugStackMeter {
    static let pattern: UInt64 = 0x5EED_DEB0_C0DE_F00D
    /// هامش تحت نقطة الطلاء في آخر الدورة / قبل الفحص
    static let turnMargin: UInt = 16 * 1024
    static let checkMargin: UInt = 4 * 1024
    /// بُعد عن قاع المكدس (صفحة الحماية تحته)
    static let guardGap: UInt = 16 * 1024
    /// أقصى ما يُراقَب تحت القمة (الجهاز ١ م.ب؛ المحاكي أكبر)
    static let maxSpan: UInt = 1536 * 1024
    static let chunkSize: UInt = 4096

    /// أعلى عنوان في المكدس (يكبر المكدس نزولاً)
    let top: UInt
    /// أدنى عنوان مطليّ
    let floor: UInt
    /// [floor, paintedTop) فيه النمط إلا ما اتّسخ بعد آخر طلاء
    private(set) var paintedTop: UInt
    /// أعمق عنوان سُجِّل داخل الدورة الحالية (من الفحوص)
    private var pendingLow: UInt = .max
    private let chunk: UnsafeMutableRawPointer

    var spanKB: Int { Int((top - floor) / 1024) }

    init?(maxSpan: UInt = DebugStackMeter.maxSpan) {
        guard pthread_main_np() != 0 else { return nil }
        let thread = pthread_self()
        let top = UInt(bitPattern: pthread_get_stackaddr_np(thread))
        let size = UInt(pthread_get_stacksize_np(thread))
        guard size > Self.guardGap * 4, top > size else { return nil }
        self.top = top
        let lowest = max(top - size + Self.guardGap, top - min(size, maxSpan))
        floor = (lowest + 15) & ~UInt(15)
        paintedTop = floor
        chunk = UnsafeMutableRawPointer.allocate(byteCount: Int(Self.chunkSize), alignment: 16)
        var p = Self.pattern
        memset_pattern8(chunk, &p, Int(Self.chunkSize))
    }

    deinit { chunk.deallocate() }

    /// عنوان داخل إطار هذه الدالة ≈ مؤشر المكدس عند المستدعي
    @inline(never) static func here() -> UInt {
        var marker: UInt8 = 0
        return withUnsafeMutablePointer(to: &marker) { UInt(bitPattern: $0) }
    }

    func depthKB(_ address: UInt) -> Int { address >= top ? 0 : Int((top - address) / 1024) }

    /// يطلي [lo, hi) حيث hi تحت إطار هذه الدالة بـ`margin` — يرجع الحدّ الأعلى الجديد للمنطقة المطلية
    @inline(never) private func paint(from lo: UInt, margin: UInt) -> UInt {
        let sp = Self.here()
        guard sp > floor + margin else { return floor }
        let hi = (sp - margin) & ~UInt(15)
        if hi > lo, lo >= floor, let dst = UnsafeMutableRawPointer(bitPattern: lo) {
            memset_pattern8(dst, chunk, Int(hi - lo))
        }
        return max(floor, hi)
    }

    /// أعمق (أدنى) عنوان تغيّر نمطه في [floor, end)
    private func lowestDirty(below end: UInt) -> UInt? {
        var p = floor
        while p < end {
            let n = min(Self.chunkSize, end - p)
            if memcmp(UnsafeRawPointer(bitPattern: p), chunk, Int(n)) != 0 {
                var q = p
                while q < p + n {
                    if UnsafeRawPointer(bitPattern: q)!.load(as: UInt64.self) != Self.pattern { return q }
                    q += 8
                }
            }
            p += n
        }
        return nil
    }

    /// آخر الدورة (الخيط الرئيسي على وشك النوم): أعمق عنوان بلغه المكدس منذ الدورة السابقة — nil = لم ينزل تحت الحدّ
    /// المطليّ — ثم يُعاد طلاء ما اتّسخ
    func endTurn() -> UInt? {
        var low = pendingLow
        pendingLow = .max
        var dirty: UInt?
        if paintedTop > floor {
            dirty = lowestDirty(below: paintedTop)
            if let dirty { low = min(low, dirty) }
        }
        paintedTop = paint(from: min(dirty ?? paintedTop, paintedTop), margin: Self.turnMargin)
        return low == .max ? nil : low
    }

    /// بداية فحص داخل دورة: يحفظ أعمق نقطة حتى الآن، ثم يطلي تحت النقطة الحالية — يرجع عنوان الدخول
    @inline(never) func checkBegin() -> UInt {
        let entry = Self.here()
        var start = paintedTop
        if paintedTop > floor, let d = lowestDirty(below: paintedTop) {
            pendingLow = min(pendingLow, d)
            start = d
        }
        paintedTop = paint(from: min(start, paintedTop), margin: Self.checkMargin)
        pendingLow = min(pendingLow, entry)
        return entry
    }

    /// نهاية الفحص: أعمق عنوان بلغه ما بين البداية والنهاية (أو حدّ الطلاء إن لم ينزل تحته)
    func checkEnd() -> UInt {
        let d = (paintedTop > floor ? lowestDirty(below: paintedTop) : nil) ?? paintedTop
        pendingLow = min(pendingLow, d)
        return d
    }
}

#if !DEBUG_PROBE_TEST

// MARK: - الواجهة للوحدات

extension DebugAdminProbe {
    /// فشل مصطنع (`-tmpFailStores`) — المخزن يعامله كأي خطأ جلب
    struct InjectedFailure: LocalizedError {
        let store: Store
        var errorDescription: String? { "DEBUG -tmpFailStores \(store.rawValue)" }
    }

    /// تجربة دور أو جدول مفعّلة → لا كتابة على السيرفر
    static var isDryRun: Bool { DebugArgs.current.isDryRun }

    /// قبل كل كتابة: `if DebugAdminProbe.dryRun("decide_admin_request approve \(id)") { /* نجاح مصطنع */ return … }`
    /// يرجع true (ويسجّل «DRY-RUN …») ما دام `-tmpAdminRole`/`-tmpRoleMatrix` مفعّلاً
    @discardableResult
    static func dryRun(_ what: @autoclosure () -> String) -> Bool {
        guard isDryRun else { return false }
        DebugProbeLog.line("DRY-RUN \(what()) — not sent, faked success (-tmpAdminRole/-tmpRoleMatrix on)")
        return true
    }

    /// هل يُصطنع فشل هذا الجلب؟ `hasLoaded` = في المخزن بيانات من تحميل ناجح سابق (لـ`@ثوانٍ`)
    static func shouldFail(_ store: Store, hasLoaded: Bool) -> Bool {
        guard let delay = DebugArgs.current.failStores[store] else { return false }
        if delay > 0 {
            guard hasLoaded, ProcessInfo.processInfo.systemUptime - DebugArgs.launchUptime >= delay else { return false }
        }
        DebugProbeLog.line("FAIL-STORE \(store.rawValue) — injected load failure (-tmpFailStores)")
        return true
    }

    /// أول سطر داخل `do { … }` الجلب: `try DebugAdminProbe.failIfAsked(.accounts, hasLoaded: rows != nil)`
    static func failIfAsked(_ store: Store, hasLoaded: Bool) throws {
        if shouldFail(store, hasLoaded: hasLoaded) { throw InjectedFailure(store: store) }
    }

    /// الخطأ مصطنع؟ — لتجنّب `Log.error` (يبلّغ السيرفر) في `catch`
    static func isInjected(_ error: Error) -> Bool { error is InjectedFailure }

    /// فحص كلفة بناء جسم واحد (`-tmpStackCheck`، ≤ 64 ك.ب): `var body: some View { DebugAdminProbe.stackCheck("AdminFooCard") { content } }`
    static func stackCheck<V>(_ type: String, limitKB: Int = DebugStackLimit.check, _ make: () -> V) -> V {
        guard let engine = DebugStackEngine.shared, engine.checkEnabled, Thread.isMainThread else { return make() }
        let entry = engine.meter.checkBegin()
        let value = make()
        let low = engine.meter.checkEnd()
        engine.checkDone(type, limitKB: limitKB, entry: entry, low: low)
        return value
    }

    // MARK: الدور والجدول (`AuthViewModel` / `AdminRoleMatrix`)

    @MainActor private static var realRole: FamilyMember.UserRole?
    @MainActor private static var matrixAnnounced = false

    /// `-tmpAdminRole`: الدور المعروض بدل `role` — لأدوار الإدارة فقط (لا يرفع عضواً أو معلّقاً إلى الإدارة)
    @MainActor static func forcedRole(over role: FamilyMember.UserRole) -> FamilyMember.UserRole? {
        guard let raw = DebugArgs.current.adminRole, let forced = FamilyMember.UserRole(rawValue: raw),
              [.owner, .admin, .monitor, .supervisor].contains(role) else { return nil }
        if forced != role, realRole == nil {
            realRole = role
            DebugProbeLog.line("DEBUG-PROBE role \(role.rawValue) → \(forced.rawValue) (display only; the server still answers as \(role.rawValue))")
        }
        return forced
    }

    /// `-tmpRoleMatrix`: صفّ الدور من الجدول البديل — يقرؤه `AdminRoleMatrix.roleObject` (سطر DEBUG هناك) قبل قيمة السيرفر
    @MainActor static func roleMatrixOverride(_ role: String) -> [String: Any]? {
        guard let matrix = DebugArgs.current.roleMatrix else { return nil }
        if !matrixAnnounced {
            matrixAnnounced = true
            DebugProbeLog.line("DEBUG-PROBE role matrix override in use (-tmpRoleMatrix)")
        }
        return matrix[role] as? [String: Any]
    }

    // MARK: الإقلاع

    @MainActor private static var launched = false

    /// مرة واحدة من `debugAdminProbeRoot()`: الأخطاء، سطر الإقلاع، مقياس المكدس
    @MainActor static func launchOnce() {
        guard !launched else { return }
        launched = true
        let args = DebugArgs.current
        guard args.anyActive else { return }
        _ = DebugArgs.launchUptime
        for e in args.errors { DebugProbeLog.error(e) }
        validateMatrix(args.roleMatrix)
        DebugProbeLog.line("DEBUG-PROBE launch \(args.summary)")
        if args.matrixFlagPresent, !args.roleFlagPresent {
            DebugProbeLog.line("DEBUG-PROBE note: the owner always sees everything — pair -tmpRoleMatrix with -tmpAdminRole admin|monitor|supervisor")
        }
        if args.stackDepth || args.stackCheck { DebugStackEngine.start(check: args.stackCheck) }
    }

    /// فحص شكل الجدول البديل بأسماء الأقسام والخانات الحقيقية — المجهول خطأ (ويُترك كما هو: القارئ يتجاهله)
    @MainActor private static func validateMatrix(_ matrix: [String: Any]?) {
        guard let matrix else { return }
        let levels = "edit|read|none"
        for (role, raw) in matrix {
            guard ["admin", "monitor", "supervisor"].contains(role) else {
                DebugProbeLog.error("-tmpRoleMatrix: unknown role key \"\(role)\" (use admin|monitor|supervisor; the owner is never in the matrix)")
                continue
            }
            guard let row = raw as? [String: Any] else {
                DebugProbeLog.error("-tmpRoleMatrix: \(role) must be an object {areas, items, attention_fourth}")
                continue
            }
            for (key, value) in row {
                switch key {
                case "areas", "items":
                    guard let group = value as? [String: Any] else {
                        DebugProbeLog.error("-tmpRoleMatrix: \(role).\(key) must be an object")
                        continue
                    }
                    for (name, level) in group {
                        let known = key == "areas" ? AdminArea(rawValue: name) != nil : AdminRoleItem(rawValue: name) != nil
                        if !known { DebugProbeLog.error("-tmpRoleMatrix: unknown \(key) key \"\(name)\" in \(role)") }
                        if AdminAccess(rawValue: level as? String ?? "") == nil {
                            DebugProbeLog.error("-tmpRoleMatrix: unknown value \"\(level)\" for \(role).\(key).\(name) (use \(levels))")
                        }
                    }
                case "attention_fourth":
                    if AdminAttentionFourth(rawValue: value as? String ?? "") == nil {
                        DebugProbeLog.error("-tmpRoleMatrix: unknown value \"\(value)\" for \(role).attention_fourth (use messages|tree_issues|reports)")
                    }
                default:
                    DebugProbeLog.error("-tmpRoleMatrix: unknown key \"\(key)\" in \(role) (use areas|items|attention_fourth)")
                }
            }
        }
    }
}

// MARK: - محرّك المكدس: يقيس في آخر كل دورة للخيط الرئيسي، ويطبع سطراً حين تهدأ القيمة

nonisolated final class DebugStackEngine {
    nonisolated(unsafe) static var shared: DebugStackEngine?

    /// مهلة الهدوء قبل الطباعة (ث)
    private static let settle: TimeInterval = 1.2

    private final class Subject {
        enum Kind { case page, tab, check }
        let name: String
        let kind: Kind
        var limitKB: Int
        /// الصفحة: أعمق نقطة نُفِّذ فيها جسمها · التبويب: علامة الماء · الفحص: أكبر كلفة
        var valueKB = 0
        /// علامة الماء أثناء ظهور الصفحة (للمعلومة)
        var highWaterKB = 0
        var deepest: (name: String, kb: Int)?
        var depthKB = 0
        var lastChange = ProcessInfo.processInfo.systemUptime
        var open = true
        var emitted: (Int, Int)?

        init(name: String, kind: Kind, limitKB: Int) {
            self.name = name
            self.kind = kind
            self.limitKB = limitKB
        }

        var current: (Int, Int) { (valueKB, highWaterKB) }
        var pending: Bool { emitted.map { $0 != current } ?? (valueKB > 0 || highWaterKB > 0) }
    }

    let meter: DebugStackMeter
    let checkEnabled: Bool
    private var pages: [String: Subject] = [:]
    private var checks: [String: Subject] = [:]
    private var tab: Subject?
    /// الأنواع التي قيست في الدورة الحالية (للإشارة إلى «الأعمق»)
    private var turnTypes: [(name: String, kb: Int)] = []
    private var maxSeenKB = 0
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private var armedReported = false

    private init(meter: DebugStackMeter, check: Bool) {
        self.meter = meter
        checkEnabled = check
    }

    static func start(check: Bool) {
        guard Thread.isMainThread, shared == nil, let meter = DebugStackMeter() else {
            DebugProbeLog.error("-tmpStackDepth: stack meter unavailable (not on the main thread?)")
            return
        }
        let engine = DebugStackEngine(meter: meter, check: check)
        shared = engine
        _ = meter.endTurn()   // أول طلاء من هنا
        // بعد التزام Core Animation (2000000) — كل عمل الدورة قبله
        let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue,
                                                          true, CFIndex.max) { _, _ in engine.turnEnded() }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 0.5, 0.5, 0, 0) { _ in
            engine.tick()
        }
        CFRunLoopAddTimer(CFRunLoopGetMain(), timer, .commonModes)
        DebugProbeLog.line("STACK meter on: main thread, spanKB=\(meter.spanKB), limits today=\(DebugStackLimit.today) tab=\(DebugStackLimit.tab) page=\(DebugStackLimit.page) check=\(DebugStackLimit.check)\(check ? "" : " (checks off: add -tmpStackCheck)")")
    }

    // MARK: من الصفحات

    static func probeBody(_ name: String, limitKB: Int) {
        guard let engine = shared, Thread.isMainThread else { return }
        let depth = engine.meter.depthKB(DebugStackMeter.here())
        let page = engine.pages[name] ?? {
            let s = Subject(name: name, kind: .page, limitKB: limitKB)
            engine.pages[name] = s
            return s
        }()
        if !page.open { engine.reopen(page) }
        page.limitKB = limitKB
        if depth > page.valueKB { page.valueKB = depth; page.lastChange = ProcessInfo.processInfo.systemUptime }
        engine.turnTypes.append((name, depth))
    }

    static func appeared(_ name: String) {
        guard let engine = shared, let page = engine.pages[name] else { return }
        if !page.open { engine.reopen(page) }
    }

    static func disappeared(_ name: String) {
        guard let engine = shared, let page = engine.pages[name], page.open else { return }
        if page.pending { engine.emit(page) }
        page.open = false
    }

    func checkDone(_ name: String, limitKB: Int, entry: UInt, low: UInt) {
        let stepKB = low < entry ? Int((entry - low) / 1024) : 0
        let entryKB = meter.depthKB(entry)
        let check = checks[name] ?? {
            let s = Subject(name: name, kind: .check, limitKB: limitKB)
            checks[name] = s
            return s
        }()
        check.limitKB = limitKB
        check.depthKB = max(check.depthKB, entryKB)
        if stepKB > check.valueKB { check.valueKB = stepKB; check.lastChange = ProcessInfo.processInfo.systemUptime }
        turnTypes.append((name, entryKB + stepKB))
    }

    private func reopen(_ s: Subject) {
        s.open = true
        s.valueKB = 0
        s.highWaterKB = 0
        s.deepest = nil
        s.emitted = nil
        s.lastChange = ProcessInfo.processInfo.systemUptime
    }

    // MARK: الدورة والطباعة

    private func adminTabActive() -> Bool {
        if #available(iOS 17.0, *) {
            return MainActor.assumeIsolated { AppSection.current == .admin }
        }
        return pages.values.contains { $0.open }
    }

    func turnEnded() {
        let types = turnTypes
        turnTypes.removeAll()
        let deepestType = types.max { $0.kb < $1.kb }
        let peakKB = meter.endTurn().map(meter.depthKB) ?? 0
        maxSeenKB = max(maxSeenKB, peakKB)
        let now = ProcessInfo.processInfo.systemUptime

        func absorb(_ s: Subject, _ value: Int, into keyPath: ReferenceWritableKeyPath<Subject, Int>) {
            if value > s[keyPath: keyPath] { s[keyPath: keyPath] = value; s.lastChange = now }
            if let d = deepestType, d.kb > (s.deepest?.kb ?? -1) { s.deepest = d }
        }
        for page in pages.values where page.open { absorb(page, peakKB, into: \.highWaterKB) }

        if adminTabActive() {
            if tab == nil || tab?.open == false {
                tab = Subject(name: "AdminTab", kind: .tab, limitKB: DebugStackLimit.tab)
            }
            if let tab { absorb(tab, peakKB, into: \.valueKB) }
        } else if let tab, tab.open {
            if tab.pending { emit(tab) }
            tab.open = false
        }
    }

    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if !armedReported, now - startedAt >= 5 {
            armedReported = true
            DebugProbeLog.line("STACK meter armed: peakKB=\(maxSeenKB) since start (app-wide, info only)")
        }
        let all = Array(pages.values) + Array(checks.values) + [tab].compactMap { $0 }
        for s in all where s.open && s.pending && now - s.lastChange >= Self.settle { emit(s) }
    }

    private func emit(_ s: Subject) {
        s.emitted = s.current
        let pass = s.valueKB <= s.limitKB
        var text: String
        switch s.kind {
        case .page:
            text = "STACK page=\(s.name) peakKB=\(s.valueKB) limitKB=\(s.limitKB) \(pass ? "PASS" : "FAIL") hwKB=\(s.highWaterKB)"
        case .tab:
            text = "STACK page=\(s.name) peakKB=\(s.valueKB) limitKB=\(s.limitKB) \(pass ? "PASS" : "FAIL")"
        case .check:
            text = "STACK check=\(s.name) peakKB=\(s.valueKB) limitKB=\(s.limitKB) \(pass ? "PASS" : "FAIL") depthKB=\(s.depthKB)"
        }
        if !pass {
            let deepest = s.kind == .check ? s.name : (s.deepest?.name ?? "unprobed — add .debugStackProbe(…) to its pages/cards")
            let at = s.kind == .check ? "" : (s.deepest.map { "@\($0.kb)KB" } ?? "")
            let fix = s.kind == .check
                ? "split \(s.name)'s body into smaller View types, each behind AnyView"
                : "open \(deepest) through AdminLazyPage { AnyView(…) } and put its big cards behind AnyView"
            text += " deepest=\(deepest)\(at) fix=\"\(fix)\""
        }
        DebugProbeLog.line(text)
    }
}

// MARK: - SwiftUI

private struct DebugStackProbeModifier: ViewModifier {
    let page: String
    let limitKB: Int

    func body(content: Content) -> some View {
        DebugStackEngine.probeBody(page, limitKB: limitKB)
        return content
            .onAppear { DebugStackEngine.appeared(page) }
            .onDisappear { DebugStackEngine.disappeared(page) }
    }
}

/// شارة DEBUG أسفل الشاشة (في منطقة مؤشّر الرجوع للرئيسية) — لا تلتقط اللمس ولا يقرؤها القارئ الصوتي
private struct DebugAdminProbeRoot: ViewModifier {
    func body(content: Content) -> some View {
        DebugAdminProbe.launchOnce()
        let args = DebugArgs.current
        return content.overlay {
            if args.anyActive {
                VStack {
                    Spacer(minLength: 0)
                    Text(verbatim: "DEBUG · " + args.summary)
                        .dsFont(.micro)
                        .dynamicTypeSize(.large)   // ثابتة الحجم: لا تغطّي لقطات AX
                        .foregroundColor(DS.Color.textOnPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, DS.Spacing.xsm)
                        .padding(.vertical, DS.Spacing.xxs)
                        .background(Capsule().fill(args.errors.isEmpty ? DS.Color.warningFill : DS.Color.errorFill))
                        .padding(.bottom, DS.Spacing.xxs)
                }
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    /// مقياس صفحة (`-tmpStackDepth`): ضعه على الصفحة نفسها حيث تُنشأ — `AdminFooPage().debugStackProbe("AdminFooPage")`
    /// أو آخر سلسلة جسمها. «اليوم»: `limitKB: DebugStackLimit.today`
    func debugStackProbe(_ page: String, limitKB: Int = DebugStackLimit.page) -> some View {
        modifier(DebugStackProbeModifier(page: page, limitKB: limitKB))
    }

    /// جذر التطبيق فقط (`FamilyTreeV2App`): سطر الإقلاع والأخطاء والشارة ومقياس المكدس
    func debugAdminProbeRoot() -> some View {
        modifier(DebugAdminProbeRoot())
    }
}

#endif // !DEBUG_PROBE_TEST

#else

// MARK: - الإصدار: بدائل ثابتة يحذفها المترجم (لا قراءة أعلام ولا مقياس ولا شارة)

extension DebugAdminProbe {
    @inline(__always) static var isDryRun: Bool { false }
    @inline(__always) @discardableResult static func dryRun(_ what: @autoclosure () -> String) -> Bool { false }
    @inline(__always) static func shouldFail(_ store: Store, hasLoaded: Bool) -> Bool { false }
    @inline(__always) static func failIfAsked(_ store: Store, hasLoaded: Bool) throws {}
    @inline(__always) static func isInjected(_ error: Error) -> Bool { false }
    @inline(__always) static func stackCheck<V>(_ type: String, limitKB: Int = DebugStackLimit.check, _ make: () -> V) -> V { make() }
}

extension View {
    @inline(__always) func debugStackProbe(_ page: String, limitKB: Int = DebugStackLimit.page) -> Self { self }
}

#endif
