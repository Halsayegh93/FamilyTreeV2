import Foundation
import Combine
import Supabase

// MARK: - «طلب تغيير الصورة» (طلب المالك ٢٠٢٦-١١-١١)
//
// المالك/المدير/المراقب (`canEditMembers`) يطلب من عضو له حساب تغيير صورته بسبب، مع خيار إخفاء الحالية حتى يغيّرها.
// السيرفر (`20261111160000_photo_change_request`، لم يُطبَّق بعد): الجدول `photo_change_requests` (الطاقم يقرأ الكل،
// والعضو طلبه المفتوح فقط — بأعمدة محددة، فلا `select=*`)، والكتابة عبر `request_photo_change` / `cancel_photo_change`
// فقط، والمشغّل يغلق الطلب حين يرفع العضو صورة جديدة (أو تُعتمد صورته المقترحة) ويُظهر ما أخفاه الطلب.
// قبل تطبيق الترحيل: القراءة تفشل بهدوء (لا مربّع ولا سطر معلّق)، والإرسال يعرض «تحتاج تحديث السيرفر».
//
// «نبّهه يضيف صورة» + التذكير (P1، ٢٠٢٦-١١-٢٦، `20261126180000_photo_add_request`): `nudge` (بلا سبب لمن لا صورة له)،
// `remind` («ذكّره الحين» = نفس النداء بسببه، يُعدّ تذكيراً)، `requestAll` («نبّههم كلهم»)، `refreshAllOpen` (قائمة
// «مسجّلون بلا صورة»). الأعمدة الجديدة `notified_at`/`reminders_sent` تُقرأ إن سمح السيرفر، وإلا الأعمدة القديمة (قبل
// الترحيل). كل كتابة تمرّ أولاً بـ`DebugAdminProbe.dryRun` (نجاح مصطنع أثناء تجربة دور). المنطق: PhotoNudgeLogic.swift.

extension Notification.Name {
    /// الضغط على إشعار «طلب تغيير الصورة الشخصية» من خارج التطبيق — `PhotoReminderGate` يعرض مربّع العضو
    static let openPhotoChangeRequest = Notification.Name("openPhotoChangeRequest")
}

/// طلب تغيير صورة مفتوح (الأعمدة المسموح بقراءتها فقط)
struct PhotoChangeRequest: Decodable, Identifiable, Equatable {
    let id: UUID
    let memberId: UUID
    let reason: String
    let hidePhoto: Bool
    let requestedAtRaw: String?
    /// آخر إشعار وصله (P1) — nil على السيرفر القديم
    var notifiedAtRaw: String? = nil
    /// كم مرة أُعيد إشعاره (P1) — nil على السيرفر القديم
    var remindersSent: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, reason
        case memberId = "member_id"
        case hidePhoto = "hide_photo"
        case requestedAtRaw = "requested_at"
        case notifiedAtRaw = "notified_at"
        case remindersSent = "reminders_sent"
    }

    private static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)
    }

    var requestedAt: Date? { Self.date(requestedAtRaw) }
    var notifiedAt: Date? { Self.date(notifiedAtRaw) }

    /// للمنطق الخالص (`PhotoNudgeLogic`)
    var nudgeOpen: PhotoNudgeLogic.Open {
        PhotoNudgeLogic.Open(notifiedAt: notifiedAt, requestedAt: requestedAt, remindersSent: remindersSent,
                             reason: reason, hidePhoto: hidePhoto)
    }

    /// «مرة لكل إشعار» على جهاز العضو
    var seenToken: String {
        PhotoNudgeLogic.seenToken(requestId: id, notifiedAtRaw: notifiedAtRaw, requestedAtRaw: requestedAtRaw)
    }

    /// «11/11/2026» — الصيغة الموحّدة
    var sinceText: String { requestedAt.map { DateHelper.displayDate($0) } ?? "—" }
}

/// رسالة رفض «نبّههم كلهم» (عربية جاهزة للعرض)
struct PhotoNudgeError: Error, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
}

/// نتيجة «نبّهه»/«ذكّره الحين» (F4): وصله فعلاً، أو أُرسل قبل أقل من دقيقة (السيرفر لم يُعد الإشعار — V15)، أو له
/// صورة الآن (البيانات قديمة — V11)، أو رسالة الخطأ
enum PhotoNudgeOutcome: Equatable {
    case sent
    case tooSoon
    case stale
    case failed(String)
}

