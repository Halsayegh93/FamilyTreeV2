import Foundation
import UIKit

/// رفع ملف للمكتبة من داخل امتداد المشاركة.
///
/// لا نستورد حزمة Supabase هنا عمداً — الامتداد له سقف ذاكرة ضيّق، ونداءان
/// REST يكفيان: رفع للتخزين ثم إدراج صف. نستخدم رمز الجلسة المشترك عبر
/// App Group (انظر SharedSessionStore في التطبيق).
enum ShareUploader {

    enum UploadError: LocalizedError {
        case notSignedIn
        case storageFailed(String)
        case insertFailed(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "افتح التطبيق وسجّل دخولك أولاً، ثم أعد المشاركة."
            case .storageFailed(let m):
                return "تعذّر رفع الملف. \(m)"
            case .insertFailed(let m):
                return "رُفع الملف لكن تعذّر حفظ بياناته. \(m)"
            }
        }
    }

    /// أقسام المكتبة — مطابقة ArchiveItem.Category في التطبيق.
    enum Category: String, CaseIterable, Identifiable {
        case documents = "documents"
        case books = "books"
        case oldPhotos = "old_photos"
        case other = "other"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .documents: return "وثائق"   // نفس الاسم المدمج في التطبيق
            case .books:     return "كتب"
            case .oldPhotos: return "صور قديمة"
            case .other:     return "أخرى"
            }
        }

        var icon: String {
            switch self {
            case .documents: return "doc.text.fill"
            case .books:     return "books.vertical.fill"
            case .oldPhotos: return "photo.on.rectangle.angled"
            case .other:     return "square.grid.2x2.fill"
            }
        }
    }

    /// تصنيف المكتبة كما في «التصنيفات» على السيرفر (الاسم والأيقونة والترتيب) — مثل CategoryStore في التطبيق.
    /// المفتاح المدمج (documents/books/old_photos/other) يُحفظ في `category`، والمخصّص في `category_key` مع `other`.
    struct LiveCategory: Identifiable, Hashable {
        let key: String
        let title: String
        let icon: String
        var id: String { key }
        var builtIn: Category? { Category(rawValue: key) }
    }

    /// يجلب تصنيفات المكتبة الظاهرة — nil عند الفشل (يعرض الامتداد القائمة المدمجة)
    static func fetchCategories() async -> [LiveCategory]? {
        guard let session = SharedSessionStore.current() else { return nil }
        var comps = URLComponents(url: ShareConfig.url.appendingPathComponent("rest/v1/content_categories"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "select", value: "key,name_ar,icon_key,sort_order"),
                             URLQueryItem(name: "section", value: "eq.archive"),
                             URLQueryItem(name: "is_active", value: "eq.true"),
                             URLQueryItem(name: "order", value: "sort_order")]
        guard let url = comps?.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(ShareConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        struct Row: Decodable { let key: String; let name_ar: String; let icon_key: String? }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([Row].self, from: data), !rows.isEmpty else { return nil }
        return rows.map { row in
            // «وفاة/قلب مشطوب» وأمثاله لا تخصّ المكتبة؛ الرمز كما خزّنته الإدارة وإلا رمز المدمج
            let icon = row.icon_key.flatMap { UIImage(systemName: $0) != nil ? $0 : nil }
                ?? Category(rawValue: row.key)?.icon ?? "folder.fill"
            return LiveCategory(key: row.key, title: row.name_ar, icon: icon)
        }
    }

    /// آخر تصنيفات حمّلها التطبيق (CategoryStore ينشرها لحاوية App Group) — لا تحتاج شبكة ولا جلسة
    static func cachedCategories() -> [LiveCategory]? {
        guard let data = UserDefaults(suiteName: SharedSessionStore.appGroupId)?.data(forKey: "shared.archiveCategories"),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return nil }
        let items = list.compactMap { d -> LiveCategory? in
            guard let key = d["key"], let name = d["name_ar"] else { return nil }
            let icon = d["icon"].flatMap { UIImage(systemName: $0) != nil ? $0 : nil }
                ?? Category(rawValue: key)?.icon ?? "folder.fill"
            return LiveCategory(key: key, title: name, icon: icon)
        }
        return items.isEmpty ? nil : items
    }

    static var builtInCategories: [LiveCategory] {
        Category.allCases.map { LiveCategory(key: $0.rawValue, title: $0.title, icon: $0.icon) }
    }

    private static let bucket = "family-archive"
    private static let table = "family_archive"
    private static let avatarBucket = "avatars"

    static func upload(title: String,
                       description: String?,
                       category: LiveCategory,
                       fileName: String,
                       mimeType: String,
                       data: Data) async throws {
        guard let session = SharedSessionStore.current() else {
            throw UploadError.notSignedIn
        }

        let itemId = UUID().uuidString
        var ext = (fileName as NSString).pathExtension.lowercased()
        if ext.isEmpty { ext = defaultExtension(for: mimeType) }
        // المدمج في `category`، والمخصّص `other` + `category_key` (مثل ArchiveItem.storageFields في التطبيق)
        let storedCategory = category.builtIn?.rawValue ?? Category.other.rawValue
        let storagePath = "\(storedCategory)/\(itemId).\(ext)"

        // ١) رفع الملف إلى Storage
        var uploadRequest = URLRequest(
            url: ShareConfig.url.appendingPathComponent("storage/v1/object/\(bucket)/\(storagePath)")
        )
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue(ShareConfig.anonKey, forHTTPHeaderField: "apikey")
        uploadRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        uploadRequest.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        uploadRequest.httpBody = data

        let (uploadBody, uploadResponse) = try await URLSession.shared.data(for: uploadRequest)
        guard let http = uploadResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UploadError.storageFailed(shortMessage(uploadBody, uploadResponse))
        }

        // ٢) الرابط العام للملف
        let publicURL = ShareConfig.url
            .appendingPathComponent("storage/v1/object/public/\(bucket)/\(storagePath)")
            .absoluteString

        // ٣) إدراج صف المكتبة — الإدارة يُعتمد رفعها فوراً، وغيرها ينتظر الموافقة
        let now = ISO8601DateFormatter().string(from: Date())
        var row: [String: Any] = [
            "id": itemId,
            "title": title,
            "category": storedCategory,
            "file_url": publicURL,
            "file_type": mimeType,
            "file_size": data.count,
            "file_name": fileName,
            "uploaded_by": session.memberId,
            "approval_status": session.isAdmin ? "approved" : "pending",
        ]
        if let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            row["description"] = description
        }
        if category.builtIn == nil { row["category_key"] = category.key }
        if session.isAdmin {
            row["approved_by"] = session.memberId
            row["approved_at"] = now
        }

        var insertRequest = URLRequest(
            url: ShareConfig.url.appendingPathComponent("rest/v1/\(table)")
        )
        insertRequest.httpMethod = "POST"
        insertRequest.setValue(ShareConfig.anonKey, forHTTPHeaderField: "apikey")
        insertRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        insertRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        insertRequest.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        insertRequest.httpBody = try JSONSerialization.data(withJSONObject: row)

        let (insertBody, insertResponse) = try await URLSession.shared.data(for: insertRequest)
        guard let http = insertResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UploadError.insertFailed(shortMessage(insertBody, insertResponse))
        }
    }

    // MARK: - الصورة الشخصية

    /// يرفع صورة كصورة شخصية للعضو ويحدّث `profiles.avatar_url`.
    /// الصورة تُقصّ مربّعة من المنتصف قبل الرفع (الامتداد بلا قاصّ يدوي).
    static func uploadAvatar(fileName: String, data: Data) async throws {
        guard let session = SharedSessionStore.current() else {
            throw UploadError.notSignedIn
        }

        let squared = squareCropped(data) ?? data
        // نفس نمط التطبيق: اسم ثابت للعضو مع upsert، ثم cache-busting بالرابط
        let path = "\(session.memberId).jpg"

        var upload = URLRequest(
            url: ShareConfig.url.appendingPathComponent("storage/v1/object/\(avatarBucket)/\(path)")
        )
        upload.httpMethod = "POST"
        upload.setValue(ShareConfig.anonKey, forHTTPHeaderField: "apikey")
        upload.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        upload.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        upload.setValue("true", forHTTPHeaderField: "x-upsert")
        upload.httpBody = squared

        let (body, response) = try await URLSession.shared.data(for: upload)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UploadError.storageFailed(shortMessage(body, response))
        }

        let stamp = Int(Date().timeIntervalSince1970)
        let publicURL = ShareConfig.url
            .appendingPathComponent("storage/v1/object/public/\(avatarBucket)/\(path)")
            .absoluteString + "?v=\(stamp)"

        var update = URLRequest(
            url: ShareConfig.url.appendingPathComponent("rest/v1/profiles?id=eq.\(session.memberId)")
        )
        update.httpMethod = "PATCH"
        update.setValue(ShareConfig.anonKey, forHTTPHeaderField: "apikey")
        update.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        update.setValue("application/json", forHTTPHeaderField: "Content-Type")
        update.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        update.httpBody = try JSONSerialization.data(withJSONObject: ["avatar_url": publicURL])

        let (updateBody, updateResponse) = try await URLSession.shared.data(for: update)
        guard let http = updateResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UploadError.insertFailed(shortMessage(updateBody, updateResponse))
        }
    }

    /// قصّ مربّع من منتصف الصورة + تصغير لحدّ معقول، ثم ترميز JPEG.
    private static func squareCropped(_ data: Data, maxSide: CGFloat = 1024) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let w = image.size.width, h = image.size.height
        let side = min(w, h)
        let origin = CGPoint(x: (w - side) / 2, y: (h - side) / 2)

        // نطبّق اتجاه الصورة أولاً حتى لا يقصّ من الجهة الخطأ
        let upright: UIImage
        if image.imageOrientation == .up {
            upright = image
        } else {
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            upright = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        }

        guard let cgImage = upright.cgImage?.cropping(to: CGRect(
            x: origin.x * upright.scale,
            y: origin.y * upright.scale,
            width: side * upright.scale,
            height: side * upright.scale
        )) else { return nil }

        var square = UIImage(cgImage: cgImage, scale: upright.scale, orientation: .up)
        if side > maxSide {
            let target = CGSize(width: maxSide, height: maxSide)
            square = UIGraphicsImageRenderer(size: target).image { _ in
                square.draw(in: CGRect(origin: .zero, size: target))
            }
        }
        return square.jpegData(compressionQuality: 0.85)
    }

    // MARK: - مساعدات

    private static func defaultExtension(for mimeType: String) -> String {
        switch mimeType {
        case "application/pdf": return "pdf"
        case "image/png":       return "png"
        case "image/heic":      return "heic"
        default:                return "jpg"
        }
    }

    /// رسالة مختصرة من رد الخادم — لا نعرض JSON كاملاً للمستخدم.
    private static func shortMessage(_ data: Data, _ response: URLResponse) -> String {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = (obj["message"] ?? obj["error"] ?? obj["msg"]) as? String {
            return message
        }
        return "رمز الخطأ \(code)"
    }
}

/// إعدادات الاتصال — تُقرأ من Info.plist الامتداد كما في التطبيق.
enum ShareConfig {
    /// نفس قيم SupabaseConfig.Defaults في التطبيق — المفتاح عام (publishable)
    /// وسياسات RLS هي ما يحمي البيانات، لا سرّية المفتاح.
    static let url = URL(string: "https://poxyxsgvzwmnmewytsiw.supabase.co")!
    static let anonKey = "sb_publishable_o4VLYXBvBhvmvAv0n_z68g_JAMIb6v1"
}
