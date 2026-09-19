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

private struct ProjectPhotoIndex: Identifiable { let id: Int }

/// عارض بملء الشاشة بالسحب بين الصور
private struct ProjectPhotoViewer: View {
    let urls: [String]
    let startIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                    CachedAsyncImage(url: URL(string: url)) { img in
                        img.resizable().scaledToFit()
                    } placeholder: { ProgressView().tint(.white) }
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))

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
    }
}
