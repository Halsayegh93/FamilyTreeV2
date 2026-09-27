import SwiftUI

// MARK: - «التعليمات» — من علامة المعلومات في الرئيسية (طلب المالك ٢٠٢٦-٠٩-٢٧)
//
// تعليمات الشجرة نقطةً نقطة، بصفحات واضحة (طلب المالك: «بالصورة… من الواجهة الحقيقية…
// واضحة ومفهومة كل نقطة»): كل صفحة = رقمها + عنوان عريض + لقطة حقيقية من الشجرة
// (بأسماء تجريبية، فاتح وداكن في Assets: Guide*) عليها إصبع أو دائرة في المكان نفسه
// + سطر شرح واحد. «التالي» ينقل للنقطة التالية، والسحب يرجع.
//   ١ اضغط على الصورة ← يظهر الأبناء   ٢ اضغط على الاسم ← تفاصيل العضو
//   ٣ الرقم فوق الصورة                   ٤ أنت هنا
//   ٥ المتوفّى                            ٦ أزرار الشجرة
// مع «تقليل الحركة»: قبل ← بعد جنباً إلى جنب، والدوائر ثابتة.
// العلامة فيها قسمان منفصلان بمبدّل كبير أعلى المربّع (طلب المالك): «عن التطبيق» أولاً
// (الاسم والإصدار ومصمّم التطبيق — محتوى العلامة الأصلي) ثم «التعليمات» وحدها.

