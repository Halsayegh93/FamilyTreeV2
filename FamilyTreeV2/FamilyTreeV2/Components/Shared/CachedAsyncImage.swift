import SwiftUI

/// A drop-in replacement for AsyncImage with URLCache-based caching.
/// Prevents re-downloading the same image on every view appear.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url else { return }
        // فحص «اللاق» ٢٠٢٦-١٠-٠٧: ذاكرة للصور المفكوكة، والقراءة والفكّ خارج الخيط الرئيسي.
        // الصور الخاصة ٢٠٢٦-١٠-١٩: التحميل عبر `CachedImageLoader` (رابط موقَّع، والكاش بهوية الملف).
        if let hit = CachedImageLoader.memoryHit(for: url) {
            self.image = hit
            return
        }
        // Task cancelled or network error — no action needed
        if let loaded = try? await CachedImageLoader.load(url) {
            self.image = loaded
        }
    }
}

/// تحميل مشترك لـ `CachedAsyncImage` و`CachedAsyncPhaseImage`.
/// مفتاح الكاش (الذاكرة + القرص) = هوية الملف `bucket/path?v=` عبر `StorageURLResolver.cacheKeyURL` —
/// لا الرابط الموقَّع — فلا تُعاد التنزيلات كل ساعة. التوقيع لا يُطلب إلا إن لم تكن الصورة في الكاش.
enum CachedImageLoader {
    /// من ذاكرة الصور المفكوكة (سريع — يصلح للخيط الرئيسي)
    static func memoryHit(for url: URL) -> UIImage? {
        ImageCache.shared.decodedImage(for: StorageURLResolver.shared.cacheKeyURL(for: url))
    }

    /// nil = أُلغيت المهمّة؛ يرمي عند فشل التنزيل/الفكّ
    static func load(_ url: URL) async throws -> UIImage? {
        let resolver = StorageURLResolver.shared
        let key = resolver.cacheKeyURL(for: url)
        if let hit = ImageCache.shared.decodedImage(for: key) { return hit }
        let keyRequest = URLRequest(url: key)

        // Check cache first (disk/memory read + decode off the main thread)
        if let cached = await Task.detached(priority: .userInitiated, operation: {
            ImageCache.shared.cachedImage(for: keyRequest)
        }).value {
            return cached
        }

        // الموقَّع أولاً؛ إن فشل تنزيله فالرابط الأصلي (نفس سلوك اليوم)
        let fetchURL = await resolver.displayURL(for: url)
        guard !Task.isCancelled else { return nil }
        var candidates = [fetchURL]
        if fetchURL != url { candidates.append(url) }
        var lastError: Error = URLError(.cannotDecodeContentData)
        for candidate in candidates {
            do {
                // Download with structured concurrency — cancels automatically when view disappears
                let (data, response) = try await URLSession.shared.data(for: URLRequest(url: candidate))
                guard !Task.isCancelled else { return nil }
                if let uiImage = await Task.detached(priority: .userInitiated, operation: {
                    ImageCache.shared.store(data, response: response, for: keyRequest)
                }).value {
                    return uiImage
                }
                lastError = URLError(.cannotDecodeContentData)
            } catch {
                if Task.isCancelled { return nil }
                lastError = error
            }
            if candidate != url { resolver.invalidate(url) }
        }
        throw lastError
    }
}

