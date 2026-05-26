import Foundation
import SwiftUI

/// عنصر في أرشيف العائلة — وثيقة PDF أو صورة قديمة أو كتاب رقمي.
/// مرتبط بـ Supabase table `family_archive` و bucket `family-archive`.
struct ArchiveItem: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let description: String?
    let category: Category
    let fileUrl: String           // URL عام لـ Supabase Storage
    let fileType: String          // MIME (مثلاً: application/pdf, image/jpeg)
    let fileSize: Int64?          // الحجم بالبايت — للعرض
    let fileName: String?         // الاسم الأصلي للملف — للتنزيل
    let thumbnailUrl: String?     // مصغّرة للـ PDF (الصفحة الأولى) — اختيارية
    let uploadedBy: UUID
    let createdAt: Date
    /// إخفاء soft من قِبَل الإدارة — العضو العادي ما يشوف، الإدارة تشوف بعلامة مميّزة.
    /// `var` لتسهيل التحديث المحلّي بعد toggle.
    var isHidden: Bool
    /// حالة الموافقة. الافتراضي pending للأعضاء العاديين، approved للإدارة.
    var approvalStatus: ApprovalStatus
    var approvedBy: UUID?
    var approvedAt: Date?

    enum ApprovalStatus: String, Codable {
        case pending, approved, rejected
    }

    enum Category: String, Codable, CaseIterable, Identifiable {
        case documents = "documents"
        case books = "books"
        case oldPhotos = "old_photos"
        case other = "other"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .documents:  return "وثائق"
            case .books:      return "كتب"
            case .oldPhotos:  return "صور قديمة"
            case .other:      return "أخرى"
            }
        }

        var displayNameEn: String {
            switch self {
            case .documents:  return "Documents"
            case .books:      return "Books"
            case .oldPhotos:  return "Old Photos"
            case .other:      return "Other"
            }
        }

        /// أيقونة SF Symbol مناسبة للقسم.
        var iconName: String {
            switch self {
            case .documents:  return "doc.text.fill"
            case .books:      return "book.closed.fill"
            case .oldPhotos:  return "photo.stack.fill"
            case .other:      return "folder.fill"
            }
        }

        /// لون مميّز لكل قسم — يفيد تصميم الفلاتر الفاخر.
        var accentColor: Color {
            switch self {
            case .documents:  return DS.Color.info        // أزرق رسمي
            case .books:      return DS.Color.warning     // ذهبي دافئ
            case .oldPhotos:  return DS.Color.neonPink    // وردي عتيق (sepia feel)
            case .other:      return DS.Color.textSecondary
            }
        }
    }

    /// هل العنصر صورة (لعرضها بمعاينة في الشبكة).
    var isImage: Bool {
        fileType.hasPrefix("image/")
    }

    /// هل العنصر PDF.
    var isPDF: Bool {
        fileType == "application/pdf"
    }

    /// نص مقروء لحجم الملف ("12.4 MB", "550 KB").
    var formattedSize: String {
        guard let bytes = fileSize, bytes > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case category
        case fileUrl        = "file_url"
        case fileType       = "file_type"
        case fileSize       = "file_size"
        case fileName       = "file_name"
        case thumbnailUrl   = "thumbnail_url"
        case uploadedBy     = "uploaded_by"
        case createdAt      = "created_at"
        case isHidden       = "is_hidden"
        case approvalStatus = "approval_status"
        case approvedBy     = "approved_by"
        case approvedAt     = "approved_at"
    }

    // Decoder متسامح: يفترض القيم الافتراضية للحقول الجديدة (للتوافق مع
    // migrations القديمة قبل تطبيقها).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self,    forKey: .id)
        title           = try c.decode(String.self,  forKey: .title)
        description     = try c.decodeIfPresent(String.self, forKey: .description)
        category        = try c.decode(Category.self, forKey: .category)
        fileUrl         = try c.decode(String.self,  forKey: .fileUrl)
        fileType        = try c.decode(String.self,  forKey: .fileType)
        fileSize        = try c.decodeIfPresent(Int64.self,  forKey: .fileSize)
        fileName        = try c.decodeIfPresent(String.self, forKey: .fileName)
        thumbnailUrl    = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        uploadedBy      = try c.decode(UUID.self,    forKey: .uploadedBy)
        createdAt       = try c.decode(Date.self,    forKey: .createdAt)
        isHidden        = try c.decodeIfPresent(Bool.self,   forKey: .isHidden) ?? false
        // إذا لا يوجد عمود approval_status (قبل migration الموافقة)، نعتبره مقبولاً
        approvalStatus  = try c.decodeIfPresent(ApprovalStatus.self, forKey: .approvalStatus) ?? .approved
        approvedBy      = try c.decodeIfPresent(UUID.self, forKey: .approvedBy)
        approvedAt      = try c.decodeIfPresent(Date.self, forKey: .approvedAt)
    }
}
