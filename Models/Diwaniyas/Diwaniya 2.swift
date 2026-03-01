import Foundation
import CoreLocation

struct Diwaniya: Identifiable, Codable {
    let id: UUID
    var ownerId: UUID
    var ownerName: String
    var title: String
    var scheduleText: String?
    var contactPhone: String?
    var mapsUrl: String?
    var imageUrl: String?
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
        case approvalStatus = "approval_status"
        case approvedBy = "approved_by"
    }
}
