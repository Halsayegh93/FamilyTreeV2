import Foundation
import Supabase
import SwiftUI
import Combine

/// ViewModel لأرشيف العائلة — جلب/رفع/حذف عناصر الأرشيف (PDF + صور).
/// يستخدم Supabase Storage bucket `family-archive` و table `family_archive`.
@MainActor
final class FamilyArchiveViewModel: ObservableObject {

    private let supabase = SupabaseConfig.client
    private let tableName = "family_archive"
    private let bucketName = "family-archive"

    weak var authVM: AuthViewModel?

    @Published var items: [ArchiveItem] = []
    @Published var isLoading = false
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0
    @Published var errorMessage: String?

    func configure(authVM: AuthViewModel) {
        self.authVM = authVM
    }

    // MARK: - Fetch

    func fetchItems() async {
        guard NetworkMonitor.shared.isConnected else { return }
        isLoading = true
        errorMessage = nil
        do {
            let response: [ArchiveItem] = try await supabase
                .from(tableName)
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
            self.items = response
            Log.info("[Archive] جلب \(response.count) عنصر")
        } catch {
            // قد يكون الجدول غير موجود بعد (قبل تشغيل migration)
            if isMissingTableError(error) {
                self.items = []
                self.errorMessage = nil
                Log.warning("[Archive] جدول family_archive غير موجود — تجاهُل")
            } else {
                self.errorMessage = L10n.t("تعذّر تحميل الأرشيف.", "Failed to load archive.")
                Log.error("[Archive] خطأ جلب: \(error.localizedDescription)")
            }
        }
        isLoading = false
    }

    // MARK: - Upload

    /// رفع ملف للأرشيف. يتولّى رفع الملف لـ Storage ثم إدراج صف في الجدول.
    /// - Returns: العنصر الجديد عند النجاح، nil عند الفشل.
    @discardableResult
    func uploadItem(
        title: String,
        description: String?,
        category: ArchiveItem.Category,
        fileData: Data,
        fileName: String,
        mimeType: String
    ) async -> ArchiveItem? {
        guard NetworkMonitor.shared.requireOnline() else { return nil }
        guard let uploaderId = authVM?.currentUser?.id else {
            errorMessage = L10n.t("لم يتم تسجيل الدخول.", "Not signed in.")
            return nil
        }
        guard authVM?.isAdmin == true else {
            errorMessage = L10n.t("الرفع متاح للمدراء فقط.", "Upload is restricted to admins.")
            return nil
        }

        isUploading = true
        uploadProgress = 0
        errorMessage = nil
        defer { isUploading = false; uploadProgress = 0 }

        let itemId = UUID()
        let ext = (fileName as NSString).pathExtension.lowercased()
        let safeExt = ext.isEmpty ? defaultExtension(for: mimeType) : ext
        // مسار التخزين: {category}/{uuid}.{ext} — يفصل الأقسام في Storage أيضاً
        let storagePath = "\(category.rawValue)/\(itemId.uuidString).\(safeExt)"

        do {
            // 1) رفع الملف إلى Storage
            uploadProgress = 0.1
            try await supabase.storage
                .from(bucketName)
                .upload(storagePath, data: fileData, options: .init(
                    contentType: mimeType,
                    upsert: false
                ))
            uploadProgress = 0.7

            // 2) الحصول على URL عام
            let publicURL = try supabase.storage
                .from(bucketName)
                .getPublicURL(path: storagePath)

            // 3) إدراج صف في الجدول
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload: [String: AnyEncodable] = [
                "id":            AnyEncodable(itemId.uuidString),
                "title":         AnyEncodable(trimmedTitle),
                "description":   AnyEncodable((trimmedDescription?.isEmpty ?? true) ? Optional<String>.none : trimmedDescription),
                "category":      AnyEncodable(category.rawValue),
                "file_url":      AnyEncodable(publicURL.absoluteString),
                "file_type":     AnyEncodable(mimeType),
                "file_size":     AnyEncodable(Int64(fileData.count)),
                "file_name":     AnyEncodable(fileName),
                "uploaded_by":   AnyEncodable(uploaderId.uuidString)
            ]

            let inserted: [ArchiveItem] = try await supabase
                .from(tableName)
                .insert(payload)
                .select()
                .execute()
                .value
            uploadProgress = 1.0

            if let newItem = inserted.first {
                items.insert(newItem, at: 0)
                Log.info("[Archive] رفع ناجح: \(newItem.title)")
                return newItem
            }
            return nil
        } catch {
            // تنظيف: لو رفع الملف نجح والإدراج فشل، احذف الملف
            try? await supabase.storage.from(bucketName).remove(paths: [storagePath])
            self.errorMessage = L10n.t("تعذّر رفع العنصر.", "Failed to upload item.")
            Log.error("[Archive] خطأ رفع: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Delete

    func deleteItem(_ item: ArchiveItem) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard authVM?.isAdmin == true else {
            errorMessage = L10n.t("الحذف متاح للمدراء فقط.", "Delete is restricted to admins.")
            return
        }

        // تحديث تفاؤلي
        let originalIndex = items.firstIndex(of: item)
        if let idx = originalIndex {
            items.remove(at: idx)
        }

        do {
            // 1) حذف الصف من الجدول
            try await supabase
                .from(tableName)
                .delete()
                .eq("id", value: item.id.uuidString)
                .execute()

            // 2) حذف الملف من Storage (best-effort)
            if let path = storagePath(from: item.fileUrl) {
                try? await supabase.storage.from(bucketName).remove(paths: [path])
            }
            Log.info("[Archive] حذف ناجح: \(item.title)")
        } catch {
            // استرجاع عند الفشل
            if let idx = originalIndex {
                items.insert(item, at: min(idx, items.count))
            }
            self.errorMessage = L10n.t("تعذّر حذف العنصر.", "Failed to delete item.")
            Log.error("[Archive] خطأ حذف: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// عناصر القسم معيّن — مفلترة من القائمة الكاملة.
    func items(in category: ArchiveItem.Category) -> [ArchiveItem] {
        items.filter { $0.category == category }
    }

    /// عدد العناصر في قسم معيّن.
    func count(in category: ArchiveItem.Category) -> Int {
        items(in: category).count
    }

    /// استخراج مسار التخزين من URL عام (لإستخدامه عند الحذف).
    private func storagePath(from publicURL: String) -> String? {
        // النمط: .../storage/v1/object/public/family-archive/<path>
        guard let range = publicURL.range(of: "/object/public/\(bucketName)/") else { return nil }
        return String(publicURL[range.upperBound...])
    }

    /// امتداد افتراضي بناءً على MIME (احتياط لو fileName بدون امتداد).
    private func defaultExtension(for mime: String) -> String {
        switch mime {
        case "application/pdf": return "pdf"
        case "image/jpeg":      return "jpg"
        case "image/png":       return "png"
        case "image/heic":      return "heic"
        default:                return "bin"
        }
    }

    private func isMissingTableError(_ error: Error) -> Bool {
        let msg = error.localizedDescription.lowercased()
        return msg.contains("does not exist") || msg.contains("relation") && msg.contains("not")
            || msg.contains("42p01") || msg.contains("pgrst205")
    }
}