/// الأسباب الجاهزة في مربّع الطلب
enum PhotoChangeReason: String, CaseIterable, Identifiable {
    case unclear, inappropriate, notOwner, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unclear: return L10n.t("الصورة غير واضحة", "The photo isn't clear")
        case .inappropriate: return L10n.t("الصورة غير مناسبة", "The photo isn't appropriate")
        case .notOwner: return L10n.t("الصورة ليست لصاحب الحساب", "The photo isn't of the account holder")
        case .other: return L10n.t("سبب آخر", "Another reason")
        }
    }

    var icon: String {
        switch self {
        case .unclear: return "eye.slash"
        case .inappropriate: return "exclamationmark.triangle"
        case .notOwner: return "person.crop.circle.badge.questionmark"
        case .other: return "text.bubble"
        }
    }
}

@MainActor
final class PhotoChangeRequestStore: ObservableObject {
    static let shared = PhotoChangeRequestStore()

    /// حدّ السبب على السيرفر
    static let reasonLimit = 200
    /// الأعمدة التي يقرؤها `authenticated` (منح أعمدة على السيرفر)
    private static let columns = "id,member_id,reason,hide_photo,requested_at"
    /// + `notified_at`/`reminders_sent` بعد `20261126180000_photo_add_request`
    private static let columnsV2 = columns + ",notified_at,reminders_sent"
    /// السيرفر يسمح بالأعمدة الجديدة؟ nil = لم يُجرَّب بعد؛ false = يُقرأ القديم حتى يُعاد فتح التطبيق
    private var serverHasV2: Bool?

    /// الطلب المفتوح لكل عضو حُمّل (للإدارة) — غياب المفتاح = لم يُحمَّل أو لا طلب
    @Published private(set) var openByMember: [UUID: PhotoChangeRequest] = [:]
    /// طلب العضو الحالي المفتوح
    @Published private(set) var mine: PhotoChangeRequest?
    /// كل الطلبات المفتوحة (قائمة «مسجّلون بلا صورة») — حال الجلب (`AdminStoreHealth`)
    @Published private(set) var allOpenHealth: AdminStoreHealth = .idle

    private var supabase: SupabaseClient { SupabaseConfig.client }

    /// F4 (V31): رقم كل كتابة محلية في `openByMember` — جلب الكل يدمج ولا يمحو ما كُتب بعد بدئه
    private var writeSeq = 0
    private var lastWrite: [UUID: Int] = [:]

    func open(for memberId: UUID) -> PhotoChangeRequest? { openByMember[memberId] }

    /// كتابة محلية لعضو واحد (تُسجَّل برقمها)
    private func setOpen(_ request: PhotoChangeRequest?, for memberId: UUID) {
        writeSeq += 1
        lastWrite[memberId] = writeSeq
        openByMember[memberId] = request
    }

    // MARK: القراءة

    /// الأعمدة الجديدة أولاً؛ رفضها (عمود غير موجود 42703 أو غير ممنوح 42501 — قبل الترحيل) يرجع للقديمة
    private func fetchRows(memberId: UUID?) async throws -> [PhotoChangeRequest] {
        func run(_ columns: String) async throws -> [PhotoChangeRequest] {
            var query = supabase.from("photo_change_requests").select(columns).is("resolved_at", value: nil)
            if let memberId { query = query.eq("member_id", value: memberId.uuidString) }
            if memberId != nil { return try await query.limit(1).execute().value }
            return try await query.execute().value
        }
        if serverHasV2 != false {
            do {
                let rows = try await run(Self.columnsV2)
                serverHasV2 = true
                return rows
            } catch {
                guard Self.isMissingColumns(error) else { throw error }
                serverHasV2 = false
            }
        }
        return try await run(Self.columns)
    }

    private static func isMissingColumns(_ error: Error) -> Bool {
        let pg = error as? PostgrestError
        if pg?.code == "42703" || pg?.code == "42501" { return true }
        let raw = ErrorHelper.description(error)
        return raw.localizedCaseInsensitiveContains("does not exist") || raw.localizedCaseInsensitiveContains("permission denied")
    }

    private func fetchOpen(memberId: UUID) async throws -> PhotoChangeRequest? {
        try await fetchRows(memberId: memberId).first
    }

