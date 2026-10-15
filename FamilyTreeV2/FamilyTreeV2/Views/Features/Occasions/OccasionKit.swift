import SwiftUI
import UIKit
import CoreText
import ImageIO

/// ملفات تصميم بوستات المناسبات (الخط المرخّص URW Geometric Arabic، مخطوطات الآيات،
/// الخلفيات، الإطارات، الشعار). هذا المستودع عام، فالملفات المرخّصة **ما تنحفظ فيه** —
/// تنزل وقت التشغيل من الموقع (public/occasion-kit في familytree-web) وتنخزن في Caches.
@MainActor
final class OccasionKit: ObservableObject {
    static let shared = OccasionKit()

    /// ارفع الرقم إذا تغيّرت ملفات occasion-kit في الموقع بنفس الأسماء (يتجاهل النسخة المخزّنة)
    static let version = "1"

    /// يمكن تغييره من Info.plist بالمفتاح OCCASION_KIT_BASE_URL
    nonisolated static var baseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "OCCASION_KIT_BASE_URL") as? String,
           !raw.isEmpty, let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://app.almohali.com/occasion-kit/")!
    }

    enum FontWeight: CaseIterable {
        case regular, semibold, extrabold

        var file: String {
            switch self {
            case .regular: return "fonts/urw-geometric-arabic-regular.ttf"
            case .semibold: return "fonts/urw-geometric-arabic-semibold.ttf"
            case .extrabold: return "fonts/urw-geometric-arabic-extrabold.ttf"
            }
        }

        var postScriptName: String {
            switch self {
            case .regular: return "URWGeometricArabic-Regular"
            case .semibold: return "URWGeometricArabic-SemiBold"
            case .extrabold: return "URWGeometricArabic-ExtraBold"
            }
        }

        /// ارتفاع السطر الطبيعي للخط (ascent + descent + lineGap) بوحدة em — لمطابقة line-height في التصميم
        var lineHeightEm: CGFloat {
            switch self {
            case .regular: return 1.524
            case .semibold: return 1.572
            case .extrabold: return 1.644
            }
        }
    }

    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    /// يتغيّر كلما توفّرت ملفات جديدة — تمرّره الشاشة للرسم حتى يتحدّث
    @Published private(set) var revision = 0

    private var images: [String: UIImage] = [:]
    private var recent: [String] = []
    private var registeredFonts: Set<String> = []
    private var inFlight = 0
    private let cacheDir: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = caches.appendingPathComponent("OccasionKit/v\(Self.version)", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    var fontsReady: Bool { registeredFonts.count == FontWeight.allCases.count }

    func image(_ path: String) -> UIImage? { images[path] }

    /// يجهّز الخط + ملفات القالب المطلوبة. يرجع false إذا فشل تحميل أي ملف.
    @discardableResult
    func prepare(_ paths: [String]) async -> Bool {
        let fontPaths = FontWeight.allCases.map(\.file).filter { !registeredFonts.contains($0) }
        let imagePaths = paths.filter { images[$0] == nil }
        touch(paths)
        let missing = fontPaths + imagePaths
        guard !missing.isEmpty else {
            failed = false
            return true
        }

        // أكثر من تحميل ممكن يشتغل (تغيير القالب يلغي القديم) — المؤشر يبقى لين يخلص آخرها
        inFlight += 1
        isLoading = true
        failed = false
        defer {
            inFlight -= 1
            isLoading = inFlight > 0
        }

        let base = Self.baseURL
        let dir = cacheDir
        var ok = true
        // التنزيل وفك الصور في مهام خلفية — الخيط الرئيسي يستلم النتيجة جاهزة
        await withTaskGroup(of: (String, URL?, UIImage?).self) { group in
            for path in missing {
                group.addTask {
                    guard let url = try? await Self.download(path, base: base, dir: dir) else { return (path, nil, nil) }
                    if path.hasPrefix("fonts/") { return (path, url, nil) }
                    // الخلفيات (ونموذج ١: خلفية وحدة تغطي أي مقاس) بدقة الستوري، والباقي يكفيه 1100
                    let isBackground = path.hasPrefix("bg/") || path.hasPrefix("m1/bg/")
                    let img = Self.decode(url, maxPixel: isBackground ? 1920 : 1100)
                    if img == nil { try? FileManager.default.removeItem(at: url) }   // ملف تالف — ينزل من جديد المرة الجاية
                    return (path, url, img)
                }
            }
            for await (path, fileURL, img) in group {
                guard let fileURL else {
                    ok = false
                    Log.warning("OccasionKit: failed to load \(path)")
                    continue
                }
                if path.hasPrefix("fonts/") {
                    if Self.registerFont(at: fileURL) {
                        registeredFonts.insert(path)
                    } else {
                        ok = false
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                } else if let img {
                    images[path] = img
                } else {
                    ok = false
                }
            }
        }
        prune()
        // الإلغاء (تغيير القالب أو إغلاق الشاشة) ما يعتبر فشل
        failed = !ok && !Task.isCancelled
        revision += 1
        return ok
    }

    // MARK: - داخلي

    /// نحتفظ بآخر الملفات المستخدمة فقط (الخلفيات كبيرة في الذاكرة)
    private func touch(_ paths: [String]) {
        recent.removeAll { paths.contains($0) }
        recent.append(contentsOf: paths)
    }

    private func prune() {
        let keep = Set(recent.suffix(14))
        images = images.filter { keep.contains($0.key) }
        recent = Array(recent.suffix(14))
    }

    /// ينزّل الملف مرة وحدة ويخزّنه؛ بعدها يقرأ من Caches
    nonisolated private static func download(_ path: String, base: URL, dir: URL) async throws -> URL {
        let local = dir.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: local.path) { return local }
        let remote = base.appendingPathComponent(path)
        let (data, response) = try await URLSession.shared.data(from: remote)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
            throw URLError(.badServerResponse)
        }
        try FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: local, options: .atomic)
        return local
    }

    nonisolated private static func registerFont(at url: URL) -> Bool {
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
        if let err = error?.takeRetainedValue(),
           CFErrorGetCode(err) == CTFontManagerError.alreadyRegistered.rawValue {
            return true
        }
        return false
    }

    /// فك الصورة بحجم مناسب (الملفات بدقة 2x للويب — هنا يكفي 1x لأن الرسم 1080 بكسل)
    nonisolated private static func decode(_ url: URL, maxPixel: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}
