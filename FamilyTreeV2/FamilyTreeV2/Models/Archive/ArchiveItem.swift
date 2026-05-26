import Foundation

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
        case fileUrl       = "file_url"
        case fileType      = "file_type"
        case fileSize      = "file_size"
        case fileName      = "file_name"
        case thumbnailUrl  = "thumbnail_url"
        case uploadedBy    = "uploaded_by"
        case createdAt     = "created_at"
    }
}