struct AppGuideBox: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var section: InfoSection = .about

    enum InfoSection: Hashable { case guide, about }

    private var pages: [GuidePage] { GuidePage.all }
    private var isLast: Bool { page == pages.count - 1 }
    private var isGuide: Bool { section == .guide }

    var body: some View {
        DSComposer(
            title: isGuide ? L10n.t("التعليمات", "Instructions") : L10n.t("عن التطبيق", "About the app"),
            subtitle: isGuide ? L10n.t("شجرة العائلة خطوة بخطوة", "The family tree, step by step")
                              : L10n.t("تطبيق عائلة المحمدعلي", "Al-Mohammad Ali Family App"),
            icon: isGuide ? "hand.tap.fill" : "info.circle.fill",
            tint: DS.Color.actionNavy,
            actionTitle: isLast ? L10n.t("تم", "Done") : L10n.t("التالي", "Next"),
            actionIcon: isLast ? "checkmark" : (L10n.isArabic ? "chevron.left" : "chevron.right"),
            showsAction: isGuide,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: true,
            onSubmit: {
                if isLast {
                    dismiss()
                } else {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) { page += 1 }
                }
            },
            onCancel: { dismiss() }
        ) {
            sectionSwitch

            if isGuide {
                guideContent
            } else {
                aboutContent
            }
        }
    }

    // MARK: - مبدّل القسمين — نفس المبدّل الكبير المرتّب في «الإشعارات | المستجدات»

    private var sectionSwitch: some View {
        // «عن التطبيق» أولاً ثم «التعليمات» (طلب المالك) — ويفتح على «عن التطبيق»
        DSSegmentedSwitch(
            options: [
                DSSegmentOption(id: InfoSection.about, title: L10n.t("عن التطبيق", "About"), icon: "info.circle.fill"),
                DSSegmentOption(id: InfoSection.guide, title: L10n.t("التعليمات", "Instructions"), icon: "hand.tap.fill")
            ],
            selection: $section
        )
    }

    // MARK: - قسم «التعليمات»

    private var guideContent: some View {
            VStack(spacing: DS.Spacing.sm) {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { i in
                        GuidePageView(page: pages[i], number: i + 1, total: pages.count,
                                      isCurrent: page == i, reduceMotion: reduceMotion)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 384)

                pageDots
            }
            .padding(.bottom, DS.Spacing.xs)
    }

    // MARK: - قسم «عن التطبيق» (محتوى العلامة الأصلي: الأيقونة والاسم والإصدار ومصمّم التطبيق)

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return b.map { "\(v) (\($0))" } ?? v
    }

    private var aboutContent: some View {
        VStack(spacing: DS.Spacing.md) {
            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(L10n.t("تطبيق عائلة المحمدعلي", "Al-Mohammad Ali Family App"))
                    .font(DS.Font.plex(17, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("الإصدار \(appVersion)", "Version \(appVersion)"))
                    .font(DS.Font.plex(13, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
            }

            VStack(spacing: 3) {
                Text("عمل هذا التطبيق")
                    .font(DS.Font.plex(11, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
                Text("حسن الصايغ")
                    .font(DS.Font.plex(16, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text("Made by Hasan Al-Sayegh")
                    .font(DS.Font.plex(13, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .padding(.vertical, DS.Spacing.sm)
            .padding(.horizontal, DS.Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.background))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.textTertiary.opacity(0.15), lineWidth: 1))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    /// نقاط الصفحات — الحالية ممتدة بلون الإجراء (قابلة للضغط)
    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(pages.indices, id: \.self) { i in
                Capsule()
                    .fill(i == page ? DS.Color.actionNavy.dsReadableGlyph : DS.Color.textTertiary.opacity(0.35))
                    .frame(width: i == page ? 18 : 7, height: 7)
                    .frame(minWidth: 22, minHeight: 30)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) { page = i }
                    }
                    .accessibilityLabel(L10n.t("النقطة \(i + 1) من \(pages.count)", "Step \(i + 1) of \(pages.count)"))
                    .accessibilityAddTraits(i == page ? [.isButton, .isSelected] : .isButton)
            }
        }
        .animation(reduceMotion ? nil : DS.Anim.snappy, value: page)
    }
}

// MARK: - تعريف النقاط

private struct GuidePage {
    enum Visual {
        /// إصبع يضغط مكاناً في لقطة «قبل» ← تتحوّل للقطة «بعد»
        case tap(before: String, after: String, at: CGPoint, aspect: CGFloat)
        /// دائرة تنبض حول مكان في لقطة (نصف القطر نسبة من عرض اللقطة)
        case spot(image: String, at: CGPoint, radius: CGFloat, aspect: CGFloat)
        /// شريط أدوات الشجرة بأرقام على كل زر وشرح كل رقم
        case toolbar
    }

    let title: String
    let text: String
    let visual: Visual

    static let treeAspect: CGFloat = 1206.0 / 1074.0
    static let nameAspect: CGFloat = 1206.0 / 1545.0

    static var all: [GuidePage] {
        [
            GuidePage(title: L10n.t("اضغط على الصورة", "Tap the photo"),
                      text: L10n.t("يظهر أبناء العضو تحته، واضغط عليها مرة ثانية لإخفائهم.",
                                   "The member's children appear below; tap it again to hide them."),
                      visual: .tap(before: "GuideTreeBefore", after: "GuideTreeAfter",
                                   at: CGPoint(x: 0.5, y: 0.7095), aspect: treeAspect)),
            GuidePage(title: L10n.t("اضغط على الاسم", "Tap the name"),
                      text: L10n.t("تنفتح تفاصيل العضو: معلوماته وعائلته وصلة القرابة.",
                                   "The member's details open: info, family and kinship."),
                      visual: .tap(before: "GuideNameBefore", after: "GuideNameAfter",
                                   at: CGPoint(x: 0.5, y: 0.4854), aspect: nameAspect)),
            GuidePage(title: L10n.t("الرقم فوق الصورة", "The number on the photo"),
                      text: L10n.t("عدد أبناء العضو — والسهم يعني إنك تقدر تفتحهم.",
                                   "How many children the member has — the arrow means you can open them."),
                      visual: .spot(image: "GuideTreeBefore", at: CGPoint(x: 0.4378, y: 0.634),
                                    radius: 0.075, aspect: treeAspect)),
            GuidePage(title: L10n.t("أنت هنا", "You are here"),
                      text: L10n.t("الإطار الأخضر وعلامة «أنت هنا» تبيّن مكانك في الشجرة.",
                                   "The green ring and «You» mark show your place in the tree."),
                      visual: .spot(image: "GuideTreeAfter", at: CGPoint(x: 0.5, y: 0.755),
                                    radius: 0.14, aspect: treeAspect)),
            GuidePage(title: L10n.t("المتوفّى", "Deceased"),
                      text: L10n.t("صورته رمادية، وتحت اسمه شريط أحمر فيه سنة الوفاة ثم الميلاد.",
                                   "Their photo is grey, with a red strip under the name showing the death then birth year."),
                      visual: .spot(image: "GuideTreeBefore", at: CGPoint(x: 0.5, y: 0.355),
                                    radius: 0.15, aspect: treeAspect)),
            GuidePage(title: L10n.t("أزرار الشجرة", "Tree buttons"),
                      text: L10n.t("هذي الأزرار في أعلى الشجرة.",
                                   "These buttons are at the top of the tree."),
                      visual: .toolbar)
        ]
    }
}

// MARK: - صفحة نقطة واحدة

private struct GuidePageView: View {
    let page: GuidePage
    let number: Int
    let total: Int
    let isCurrent: Bool
    let reduceMotion: Bool
    @State private var start = Date()

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            // الرقم + العنوان
            HStack(spacing: DS.Spacing.sm) {
                Text("\(number)")
                    .font(DS.Font.plex(15, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DSActionFill.style()))
                    .accessibilityHidden(true)
                Text(page.title)
                    .font(DS.Font.plex(18, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                Spacer(minLength: 0)
                Text(L10n.t("\(number) من \(total)", "\(number) of \(total)"))
                    .font(DS.Font.plex(11.5, weight: .semibold))
                    .foregroundColor(DS.Color.textTertiary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            visual
                .frame(maxWidth: .infinity)
                .frame(height: 300)

            Text(page.text)
                .font(DS.Font.plex(14, weight: .semibold))
                .foregroundColor(DS.Color.fieldValue)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 2)
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: isCurrent) { current in
            if current { start = Date() }   // تبدأ الحركة من أولها كلما وصلت للنقطة
        }
    }

    @ViewBuilder
    private var visual: some View {
        switch page.visual {
        case let .tap(before, after, at, aspect):
            if reduceMotion {
                HStack(spacing: DS.Spacing.xs) {
                    GuideTapScene(before: before, after: after, at: at, aspect: aspect, t: 0.95)
                    Image(systemName: L10n.isArabic ? "arrow.left" : "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(DS.Color.textTertiary)
                        .accessibilityHidden(true)
                    GuideTapScene(before: before, after: after, at: at, aspect: aspect, t: 2.5)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(page.text)
            } else {
                TimelineView(.animation(paused: !isCurrent)) { ctx in
                    let t = max(0, ctx.date.timeIntervalSince(start)).truncatingRemainder(dividingBy: GuideTapScene.period)
                    GuideTapScene(before: before, after: after, at: at, aspect: aspect, t: t)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(page.text)
            }
        case let .spot(image, at, radius, aspect):
            TimelineView(.animation(paused: reduceMotion || !isCurrent)) { ctx in
                GuideSpotScene(image: image, at: at, radius: radius, aspect: aspect,
                               pulse: reduceMotion ? 0.5 : ctx.date.timeIntervalSince(start))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(page.text)
        case .toolbar:
            GuideToolbarScene()
        }
    }
}

// MARK: - مشهد الضغط: لقطة «قبل» + إصبع ← لقطة «بعد»

private struct GuideTapScene: View {
    let before: String
    let after: String
    let at: CGPoint
    let aspect: CGFloat
    let t: Double

    static let period = 4.4

    private static func seg(_ t: Double, _ a: Double, _ b: Double) -> Double {
        min(1, max(0, (t - a) / (b - a)))
    }
    private static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    var body: some View {
        let handIn = Self.ease(Self.seg(t, 0.2, 0.85))
        let handOut = Self.seg(t, 1.1, 1.3)
        let pressX = Self.seg(t, 0.85, 1.05)
        let press = pressX <= 0 || pressX >= 1 ? 0 : (pressX < 0.5 ? pressX * 2 : (1 - pressX) * 2)
        let ripple = Self.seg(t, 0.88, 1.3)
        // الموجة والإصبع يخلصون قبل ما تتحوّل اللقطة — حتى ما تقع الموجة على عنصر ثاني في «بعد»
        let shown = Self.ease(Self.seg(t, 1.3, 1.7)) * (1 - Self.ease(Self.seg(t, 3.7, 4.1)))

        return GuideShot(aspect: aspect) {
            ZStack {
                Image(before).resizable().scaledToFit().opacity(1 - shown)
                Image(after).resizable().scaledToFit().opacity(shown)
            }
        } overlay: { size in
            let target = CGPoint(x: at.x * size.width, y: at.y * size.height)
            let rest = CGPoint(x: size.width * 0.86, y: size.height * 0.96)
            let hand = CGPoint(x: rest.x + (target.x - rest.x) * handIn,
                               y: rest.y + (target.y - rest.y) * handIn)
            ZStack {
                Circle()
                    .stroke(DS.Color.warning, lineWidth: 3)
                    .frame(width: 34, height: 34)
                    .scaleEffect(0.5 + 1.6 * ripple)
                    .opacity(ripple > 0 && ripple < 1 ? (1 - ripple) : 0)
                    .position(target)
                GuideFinger(press: press)
                    .position(x: hand.x + 12, y: hand.y + 15)
                    .opacity(min(1, handIn * 3) * (1 - handOut))
            }
        }
    }
}

// MARK: - مشهد الدائرة: لقطة + دائرة تنبض حول المكان

private struct GuideSpotScene: View {
    let image: String
    let at: CGPoint
    let radius: CGFloat
    let aspect: CGFloat
    /// الوقت للنبض (ثابت مع «تقليل الحركة»)
    let pulse: Double

    var body: some View {
        let wave = (sin(pulse * 2 * .pi / 1.6) + 1) / 2   // ٠…١
        return GuideShot(aspect: aspect) {
            Image(image).resizable().scaledToFit()
        } overlay: { size in
            let center = CGPoint(x: at.x * size.width, y: at.y * size.height)
            let r = radius * size.width
            ZStack {
                // تعتيم خفيف خارج الدائرة حتى يبرز المكان
                Rectangle()
                    .fill(Color.black.opacity(0.28))
                    .mask(
                        Rectangle()
                            .overlay(Circle().frame(width: r * 2, height: r * 2)
                                .position(center)
                                .blendMode(.destinationOut))
                            .compositingGroup()
                    )
                Circle()
                    .stroke(DS.Color.warning, lineWidth: 3)
                    .frame(width: r * 2, height: r * 2)
                    .position(center)
                Circle()
                    .stroke(DS.Color.warning.opacity(0.5 * (1 - wave)), lineWidth: 2)
                    .frame(width: r * 2 * (1 + 0.25 * wave), height: r * 2 * (1 + 0.25 * wave))
                    .position(center)
            }
        }
    }
}

// MARK: - أزرار الشجرة: الشريط الحقيقي فوق، وتحته أربع بطاقات مرتّبة — لكل زر شكله وعمله

private struct GuideToolbarScene: View {
    private enum Look {
        case circle(String)   // زر دائري بأيقونة (مثل الشجرة)
        case switcher         // مبدّل «شجرة العائلة | النساء»
    }

    private struct Item: Identifiable {
        let id: Int
        let look: Look
        let title: String
        let detail: String
    }

    private var items: [Item] {
        [
            Item(id: 1, look: .circle("magnifyingglass"),
                 title: L10n.t("البحث", "Search"),
                 detail: L10n.t("ابحث عن أي عضو باسمه", "Find any member by name")),
            Item(id: 2, look: .circle("house.fill"),
                 title: L10n.t("البداية", "Start"),
                 detail: L10n.t("يرجعك لأعلى الشجرة", "Back to the top of the tree")),
            Item(id: 3, look: .switcher,
                 title: L10n.t("العائلة / النساء", "Family / Women"),
                 detail: L10n.t("تبدّل بين الشجرتين", "Switch between the two trees")),
            Item(id: 4, look: .circle("location.fill"),
                 title: L10n.t("موقعي", "Me"),
                 detail: L10n.t("يوصلك لمكانك «أنت هنا»", "Takes you to your place"))
        ]
    }

    private let columns = [GridItem(.flexible(), spacing: DS.Spacing.sm),
                           GridItem(.flexible(), spacing: DS.Spacing.sm)]

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            // الشريط الحقيقي كما يظهر أعلى الشجرة
            GuideShot(aspect: 1158.0 / 160.0) {
                Image("GuideTreeToolbar").resizable().scaledToFit()
            } overlay: { _ in EmptyView() }
            .accessibilityHidden(true)

            LazyVGrid(columns: columns, spacing: DS.Spacing.sm) {
                ForEach(items) { item in
                    VStack(spacing: 5) {
                        look(item.look)
                            .frame(height: 40)
                        Text(item.title)
                            .font(DS.Font.plex(13, weight: .bold))
                            .foregroundColor(DS.Color.fieldLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(item.detail)
                            .font(DS.Font.plex(11.5))
                            .foregroundColor(DS.Color.fieldValue)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, DS.Spacing.sm)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .top)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.background))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(DS.Color.textTertiary.opacity(0.15), lineWidth: 1))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// شكل الزر كما في شريط الشجرة
    @ViewBuilder
    private func look(_ look: Look) -> some View {
        switch look {
        case .circle(let icon):
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(DS.Color.primary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(DS.Color.surface))
                .overlay(Circle().strokeBorder(DS.Color.textTertiary.opacity(0.25), lineWidth: 1))
                .accessibilityHidden(true)
        case .switcher:
            HStack(spacing: 2) {
                Text(L10n.t("شجرة العائلة", "Family"))
                    .font(DS.Font.plex(10.5, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(DSActionFill.style()))
                Text(L10n.t("النساء", "Women"))
                    .font(DS.Font.plex(10.5, weight: .bold))
                    .foregroundColor(DS.Color.textSecondary)
                    .padding(.horizontal, 6)
            }
            .padding(3)
            .background(Capsule().fill(DS.Color.surface))
            .overlay(Capsule().strokeBorder(DS.Color.textTertiary.opacity(0.25), lineWidth: 1))
            .fixedSize()
            .accessibilityHidden(true)
        }
    }
}

// MARK: - أدوات مشتركة

/// لقطة بإطار مدوّر وطبقة رسم فوقها بنفس مقاسها (الإحداثيات من اليسار دائماً)
private struct GuideShot<Content: View, Overlay: View>: View {
    let aspect: CGFloat
    @ViewBuilder let content: () -> Content
    @ViewBuilder let overlay: (CGSize) -> Overlay

    var body: some View {
        content()
            .aspectRatio(aspect, contentMode: .fit)
            .overlay { GeometryReader { g in overlay(g.size) } }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.textTertiary.opacity(0.22), lineWidth: 1))
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// الإصبع: أبيض بحدّ أسود — واضح على اللقطات الفاتحة والداكنة
private struct GuideFinger: View {
    let press: Double
    var body: some View {
        ZStack {
            Image(systemName: "hand.point.up.left.fill")
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.45), radius: 4, x: 0, y: 2)
            Image(systemName: "hand.point.up.left")
                .foregroundStyle(Color.black.opacity(0.75))
        }
        .font(.system(size: 34, weight: .regular))
        .scaleEffect(1 - 0.14 * press, anchor: .topLeading)
        .accessibilityHidden(true)
    }
}
