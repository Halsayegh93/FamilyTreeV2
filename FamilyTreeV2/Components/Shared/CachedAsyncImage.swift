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
        guard let url, image == nil else { return }

        let request = URLRequest(url: url)

        // Check cache first (synchronous)
        if let cachedResponse = ImageCache.shared.cache.cachedResponse(for: request),
           let uiImage = UIImage(data: cachedResponse.data) {
            self.image = uiImage
            return
        }

        // Download with structured concurrency — cancels automatically when view disappears
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return }
            guard let uiImage = UIImage(data: data) else { return }

            // Store in cache
            let cachedResponse = CachedURLResponse(response: response, data: data)
            ImageCache.shared.cache.storeCachedResponse(cachedResponse, for: request)

            self.image = uiImage
        } catch {
            // Task cancelled or network error — no action needed
        }
    }
}

/// Shared image cache — 100 MB memory, 300 MB disk
final class ImageCache {
    static let shared = ImageCache()
    let cache: URLCache

    private init() {
        cache = URLCache(
            memoryCapacity: 100 * 1024 * 1024,   // 100 MB
            diskCapacity: 300 * 1024 * 1024,      // 300 MB
            diskPath: "family_tree_images"
        )
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
        let request = URLRequest(url: url)

        if let cached = ImageCache.shared.cache.cachedResponse(for: request),
           let uiImage = UIImage(data: cached.data) {
            phase = .success(Image(uiImage: uiImage))
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return }
            guard let uiImage = UIImage(data: data) else {
                phase = .failure(URLError(.cannotDecodeContentData))
                return
            }
            let cached = CachedURLResponse(response: response, data: data)
            ImageCache.shared.cache.storeCachedResponse(cached, for: request)
            phase = .success(Image(uiImage: uiImage))
        } catch {
            if !Task.isCancelled { phase = .failure(error) }
        }
    }
}
