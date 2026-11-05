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

/// قسم «الصور» في صفحة المشروع (طلب المالك ٢٠٢٦-١٠-٢٣ الخيار «ب»: الرأس للشعار والاسم فقط، والصور
/// في قسمها تحت «نبذة عن المشروع» مباشرة): صور كثيرة ← صفحات أفقية تُسحب بزوايا مدوّرة ونقاط صغيرة
/// تحتها؛ صورة واحدة ← الصورة وحدها بلا نقاط؛ بلا صور ← لا يُرسم القسم (يتحقّق المستدعي).
/// كل صورة بنسبتها الطبيعية (`scaledToFit` بعرض البطاقة، بلا قصّ): ارتفاع الشريط = أطول الصور نسبةً
/// حتى سقف `maxHeight` (٧٠٪ من ارتفاع المربّع)، والأقصر تتوسّط على أرضية البطاقة.
/// الضغط على صورة يفتح العارض بملء الشاشة (`ProjectPhotoViewer`) من تلك الصورة.
struct ProjectPhotosCarousel: View {
    let urls: [String]
    /// سقف ارتفاع الصورة — ٧٠٪ من ارتفاع المربّع (لا تأخذ الصورة الطويلة المربّع كله)
    var maxHeight: CGFloat = 320
    @State private var page = 0
    @State private var viewerIndex: Int?
    /// فُتح العارض مرة من هذا المربّع — تُخفى شارة «تكبير»
    @State private var viewerOpened = false
    /// نسبة كل صورة (العرض ÷ الارتفاع) بعد تحميلها
    @State private var aspects: [String: CGFloat] = [:]
    @State private var width: CGFloat = 0

    /// ارتفاع الشريط — أطول الصور نسبةً (أصغر عرض÷ارتفاع) بعرض البطاقة حتى السقف؛ قبل التحميل ١٦:١٠
    private func stripHeight(_ photos: [String]) -> CGFloat {
        let known = photos.compactMap { aspects[$0] }.filter { $0 > 0 }
        let aspect = known.min() ?? 1.6
        guard width > 0 else { return min(maxHeight, 200) }
        return min(maxHeight, width / aspect)
    }

    private var photos: [String] { urls.filter { !$0.isEmpty } }

    var body: some View {
        let photos = photos
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // عنوان القسم الموحّد (قرص مجسّم + عنوان + العدد)
            DSSectionTitle(title: L10n.t("الصور", "Photos"), icon: "photo.on.rectangle.angled",
                           tint: AppSection.projects.ink, trailing: "\(photos.count)", iconSize: DS.Icon.inline)

            Group {
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
            .frame(maxWidth: .infinity)
            .frame(height: stripHeight(photos))
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { width = geo.size.width }
                    .onChange(of: geo.size.width) { width = $0 }
            })
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .animation(DS.Anim.quick, value: aspects.count)

            if photos.count > 1 { pageDots(photos.count) }
        }
        // البطاقة الواحدة (`.dsCard`)
        .dsCard(padding: DS.Spacing.lg)
        .fullScreenCover(item: Binding(
            get: { viewerIndex.map { ProjectPhotoIndex(id: $0) } },
            set: { viewerIndex = $0?.id }
        )) { start in
            ProjectPhotoViewer(urls: photos, startIndex: start.id)
        }
        // نِسَب الصور من نفس الكاش (لا تنزيل مكرّر — نفس ما تعرضه الصفحات)
        .task(id: photos) {
            for url in photos where aspects[url] == nil {
                guard let u = URL(string: url),
                      let img = try? await CachedImageLoader.load(u), img.size.height > 0 else { continue }
                aspects[url] = img.size.width / img.size.height
            }
        }
    }

    private func photoButton(_ photos: [String], _ idx: Int) -> some View {
        Button { viewerIndex = idx; viewerOpened = true } label: {
            CachedAsyncImage(url: URL(string: photos[idx])) { img in
                img.resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    // شارة «تكبير» في الوسط — تظهر فقط بعد وصول الصورة ثم تختفي
                    .overlay { ZoomHintBadge(dismissed: viewerOpened) }
            } placeholder: {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.mutedBackground)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("صورة \(idx + 1) من \(photos.count)", "Photo \(idx + 1) of \(photos.count)"))
        .accessibilityHint(L10n.t("اضغط للتكبير", "Tap to enlarge"))
    }

    /// نقاط الصفحات — صغيرة تحت الصورة بلون القسم، الحالية كبسولة أعرض
    private func pageDots(_ count: Int) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(0..<count, id: \.self) { idx in
                Capsule()
                    .fill(AppSection.projects.ink.opacity(idx == page ? 1 : DS.Opacity.tintStroke))
                    .frame(width: idx == page ? DS.Spacing.md : DS.Spacing.xsm, height: DS.Spacing.xsm)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(DS.Anim.quick, value: page)
        .accessibilityHidden(true)
    }
}

