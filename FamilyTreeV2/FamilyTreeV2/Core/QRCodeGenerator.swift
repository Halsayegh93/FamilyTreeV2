import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - QRCodeGenerator
// مولّد الباركود — ينشئ QR Code من نص باستخدام CoreImage

enum QRCodeGenerator {

    /// توليد صورة QR Code من نص — الخلفية شفافة
    static func generate(from string: String, size: CGFloat = 300) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        // تكبير الصورة
        let scale = size / ciImage.extent.width
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        // تحويل الأبيض لشفاف
        guard let transparent = makeWhiteTransparent(cgImage) else {
            return UIImage(cgImage: cgImage)
        }
        return UIImage(cgImage: transparent)
    }

    /// توليد deep link للعضو
    static func memberDeepLink(memberId: UUID) -> String {
        "familytree://member/\(memberId.uuidString)"
    }

    // MARK: - Private

    /// تحويل البكسلات البيضاء إلى شفافة
    private static func makeWhiteTransparent(_ image: CGImage) -> CGImage? {
        let maskingColors: [CGFloat] = [200, 255, 200, 255, 200, 255]
        return image.copy(maskingColorComponents: maskingColors)
    }
}
