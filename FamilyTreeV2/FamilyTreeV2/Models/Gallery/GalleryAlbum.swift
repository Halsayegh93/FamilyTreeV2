import Foundation
import SwiftUI

/// ألبوم في معرض الصور — مجموعة صور تحت مسمّى وسنة اختيارية.
/// مرتبط بـ Supabase table `gallery_albums` و bucket `family-gallery`.
/// الإنشاء/الرفع/الحذف للإدارة فقط (owner + admin).
struct GalleryAlbum: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let title: String
    let year: Int?                  // سنة الألبوم — اختيارية (للتجميع تحت رؤوس السنوات)
    let coverUrl: String?           // غلاف مختار يدوياً — اختياري (يُشتق من أول صورة إن غاب)
    let createdBy: UUID
    let createdAt: Date
    /// إخفاء soft من قِبَل الإدارة — `var` لتسهيل التحديث المحلّي بعد toggle.
    var isHidden: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case year
        case coverUrl   = "cover_url"
        case createdBy  = "created_by"
        case createdAt  = "created_at"
        case isHidden   = "is_hidden"
    }

    // Decoder متسامح: يفترض القيم الافتراضية للحقول الجديدة (توافق مع migrations قديمة).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self, forKey: .id)
        title     = try c.decode(String.self, forKey: .title)
        year      = try c.decodeIfPresent(Int.self, forKey: .year)
        coverUrl  = try c.decodeIfPresent(String.self, forKey: .coverUrl)
        createdBy = try c.decode(UUID.self, forKey: .createdBy)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        isHidden  = try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }

    init(id: UUID, title: String, year: Int?, coverUrl: String?,
         createdBy: UUID, createdAt: Date, isHidden: Bool) {
        self.id = id
        self.title = title
        self.year = year
        self.coverUrl = coverUrl
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.isHidden = isHidden
    }
}

/// صورة داخل ألبوم في معرض الصور.
/// مرتبطة بـ Supabase table `gallery_photos`.
struct GalleryPhoto: Identifiable, Codable, Equatable {
    let id: UUID
    let albumId: UUID
    let photoUrl: String
    let caption: String?
    let sortOrder: Int
    let uploadedBy: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case albumId    = "album_id"
        case photoUrl   = "photo_url"
        case caption
        case sortOrder  = "sort_order"
        case uploadedBy = "uploaded_by"
        case createdAt  = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self, forKey: .id)
        albumId    = try c.decode(UUID.self, forKey: .albumId)
        photoUrl   = try c.decode(String.self, forKey: .photoUrl)
        caption    = try c.decodeIfPresent(String.self, forKey: .caption)
        sortOrder  = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        uploadedBy = try c.decode(UUID.self, forKey: .uploadedBy)
        createdAt  = try c.decode(Date.self, forKey: .createdAt)
    }
}
