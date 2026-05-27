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

        isUploading = true
        uploadProgress = 0
        errorMessage = nil
        defer { isUploading = false; uploadProgress = 0 }

        // المدير/المالك → موافق عليه تلقائياً. غيره → بانتظار الموافقة.
        let isAdmin = authVM?.isAdmin == true

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
            let nowIso = ISO8601DateFormatter().string(from: Date())
            var payload: [String: AnyEncodable] = [
                "id":              AnyEncodable(itemId.uuidString),
                "title":           AnyEncodable(trimmedTitle),
                "description":     AnyEncodable((trimmedDescription?.isEmpty ?? true) ? Optional<String>.none : trimmedDescription),
                "category":        AnyEncodable(category.rawValue),
                "file_url":        AnyEncodable(publicURL.absoluteString),
                "file_type":       AnyEncodable(mimeType),
                "file_size":       AnyEncodable(Int64(fileData.count)),
                "file_name":       AnyEncodable(fileName),
                "uploaded_by":     AnyEncodable(uploaderId.uuidString),
                "approval_status": AnyEncodable(isAdmin ? "approved" : "pending")
            ]
            if isAdmin {
                payload["approved_by"] = AnyEncodable(uploaderId.uuidString)
                payload["approved_at"] = AnyEncodable(nowIso)
            }

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
            _ = try? await supabase.storage.from(bucketName).remove(paths: [storagePath])
            self.errorMessage = L10n.t("تعذّر رفع العنصر.", "Failed to upload item.")
            Log.error("[Archive] خطأ رفع: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Approval (admin + owner)

    /// الموافقة على عنصر معلَّق — يصير مرئياً للجميع.
    func approveItem(_ item: ArchiveItem) async {
        await setApproval(item: item, status: .approved)
    }

    /// رفض عنصر معلَّق — يبقى موجود لكن لا يظهر للجمهور.
    func rejectItem(_ item: ArchiveItem) async {
        await setApproval(item: item, status: .rejected)
    }

    private func setApproval(item: ArchiveItem, status: ArchiveItem.ApprovalStatus) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard authVM?.isAdmin == true, let approverId = authVM?.currentUser?.id else {
            errorMessage = L10n.t("الموافقة متاحة للمدراء فقط.",
                                  "Approval is restricted to admins.")
            return
        }

        // تحديث تفاؤلي
        let oldStatus = item.approvalStatus
        let oldApprover = item.approvedBy
        let oldApprovedAt = item.approvedAt
        if let idx = items.firstIndex(of: item) {
            items[idx].approvalStatus = status
            items[idx].approvedBy = approverId
            items[idx].approvedAt = Date()
        }

        let nowIso = ISO8601DateFormatter().string(from: Date())
        let payload: [String: AnyEncodable] = [
            "approval_status": AnyEncodable(status.rawValue),
            "approved_by":     AnyEncodable(approverId.uuidString),
            "approved_at":     AnyEncodable(nowIso)
        ]

        do {
            try await supabase
                .from(tableName)
                .update(payload)
                .eq("id", value: item.id.uuidString)
                .execute()
            Log.info("[Archive] \(status.rawValue): \(item.title)")
        } catch {
            // استرجاع
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx].approvalStatus = oldStatus
                items[idx].approvedBy = oldApprover
                items[idx].approvedAt = oldApprovedAt
            }
            self.errorMessage = L10n.t("تعذّر تحديث حالة الموافقة.",
                                       "Failed to update approval.")
            Log.error("[Archive] خطأ setApproval: \(error.localizedDescription)")
        }
    }

    // MARK: - Toggle Hidden (soft hide / show)

    /// إخفاء/إظهار عنصر دون حذف. متاح لـ owner + admin فقط.
    func toggleHidden(_ item: ArchiveItem) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard authVM?.isAdmin == true else {
            errorMessage = L10n.t("الإخفاء متاح للمدراء فقط.", "Hiding is restricted to admins.")
            return
        }

        let newValue = !item.isHidden
        // تحديث تفاؤلي
        if let idx = items.firstIndex(of: item) {
            items[idx].isHidden = newValue
        }

        do {
            try await supabase
                .from(tableName)
                .update(["is_hidden": newValue])
                .eq("id", value: item.id.uuidString)
                .execute()
            Log.info("[Archive] \(newValue ? "إخفاء" : "إظهار"): \(item.title)")
        } catch {
            // استرجاع عند الفشل
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx].isHidden = !newValue
            }
            self.errorMessage = L10n.t("تعذّر تغيير حالة الإخفاء.",
                                       "Failed to toggle visibility.")
            Log.error("[Archive] خطأ toggleHidden: \(error.localizedDescription)")
        }
    }

    // MARK: - Batch Operations

    /// حذف عدة عناصر دفعة واحدة (للمدراء فقط).
    func deleteItems(ids: Set<UUID>) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard authVM?.isAdmin == true else {
            errorMessage = L10n.t("الحذف متاح للمدراء فقط.", "Delete is restricted to admins.")
            return
        }
        guard !ids.isEmpty else { return }

        // التقاط العناصر قبل الحذف (للاسترجاع عند الفشل ولتنظيف Storage)
        let targets = items.filter { ids.contains($0.id) }
        let idStrings = targets.map { $0.id.uuidString }

        // إزالة محلية تفاؤلية
        items.removeAll { ids.contains($0.id) }

        do {
            try await supabase
                .from(tableName)
                .delete()
                .in("id", values: idStrings)
                .execute()

            // حذف الملفات من Storage (best-effort)
            let paths = targets.compactMap { storagePath(from: $0.fileUrl) }
            if !paths.isEmpty {
                _ = try? await supabase.storage.from(bucketName).remove(paths: paths)
            }
            Log.info("[Archive] حذف دفعي: \(targets.count) عنصر")
        } catch {
            // استرجاع
            items.append(contentsOf: targets)
            items.sort { $0.createdAt > $1.createdAt }
            self.errorMessage = L10n.t("تعذّر حذف بعض العناصر.",
                                       "Failed to delete some items.")
            Log.error("[Archive] خطأ حذف دفعي: \(error.localizedDescription)")
        }
    }

    /// تعيين isHidden لعدة عناصر دفعة واحدة (للمدراء فقط).
    func setHidden(ids: Set<UUID>, hidden: Bool) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard authVM?.isAdmin == true else {
            errorMessage = L10n.t("الإخفاء متاح للمدراء فقط.", "Hiding is restricted to admins.")
            return
        }
        guard !ids.isEmpty else { return }

        let idStrings = Array(ids).map { $0.uuidString }

        // تحديث محلي تفاؤلي
        for i in items.indices where ids.contains(items[i].id) {
            items[i].isHidden = hidden
        }

        do {
            try await supabase
                .from(tableName)
                .update(["is_hidden": hidden])
                .in("id", values: idStrings)
                .execute()
            Log.info("[Archive] \(hidden ? "إخفاء" : "إظهار") دفعي: \(ids.count) عنصر")
        } catch {
            // استرجاع
            for i in items.indices where ids.contains(items[i].id) {
                items[i].isHidden = !hidden
            }
            self.errorMessage = L10n.t("تعذّر تغيير الحالة.", "Failed to toggle visibility.")
            Log.error("[Archive] خطأ setHidden دفعي: \(error.localizedDescription)")
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
                _ = try? await supabase.storage.from(bucketName).remove(paths: [path])
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

    /// عناصر قسم معيّن — أو الكل لو `nil`.
    func items(in category: ArchiveItem.Category?) -> [ArchiveItem] {
        guard let category else { return items }
        return items.filter { $0.category == category }
    }

    /// عدد العناصر في قسم معيّن — أو الإجمالي لو `nil`.
    func count(in category: ArchiveItem.Category?) -> Int {
        items(in: category).count
    }

    /// عدد العناصر بانتظار الموافقة (يفيد المدراء).
    var pendingCount: Int {
        items.filter { $0.approvalStatus == .pending }.count
    }

    /// استخراج مسار التخزين من URL عام (لإستخدامه عند الحذف).
    private func storagePath(from publicURL: String) -> String? {
        // النمط: .../storage/v1/object/public/family-archive/<path>
        guard let range = publicURL.range(of: "/object/public/\(bucketName)/") else { return nil }
        let path = String(publicURL[range.upperBound...])
        return path.isEmpty ? nil : path
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
        // أولوية operators صريحة بأقواس
        return msg.contains("does not exist")
            || (msg.contains("relation") && msg.contains("not"))
            || msg.contains("42p01")
            || msg.contains("pgrst205")
    }
}
