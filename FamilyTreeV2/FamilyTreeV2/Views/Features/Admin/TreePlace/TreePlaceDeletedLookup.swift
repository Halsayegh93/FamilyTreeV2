import Foundation
import Supabase

// MARK: - مكان المحذوف (§9، السيرفر `20261113130000_member_delete_requests_and_log` — حيّ)
//
// كل حذف حقيقي من ٢٠٢٦-١١-١٣ يُحفظ مكانه (أبوه، زوجها، ترتيبه، من حذف ومتى، وطلبه إن وُجد) ويُقرأ عبر
// `member_delete_places()` للمالك والمدير والمراقب فقط. المكان الواحد للبحث: `TreePlaceDeletedLookup` — يستعمله
// إشعار الحذف (§7) والطلب المعالَج (§8) و«المنجزة» (حذف الإدارة المباشر).

/// صفّ من سجلّ أماكن المحذوفين
nonisolated struct MemberDeletePlace: Decodable, Sendable, Identifiable, Equatable {
    let memberId: UUID
    let tree: String
    let firstName: String?
    let fullName: String?
    let gender: String?
    let parentId: UUID?
    let parentName: String?
    let motherId: UUID?
    let husbandId: UUID?
    let sortOrder: Double?
    let birthDate: String?
    let isDeceased: Bool?
    let avatarUrl: String?
    let deletedBy: UUID?
    let deletedByName: String?
    let deletedByRole: String?
    let requestId: UUID?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case memberId = "member_id", tree, firstName = "first_name", fullName = "full_name", gender
        case parentId = "parent_id", parentName = "parent_name", motherId = "mother_id", husbandId = "husband_id"
        case sortOrder = "sort_order", birthDate = "birth_date", isDeceased = "is_deceased", avatarUrl = "avatar_url"
        case deletedBy = "deleted_by", deletedByName = "deleted_by_name", deletedByRole = "deleted_by_role"
        case requestId = "request_id", deletedAt = "deleted_at"
    }

    var id: String { memberId.uuidString + (deletedAt ?? "") }

    var isWomenTree: Bool { tree == "women" }

    var isFemale: Bool {
        let g = gender?.lowercased() ?? ""
        return g == "female" || (isWomenTree && g != "male")
    }

    /// الاسم الأول المحفوظ (وإلا أول الاسم الكامل)
    var displayFirstName: String {
        let first = firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !first.isEmpty { return first }
        return PersonName.firstUnit(fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    /// الاسم الكامل المحفوظ (وإلا الأول)
    var displayFullName: String {
        let full = fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return full.isEmpty ? displayFirstName : full
    }

    /// ترتيبه بين إخوته وقت الحذف — للرسم بين الإخوة الحاليين
    var sortIndex: Int {
        guard let s = sortOrder, s.isFinite, abs(s) < Double(Int.max / 2) else { return Int.max }
        return Int(s.rounded())
    }

    /// وقت الحذف (بأجزاء الثانية أو بدونها)
    var deletedDate: Date? {
        guard let raw = deletedAt else { return nil }
        if let d = DateHelper.parse(raw) { return d }
        return DateParsing.isoPlain.date(from: raw)
    }

    /// حذف مباشر من الإدارة (بلا طلب) — صفّ «المنجزة»
    var isStaffDirect: Bool {
        requestId == nil && ["owner", "admin", "monitor", "supervisor"].contains(deletedByRole ?? "")
    }
}

/// البحث الواحد عن مكان المحذوف — مخبّأ لكل معرّف (السجلّ لا يتغيّر)
enum TreePlaceDeletedLookup {
    enum Result: Equatable {
        case found(MemberDeletePlace)
        /// لا سجلّ له (حُذف قبل حفظ الأماكن)
        case missing
        /// تعذّر السؤال (اتصال، أو دور بلا صلاحية) — يبقى الاحتياط القديم
        case unavailable
    }

    private static var found: [UUID: MemberDeletePlace] = [:]
    private static var missing: Set<UUID> = []

    /// ما عُرف دون سؤال جديد — nil = لم يُسأل بعد
    static func cached(_ id: UUID) -> Result? {
        if let row = found[id] { return .found(row) }
        return missing.contains(id) ? .missing : nil
    }

    /// صفّ وصل من قائمة («المنجزة») — يُحفظ فلا يُسأل عنه ثانية
    static func remember(_ row: MemberDeletePlace) {
        if found[row.memberId] == nil { found[row.memberId] = row }
        missing.remove(row.memberId)
    }

    static func lookup(_ id: UUID) async -> Result {
        if let known = cached(id) { return known }
        nonisolated struct Params: Encodable { let p_ids: [String] }
        do {
            let rows: [MemberDeletePlace] = try await SupabaseConfig.client
                .rpc("member_delete_places", params: Params(p_ids: [id.uuidString]))
                .execute()
                .value
            if let row = rows.first {
                found[id] = row
                return .found(row)
            }
            missing.insert(id)
            return .missing
        } catch {
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[DeletePlaces] تعذّر جلب مكان المحذوف: \(error.localizedDescription)")
            }
            return .unavailable
        }
    }

    /// المحذوفون منذ تاريخ (الأحدث أولاً) — لـ«المنجزة»
    static func recent(since: Date, limit: Int = 200) async throws -> [MemberDeletePlace] {
        nonisolated struct Params: Encodable { let p_since: String; let p_limit: Int }
        let rows: [MemberDeletePlace] = try await SupabaseConfig.client
            .rpc("member_delete_places",
                 params: Params(p_since: DateParsing.isoString(since), p_limit: limit))
            .execute()
            .value
        rows.forEach(remember)
        return rows
    }
}
