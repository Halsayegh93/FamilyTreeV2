import SwiftUI
import PDFKit

/// تحميل ملف PDF من المكتبة: يُنزَّل مرة إلى ملف مؤقت ثم يُفتح منه (`PDFDocument(url:)` يقرأ الصفحة عند عرضها،
/// فالكتاب الكبير لا يُحمَّل كله في الذاكرة). الرابط الموقَّع للمستودع الخاص من `StorageURLResolver`.
enum ArchivePDFLoader {
    private static var folder: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("archive-pdf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// اسم ثابت للملف من مساره (بلا معاملات التوقيع المتغيّرة)
    private static func cacheFile(for url: URL) -> URL {
        let key = url.path.replacingOccurrences(of: "/", with: "_")
        return folder.appendingPathComponent(key.hasSuffix(".pdf") ? key : key + ".pdf")
    }

    static func document(for url: URL) async -> PDFDocument? {
        let file = cacheFile(for: url)
        if FileManager.default.fileExists(atPath: file.path), let doc = PDFDocument(url: file) { return doc }
        do {
            let fetchURL = await StorageURLResolver.shared.displayURL(for: url)
            let (temp, _) = try await URLSession.shared.download(from: fetchURL)
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: temp, to: file)
            return PDFDocument(url: file)
        } catch {
            if ErrorHelper.isCancellation(error) { return nil }
            Log.warning("[ARCHIVE] تعذّر تحميل الملف: \(error.localizedDescription)")
            return nil
        }
    }
}

/// قارئ PDF بملء الشاشة (طلب المالك ٢٠٢٦-١٠-٢٩): صفحة واحدة، السحب يميناً ويساراً يقلّب صفحات هذا الملف وحده،
/// وتحتها شريط مصغّرات الصفحات — الضغط على مصغّرة ينقل إليها. القرصة تكبّر الصفحة.
struct ArchivePDFReader: View {
    let url: URL
    let title: String
    /// تُحجب الصفحات عن لقطة الشاشة (`LibraryProtection`)
    var shielded: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var document: PDFDocument?
    @State private var failed = false
    @State private var page = 0

    var body: some View {
        ZStack(alignment: .top) {
            DS.Color.overlayDark.ignoresSafeArea()

            if let document {
                ArchivePDFPager(document: document, page: $page)
                    .environment(\.layoutDirection, .leftToRight)
                    .screenCaptureShielded(shielded)
                    .padding(.top, DS.Icon.tapTarget + DS.Spacing.md)
            } else if failed {
                DSEmptyView(L10n.t("تعذّر فتح الملف", "Couldn't open the file"),
                            section: .library, icon: "doc.questionmark", compact: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(DS.Color.overlayText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(L10n.t("جاري التحميل", "Loading"))
            }

            HStack(spacing: DS.Spacing.sm) {
                if let count = document?.pageCount, count > 1 {
                    Text(verbatim: L10n.t("\(page + 1) من \(count)", "\(page + 1) of \(count)"))
                        .dsFont(.rowTitleCompact)
                        .foregroundColor(DS.Color.overlayText)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(Capsule().fill(DS.Color.overlayDark))
                }
                Text(title)
                    .dsFont(.rowTitleCompact)
                    .foregroundColor(DS.Color.overlayText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                DSCloseButton(context: .onMedia) { dismiss() }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)
        }
        .task {
            guard document == nil else { return }
            document = await ArchivePDFLoader.document(for: url)
            failed = document == nil
        }
    }
}

/// الصفحة (`PDFView` بتقليب أفقي صفحة صفحة) فوق شريط المصغّرات (`PDFThumbnailView`)
private struct ArchivePDFPager: UIViewRepresentable {
    let document: PDFDocument
    @Binding var page: Int

    func makeUIView(context: Context) -> UIView {
        let container = PagerContainer()
        container.backgroundColor = .clear

        let pdf = PDFView()
        pdf.backgroundColor = .clear
        pdf.displayMode = .singlePage
        pdf.displayDirection = .horizontal
        // الكتب العربية تتقلّب من اليمين
        pdf.displaysRTL = L10n.isArabic
        pdf.usePageViewController(true, withViewOptions: nil)
        pdf.document = document
        container.pdf = pdf

        let thumbs = PDFThumbnailView()
        thumbs.pdfView = pdf
        thumbs.layoutMode = .horizontal
        thumbs.thumbnailSize = CGSize(width: 36, height: 50)
        thumbs.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        thumbs.isHidden = document.pageCount < 2

        [pdf, thumbs].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }
        NSLayoutConstraint.activate([
            pdf.topAnchor.constraint(equalTo: container.topAnchor),
            pdf.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pdf.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pdf.bottomAnchor.constraint(equalTo: thumbs.topAnchor, constant: -8),
            thumbs.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            thumbs.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            thumbs.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor),
            thumbs.heightAnchor.constraint(equalToConstant: document.pageCount < 2 ? 0 : 66)
        ])

        context.coordinator.observe(pdf)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    /// المقاس يُضبط بعد أن يأخذ العرض حجمه (قبلها «ملء الشاشة» = صفر فتختفي الصفحة)
    final class PagerContainer: UIView {
        weak var pdf: PDFView?
        private var lastSize: CGSize = .zero

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let pdf, pdf.bounds.size != .zero, pdf.bounds.size != lastSize else { return }
            lastSize = pdf.bounds.size
            pdf.autoScales = true
            pdf.minScaleFactor = pdf.scaleFactorForSizeToFit
            pdf.maxScaleFactor = max(pdf.scaleFactorForSizeToFit * 6, 1)
            pdf.scaleFactor = pdf.scaleFactorForSizeToFit
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(page: $page) }

    final class Coordinator: NSObject {
        private var page: Binding<Int>
        private var token: NSObjectProtocol?

        init(page: Binding<Int>) { self.page = page }

        func observe(_ pdf: PDFView) {
            token = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: pdf, queue: .main) { [weak self] _ in
                guard let current = pdf.currentPage, let doc = pdf.document else { return }
                self?.page.wrappedValue = doc.index(for: current)
            }
        }

        deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    }
}
