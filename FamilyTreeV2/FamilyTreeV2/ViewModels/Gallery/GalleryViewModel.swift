import Foundation
import Supabase
import SwiftUI
import Combine

/// ViewModel لمعرض الصور — ألبومات وصور. الإنشاء/الرفع/الحذف للإدارة فقط.
/// يستخدم Supabase Storage bucket `family-gallery` و tables `gallery_albums` + `gallery_photos`.
@MainActor
final class GalleryViewModel: ObservableObject {

    private let supabase = SupabaseConfig.client
    private let albumsTable = "gallery_albums"
    private let photosTable = "gallery_photos"
    private let bucketName = "family-gallery"

    weak var authVM: AuthViewModel?

    @Published var albums: [GalleryAlbum] = []
    @Published var photos: [GalleryPhoto] = []      // كل الصور (تُجمّع محلياً حسب الألبوم)
    @Published var isLoading = false
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0
    @Published var errorMessage: String?

    func configure(authVM: AuthViewModel) {
        self.authVM = authVM
    }

    // MARK: - Fetch

    /// جلب الألبومات والصور معاً.
    func fetchAll() async {
        guard NetworkMonitor.shared.isConnected else { return }
        isLoading = true
        errorMessage = nil
        await fetchAlbums()
        await fetchPhotos()
        isLoading = false
    }

    func fetchAlbums() async {
        do {
            let response: [GalleryAlbum] = try await supabase
                .from(albumsTable)
                .select()
                .order("year", ascending: false)
                .order("created_at", ascending: false)
                .execute()
                .value
            self.albums = response
            Log.info("[Gallery] جلب \(response.count) ألبوم")
        } catch {
            if isMissingTableError(error) {
                self.albums = []
                Log.warning("[Gallery] جدول gallery_albums غير موجود — تجاهُل")
            } else {
                self.errorMessage = L10n.t("تعذّر تحميل المعرض.", "Failed to load gallery.")
                Log.error("[Gallery] خطأ جلب الألبومات: \(error.localizedDescription)")
            }
        }
    }

