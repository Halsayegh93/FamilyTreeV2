import SwiftUI
import UIKit

// MARK: - عارض صور قابل للتكبير والتقليب (طلب المالك ٢٠٢٦-١٠-٢٣)
//
// «في الصورة نبي نروح يمين او يسار عند التكبير في المكتبة عند العرض».
// مبني على UIScrollView (لا إيماءات SwiftUI) لأن تكبير UIKit يعطي مجاناً وبدقّة:
// القرصة حول مركزها، والتحريك محصور بحواف الصورة، وتوسيط الصورة الأصغر من الإطار.
// • مكبّرة: السحب يحرّك الصورة فقط (التقليب مقفل) — بلا انزلاق بعد رفع الإصبع
// • غير مكبّرة: السحب أفقياً يقلّب بين الصور (السحب يميناً = التالية في العربية)
// • ضغطتان: تكبير عند نقطة الضغط، وضغطتان مرة ثانية للرجوع؛ القرصة ١×–٤×
// • إصبعان لا يقلّبان الصفحة — القرصة للتكبير وحده

struct ZoomablePhotoPager: UIViewRepresentable {
    let urls: [String]
    let startIndex: Int
    /// السحب يميناً يأتي بالتالية (العربية)
    let isRTL: Bool
    var maxScale: CGFloat = 4
    var doubleTapScale: CGFloat = 2.5
    var onIndexChange: (Int) -> Void
    /// الصفحات التي وصلت صورتها — ليظهر مؤشّر التحميل فوق غيرها
    var onLoadedChange: (Set<Int>) -> Void

    func makeUIView(context: Context) -> PhotoPagerView {
        let view = PhotoPagerView(urls: urls, startIndex: startIndex, isRTL: isRTL,
                                  maxScale: maxScale, doubleTapScale: doubleTapScale)
        view.onIndexChange = onIndexChange
        view.onLoadedChange = onLoadedChange
        return view
    }

    func updateUIView(_ view: PhotoPagerView, context: Context) {
        view.onIndexChange = onIndexChange
        view.onLoadedChange = onLoadedChange
    }
}

/// المقلِّب: UIScrollView أفقي بالصفحات، وفي كل صفحة `PhotoZoomView`
final class PhotoPagerView: UIView, UIScrollViewDelegate {
    var onIndexChange: ((Int) -> Void)?
    var onLoadedChange: ((Set<Int>) -> Void)?

    private let urls: [String]
    private let isRTL: Bool
    private let pager = UIScrollView()
    private var pages: [PhotoZoomView] = []
    private var current: Int
    private var lastSize: CGSize = .zero
    /// أثناء إعادة التخطيط (تدوير) لا يُحسب تغيّر الصفحة من الإزاحة
    private var relayingOut = false
    private var loaded: Set<Int> = [] {
        didSet { if loaded != oldValue { onLoadedChange?(loaded) } }
    }

    init(urls: [String], startIndex: Int, isRTL: Bool, maxScale: CGFloat, doubleTapScale: CGFloat) {
        self.urls = urls
        self.isRTL = isRTL
        self.current = min(max(0, startIndex), max(0, urls.count - 1))
        super.init(frame: .zero)

        pager.isPagingEnabled = true
        pager.showsHorizontalScrollIndicator = false
        pager.showsVerticalScrollIndicator = false
        pager.contentInsetAdjustmentBehavior = .never
        pager.alwaysBounceVertical = false
        pager.delegate = self
        // إصبعان = قرصة للتكبير، لا تقليب
        pager.panGestureRecognizer.maximumNumberOfTouches = 1
        pager.isScrollEnabled = urls.count > 1
        addSubview(pager)

        for idx in urls.indices {
            let page = PhotoZoomView(maxScale: maxScale, doubleTapScale: doubleTapScale)
            page.onZoomChange = { [weak self] zoomed in self?.zoomChanged(zoomed) }
            page.onLoaded = { [weak self] in self?.loaded.insert(idx) }
            pager.addSubview(page)
            pages.append(page)
        }
        loadAround(current)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// موضع الصفحة على المحور الفيزيائي — في العربية الأولى على اليمين
    private func slot(for index: Int) -> Int { isRTL ? urls.count - 1 - index : index }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize, bounds.width > 0 else { return }
        lastSize = bounds.size
        relayingOut = true
        pager.frame = bounds
        for (idx, page) in pages.enumerated() {
            page.frame = CGRect(x: CGFloat(slot(for: idx)) * bounds.width, y: 0,
                                width: bounds.width, height: bounds.height)
        }
        pager.contentSize = CGSize(width: bounds.width * CGFloat(urls.count), height: bounds.height)
        pager.contentOffset = CGPoint(x: CGFloat(slot(for: current)) * bounds.width, y: 0)
        relayingOut = false
    }

