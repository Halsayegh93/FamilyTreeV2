import UIKit
import ImageIO

// MARK: - ImageProcessor
// معالج الصور المركزي — تصغير + ضغط + إزالة البيانات الوصفية

enum ImageProcessor {

    // MARK: - Use Cases

    enum UseCase {
        case avatar       // صورة شخصية
        case cover        // صورة غلاف
        case news         // صورة خبر
        case story        // ستوري
        case gallery      // معرض صور
        case projectLogo  // شعار مشروع
        case thumbnail    // صورة مصغرة
        case contact      // صورة تواصل

        var maxWidth: CGFloat {
            switch self {
            case .avatar, .projectLogo: return 800
            case .cover:                return 1200
            case .news, .gallery:       return 1600
            case .story:                return 1080
            case .thumbnail:            return 200
            case .contact:              return 1200
            }
        }

        var maxHeight: CGFloat {
            switch self {
            case .avatar, .projectLogo: return 800
            case .cover:                return 800
            case .news, .gallery:       return 1200
            case .story:                return 1920
            case .thumbnail:            return 200
            case .contact:              return 1200
            }
        }

        var compressionQuality: CGFloat {
            switch self {
            case .avatar:       return 0.6
            case .cover:        return 0.7
            case .news:         return 0.7
            case .story:        return 0.7
            case .gallery:      return 0.65
            case .projectLogo:  return 0.7
            case .thumbnail:    return 0.5
            case .contact:      return 0.7
            }
        }
    }

    // MARK: - Public API

    /// معالجة الصورة: تصغير + إزالة الشفافية + ضغط
    static func process(_ image: UIImage, for useCase: UseCase) -> Data? {
        let resized = resize(image, maxWidth: useCase.maxWidth, maxHeight: useCase.maxHeight)
        let opaque = removeAlpha(resized)

        guard let data = opaque.jpegData(compressionQuality: useCase.compressionQuality) else {
            return nil
        }

        let originalSize = image.jpegData(compressionQuality: 1.0)?.count ?? 0
        let newSize = data.count
        let reduction = originalSize > 0 ? Int((1.0 - Double(newSize) / Double(originalSize)) * 100) : 0
        Log.info("[ImageProcessor] \(useCase): \(formatBytes(originalSize)) → \(formatBytes(newSize)) (-\(reduction)%)")

        return data
    }

    /// تصغير الصورة مع الحفاظ على النسبة
    static func resize(_ image: UIImage, maxWidth: CGFloat, maxHeight: CGFloat) -> UIImage {
        let size = image.size

        // لا حاجة للتصغير إذا الصورة أصغر من الحد الأقصى
        guard size.width > maxWidth || size.height > maxHeight else { return image }

        let widthRatio = maxWidth / size.width
        let heightRatio = maxHeight / size.height
        let ratio = min(widthRatio, heightRatio)

        let newSize = CGSize(
            width: floor(size.width * ratio),
            height: floor(size.height * ratio)
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // بكسل حقيقي بدون مضاعفة scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// إنشاء صورة مصغرة
    static func thumbnail(_ image: UIImage) -> Data? {
        process(image, for: .thumbnail)
    }

    // MARK: - Private Helpers

    /// إزالة قناة الشفافية (alpha) لتقليل الحجم
    private static func removeAlpha(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// تنسيق حجم البايتات للعرض
    private static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }
}