    func fetchPhotos() async {
        do {
            let response: [GalleryPhoto] = try await supabase
                .from(photosTable)
                .select()
                .order("sort_order", ascending: true)
                .order("created_at", ascending: true)
                .execute()
                .value
            self.photos = response
            Log.info("[Gallery] جلب \(response.count) صورة")
        } catch {
            if isMissingTableError(error) {
                self.photos = []
                Log.warning("[Gallery] جدول gallery_photos غير موجود — تجاهُل")
            } else {
                self.errorMessage = L10n.t("تعذّر تحميل الصور.", "Failed to load photos.")
                Log.error("[Gallery] خطأ جلب الصور: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Grouping Helpers

    /// صور ألبوم معيّن مرتّبة (sort_order ثم created_at).
    func photos(in albumId: UUID) -> [GalleryPhoto] {
        photos
            .filter { $0.albumId == albumId }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.createdAt < $1.createdAt
            }
    }

    /// عدد الصور في ألبوم.
    func photoCount(in albumId: UUID) -> Int {
        photos.reduce(0) { $0 + ($1.albumId == albumId ? 1 : 0) }
    }

    /// رابط الغلاف — الغلاف المختار يدوياً أو أول صورة.
    func coverURL(for album: GalleryAlbum) -> String? {
        if let cover = album.coverUrl, !cover.isEmpty { return cover }
        return photos(in: album.id).first?.photoUrl
    }

    /// الألبومات مجمّعة تحت رؤوس السنوات — السنوات تنازلياً، وبلا سنة في الأخير.
    /// كل عنصر: (السنة أو nil, ألبومات تلك السنة).
    var albumsGroupedByYear: [(year: Int?, albums: [GalleryAlbum])] {
        let visible = albums.filter { !$0.isHidden || (authVM?.isAdmin == true) }
        let grouped = Dictionary(grouping: visible) { $0.year }
        // السنوات المعرّفة تنازلياً، ثم مجموعة "بلا سنة" (nil) أخيراً.
        let datedKeys = grouped.keys.compactMap { $0 }.sorted(by: >)
        var result: [(Int?, [GalleryAlbum])] = datedKeys.map { ($0, grouped[$0] ?? []) }
        if let undated = grouped[nil], !undated.isEmpty {
            result.append((nil, undated))
        }
        return result.map { (year: $0.0, albums: $0.1) }
    }

    /// أحدث صورة في كل المعرض — لغلاف مربّع الرئيسية.
    var latestCoverURL: String? {
        photos.max(by: { $0.createdAt < $1.createdAt })?.photoUrl
    }

    // MARK: - Create Album

    @discardableResult
    func createAlbum(title: String, year: Int?) async -> GalleryAlbum? {
        guard NetworkMonitor.shared.requireOnline() else { return nil }
        guard authVM?.isAdmin == true, let creatorId = authVM?.currentUser?.id else {
            errorMessage = L10n.t("الإنشاء متاح للإدارة فقط.", "Only admins can create albums.")
            return nil
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let albumId = UUID()
        var payload: [String: AnyEncodable] = [
            "id":         AnyEncodable(albumId.uuidString),
            "title":      AnyEncodable(trimmed),
            "created_by": AnyEncodable(creatorId.uuidString)
        ]
        if let year { payload["year"] = AnyEncodable(year) }

        do {
            let inserted: [GalleryAlbum] = try await supabase
                .from(albumsTable)
                .insert(payload)
                .select()
                .execute()
                .value
            if let newAlbum = inserted.first {
                albums.insert(newAlbum, at: 0)
                Log.info("[Gallery] إنشاء ألبوم: \(newAlbum.title)")
                return newAlbum
            }
            return nil
        } catch {
            self.errorMessage = L10n.t("تعذّر إنشاء الألبوم.", "Failed to create album.")
            Log.error("[Gallery] خطأ إنشاء ألبوم: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Update Album (title / year)

    func updateAlbum(_ album: GalleryAlbum, title: String, year: Int?) async -> Bool {
        guard NetworkMonitor.shared.requireOnline() else { return false }
        guard authVM?.isAdmin == true else {
            errorMessage = L10n.t("التعديل متاح للإدارة فقط.", "Only admins can edit.")
            return false
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let payload: [String: AnyEncodable] = [
            "title": AnyEncodable(trimmed),
            "year":  AnyEncodable(year)
        ]
        do {
            let updated: [GalleryAlbum] = try await supabase
                .from(albumsTable)
                .update(payload)
                .eq("id", value: album.id.uuidString)
                .select()
                .execute()
                .value
            if let newAlbum = updated.first, let idx = albums.firstIndex(where: { $0.id == album.id }) {
                albums[idx] = newAlbum
            }
            Log.info("[Gallery] تعديل ألبوم: \(trimmed)")
            return true
        } catch {
            self.errorMessage = L10n.t("تعذّر حفظ التعديل.", "Failed to save changes.")
            Log.error("[Gallery] خطأ تعديل ألبوم: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Toggle Hidden

    func toggleHidden(_ album: GalleryAlbum) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard authVM?.isAdmin == true else {
            errorMessage = L10n.t("الإخفاء متاح للإدارة فقط.", "Only admins can hide.")
            return
        }
        let newValue = !album.isHidden
        if let idx = albums.firstIndex(where: { $0.id == album.id }) {
            albums[idx].isHidden = newValue
        }
        do {
            try await supabase
                .from(albumsTable)
                .update(["is_hidden": newValue])
                .eq("id", value: album.id.uuidString)
                .execute()
            Log.info("[Gallery] \(newValue ? "إخفاء" : "إظهار") ألبوم: \(album.title)")
        } catch {
            if let idx = albums.firstIndex(where: { $0.id == album.id }) {
                albums[idx].isHidden = !newValue
            }
            self.errorMessage = L10n.t("تعذّر تغيير حالة الإخفاء.", "Failed to toggle visibility.")
            Log.error("[Gallery] خطأ toggleHidden: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete Album (+ صوره + ملفات Storage)

    func deleteAlbum(_ album: GalleryAlbum) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard authVM?.isAdmin == true else {
            errorMessage = L10n.t("الحذف متاح للإدارة فقط.", "Only admins can delete.")
            return
        }

        let albumPhotos = photos(in: album.id)
        // إزالة محلية تفاؤلية
        let originalAlbums = albums
        let originalPhotos = photos
        albums.removeAll { $0.id == album.id }
        photos.removeAll { $0.albumId == album.id }

        do {
            // 1) حذف صفوف الصور (الجدول قد يملك ON DELETE CASCADE أيضاً، لكن نضمنها)
            try await supabase
                .from(photosTable)
                .delete()
                .eq("album_id", value: album.id.uuidString)
                .execute()
            // 2) حذف صف الألبوم
            try await supabase
                .from(albumsTable)
                .delete()
                .eq("id", value: album.id.uuidString)
                .execute()
            // 3) حذف ملفات Storage (best-effort)
            let paths = albumPhotos.compactMap { storagePath(from: $0.photoUrl) }
            if !paths.isEmpty {
                _ = try? await supabase.storage.from(bucketName).remove(paths: paths)
            }
            Log.info("[Gallery] حذف ألبوم: \(album.title) (\(albumPhotos.count) صورة)")
        } catch {
            albums = originalAlbums
            photos = originalPhotos
            self.errorMessage = L10n.t("تعذّر حذف الألبوم.", "Failed to delete album.")
            Log.error("[Gallery] خطأ حذف ألبوم: \(error.localizedDescription)")
        }
    }

    // MARK: - Add Photos (رفع دفعي)

    /// رفع عدة صور لألبوم. يحوّل كل UIImage لـ JPEG ويرفعه ثم يُدرج صفاً.
    /// - Returns: عدد الصور المرفوعة بنجاح.
    @discardableResult
    func addPhotos(albumId: UUID, images: [UIImage]) async -> Int {
        guard NetworkMonitor.shared.requireOnline() else { return 0 }
        guard authVM?.isAdmin == true, let uploaderId = authVM?.currentUser?.id else {
            errorMessage = L10n.t("الرفع متاح للإدارة فقط.", "Only admins can upload.")
            return 0
        }
        guard !images.isEmpty else { return 0 }

        isUploading = true
        uploadProgress = 0
        errorMessage = nil
        defer { isUploading = false; uploadProgress = 0 }

        // ترتيب البداية بعد آخر صورة موجودة
        var nextOrder = (photos(in: albumId).map { $0.sortOrder }.max() ?? -1) + 1
        var uploaded = 0

        for (index, image) in images.enumerated() {
            guard let data = image.jpegData(compressionQuality: 0.85) else { continue }
            let photoId = UUID()
            let storagePath = "\(albumId.uuidString)/\(photoId.uuidString).jpg"
            do {
                try await supabase.storage
                    .from(bucketName)
                    .upload(storagePath, data: data, options: .init(
                        contentType: "image/jpeg",
                        upsert: false
                    ))
                let publicURL = try supabase.storage
                    .from(bucketName)
                    .getPublicURL(path: storagePath)

                let payload: [String: AnyEncodable] = [
                    "id":          AnyEncodable(photoId.uuidString),
                    "album_id":    AnyEncodable(albumId.uuidString),
                    "photo_url":   AnyEncodable(publicURL.absoluteString),
                    "sort_order":  AnyEncodable(nextOrder),
                    "uploaded_by": AnyEncodable(uploaderId.uuidString)
                ]
                let inserted: [GalleryPhoto] = try await supabase
                    .from(photosTable)
                    .insert(payload)
                    .select()
                    .execute()
                    .value
                if let newPhoto = inserted.first {
                    photos.append(newPhoto)
                    uploaded += 1
                    nextOrder += 1
                }
            } catch {
                // تنظيف: لو رفع الملف نجح والإدراج فشل
                _ = try? await supabase.storage.from(bucketName).remove(paths: [storagePath])
                Log.error("[Gallery] خطأ رفع صورة: \(error.localizedDescription)")
            }
            uploadProgress = Double(index + 1) / Double(images.count)
        }

        if uploaded == 0 {
            errorMessage = L10n.t("تعذّر رفع الصور.", "Failed to upload photos.")
        } else {
            Log.info("[Gallery] رفع \(uploaded)/\(images.count) صورة")
        }
        return uploaded
    }

    // MARK: - Delete Photo

    func deletePhoto(_ photo: GalleryPhoto) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard authVM?.isAdmin == true else {
            errorMessage = L10n.t("الحذف متاح للإدارة فقط.", "Only admins can delete.")
            return
        }
        let original = photos
        photos.removeAll { $0.id == photo.id }
        do {
            try await supabase
                .from(photosTable)
                .delete()
                .eq("id", value: photo.id.uuidString)
                .execute()
            if let path = storagePath(from: photo.photoUrl) {
                _ = try? await supabase.storage.from(bucketName).remove(paths: [path])
            }
            Log.info("[Gallery] حذف صورة")
        } catch {
            photos = original
            self.errorMessage = L10n.t("تعذّر حذف الصورة.", "Failed to delete photo.")
            Log.error("[Gallery] خطأ حذف صورة: \(error.localizedDescription)")
        }
    }

    /// حذف عدة صور دفعة واحدة (للإدارة).
    func deletePhotos(ids: Set<UUID>) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard authVM?.isAdmin == true else {
            errorMessage = L10n.t("الحذف متاح للإدارة فقط.", "Only admins can delete.")
            return
        }
        guard !ids.isEmpty else { return }
        let targets = photos.filter { ids.contains($0.id) }
        let idStrings = targets.map { $0.id.uuidString }
        let original = photos
        photos.removeAll { ids.contains($0.id) }
        do {
            try await supabase
                .from(photosTable)
                .delete()
                .in("id", values: idStrings)
                .execute()
            let paths = targets.compactMap { storagePath(from: $0.photoUrl) }
            if !paths.isEmpty {
                _ = try? await supabase.storage.from(bucketName).remove(paths: paths)
            }
            Log.info("[Gallery] حذف دفعي: \(targets.count) صورة")
        } catch {
            photos = original
            self.errorMessage = L10n.t("تعذّر حذف بعض الصور.", "Failed to delete some photos.")
            Log.error("[Gallery] خطأ حذف دفعي: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// استخراج مسار التخزين من URL عام (لإستخدامه عند الحذف).
    private func storagePath(from publicURL: String) -> String? {
        guard let range = publicURL.range(of: "/object/public/\(bucketName)/") else { return nil }
        let path = String(publicURL[range.upperBound...])
        return path.isEmpty ? nil : path
    }

    private func isMissingTableError(_ error: Error) -> Bool {
        let msg = error.localizedDescription.lowercased()
        return msg.contains("does not exist")
            || (msg.contains("relation") && msg.contains("not"))
            || msg.contains("42p01")
            || msg.contains("pgrst205")
    }
}
