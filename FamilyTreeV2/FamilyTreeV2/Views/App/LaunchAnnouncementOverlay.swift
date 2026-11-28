import SwiftUI

// MARK: - مربّع إعلان الفتح (العينة launch-announcements، الشاشة ٢)
//
// صورة المالك تملأ بطاقة ٤:٥ بزوايا مدوّرة (ملاءمة داخلها، والخلفية كحلية فيبدو الهامش مقصوداً)، بحدّ أقصى ٧٠٪ من
// ارتفاع الشاشة، بلا عنوان ولا رأس. ✕ على ركن الصورة يجيب التالي، ونقاط تحتها حين يكون أكثر من إعلان، والزرّ تحتها
// (إلا «بدون زر»). «تقليل الحركة»: تلاشٍ فقط. القارئ الصوتي: الصورة «إعلان» ثم الزرّ، و✕ «إغلاق».

extension DS {
    /// مقاسات مربّع إعلان الفتح — مكان واحد (البطاقة في المربّع ومصغّرتها في المنشئ والقائمة)
    enum LaunchCard {
        /// عرض ÷ ارتفاع — المقاس المناسب 1080 × 1350 (طولي 4:5)
        static let aspect: CGFloat = 4.0 / 5.0
        /// أقصى ارتفاع من الشاشة
        static let maxHeightShare: CGFloat = 0.7
        static let radius: CGFloat = DS.Radius.xl
        /// خلفية البطاقة خلف الصورة (كحلي الرأس)
        static let fill = DS.Color.bandFill
        /// تعتيم ما خلف المربّع
        static let dim: Double = 0.6
        /// نقاط الصفحات تحت الصورة
        static let dotSize: CGFloat = 6
        static let dotActiveWidth: CGFloat = 18
        static let dotIdle = SwiftUI.Color.white.opacity(0.6)
        static let dotActive = DS.Color.accentLight
        /// مصغّرة الصورة في منشئ الإعلان
        static let composerThumbWidth: CGFloat = 120
        /// مصغّرة الصفّ في «الإعلانات عند الفتح»
        static let rowThumbWidth: CGFloat = DS.Icon.row
        static let rowThumbRadius: CGFloat = DS.Radius.sm
    }
}

struct LaunchAnnouncementOverlay: View {
    let slides: [LaunchAnnouncementSlide]
    let storeURL: URL?
    let onFinish: (LaunchAnnouncementWindow.Outcome) -> Void

    @State private var index = 0
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var slide: LaunchAnnouncementSlide { slides[min(index, slides.count - 1)] }

    var body: some View {
        GeometryReader { geo in
            let available = geo.size.width - DS.Spacing.lg * 2
            let height = min(geo.size.height * DS.LaunchCard.maxHeightShare, available / DS.LaunchCard.aspect)
            let width = height * DS.LaunchCard.aspect
            ZStack {
                Color.black.opacity(appeared ? DS.LaunchCard.dim : 0)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                VStack(spacing: DS.Spacing.md) {
                    card(width: width, height: height)
                    if slides.count > 1 { dots }
                    if let action = buttonAction(for: slide.item), let title = slide.item.buttonText {
                        Button(action: action) {
                            Text(title)
                                .dsFont(.button)
                                .foregroundColor(DS.Color.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: DSBox.buttonHeightLarge)
                                .background(RoundedRectangle(cornerRadius: DSBox.buttonRadius, style: .continuous)
                                    .fill(DS.Color.surface))
                                .contentShape(RoundedRectangle(cornerRadius: DSBox.buttonRadius, style: .continuous))
                        }
                        .buttonStyle(DSPressStyle())
                    }
                }
                .frame(width: width)
                .scaleEffect(appeared || reduceMotion ? 1 : DSMotion.panelScale)
                .offset(y: appeared || reduceMotion ? 0 : DSMotion.panelRise)
                .opacity(appeared ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? DSMotion.fade : DSMotion.panel) { appeared = true }
        }
    }

    private func card(width: CGFloat, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.LaunchCard.radius, style: .continuous)
        return ZStack {
            shape.fill(DS.LaunchCard.fill)
            Image(uiImage: slide.image)
                .resizable()
                .scaledToFit()
                .id(slide.id)
                .transition(.opacity)
                .accessibilityLabel(L10n.t("إعلان", "Announcement"))
                .accessibilityAddTraits(.isImage)
                .accessibilityValue(slides.count > 1
                                    ? L10n.t("\(index + 1) من \(slides.count)", "\(index + 1) of \(slides.count)") : "")
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .dsCardShadow()
        .overlay(alignment: .topTrailing) {
            DSCloseButton(context: .onMedia, label: L10n.t("إغلاق", "Close")) { next() }
                .padding(DS.Spacing.xs)
        }
    }

    private var dots: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(slides.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? DS.LaunchCard.dotActive : DS.LaunchCard.dotIdle)
                    .frame(width: i == index ? DS.LaunchCard.dotActiveWidth : DS.LaunchCard.dotSize,
                           height: DS.LaunchCard.dotSize)
            }
        }
        .accessibilityHidden(true)
    }

    /// إجراء الزرّ — nil = بلا زرّ (أو لا رابط صالح)
    private func buttonAction(for item: LaunchAnnouncement) -> (() -> Void)? {
        switch item.kind {
        case .none:
            return nil
        case .news:
            return { onFinish(.openNews) }
        case .update:
            guard let storeURL else { return nil }
            return { UIApplication.shared.open(storeURL); next() }
        case .link:
            guard let url = Self.linkURL(item.buttonUrl) else { return nil }
            return { UIApplication.shared.open(url); next() }
        }
    }

    /// رابط كتبه المالك — بلا بروتوكول يُفتح بـ https
    static func linkURL(_ raw: String?) -> URL? {
        let s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let full = s.contains("://") ? s : "https://\(s)"
        guard let url = URL(string: full), url.host != nil else { return nil }
        return url
    }

    /// ✕ والزرّ: التالي، وبعد الأخير يكمل التطبيق
    private func next() {
        if index + 1 < slides.count {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? DSMotion.fade : DS.Anim.smooth) { index += 1 }
        } else {
            onFinish(.finished)
        }
    }
}
