import SwiftUI

// MARK: - «المربّع اللي ينسحب» في «اليوم» (الدفعة ١٠، اختيار المالك ٢٠٢٦-١٠-٢٠)
//
// مربّع أبيض واحد يصعد فوق حافة الرأس الكحلي (مكان بطاقة «إحصاء الأفراد» السابقة) بصفحتين تُسحبان أفقياً:
// ١) «يحتاج انتباهك» (الأرقام الأربعة + سطر «حالة النظام») · ٢) «إحصاء الأفراد» (الحلقات الثلاث + المسجّلون) — وتحته نقطتا
// الصفحة. الاتجاه عربي صحيح: الأولى على اليمين والثانية على يسارها (السحب يميناً يأتي بها)، وبالإنجليزية بالعكس. يتذكّر آخر
// صفحة لكل مستخدم (`@AppStorage`). الحلقات تمتلئ وأرقامها تعدّ حين تظهر الصفحة الثانية أول مرة (`dsGaugeHold`). القارئ
// الصوتي: الصفحة الظاهرة فقط، والنقاط عنصر قابل للتعديل (أعلى/أسفل) بإجراءين «التالي/السابق». الصفحتان بارتفاع واحد (الأطول)
// فلا يقفز ما تحته. صفحة واحدة (المشرف بلا «إحصاء الأفراد») = المربّع بلا نقاط ولا سحب.
// الدفعة ١٣ (المالك: «نصغره شوي و الى داخله نكبر» + «النقطتين… خلهم داخل المربع»): حشوة أضيق (`DS.Hub.swipePadding`)،
// والنقطتان داخل المربّع في شريط أسفله (`DS.Hub.pageDotsHeight`) بدل صفّ تحته — الصفحتان تحشوان الجانبين والأعلى فقط
// والمربّع يضيف الأسفل (شريط النقاط، أو الحشوة نفسها لصفحة واحدة).
// مقسِّم خفيف بلا `TabView` (ارتفاع الصفحات يتبع المحتوى، والاتجاه العربي مضبوط): `AdminPagerLayout` + سحب أفقي. من iOS 18
// السحب إيماءة UIKit أفقية فقط (`AdminHorizontalPan`) تُلغي لمس ما تحتها حين تبدأ — فالسحب لا يفتح الرقم الذي بدأ عليه،
// والعمودي يبقى للتمرير؛ قبل iOS 18 `DragGesture` متزامن مع التمرير.

struct AdminTodaySwipeCard: View {
    let attention: AnyView
    let census: AnyView?
    @AppStorage private var stored: Int
    @State private var dragX: CGFloat = 0
    /// «إحصاء الأفراد» ظهر مرة — قبله حلقاته ساكنة فارغة (تمتلئ أمام العين لا خارج الشاشة)
    @State private var censusSeen = false
    @Environment(\.layoutDirection) private var direction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// `userKey`: معرّف المستخدم — لكل مستخدم آخر صفحته
    init(userKey: String, attention: AnyView, census: AnyView?) {
        self.attention = attention
        self.census = census
        _stored = AppStorage(wrappedValue: 0, "admin.today.swipePage.\(userKey)")
    }

    private var count: Int { census == nil ? 1 : 2 }
    private var page: Int { min(max(stored, 0), count - 1) }
    private var rtl: Bool { direction == .rightToLeft }

    private static let titles = [L10n.t("يحتاج انتباهك", "Needs your attention"), L10n.t("إحصاء الأفراد", "Family census")]

    var body: some View {
        // من أحجام إمكانية الوصول «إحصاء الأفراد» كتل طويلة — المربّع بطول الصفحة الظاهرة (لا فراغ كبير في الأولى)
        AdminPagerLayout(page: page, drag: dragX, rtl: rtl, matchesHeights: !typeSize.isAccessibilitySize) {
            attention
                .environment(\.layoutDirection, direction)
                .accessibilityHidden(page != 0)
            if let census {
                census
                    .environment(\.layoutDirection, direction)
                    .environment(\.dsGaugeHold, !censusSeen)
                    .accessibilityHidden(page != 1)
            }
        }
        // الإزاحة بإحداثيات ثابتة (يسار ← يمين) ويُحسب الاتجاه العربي يدوياً؛ كل صفحة ترجع لاتجاه التطبيق
        .environment(\.layoutDirection, .leftToRight)
        // أسفل الصفحتين: شريط النقاط داخل المربّع (أو الحشوة نفسها لصفحة واحدة)
        .padding(.bottom, count > 1 ? DS.Hub.pageDotsHeight : DS.Hub.swipePadding)
        .overlay(alignment: .bottom) {
            if count > 1 {
                dots
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous))
        .adminCard(padding: 0)
        .modifier(AdminSwipeGesture(enabled: count > 1, changed: dragged, ended: released))
        .onAppear { if page == 1 { censusSeen = true } }
        .onChange(of: page) { if $0 == 1 { censusSeen = true } }
    }

    // MARK: السحب