/// Shared image cache — 50 MB memory, 200 MB disk
/// قللناها لتجنب ضغط الذاكرة على الأجهزة القديمة (iPhone 13 mini وأقدم)
/// + ذاكرة للصور المفكوكة الجاهزة للعرض (تُفرَّغ تلقائياً عند ضغط الذاكرة) — الفكّ خارج الخيط الرئيسي.
nonisolated final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    let cache: URLCache
    /// الصور المفكوكة (المفتاح = الرابط) — حدّها بالبايت
    private let decoded = NSCache<NSURL, UIImage>()
    static let decodedCostLimit = 64 * 1024 * 1024

    private init() {
        cache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,    // 50 MB (كان 100)
            diskCapacity: 200 * 1024 * 1024,     // 200 MB (كان 300)
            diskPath: "family_tree_images"
        )
        decoded.totalCostLimit = Self.decodedCostLimit
    }

    /// صورة مفكوكة من الذاكرة (سريع — يصلح للخيط الرئيسي)
    func decodedImage(for url: URL) -> UIImage? {
        decoded.object(forKey: url as NSURL)
    }

    /// من ذاكرة الروابط (قد يقرأ القرص) ثم الفكّ — خارج الخيط الرئيسي
    func cachedImage(for request: URLRequest) -> UIImage? {
        guard let response = cache.cachedResponse(for: request) else { return nil }
        return decode(response.data, url: request.url)
    }

    /// بعد التنزيل: الفكّ، ثم الحفظ في الذاكرتين إن كانت صورة — خارج الخيط الرئيسي
    func store(_ data: Data, response: URLResponse, for request: URLRequest) -> UIImage? {
        guard let image = decode(data, url: request.url) else { return nil }
        cache.storeCachedResponse(CachedURLResponse(response: Self.response(response, keyedTo: request.url), data: data),
                                  for: request)
        return image
    }

    /// الرد المحفوظ يحمل رابط المفتاح (هوية الملف) لا الرابط الموقَّع الذي نُزِّل منه
    private static func response(_ response: URLResponse, keyedTo url: URL?) -> URLResponse {
        guard let url, response.url != url else { return response }
        if let http = response as? HTTPURLResponse,
           let rekeyed = HTTPURLResponse(url: url, statusCode: http.statusCode, httpVersion: nil,
                                         headerFields: http.allHeaderFields as? [String: String]) {
            return rekeyed
        }
        return URLResponse(url: url, mimeType: response.mimeType,
                           expectedContentLength: Int(response.expectedContentLength),
                           textEncodingName: response.textEncodingName)
    }

    private func decode(_ data: Data, url: URL?) -> UIImage? {
        guard let raw = UIImage(data: data) else { return nil }
        // نفس الصورة بنفس الدقّة، مفكوكة مسبقاً (لا فكّ عند أول رسم على الخيط الرئيسي)
        let ready = raw.preparingForDisplay() ?? raw
        if let url {
            let px = ready.size.width * ready.scale * ready.size.height * ready.scale
            decoded.setObject(ready, forKey: url as NSURL, cost: Int(px) * 4)
        }
        return ready
    }
}

// MARK: - Convenience init matching AsyncImage(url:) { image in ... } pattern

extension CachedAsyncImage where Placeholder == ProgressView<EmptyView, EmptyView> {
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.url = url
        self.content = content
        self.placeholder = { ProgressView() }
    }
}

// MARK: - Phase-based init matching AsyncImage(url:) { phase in ... } pattern

/// Phase enum mirroring SwiftUI's AsyncImagePhase for CachedAsyncImage compatibility.
enum CachedImagePhase {
    case empty
    case success(Image)
    case failure(Error)

    var image: Image? {
        if case .success(let img) = self { return img }
        return nil
    }
    var error: Error? {
        if case .failure(let err) = self { return err }
        return nil
    }
}

/// Phase-based CachedAsyncImage — drop-in replacement for `AsyncImage(url:) { phase in … }`.
struct CachedAsyncPhaseImage<Content: View>: View {
    let url: URL?
    let content: (CachedImagePhase) -> Content

    @State private var phase: CachedImagePhase = .empty

    init(
        url: URL?,
        @ViewBuilder content: @escaping (CachedImagePhase) -> Content
    ) {
        self.url = url
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: url) { await loadImage() }
    }

    private func loadImage() async {
        guard let url else { return }
        // نفس مسار `CachedAsyncImage` (`CachedImageLoader`)
        if let hit = CachedImageLoader.memoryHit(for: url) {
            phase = .success(Image(uiImage: hit))
            return
        }
        do {
            guard let uiImage = try await CachedImageLoader.load(url) else { return }
            phase = .success(Image(uiImage: uiImage))
        } catch {
            if !Task.isCancelled { phase = .failure(error) }
        }
    }
}