struct ProjectPhotoIndex: Identifiable { let id: Int }

/// شارة «تكبير» في وسط الصورة القابلة للتكبير (المشاريع والمكتبة — طلب المالك ٢٠٢٦-١٠-٢٣):
/// دائرة داكنة شفّافة ~٣٦ نقطة برمز أبيض، تختفي تدريجياً بعد ثانيتين، أو فوراً بعد فتح العارض مرة
struct ZoomHintBadge: View {
    /// فُتح العارض من هذا المربّع — لا حاجة للتلميح بعدها
    var dismissed: Bool = false
    @State private var expired = false

    var body: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.black.opacity(0.4)))
            .opacity(dismissed || expired ? 0 : 1)
            .animation(.easeOut(duration: 0.4), value: dismissed || expired)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                expired = true
            }
    }
}

/// عارض بملء الشاشة (يستعمله المشاريع والمكتبة): التكبير بالقرصة أو بضغطتين والتحريك وهي مكبّرة،
/// والسحب بين الصور وهي غير مكبّرة — `ZoomablePhotoPager` (طلب المالك ٢٠٢٦-١٠-٢٣)
struct ProjectPhotoViewer: View {
    let urls: [String]
    let startIndex: Int
    /// قسم مؤشّر التحميل — المشاريع، أو المكتبة حين يفتحه عارض الأرشيف
    var section: AppSection = .projects
    /// تُحجب الصور عن لقطة الشاشة (المكتبة — `LibraryProtection`)
    var shielded: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var index: Int
    @State private var loaded: Set<Int> = []

    init(urls: [String], startIndex: Int, section: AppSection = .projects, shielded: Bool = false) {
        self.urls = urls
        self.startIndex = startIndex
        self.section = section
        self.shielded = shielded
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack(alignment: .top) {
            DS.Color.overlayDark.ignoresSafeArea()

            ZoomablePhotoPager(urls: urls, startIndex: startIndex,
                               isRTL: layoutDirection == .rightToLeft,
                               onIndexChange: { index = $0 },
                               onLoadedChange: { loaded = $0 })
                // إحداثيات فيزيائية ثابتة — اتجاه التقليب يحدّده `isRTL` نفسه
                .environment(\.layoutDirection, .leftToRight)
                .screenCaptureShielded(shielded)
                .ignoresSafeArea()

            // دوّارة صغيرة محايدة تحت الصورة حتى تصل فقط — لا مجسّم القسم فوق الصورة
            if !loaded.contains(index) {
                ProgressView()
                    .tint(DS.Color.overlayText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .accessibilityLabel(L10n.t("جاري التحميل", "Loading"))
            }

            HStack {
                // «2 من 5» — صورة واحدة بلا عدّاد
                if urls.count > 1 {
                    Text(verbatim: L10n.t("\(index + 1) من \(urls.count)", "\(index + 1) of \(urls.count)"))
                        .dsFont(.rowTitleCompact)
                        .foregroundColor(DS.Color.overlayText)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(Capsule().fill(DS.Color.overlayDark))
                }
                Spacer()
                // زرّ الإغلاق الموحّد فوق الوسائط
                DSCloseButton(context: .onMedia) { dismiss() }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)
        }
    }
}