    /// كل الطلبات المفتوحة (الطاقم — RLS) لقائمة «مسجّلون بلا صورة». الفشل يُبقي آخر قيمة ويقوله `allOpenHealth`
    func refreshAllOpen() async {
        let before = allOpenHealth
        let startSeq = writeSeq
        allOpenHealth = allOpenHealth.beginning()
        do {
            let rows = try await fetchRows(memberId: nil)
            var map: [UUID: PhotoChangeRequest] = [:]
            for row in rows { map[row.memberId] = row }
            // من لم يعد له طلب مفتوح يُمسح (أُغلق أو أُلغي من جهاز آخر) — إلا من نُبّه أو أُلغي هنا أثناء الجلب (V31)
            let written = Set(lastWrite.filter { $0.value > startSeq }.keys)
            openByMember = PhotoNudgeLogic.merged(fetched: map, current: openByMember, writtenSince: written)
            allOpenHealth = allOpenHealth.ending(success: true)
        } catch {
            // إلغاء (الصفحة أُغلقت، جلب أحدث) ليس فشلاً
            if ErrorHelper.isCancellation(error) {
                allOpenHealth = before
                return
            }
            Log.warning("[PhotoChange] all open: \(ErrorHelper.description(error))")
            allOpenHealth = allOpenHealth.ending(success: false)
        }
    }

    /// الطلب المفتوح لعضو (الإدارة) — الفشل (سيرفر قديم، اتصال) يُبقي آخر قيمة معروفة
    func refresh(memberId: UUID) async {
        do {
            let found = try await fetchOpen(memberId: memberId)
            setOpen(found, for: memberId)
        } catch {
            if ErrorHelper.isCancellation(error) { return }
            Log.warning("[PhotoChange] refresh \(memberId): \(ErrorHelper.description(error))")
        }
    }

    /// طلب العضو الحالي المفتوح — nil عند عدم وجوده أو تعذّر القراءة (المربّع لا يظهر)
    @discardableResult
    func refreshMine(userId: UUID) async -> PhotoChangeRequest? {
        #if DEBUG
        if let preview = Self.debugPreview(userId: userId) {
            mine = preview
            return preview
        }
        #endif
        do {
            mine = try await fetchOpen(memberId: userId)
        } catch {
            if ErrorHelper.isCancellation(error) { return mine }
            Log.warning("[PhotoChange] mine: \(ErrorHelper.description(error))")
            mine = nil
        }
        return mine
    }

    /// العضو غيّر صورته — المشغّل أغلق الطلب على السيرفر
    func clearMine() { mine = nil }

    // MARK: الإرسال والإلغاء (الإدارة)

    /// يرسل الطلب (أو يحدّث المفتوح) — يرجع رسالة الخطأ أو nil عند النجاح (مربّع السبب «طلب تغيير الصورة»).
    /// `nudging`: «نبّهه»/«ذكّره» بلا سبب
    func request(memberId: UUID, reason: String, hide: Bool, nudging: Bool = false) async -> String? {
        switch await deliver(memberId: memberId, reason: reason, hide: hide, nudging: nudging) {
        case .sent, .tooSoon: return nil
        case .stale: return PhotoNudgeLogic.staleText
        case .failed(let message): return message
        }
    }

    /// الإرسال بنتيجته (F4): notified_at قبل النداء وبعده من السيرفر نفسه — لم يتغيّر = أُرسل قبل أقل من دقيقة (V15)؛
    /// رفض السبب الفارغ = له صورة الآن (V11، المستدعي يحدّث العضو)
    func deliver(memberId: UUID, reason: String, hide: Bool, nudging: Bool) async -> PhotoNudgeOutcome {
        if DebugAdminProbe.dryRun("request_photo_change \(memberId) reason=«\(reason)» hide=\(hide)") {
            fakeSent(memberId: memberId, reason: reason, hide: hide)
            return .sent
        }
        guard NetworkMonitor.shared.requireOnline() else { return .failed(Self.offlineMessage) }
        struct Params: Encodable {
            let p_member: String
            let p_reason: String
            let p_hide: Bool
        }
        // قبل النداء: من السيرفر (الذاكرة قد تكون قديمة — E-6)، وإلا آخر قيمة معروفة
        let before: Date?
        do {
            before = try await fetchOpen(memberId: memberId)?.notifiedAt
        } catch {
            before = openByMember[memberId]?.notifiedAt
        }
        do {
            _ = try await supabase
                .rpc("request_photo_change", params: Params(p_member: memberId.uuidString, p_reason: reason, p_hide: hide))
                .execute()
            Log.info("[PhotoChange] طلب تغيير صورة: \(memberId)")
        } catch {
            Log.error("[PhotoChange] request: \(ErrorHelper.description(error))")
            switch Self.failure(for: error, cancelling: false, nudging: nudging) {
            case .stale: return .stale
            case .message(let message): return .failed(message)
            }
        }
        // بعده: قراءة واحدة — فشلها لا يكذّب قبول السيرفر
        let after: PhotoChangeRequest?
        do {
            after = try await fetchOpen(memberId: memberId)
        } catch {
            return .sent
        }
        setOpen(after, for: memberId)
        return PhotoNudgeLogic.reminderLanded(before: before, after: after?.notifiedAt) ? .sent : .tooSoon
    }