    /// يتبع الإصبع (إزاحة فعلية يسار ← يمين) — مقاومة عند الطرفين
    private func dragged(_ x: CGFloat) {
        let forward = rtl ? x : -x
        let atEdge = (forward > 0 && page == count - 1) || (forward < 0 && page == 0)
        dragX = x * (atEdge ? DS.Hub.swipeResistance : 1)
    }

    /// يقلب الصفحة بعد `DS.Hub.swipeDistance` أو برمية سريعة (`thrown` = حيث كانت ستقف)
    private func released(_ x: CGFloat, _ thrownX: CGFloat) {
        let moved = rtl ? x : -x
        let thrown = rtl ? thrownX : -thrownX
        var target = page
        if moved > DS.Hub.swipeDistance || thrown > DS.Hub.swipeDistance * 2 { target += 1 }
        if moved < -DS.Hub.swipeDistance || thrown < -DS.Hub.swipeDistance * 2 { target -= 1 }
        go(min(max(target, 0), count - 1))
    }

    private func go(_ target: Int) {
        if target == 1 { censusSeen = true }
        if target != page { UISelectionFeedbackGenerator().selectionChanged() }
        withAnimation(reduceMotion ? DSMotion.fade : DS.Anim.smooth) {
            stored = target
            dragX = 0
        }
    }

    // MARK: النقاط

    /// نقطتا الصفحة (الحالية كبسولة ذهبية) في شريط أسفل المربّع — الضغط يقلب، والقارئ الصوتي: «الصفحة ١ من ٢: يحتاج
    /// انتباهك» + أعلى/أسفل + «التالي/السابق»
    private var dots: some View {
        HStack(spacing: DS.Spacing.xsm) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == page ? DS.Color.accent : DS.Color.textTertiary.opacity(DS.Opacity.tintStroke))
                    .frame(width: i == page ? DS.Hub.pageDotActive : DS.Hub.pageDot, height: DS.Hub.pageDot)
            }
        }
        .frame(minWidth: DS.Icon.tapTarget, minHeight: DS.Hub.pageDotsHeight)
        .contentShape(Rectangle())
        .onTapGesture { go(page == 0 ? 1 : 0) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("الصفحة \(page + 1) من \(count): \(Self.titles[page])",
                                   "Page \(page + 1) of \(count): \(Self.titles[page])"))
        .accessibilityHint(L10n.t("اسحب لأعلى أو لأسفل للتبديل", "Swipe up or down to switch"))
        .accessibilityAdjustableAction { step in
            switch step {
            case .increment: go(min(page + 1, count - 1))
            case .decrement: go(max(page - 1, 0))
            @unknown default: break
            }
        }
        .accessibilityAction(named: L10n.t("التالي", "Next")) { go(min(page + 1, count - 1)) }
        .accessibilityAction(named: L10n.t("السابق", "Previous")) { go(max(page - 1, 0)) }
    }
}

/// الصفحات جنباً إلى جنب بعرض المربّع وارتفاع أطولها (أو الظاهرة: `matchesHeights = false`)؛ الظاهرة في مكانها والأخرى
/// بجانبها (يساراً في العربية) + إزاحة السحب. إحداثيات يسار ← يمين دائماً (الحاوية تفرضها) والاتجاه العربي من `rtl`
struct AdminPagerLayout: Layout {
    var page: Int
    var drag: CGFloat
    var rtl: Bool
    var matchesHeights = true

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let shown = heights.indices.contains(page) ? heights[page] : 0
        return CGSize(width: width, height: matchesHeights ? heights.max() ?? 0 : shown)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() {
            let step = CGFloat(index - page) * bounds.width
            subview.place(at: CGPoint(x: bounds.minX + (rtl ? -step : step) + drag, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: matchesHeights ? bounds.height : nil))
        }
    }
}

// MARK: - إيماءة السحب الأفقي

/// السحب الأفقي على المربّع: من iOS 18 إيماءة UIKit (`AdminHorizontalPan`)، وقبله `DragGesture` متزامن مع التمرير
private struct AdminSwipeGesture: ViewModifier {
    let enabled: Bool
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            if enabled {
                content.gesture(AdminHorizontalPan(changed: changed, ended: ended))
            } else {
                content
            }
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: DS.Hub.swipeMinimum)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        changed(value.translation.width)
                    }
                    .onEnded { value in ended(value.translation.width, value.predictedEndTranslation.width) },
                including: enabled ? .all : .subviews)
        }
    }
}

/// إيماءة UIKit أفقية فقط: لا تبدأ إن كانت الحركة عمودية (تبقى للتمرير)، وحين تبدأ تُلغي لمس الأزرار تحتها
/// (`cancelsTouchesInView`) — السحب لا يفتح الرقم أو الحلقة التي بدأ عليها
@available(iOS 18.0, *)
private struct AdminHorizontalPan: UIGestureRecognizerRepresentable {
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = true
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let x = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            changed(x)
        case .ended:
            // حيث كانت ستقف الرمية (نفس فكرة `predictedEndTranslation`)
            ended(x, x + recognizer.velocity(in: recognizer.view).x * DS.Hub.swipeThrow)
        case .cancelled, .failed:
            ended(0, 0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y)
        }
    }
}
