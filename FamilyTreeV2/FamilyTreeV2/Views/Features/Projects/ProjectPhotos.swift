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
    @State private var pickerItems: [PhotosPickerItem] = []

    private var total: Int { existingUrls.count + newImages.count }
    private let columns = [GridItem(.adaptive(minimum: 84), spacing: DS.Spacing.sm)]

    var body: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("صور المشروع", "Project Photos"),
                icon: "photo.on.rectangle.angled",
                trailing: "\(total)/\(projectPhotosLimit)",
                iconColor: DS.Color.primary
            )

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
                        VStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(DS.Font.scaled(18, weight: .bold))
                            Text(L10n.t("إضافة", "Add"))
                                .font(DS.Font.scaled(11, weight: .bold))
                        }
                        .foregroundColor(DS.Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 84)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .fill(DS.Color.primary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .strokeBorder(DS.Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                        )
                    }
                }
            }
            .padding(DS.Spacing.md)
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
            .frame(height: 84)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(alignment: .topLeading) {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(DS.Font.scaled(10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .padding(5)
                .accessibilityLabel(L10n.t("حذف الصورة", "Remove photo"))
            }
    }
}

/// معرض صور المشروع في صفحته — صف أفقي، والضغط يفتح الصورة بملء الشاشة
struct ProjectPhotosGallery: View {
    let urls: [String]
    @State private var viewerIndex: Int?

    var body: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("صور المشروع", "Project Photos"),
                icon: "photo.on.rectangle.angled",
                trailing: "\(urls.count)",
                iconColor: DS.Color.primary
            )
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                        Button { viewerIndex = idx } label: {
                            CachedAsyncImage(url: URL(string: url)) { img in
                                img.resizable().scaledToFill()
                            } placeholder: { DS.Color.mutedBackground }
                            .frame(width: 140, height: 105)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        }
                        .buttonStyle(DSScaleButtonStyle())
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.md)
            }
        }
        .fullScreenCover(item: Binding(
            get: { viewerIndex.map { ProjectPhotoIndex(id: $0) } },
            set: { viewerIndex = $0?.id }
        )) { start in
            ProjectPhotoViewer(urls: urls, startIndex: start.id)
        }
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
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(DS.Font.scaled(12, weight: .bold))
                Text(L10n.t("صور المشروع", "Project Photos"))
                    .font(DS.Font.plex(13, weight: .bold))
                Spacer()
                Text("\(urls.count)")
                    .font(DS.Font.plex(12, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
            }
            .foregroundColor(DS.Color.textSecondary)

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
        .padding(DS.Spacing.lg)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .dsSubtleShadow()
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
                        Color.black.opacity(0.45)
                        Text("+\(extra)")
                            .font(DS.Font.plex(20, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(L10n.t("صورة \(index + 1)", "Photo \(index + 1)"))
    }
}

private struct ProjectPhotoIndex: Identifiable { let id: Int }

/// عارض بملء الشاشة بالسحب بين الصور
private struct ProjectPhotoViewer: View {
    let urls: [String]
    let startIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var zoomed = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                    ZoomableImage(onZoomChange: { zoomed = $0 }) {
                        CachedAsyncImage(url: URL(string: url)) { img in
                            img.resizable().scaledToFit()
                        } placeholder: { ProgressView().tint(.white) }
                    }
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
            .disabled(zoomed)

            HStack {
                Text("\(index + 1) / \(urls.count)")
                    .font(DS.Font.plex(13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Button { dismiss() } label: {
                    Text(L10n.t("إغلاق", "Close"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, DS.Spacing.md)
                        .frame(height: 36)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)
        }
        .onAppear { index = startIndex }
        .onChange(of: index) { _ in zoomed = false }
    }
}