    /// «نبّهه يضيف صورة» — بلا سبب ولا إخفاء
    func nudge(memberId: UUID) async -> String? {
        await request(memberId: memberId, reason: "", hide: false, nudging: true)
    }

    func nudgeOutcome(memberId: UUID) async -> PhotoNudgeOutcome {
        await deliver(memberId: memberId, reason: "", hide: false, nudging: true)
    }

    /// «ذكّره الحين» — نفس الطلب بسببه (السيرفر يعيد الإشعار بعد دقيقة ويعدّه تذكيراً)
    func remind(memberId: UUID) async -> String? {
        let reason = openByMember[memberId]?.reason ?? ""
        return await request(memberId: memberId, reason: reason, hide: false, nudging: reason.isEmpty)
    }

    func remindOutcome(memberId: UUID) async -> PhotoNudgeOutcome {
        let reason = openByMember[memberId]?.reason ?? ""
        return await deliver(memberId: memberId, reason: reason, hide: false, nudging: reason.isEmpty)
    }

    /// «نبّههم كلهم» (المالك والمدير) — عدد من وصله، أو رسالة الخطأ. `expected` = العدد المعروض (للتجربة فقط).
    /// F4 (S-1): `memberIds` = من عرضتهم القائمة — السيرفر يعيد فحص كل واحد بقاعدتها (`20261126200000`)؛ قبل الترحيل
    /// «تحتاج تحديث السيرفر» بدل نداء القاعدة القديمة (كانت تشمل أبناء البنات ومن بلا رقم)
    func requestAll(expected: Int, memberIds: [UUID]? = nil) async -> Result<Int, PhotoNudgeError> {
        if DebugAdminProbe.dryRun("request_photo_add_all (\(expected) expected, \(memberIds?.count ?? 0) ids)") {
            return .success(expected)
        }
        guard NetworkMonitor.shared.requireOnline() else { return .failure(PhotoNudgeError(Self.offlineMessage)) }
        struct Params: Encodable { let p_member_ids: [String] }
        do {
            let sent: Int
            if let memberIds {
                sent = try await supabase
                    .rpc("request_photo_add_all", params: Params(p_member_ids: memberIds.map(\.uuidString)))
                    .execute().value
            } else {
                sent = try await supabase.rpc("request_photo_add_all").execute().value
            }
            Log.info("[PhotoChange] نبّههم كلهم: \(sent)")
            await refreshAllOpen()
            return .success(sent)
        } catch {
            Log.error("[PhotoChange] add all: \(ErrorHelper.description(error))")
            return .failure(PhotoNudgeError(Self.message(for: error, cancelling: false, nudging: true)))
        }
    }

    /// تجربة دور: طلب مفتوح محلي بإشعار «الآن» — تُرى حالات الصفّ بلا كتابة
    private func fakeSent(memberId: UUID, reason: String, hide: Bool) {
        let now = ISO8601DateFormatter().string(from: Date())
        let old = openByMember[memberId]
        setOpen(PhotoChangeRequest(
            id: old?.id ?? UUID(), memberId: memberId, reason: reason, hidePhoto: hide || (old?.hidePhoto ?? false),
            requestedAtRaw: now, notifiedAtRaw: now,
            remindersSent: old.map { ($0.remindersSent ?? 0) + 1 } ?? 0), for: memberId)
    }

