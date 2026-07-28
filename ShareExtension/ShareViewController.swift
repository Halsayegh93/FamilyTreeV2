import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// نقطة دخول امتداد المشاركة: يستخرج الملف المشارَك ثم يعرض واجهة الرفع.
final class ShareViewController: UIViewController {

    private var hosting: UIHostingController<ShareRootView>?

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        // بدون هذا يرسم النظام خلفية معتمة خلف الامتداد فيظهر فراغ أسود
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        modalPresentationStyle = .overFullScreen
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        configureSheetHeight()
        Task { await loadSharedItem() }
    }

    /// النظام يفتح الامتداد بشيت بكامل الشاشة، فيبقى فراغ أبيض تحت المحتوى.
    /// نضبط ارتفاعه على قدر النموذج مع إمكانية سحبه لأعلى.
    private func configureSheetHeight() {
        guard let sheet = sheetPresentationController else { return }
        let fitted = UISheetPresentationController.Detent.custom(identifier: .init("fitted")) { ctx in
            ctx.maximumDetentValue * 0.66
        }
        sheet.detents = [fitted, .large()]
        sheet.prefersGrabberVisible = true
        sheet.preferredCornerRadius = 24
    }

    /// يقرأ أول مرفق صالح (PDF أو صورة) من عنصر المشاركة.
    private func loadSharedItem() async {
        guard let item = (extensionContext?.inputItems as? [NSExtensionItem])?.first,
              let providers = item.attachments, !providers.isEmpty else {
            present(state: .failed("لم نجد ملفاً في هذه المشاركة."))
            return
        }

        for provider in providers {
            if let payload = await extractFile(from: provider) {
                present(state: .ready(payload))
                return
            }
        }
        present(state: .failed("نوع الملف غير مدعوم — المكتبة تقبل PDF والصور."))
    }

    private func extractFile(from provider: NSItemProvider) async -> SharedFile? {
        // PDF أولاً — أكثر ما يُشارك من واتساب
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier),
           let url = await loadFileURL(provider, type: UTType.pdf.identifier),
           let data = try? Data(contentsOf: url) {
            return SharedFile(name: url.lastPathComponent,
                              mimeType: "application/pdf",
                              data: data)
        }

        // صورة — من المعرض أو من واتساب مباشرة
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
           let url = await loadFileURL(provider, type: UTType.image.identifier),
           let data = try? Data(contentsOf: url) {
            let ext = url.pathExtension.lowercased()
            let mime: String
            switch ext {
            case "png":          mime = "image/png"
            case "heic", "heif": mime = "image/heic"
            default:             mime = "image/jpeg"
            }
            return SharedFile(name: url.lastPathComponent, mimeType: mime, data: data)
        }

        return nil
    }

    private func loadFileURL(_ provider: NSItemProvider, type: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data {
                    // بعض المصادر تعطي البايتات مباشرة — نكتبها ملفاً مؤقتاً
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                    try? data.write(to: tmp)
                    continuation.resume(returning: tmp)
                } else if let image = item as? UIImage,
                          let data = image.jpegData(compressionQuality: 0.9) {
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(UUID().uuidString).jpg")
                    try? data.write(to: tmp)
                    continuation.resume(returning: tmp)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    @MainActor
    private func present(state: ShareRootView.State) {
        hosting?.willMove(toParent: nil)
        hosting?.view.removeFromSuperview()
        hosting?.removeFromParent()

        let root = ShareRootView(
            state: state,
            onClose: { [weak self] in self?.finish() }
        )
        let controller = UIHostingController(rootView: root)
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        hosting = controller
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

/// الملف المستخرج من المشاركة.
struct SharedFile {
    let name: String
    let mimeType: String
    let data: Data

    var isPDF: Bool { mimeType == "application/pdf" }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}
