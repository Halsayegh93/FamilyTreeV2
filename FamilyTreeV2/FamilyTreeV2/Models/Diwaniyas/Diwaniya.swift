import Foundation
import CoreLocation

nonisolated struct Diwaniya: Identifiable, Codable, Sendable {
    let id: UUID
    var ownerId: UUID
    var ownerName: String
    var title: String
    var scheduleText: String?
    var contactPhone: String?
    var mapsUrl: String?
    var imageUrl: String?
    var address: String?
    var isClosed: Bool?
    var approvalStatus: String
    var approvedBy: UUID?
    
    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case ownerName = "owner_name"
        case title = "title"
        case scheduleText = "schedule_text"
        case contactPhone = "contact_phone"
        case mapsUrl = "maps_url"
        case imageUrl = "image_url"
        case address
        case isClosed = "is_closed"
        case approvalStatus = "approval_status"
        case approvedBy = "approved_by"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        ownerId = try container.decode(UUID.self, forKey: .ownerId)
        ownerName = try container.decode(String.self, forKey: .ownerName)
        title = try container.decode(String.self, forKey: .title)
        scheduleText = try container.decodeIfPresent(String.self, forKey: .scheduleText)
        contactPhone = try container.decodeIfPresent(String.self, forKey: .contactPhone)
        mapsUrl = try container.decodeIfPresent(String.self, forKey: .mapsUrl)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        address = try? container.decodeIfPresent(String.self, forKey: .address)
        isClosed = try? container.decodeIfPresent(Bool.self, forKey: .isClosed)
        approvalStatus = try container.decode(String.self, forKey: .approvalStatus)
        approvedBy = try container.decodeIfPresent(UUID.self, forKey: .approvedBy)
    }
    
    init(id: UUID, ownerId: UUID, ownerName: String, title: String, scheduleText: String?, contactPhone: String?, mapsUrl: String?, imageUrl: String?, address: String?, isClosed: Bool? = nil, approvalStatus: String, approvedBy: UUID?) {
        self.id = id
        self.ownerId = ownerId
        self.ownerName = ownerName
        self.title = title
        self.scheduleText = scheduleText
        self.contactPhone = contactPhone
        self.mapsUrl = mapsUrl
        self.imageUrl = imageUrl
        self.address = address
        self.isClosed = isClosed
        self.approvalStatus = approvalStatus
        self.approvedBy = approvedBy
    }
}
