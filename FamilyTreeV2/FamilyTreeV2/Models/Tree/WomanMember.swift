import Foundation

/// عضو في شجرة النساء (`women_members`) — الزوجات والبنات والأمهات.
/// جدول منفصل عن `profiles`. الذكور مُمثّلون بنفس المعرّف (mirror)، والنساء
/// يُضفن فقط هنا. نعرضه في تطبيق الآيفون للقراءة فقط (التعديل عبر الويب).
struct WomanMember: Identifiable, Codable, Equatable {
    let id: UUID
    let firstName: String
    let fullName: String
    let parentId: UUID?
    let husbandId: UUID?
    let motherId: UUID?
    let gender: String
    let isDeceased: Bool
    let birthDate: String?
    let avatarUrl: String?
    let photoUrl: String?
    let sortOrder: Int

    /// الصورة المفضّلة للعرض (avatar ثم photo).
    var displayImageUrl: String? {
        if let a = avatarUrl, !a.isEmpty { return a }
        if let p = photoUrl, !p.isEmpty { return p }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case fullName  = "full_name"
        case parentId  = "parent_id"
        case husbandId = "husband_id"
        case motherId  = "mother_id"
        case gender
        case isDeceased = "is_deceased"
        case birthDate  = "birth_date"
        case avatarUrl  = "avatar_url"
        case photoUrl   = "photo_url"
        case sortOrder  = "sort_order"
    }

    init(id: UUID, firstName: String, fullName: String, parentId: UUID?, husbandId: UUID?,
         motherId: UUID?, gender: String, isDeceased: Bool, birthDate: String?,
         avatarUrl: String?, photoUrl: String?, sortOrder: Int) {
        self.id = id; self.firstName = firstName; self.fullName = fullName
        self.parentId = parentId; self.husbandId = husbandId; self.motherId = motherId
        self.gender = gender; self.isDeceased = isDeceased; self.birthDate = birthDate
        self.avatarUrl = avatarUrl; self.photoUrl = photoUrl; self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self, forKey: .id)
        firstName  = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        fullName   = try c.decodeIfPresent(String.self, forKey: .fullName) ?? ""
        parentId   = try c.decodeIfPresent(UUID.self, forKey: .parentId)
        husbandId  = try c.decodeIfPresent(UUID.self, forKey: .husbandId)
        motherId   = try c.decodeIfPresent(UUID.self, forKey: .motherId)
        gender     = try c.decodeIfPresent(String.self, forKey: .gender) ?? "female"
        isDeceased = try c.decodeIfPresent(Bool.self, forKey: .isDeceased) ?? false
        birthDate  = try c.decodeIfPresent(String.self, forKey: .birthDate)
        avatarUrl  = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        photoUrl   = try c.decodeIfPresent(String.self, forKey: .photoUrl)
        sortOrder  = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }
}

/// فرد من عائلة العضو في شجرة النساء مع دوره (أم/زوجة/ابن) — للعرض في «عائلتي».
struct WomenFamilyEntry: Identifiable, Equatable {
    let member: WomanMember
    let role: Role
    var id: UUID { member.id }

    enum Role: Int, Equatable {
        case mother = 0   // تُعرض أولاً
        case wife   = 1
        case child  = 2

        var label: String {
            switch self {
            case .mother: return "الأم"
            case .wife:   return "الزوجة"
            case .child:  return "ابن/ابنة"
            }
        }
        var labelEn: String {
            switch self {
            case .mother: return "Mother"
            case .wife:   return "Wife"
            case .child:  return "Child"
            }
        }
    }
}
