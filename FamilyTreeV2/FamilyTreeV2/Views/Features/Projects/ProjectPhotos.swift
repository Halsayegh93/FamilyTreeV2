import SwiftUI
import PhotosUI

// MARK: - صور المشروع (طلب المالك)
// محرّر في الإضافة/التعديل + معرض في صفحة المشروع يفتح الصور بملء الشاشة.

/// أقصى عدد لصور المشروع
let projectPhotosLimit = 8

/// محرّر صور المشروع: الصور الحالية (روابط) + الجديدة (قبل الرفع)، مع حذف وإضافة
struct ProjectPhotosEditor: View {
    @Binding var existingUrls: [String]
    @Binding var newImages: [UIImage]
    var tint: Color = DS.Color.primary
    var index: Int = 0
    @State private var pickerItems: [PhotosPickerItem] = []

    private var total: Int { existingUrls.count + newImages.count }
    /// ضلع المصغّرة (نفس خانة «إضافة») — من مقاسات الهيكل
    private static let tileSide: CGFloat = DSBox.photoTile * 1.5
    private let columns = [GridItem(.adaptive(minimum: tileSide), spacing: DS.Spacing.sm)]

    var body: some View {
        // نفس شكل أقسام مربّعات الإضافة (طلب المالك)
        DSComposerSection(
            title: L10n.t("صور المشروع", "Project Photos"),
            icon: "photo.on.rectangle.angled",
            tint: tint,
            trailing: "\(total)/\(projectPhotosLimit)",
            index: index
        ) {
            LazyVGrid(columns: columns, spacing: DS.Spacing.sm) {
                ForEach(Array(existingUrls.enumerated()), id: \.offset) { idx, url in
                    thumb {
                        CachedAsyncImage(url: URL(string: url)) { img in
                            img.resizable().scaledToFill()
                        } placeholder: { DS.Color.mutedBackground }
                    } onRemove: {
                        withAnimation(DS.Anim.quick) { _ = existingUrls.remove(at: idx) }
                    }
                }
                ForEach(Array(newImages.enumerated()), id: \.offset) { idx, img in
                    thumb {
                        Image(uiImage: img).resizable().scaledToFill()
                    } onRemove: {
                        withAnimation(DS.Anim.quick) { _ = newImages.remove(at: idx) }
                    }
                }
                if total < projectPhotosLimit {
                    PhotosPicker(selection: $pickerItems,
                                 maxSelectionCount: projectPhotosLimit - total,
                                 matching: .images) {
                        VStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "plus")
                                .dsGlyph(DS.Glyph.xlCompact)
                            Text(L10n.t("إضافة", "Add"))
                                .dsFont(.badge)
                        }
                        .foregroundColor(AppSection.projects.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.tileSide)
                        // خانة «إضافة» المتقطّعة الموحّدة
                        .background(
                            RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
                                .fill(AppSection.projects.ink.opacity(DS.Opacity.tintFillSoft))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
                                .strokeBorder(AppSection.projects.ink.opacity(DSAddChipLabel.strokeOpacity),
                                              style: DSAddChipLabel.dash)
                        )
                    }
                }
            }
        }
        .onChange(of: pickerItems) { items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data),
                       existingUrls.count + newImages.count < projectPhotosLimit {
                        newImages.append(img)
                    }
                }
                pickerItems = []
            }
        }
    }

    private func thumb<C: View>(@ViewBuilder _ content: () -> C, onRemove: @escaping () -> Void) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(height: Self.tileSide)
            .clipShape(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous))
            .overlay(alignment: .topLeading) {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .dsGlyph(DS.Glyph.micro)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(width: DS.Icon.section, height: DS.Icon.section)
                        .background(Circle().fill(DS.Color.shadowOverlay))
                        .padding(DS.Spacing.xs)
                        // مساحة ضغط ٤٤ نقطة حول الشارة الصغيرة (حد أبل) والشكل كما هو
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget, alignment: .topLeading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("حذف الصورة", "Remove photo"))
            }
    }
}

/// صورة رأس المشروع في صفحته (طلب المالك ٢٠٢٦-١٠-٢٣ «الصور تنسحب»): صور كثيرة ← صفحات أفقية تُسحب
/// بنقاط صغيرة أعلاها؛ صورة واحدة ← الصورة وحدها؛ بلا صورة ← `ProjectHeroImage` (الشعار أو المجسّم).
/// الضغط على صورة يفتح العارض بملء الشاشة (`ProjectPhotoViewer`) من تلك الصورة.
struct ProjectHeroCarousel: View {
    let project: Project
    var markSize: CGFloat = DS.Icon.state
    @State private var page = 0
    @State private var viewerIndex: Int?

    private var photos: [String] { project.imageUrls.filter { !$0.isEmpty } }

