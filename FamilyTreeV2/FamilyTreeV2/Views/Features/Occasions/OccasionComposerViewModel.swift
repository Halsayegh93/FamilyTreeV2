import SwiftUI
import UIKit
import Photos
import PhotosUI
import ImageIO

/// حالة شاشة «بوستات المناسبات»: القالب، مكان النشر، النصوص، الصورة، والتصدير.
@MainActor
final class OccasionComposerViewModel: ObservableObject {
    @Published private(set) var template: OccasionTemplate
    @Published var placement: OccasionPlacement
    @Published private(set) var gender: OccasionGender = .male
    @Published var values: [String: String]
    @Published var photo = OccasionPhoto()
    @Published private(set) var isWorking = false
    @Published var message: String?
    @Published var shareItem: OccasionShareItem?

    let kit = OccasionKit.shared
    let templates = OccasionTemplate.all
    let placements = OccasionPlacement.all

    init() {
        let first = OccasionTemplate.all[0]
        template = first
        placement = OccasionPlacement.all[0]
        values = first.defaults(.male)
    }

    var size: OccasionSize { placement.size }

    /// مفتاح الملفات المطلوبة — يتغيّر مع القالب أو المقاس
    var assetKey: String { "\(template.id)-\(size.rawValue)" }

    // MARK: اختيارات

    func select(_ next: OccasionTemplate) {
        guard next.id != template.id else { return }
        let oldDefaults = template.defaults(gender)
        var fresh = next.defaults(gender)
        // نحتفظ بالاسم إذا انكتب
        if let name = values["name"], name != oldDefaults["name"], !name.isEmpty {
            fresh["name"] = name
        }
        template = next
        values = fresh
        photo.gray = next.kind == .death
    }

    func setGender(_ next: OccasionGender) {
        guard next != gender else { return }
        let oldDefaults = template.defaults(gender)
        let newDefaults = template.defaults(next)
        // الحقول اللي ما تعدّلت تتحوّل للصيغة الجديدة، واللي انكتب يبقى مثل ما هو
        for (key, newValue) in newDefaults where values[key] == nil || values[key] == oldDefaults[key] {
            values[key] = newValue
        }
        gender = next
    }

    func resetTexts() {
        values = template.defaults(gender)
    }

    func binding(for key: String) -> Binding<String> {
        Binding(get: { [weak self] in self?.values[key] ?? "" },
                set: { [weak self] in self?.values[key] = $0 })
    }

    func prepareAssets() async {
        await kit.prepare(template.assetPaths(for: size))
    }

    // MARK: الصورة

    func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = Self.downscaled(data, maxPixel: 1600) else {
                message = L10n.t("ما قدرنا نفتح الصورة — جرّب صورة ثانية.", "Couldn't open the photo — try another one.")
                return
            }
            photo.image = image
            photo.zoom = 1
            photo.x = 50
            photo.y = 40
        } catch {
            Log.error("Occasion photo load failed: \(error.localizedDescription)")
            message = L10n.t("ما قدرنا نفتح الصورة — جرّب صورة ثانية.", "Couldn't open the photo — try another one.")
        }
    }

    func removePhoto() {
        photo.image = nil
        photo.zoom = 1
        photo.x = 50
        photo.y = 40
    }

    /// يصغّر صورة الجوال ويثبّت اتجاهها بدون فك الصورة الأصلية كاملة في الذاكرة
    /// (الصورة تبقى على الجهاز — ما تنرفع لأي مكان)
    private static func downscaled(_ data: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: التصدير

    /// يرسم البوست بمقاسه الحقيقي (1080 × الارتفاع) بكسل
    func render() async -> UIImage? {
        guard await kit.prepare(template.assetPaths(for: size)), kit.fontsReady else { return nil }
        let view = OccasionPostView(template: template, size: size, values: values, photo: photo, kit: kit, revision: kit.revision)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size.canvas)
        renderer.scale = 1
        return renderer.uiImage
    }

    func saveToPhotos() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        guard let image = await render(), let data = image.pngData() else {
            message = renderFailedMessage
            return
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            message = L10n.t("اسمح للتطبيق بإضافة الصور من الإعدادات ← الخصوصية ← الصور.",
                             "Allow the app to add photos in Settings → Privacy → Photos.")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
            message = L10n.t("انحفظ البوست في الصور ✓", "Saved to Photos ✓")
        } catch {
            Log.error("Occasion save to Photos failed: \(error.localizedDescription)")
            message = L10n.t("ما انحفظت الصورة — حاول مرة ثانية.", "Couldn't save the image — please try again.")
        }
    }

    func share() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        guard let image = await render(), let data = image.pngData() else {
            message = renderFailedMessage
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("almohali-\(template.id)-\(size.rawValue).png")
        do {
            try data.write(to: url, options: .atomic)
            shareItem = OccasionShareItem(url: url)
        } catch {
            Log.error("Occasion share file write failed: \(error.localizedDescription)")
            message = renderFailedMessage
        }
    }

    private var renderFailedMessage: String {
        kit.failed
            ? L10n.t("تعذّر تحميل ملفات التصميم — تأكد من الاتصال وحاول مرة ثانية.", "Couldn't download the design files — check your connection and try again.")
            : L10n.t("صار خطأ أثناء تجهيز الصورة — حاول مرة ثانية.", "Something went wrong while preparing the image — please try again.")
    }
}

struct OccasionShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