    /// يلغي الطلب المفتوح — يرجع رسالة الخطأ أو nil عند النجاح
    func cancel(memberId: UUID) async -> String? {
        if DebugAdminProbe.dryRun("cancel_photo_change \(memberId)") {
            setOpen(nil, for: memberId)
            return nil
        }
        guard NetworkMonitor.shared.requireOnline() else { return Self.offlineMessage }
        struct Params: Encodable { let p_member: String }
        do {
            _ = try await supabase.rpc("cancel_photo_change", params: Params(p_member: memberId.uuidString)).execute()
            setOpen(nil, for: memberId)
            Log.info("[PhotoChange] إلغاء طلب تغيير صورة: \(memberId)")
            return nil
        } catch {
            Log.error("[PhotoChange] cancel: \(ErrorHelper.description(error))")
            return Self.message(for: error, cancelling: true)
        }
    }

    private static var offlineMessage: String {
        L10n.t("لا يوجد اتصال بالإنترنت. يرجى المحاولة لاحقاً.", "No internet connection. Try again later.")
    }

    /// رسائل رفض السيرفر حسب `hint` (النصوص في `PhotoNudgeLogic.failure`)
    static func message(for error: Error, cancelling: Bool, nudging: Bool = false) -> String {
        switch failure(for: error, cancelling: cancelling, nudging: nudging) {
        case .stale: return PhotoNudgeLogic.staleText
        case .message(let message): return message
        }
    }

    static func failure(for error: Error, cancelling: Bool, nudging: Bool) -> PhotoNudgeLogic.Failure {
        let pg = error as? PostgrestError
        let raw = ErrorHelper.description(error)
        let missing = pg?.code == "PGRST202" || raw.localizedCaseInsensitiveContains("could not find the function")
        return PhotoNudgeLogic.failure(hint: pg?.hint, missingFunction: missing, nudging: nudging, cancelling: cancelling)
    }

    // MARK: ما أُرسل للموافقة (العضو تجاوز ٣ تغييرات) — لا يعود المربّع لهذا الطلب على هذا الجهاز

    private static func sentKey(_ requestId: UUID) -> String { "photoChangeSent.\(requestId.uuidString)" }

    static func markSentForApproval(_ requestId: UUID) {
        UserDefaults.standard.set(true, forKey: sentKey(requestId))
    }

    static func isSentForApproval(_ requestId: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: sentKey(requestId))
    }

    // MARK: «مرة لكل إشعار» على جهاز العضو (P1)

    private static func seenKey(_ userId: UUID) -> String { "photoRequestSeen.\(userId.uuidString)" }
    private static func shownDayKey(_ userId: UUID) -> String { "photoRequestShownDay.\(userId.uuidString)" }

    /// الإشعار الذي رآه هذا الحساب على هذا الجهاز (معرّف الطلب + notified_at)
    static func seenToken(userId: UUID) -> String? {
        UserDefaults.standard.string(forKey: seenKey(userId))
    }

    /// ظهر المربّع لهذا الإشعار — أي إغلاق («لاحقاً»، الإغلاق، السحب) أو إضافة الصورة بعده = رآه
    static func markSeen(_ request: PhotoChangeRequest, userId: UUID, now: Date = Date()) {
        UserDefaults.standard.set(request.seenToken, forKey: seenKey(userId))
        UserDefaults.standard.set(PhotoNudgeLogic.dayKey(now), forKey: shownDayKey(userId))
    }

    /// يوم آخر ظهور لمربّع الطلب («2026-11-26») — «كمّل ملفك بصورة» لا يظهر في اليوم نفسه
    static func requestBoxDay(userId: UUID) -> String? {
        UserDefaults.standard.string(forKey: shownDayKey(userId))
    }

    // MARK: معاينة (تصحيح فقط)

    #if DEBUG
    /// `-tmpPhotoChangePreview 1` عند التشغيل: مربّع العضو بسبب تجريبي بلا سيرفر (لقطات الشاشة)
    static var isDebugPreview: Bool { UserDefaults.standard.bool(forKey: "tmpPhotoChangePreview") }

    private static func debugPreview(userId: UUID) -> PhotoChangeRequest? {
        guard isDebugPreview else { return nil }
        return PhotoChangeRequest(id: UUID(), memberId: userId,
                                  reason: PhotoChangeReason.unclear.title,
                                  hidePhoto: true,
                                  requestedAtRaw: ISO8601DateFormatter().string(from: Date()))
    }
    #endif
}