    var body: some View {
        let photos = photos
        if photos.isEmpty {
            ProjectHeroImage(project: project, markSize: markSize)
        } else {
            ZStack {
                ProjectSectionBackdrop(symbolSize: DS.Glyph.lg)
                    .accessibilityHidden(true)
                if photos.count == 1 {
                    photoButton(photos, 0)
                } else {
                    TabView(selection: $page) {
                        ForEach(photos.indices, id: \.self) { idx in
                            photoButton(photos, idx).tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .clipped()
            .overlay(alignment: .top) {
                if photos.count > 1 { pageDots(photos.count) }
            }
            .fullScreenCover(item: Binding(
                get: { viewerIndex.map { ProjectPhotoIndex(id: $0) } },
                set: { viewerIndex = $0?.id }
            )) { start in
                ProjectPhotoViewer(urls: photos, startIndex: start.id)
            }
        }
    }

    private func photoButton(_ photos: [String], _ idx: Int) -> some View {
        Button { viewerIndex = idx } label: {
            CachedAsyncImage(url: URL(string: photos[idx])) { img in
                img.resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } placeholder: { Color.clear }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("صورة \(idx + 1) من \(photos.count)", "Photo \(idx + 1) of \(photos.count)"))
    }

    /// نقاط الصفحات — صغيرة أعلى الصورة (أسفلها الشعار)، الحالية كبسولة أعرض
    private func pageDots(_ count: Int) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(0..<count, id: \.self) { idx in
                Capsule()
                    .fill(DS.Color.textOnPrimary.opacity(idx == page ? 1 : DS.Opacity.selectedStroke))
                    .frame(width: idx == page ? DS.Spacing.md : DS.Spacing.xsm, height: DS.Spacing.xsm)
            }
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(Capsule().fill(DS.Color.shadowOverlay))
        .padding(.top, DS.Spacing.sm)
        .animation(DS.Anim.quick, value: page)
        .accessibilityHidden(true)
    }
}

/// معرض صور المشروع — فسيفساء: صورة كبيرة + مربّعات جانبية، وآخر مربّع يحمل «+N»
struct ProjectPhotosMosaic: View {
    let urls: [String]
    @State private var viewerIndex: Int?

    /// أقصى ما يُعرض قبل ظهور «+N» على آخر مربّع
    private let visibleLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // عنوان القسم الموحّد (قرص مجسّم + عنوان + العدد)
            DSSectionTitle(title: L10n.t("صور المشروع", "Project Photos"), icon: "photo.on.rectangle.angled",
                           tint: AppSection.projects.ink, trailing: "\(urls.count)", iconSize: DS.Icon.inline)

            if urls.count == 1 {
                tile(0, height: 210)
            } else if urls.count == 2 {
                HStack(spacing: DS.Spacing.xs) {
                    tile(0, height: 170)
                    tile(1, height: 170)
                }
            } else {
                HStack(spacing: DS.Spacing.xs) {
                    tile(0, height: 210)
                        .frame(maxWidth: .infinity)
                    VStack(spacing: DS.Spacing.xs) {
                        tile(1, height: 101)
                        tile(2, height: 101, extra: urls.count - visibleLimit)
                    }
                    .frame(width: 104)
                }
            }
        }
        // البطاقة الواحدة (`.dsCard`)
        .dsCard(padding: DS.Spacing.lg)
        .fullScreenCover(item: Binding(
            get: { viewerIndex.map { ProjectPhotoIndex(id: $0) } },
            set: { viewerIndex = $0?.id }
        )) { start in
            ProjectPhotoViewer(urls: urls, startIndex: start.id)
        }
    }

    /// مربّع صورة — `extra` أكبر من صفر يعني بقيّة الصور تحت «+N»
    private func tile(_ index: Int, height: CGFloat, extra: Int = 0) -> some View {
        Button { viewerIndex = index } label: {
            CachedAsyncImage(url: URL(string: urls[index])) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                DS.Color.mutedBackground
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .overlay {
                if extra > 0 {
                    ZStack {
                        DS.Color.shadowHeavy
                        Text("+\(extra)")
                            .dsFont(.statValue)
                            .foregroundColor(DS.Color.textOnPrimary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(L10n.t("صورة \(index + 1)", "Photo \(index + 1)"))
    }
}

struct ProjectPhotoIndex: Identifiable { let id: Int }

/// عارض بملء الشاشة بالسحب بين الصور
struct ProjectPhotoViewer: View {
    let urls: [String]
    let startIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var zoomed = false

    var body: some View {
        ZStack(alignment: .top) {
            DS.Color.overlayDark.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                    ZoomableImage(onZoomChange: { zoomed = $0 }) {
                        CachedAsyncImage(url: URL(string: url)) { img in
                            img.resizable().scaledToFit()
                        } placeholder: { DSPageLoader(section: .projects) }
                    }
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
            .disabled(zoomed)

            HStack {
                Text("\(index + 1) / \(urls.count)")
                    .dsFont(.rowTitleCompact)
                    .foregroundColor(DS.Color.overlayText)
                Spacer()
                // زرّ الإغلاق الموحّد فوق الوسائط
                DSCloseButton(context: .onMedia) { dismiss() }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)
        }
        .onAppear { index = startIndex }
        .onChange(of: index) { _ in zoomed = false }
    }
}
