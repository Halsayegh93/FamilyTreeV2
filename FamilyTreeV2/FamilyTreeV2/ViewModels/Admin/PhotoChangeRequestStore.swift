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

    enum CodingKeys: String, CodingKey {
        case id, reason
        case memberId = "member_id"
        case hidePhoto = "hide_photo"
        case requestedAtRaw = "requested_at"
    }

    var requestedAt: Date? {
        guard let raw = requestedAtRaw else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)
    }

    /// «11/11/2026» — الصيغة الموحّدة
    var sinceText: String { requestedAt.map { DateHelper.displayDate($0) } ?? "—" }
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

    /// الطلب المفتوح لكل عضو حُمّل (للإدارة) — غياب المفتاح = لم يُحمَّل أو لا طلب
    @Published private(set) var openByMember: [UUID: PhotoChangeRequest] = [:]
    /// طلب العضو الحالي المفتوح
    @Published private(set) var mine: PhotoChangeRequest?

    private var supabase: SupabaseClient { SupabaseConfig.client }

    func open(for memberId: UUID) -> PhotoChangeRequest? { openByMember[memberId] }

    // MARK: القراءة

    private func fetchOpen(memberId: UUID) async throws -> PhotoChangeRequest? {
        let rows: [PhotoChangeRequest] = try await supabase
            .from("photo_change_requests")
            .select(Self.columns)
            .eq("member_id", value: memberId.uuidString)
            .is("resolved_at", value: nil)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// الطلب المفتوح لعضو (الإدارة) — الفشل (سيرفر قديم، اتصال) يُبقي آخر قيمة معروفة
    func refresh(memberId: UUID) async {
        do {
            let found = try await fetchOpen(memberId: memberId)
            openByMember[memberId] = found
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

    /// يرسل الطلب (أو يحدّث المفتوح) — يرجع رسالة الخطأ أو nil عند النجاح
    func request(memberId: UUID, reason: String, hide: Bool) async -> String? {
        guard NetworkMonitor.shared.requireOnline() else { return Self.offlineMessage }
        struct Params: Encodable {
            let p_member: String
            let p_reason: String
            let p_hide: Bool
        }
        do {
            _ = try await supabase
                .rpc("request_photo_change", params: Params(p_member: memberId.uuidString, p_reason: reason, p_hide: hide))
                .execute()
            Log.info("[PhotoChange] طلب تغيير صورة: \(memberId)")
            await refresh(memberId: memberId)
            return nil
        } catch {
            Log.error("[PhotoChange] request: \(ErrorHelper.description(error))")
            return Self.message(for: error, cancelling: false)
        }
    }

    /// يلغي الطلب المفتوح — يرجع رسالة الخطأ أو nil عند النجاح
    func cancel(memberId: UUID) async -> String? {
        guard NetworkMonitor.shared.requireOnline() else { return Self.offlineMessage }
        struct Params: Encodable { let p_member: String }
        do {
            _ = try await supabase.rpc("cancel_photo_change", params: Params(p_member: memberId.uuidString)).execute()
            openByMember[memberId] = nil
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

    /// رسائل رفض السيرفر حسب `hint`
    static func message(for error: Error, cancelling: Bool) -> String {
        let pg = error as? PostgrestError
        let raw = ErrorHelper.description(error)
        if pg?.code == "PGRST202" || raw.localizedCaseInsensitiveContains("could not find the function") {
            return L10n.t("هذه الميزة تحتاج تحديث السيرفر.", "This feature needs a server update.")
        }
        switch pg?.hint {
        case "not_allowed":
            return L10n.t("هذا الإجراء للمالك والمدير والمراقب فقط.", "Only the owner, admins and monitors can do this.")
        case "no_account":
            return L10n.t("ليس لهذا العضو حساب في التطبيق.", "This member has no app account.")
        case "deceased":
            return L10n.t("لا يُرسل الطلب إلى عضو متوفى.", "The request can't be sent for a deceased member.")
        case "member_not_found":
            return L10n.t("العضو غير موجود.", "Member not found.")
        case "own_profile":
            return L10n.t("لا يُرسل الطلب إلى نفسك — غيّر صورتك من «حسابي».", "You can't send this to yourself — change your photo in My Account.")
        case "owner_protected":
            return L10n.t("لا يُرسل هذا الطلب إلى المالك.", "This request can't be sent to the owner.")
        case "bad_reason":
            return L10n.t("يرجى كتابة السبب (حتى ٢٠٠ حرف).", "Please enter the reason (up to 200 characters).")
        default:
            return cancelling
                ? L10n.t("تعذّر إلغاء الطلب. تحقق من الاتصال ثم حاول مرة أخرى.", "Couldn't cancel the request. Check your connection and try again.")
                : L10n.t("تعذّر إرسال الطلب. تحقق من الاتصال ثم حاول مرة أخرى.", "Couldn't send the request. Check your connection and try again.")
        }
    }

    // MARK: ما أُرسل للموافقة (العضو تجاوز ٣ تغييرات) — لا يعود المربّع لهذا الطلب على هذا الجهاز

    private static func sentKey(_ requestId: UUID) -> String { "photoChangeSent.\(requestId.uuidString)" }

    static func markSentForApproval(_ requestId: UUID) {
        UserDefaults.standard.set(true, forKey: sentKey(requestId))
    }

    static func isSentForApproval(_ requestId: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: sentKey(requestId))
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
