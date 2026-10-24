import Foundation

nonisolated struct PhoneChangeRequest: Identifiable, Codable, Sendable {
    let id: UUID
    let memberId: UUID
    let requesterId: UUID?
    let requestType: String
    var newValue: String?
    var status: String
    let details: String?
    let createdAt: String?
    let member: FamilyMember?
    // «مسار الموافقات» (٢٠٢٦-١٠-١٥) — نفس أعمدة `AdminRequest` الاختيارية
    var stage: String? = nil
    var stageSince: String? = nil
    var recommendation: String? = nil
    var recommendationNote: String? = nil
    var recommendedBy: UUID? = nil
    var recommendedAt: String? = nil
    var infoRequest: String? = nil
    var approvedBy: UUID? = nil
    var approvedAt: String? = nil
    var approvalNote: String? = nil
    /// «طلب معلومات» منظّم (٢٠٢٦-١٠-١٥): الحقول المطلوبة وردّ العضو — اختياريان، والردّ يُقرأ بتسامح
    var infoFields: [String]? = nil
    var infoReply: ApprovalInfoValues? = nil
    /// «مسار الموافقات ٢» (طلب المالك ٢٠٢٦-١٠-١٦): الأولوية والاستلام والتصعيد والمسار السريع — اختيارية
    var priority: String? = nil
    var assignedTo: UUID? = nil
    var assignedAt: String? = nil
    var remindedAt: String? = nil
    var escalatedAt: String? = nil
    var fastTrack: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id, status, details, member, stage, recommendation
        case memberId = "member_id"
        case requesterId = "requester_id"
        case requestType = "request_type"
        case newValue = "new_value"
        case createdAt = "created_at"
        case stageSince = "stage_since"
        case recommendationNote = "recommendation_note"
        case recommendedBy = "recommended_by"
        case recommendedAt = "recommended_at"
        case infoRequest = "info_request"
        case approvedBy = "approved_by"
        case approvedAt = "approved_at"
        case approvalNote = "approval_note"
        case infoFields = "info_fields"
        case infoReply = "info_reply"
        case priority
        case assignedTo = "assigned_to"
        case assignedAt = "assigned_at"
        case remindedAt = "reminded_at"
        case escalatedAt = "escalated_at"
        case fastTrack = "fast_track"
    }
}