    // MARK: التقليب

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !relayingOut, bounds.width > 0, !urls.isEmpty else { return }
        let rawSlot = Int((scrollView.contentOffset.x / bounds.width).rounded())
        let idx = min(max(0, isRTL ? urls.count - 1 - rawSlot : rawSlot), urls.count - 1)
        guard idx != current else { return }
        current = idx
        onIndexChange?(idx)
        loadAround(idx)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // الصفحات التي خرجت من الشاشة ترجع لحجمها
        for (idx, page) in pages.enumerated() where idx != current { page.resetZoom() }
    }

    private func zoomChanged(_ zoomed: Bool) {
        // مكبّرة → السحب يحرّك الصورة فقط؛ غير مكبّرة → السحب يقلّب
        pager.isScrollEnabled = !zoomed && urls.count > 1
    }

    /// يحمّل الحالية وجارتيها، ويفرّغ البعيدة (المكتبة قد تحوي صوراً كثيرة)
    private func loadAround(_ idx: Int) {
        for (i, page) in pages.enumerated() {
            if abs(i - idx) <= 1 {
                page.load(URL(string: urls[i]))
            } else if abs(i - idx) > 2 {
                page.unload()
                loaded.remove(i)
            }
        }
    }
}

/// صفحة واحدة: UIScrollView للتكبير حول UIImageView
final class PhotoZoomView: UIScrollView, UIScrollViewDelegate {
    var onZoomChange: ((Bool) -> Void)?
    var onLoaded: (() -> Void)?

    private let imageView = UIImageView()
    private let doubleTapScale: CGFloat
    private var loadTask: Task<Void, Never>?
    private var loadedURL: URL?
    private var lastSize: CGSize = .zero
    private var wasZoomed = false

    init(maxScale: CGFloat, doubleTapScale: CGFloat) {
        self.doubleTapScale = doubleTapScale
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = maxScale
        bounces = false          // لا فراغ خلف حواف الصورة
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        // غير مكبّرة: السحب للمقلِّب لا لهذه الصفحة
        panGestureRecognizer.isEnabled = false

        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { loadTask?.cancel() }

    // MARK: التحميل

    func load(_ url: URL?) {
        guard let url, url != loadedURL else { return }
        loadedURL = url
        loadTask?.cancel()
        if let hit = CachedImageLoader.memoryHit(for: url) {
            setImage(hit)
            return
        }
        loadTask = Task { @MainActor [weak self] in
            guard let image = try? await CachedImageLoader.load(url), !Task.isCancelled else { return }
            self?.setImage(image)
        }
    }

    func unload() {
        loadTask?.cancel()
        loadTask = nil
        loadedURL = nil
        resetZoom()
        imageView.image = nil
    }

    private func setImage(_ image: UIImage) {
        imageView.image = image
        lastSize = .zero
        setNeedsLayout()
        onLoaded?()
    }

    // MARK: التخطيط

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize, bounds.width > 0 else { return }
        lastSize = bounds.size
        // حجم جديد (تدوير/صورة) — من حجم ١× بمقاس «ملائم»
        zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: fittedSize())
        contentSize = imageView.frame.size
        centerContent()
        notifyZoom()
    }

    private func fittedSize() -> CGSize {
        guard let size = imageView.image?.size, size.width > 0, size.height > 0 else { return bounds.size }
        let ratio = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * ratio, height: size.height * ratio)
    }

    /// الصورة الأصغر من الإطار في الوسط، والأكبر تتحرّك حتى حوافها فقط
    private func centerContent() {
        let insetX = max(0, (bounds.width - contentSize.width) / 2)
        let insetY = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    // MARK: التكبير

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        notifyZoom()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        notifyZoom()
    }

    /// بلا انزلاق بعد رفع الإصبع — الصورة تقف حيث تركها
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        targetContentOffset.pointee = scrollView.contentOffset
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard imageView.image != nil else { return }
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / doubleTapScale, height: bounds.height / doubleTapScale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
        }
    }

    func resetZoom() {
        guard zoomScale != minimumZoomScale else { return }
        setZoomScale(minimumZoomScale, animated: false)
    }

    private func notifyZoom() {
        let zoomed = zoomScale > minimumZoomScale + 0.01
        panGestureRecognizer.isEnabled = zoomed
        guard zoomed != wasZoomed else { return }
        wasZoomed = zoomed
        onZoomChange?(zoomed)
    }
}
