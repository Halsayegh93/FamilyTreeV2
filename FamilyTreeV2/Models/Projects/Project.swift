import Foundation

struct Project: Identifiable, Codable {
    let id: UUID
    var ownerId: UUID
    var ownerName: String
    var title: String
    var description: String?
    var logoUrl: String?
    var websiteUrl: String?
    var instagramUrl: String?
    var twitterUrl: String?
    var tiktokUrl: String?
    var snapchatUrl: String?
    var whatsappNumber: String?
    var phoneNumber: String?
    var approvalStatus: String
    var approvedBy: UUID?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case ownerName = "owner_name"
        case title
        case description
        case logoUrl = "logo_url"
        case websiteUrl = "website_url"
        case instagramUrl = "instagram_url"
        case twitterUrl = "twitter_url"
        case tiktokUrl = "tiktok_url"
        case snapchatUrl = "snapchat_url"
        case whatsappNumber = "whatsapp_number"
        case phoneNumber = "phone_number"
        case approvalStatus = "approval_status"
        case approvedBy = "approved_by"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        ownerId = try container.decode(UUID.self, forKey: .ownerId)
        ownerName = try container.decode(String.self, forKey: .ownerName)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        logoUrl = try container.decodeIfPresent(String.self, forKey: .logoUrl)
        websiteUrl = try container.decodeIfPresent(String.self, forKey: .websiteUrl)
        instagramUrl = try container.decodeIfPresent(String.self, forKey: .instagramUrl)
        twitterUrl = try container.decodeIfPresent(String.self, forKey: .twitterUrl)
        tiktokUrl = try container.decodeIfPresent(String.self, forKey: .tiktokUrl)
        snapchatUrl = try container.decodeIfPresent(String.self, forKey: .snapchatUrl)
        whatsappNumber = try container.decodeIfPresent(String.self, forKey: .whatsappNumber)
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        approvalStatus = try container.decode(String.self, forKey: .approvalStatus)
        approvedBy = try container.decodeIfPresent(UUID.self, forKey: .approvedBy)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    init(id: UUID = UUID(), ownerId: UUID, ownerName: String, title: String,
         description: String? = nil, logoUrl: String? = nil,
         websiteUrl: String? = nil, instagramUrl: String? = nil,
         twitterUrl: String? = nil, tiktokUrl: String? = nil,
         snapchatUrl: String? = nil, whatsappNumber: String? = nil,
         phoneNumber: String? = nil, approvalStatus: String = "approved",
         approvedBy: UUID? = nil, createdAt: String? = nil) {
        self.id = id
        self.ownerId = ownerId
        self.ownerName = ownerName
        self.title = title
        self.description = description
        self.logoUrl = logoUrl
        self.websiteUrl = websiteUrl
        self.instagramUrl = instagramUrl
        self.twitterUrl = twitterUrl
        self.tiktokUrl = tiktokUrl
        self.snapchatUrl = snapchatUrl
        self.whatsappNumber = whatsappNumber
        self.phoneNumber = phoneNumber
        self.approvalStatus = approvalStatus
        self.approvedBy = approvedBy
        self.createdAt = createdAt
    }

    /// Whether this project has any social media links
    var hasSocialLinks: Bool {
        instagramUrl != nil || twitterUrl != nil || tiktokUrl != nil ||
        snapchatUrl != nil || whatsappNumber != nil || websiteUrl != nil ||
        phoneNumber != nil
    }
}
