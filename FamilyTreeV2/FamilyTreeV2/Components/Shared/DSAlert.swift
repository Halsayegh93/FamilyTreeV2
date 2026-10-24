import SwiftUI
import UIKit

// MARK: - مربّع الرسائل الموحّد (طلب المالك)
//
// كل رسائل التطبيق التي تظهر في منتصف الشاشة بتصميم واحد — نفس مربّع
// «تم تجاوز حد التعديلات»: بطاقة بزوايا ٢٤، النص كله باتجاه اليمين في العربية،
// وأزرار ممتلئة بعرض البطاقة. بديل مباشر لـ `.alert(...)` بنفس توقيعه:
//     .dsAlert("العنوان", isPresented: $flag) { Button(...) } message: { Text(...) }
// يُعرض في نافذة مستقلّة فوق كل شيء (حتى فوق الأوراق المفتوحة).

// MARK: إغلاق المربّع من الأزرار

private struct DSAlertDismissKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var dsAlertDismiss: () -> Void {
        get { self[DSAlertDismissKey.self] }
        set { self[DSAlertDismissKey.self] = newValue }
    }
}

/// أزرار المربّع: الأساسي بتدرّج القسم (كحلي خارج التبويبات)، الحذف أحمر، الإلغاء رمادي — وكل ضغطة تنفّذ
/// إجراء الزر ثم تغلق المربّع.
///
/// ملاحظة مهمة: كانت الإغلاقة إيماءة لمس داخل ButtonStyle، وإيماءة الابن تتقدّم
/// على إيماءة الزر نفسه — فيُغلق المربّع ولا يُنفَّذ الإجراء (مثل «إزالة الجهاز»).
/// الآن PrimitiveButtonStyle: نستدعي trigger() صراحة ثم نغلق.
private struct DSAlertButtonStyle: PrimitiveButtonStyle {
    @Environment(\.dsAlertDismiss) private var dismiss

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.trigger()
            dismiss()
        } label: {
            configuration.label
        }
        .buttonStyle(DSAlertPressStyle(role: configuration.role))
        // التخطيط يرتّب حسب الدور: الإلغاء في مكان ثابت في كل الرسائل
        .layoutValue(key: DSAlertIsCancelKey.self, value: configuration.role == .cancel)
    }
}

/// شكل زر الرسالة = شكل أزرار كل المربّعات (`DSBoxButtonStyle` في الهيكل الموحّد): الإجراء بلون
/// القسم، الحذف أحمر، الإلغاء رمادي — نفس الارتفاع والزوايا والخط في مربّع العمل
private typealias DSAlertPressStyle = DSBoxButtonStyle

/// هل الزر «إلغاء»؟ — لترتيب موحّد في كل الرسائل
struct DSAlertIsCancelKey: LayoutValueKey {
    static let defaultValue = false
}

/// عنصر ليس زراً (حقل كتابة مثلاً) — يُوضع بعرض كامل فوق الأزرار ولا يُحتسب منها
struct DSAlertIsFieldKey: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// ضعه على حقل داخل `dsAlert`: يعطيه شكل حقول المربّعات (خلفية هادئة وحواف
    /// مستديرة وخط التطبيق)، ويمنع احتسابه زراً (فتبقى قاعدة «زرّان جنب بعض»)
    func dsAlertField() -> some View {
        // نفس شكل «ملاحظات إضافية» في طلبات التعديل (طلب المالك)
        self
            .textFieldStyle(.plain)
            .dsFont(.body)
            .foregroundColor(DS.Color.textPrimary)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.sm)
            .frame(minHeight: 38, alignment: .topLeading)
            // مملوء بخلفية هادئة (نفس رمادي زرّ «إلغاء») بدل الأبيض المحدّد — طلب المالك ٢٠٢٦-١٠-٠٧
            .background(DS.Color.mutedBackground.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .layoutValue(key: DSAlertIsFieldKey.self, value: true)
    }
}

/// زرّان جنب بعض بعرض متساوٍ، وثلاثة فأكثر فوق بعض.
/// الترتيب موحّد مهما كان ترتيب الكود (طلب المالك):
/// «إلغاء» أولاً = يمين في العربية، والإجراء بعده = يسار؛ وفي العمودي «إلغاء» آخراً.
/// تُستخدم أيضاً خارج الرسائل (`DSBoxButtons`) لبطاقات بأزرارها — نفس الصفّ في كل المربّعات.
struct DSAlertButtonsLayout: Layout {
    var spacing: CGFloat = DS.Spacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 280
        let fields = subviews.filter { $0[DSAlertIsFieldKey.self] }
        let buttons = subviews.filter { !$0[DSAlertIsFieldKey.self] }

        var height: CGFloat = 0
        for field in fields {
            height += field.sizeThatFits(ProposedViewSize(width: width, height: nil)).height + spacing
        }
        if buttons.count == 2 {
            let each = (width - spacing) / 2
            height += buttons.map { $0.sizeThatFits(ProposedViewSize(width: each, height: nil)).height }.max() ?? 0
        } else {
            let heights = buttons.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
            height += heights.reduce(0, +) + spacing * CGFloat(max(0, buttons.count - 1))
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let fields = subviews.filter { $0[DSAlertIsFieldKey.self] }
        let buttons = subviews.filter { !$0[DSAlertIsFieldKey.self] }

        // الحقول أولاً بعرض كامل
        var y = bounds.minY
        for field in fields {
            let h = field.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            field.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                        proposal: ProposedViewSize(width: bounds.width, height: h))
            y += h + spacing
        }

        if buttons.count == 2 {
            let each = (bounds.width - spacing) / 2
            let h = max(bounds.maxY - y, 0)
            // «إلغاء» في الجهة اليسرى والإجراء في الجهة الأخرى (طلب المالك)
            let ordered = buttons.sorted { a, b in !a[DSAlertIsCancelKey.self] && b[DSAlertIsCancelKey.self] }
            for (i, view) in ordered.enumerated() {
                let x = bounds.minX + CGFloat(i) * (each + spacing)
                view.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                           proposal: ProposedViewSize(width: each, height: h))
            }
            return
        }
        // عمودياً: الإجراءات أولاً ثم الإلغاء في الأسفل
        let ordered = buttons.sorted { a, b in !a[DSAlertIsCancelKey.self] && b[DSAlertIsCancelKey.self] }
        for view in ordered {
            let h = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            view.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                       proposal: ProposedViewSize(width: bounds.width, height: h))
            y += h + spacing
        }
    }
}

// MARK: البطاقة

/// بطاقة المربّع الوسطي — تُستخدم للرسائل ولمربّعات خاصة (مثل «عن التطبيق»)
struct DSCenterCard<Content: View>: View {
    /// «تقليل الحركة» (توصية أبل): تلاشٍ فقط بلا تكبير ولا انزلاق
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onBackgroundTap: (() -> Void)?
    /// المحتوى يدخل بعد البطاقة (تلاشٍ + صعود خفيف) — false لمحتوى يُدخل عناصره
    /// تباعاً بنفسه (مثل رسائل dsAlert: العنوان ← النص ← الأزرار)
    var animatesContent: Bool = true
    /// عنوان البطاقة وأيقونته: يرسمان الرأس المضغوط (`DSComposerHeader(compact:)`) بلون القسم أعلى
    /// البطاقة — نفس رأس مربّع العمل بأصغر. nil = بلا رأس (شريط رفيع بلون القسم فقط)
    var title: String? = nil
    var icon: String? = nil
    /// وضع العرض: المحتوى كله يتمرّر داخل البطاقة إن لم يتّسع — false لمحتوى يمرّر جزءه الطويل بنفسه
    /// (رسائل dsAlert: النص يتمرّر والأزرار ثابتة)
    var scrollsContent: Bool = true
    @ViewBuilder let content: () -> Content
    @State private var appeared = false
    /// لون القسم للشريط الرفيع — من الواجهة التي فتحتها، واحتياطاً القسم المختار ثم كحلي العلامة
    @Environment(\.dsSection) private var section
    private var accentTint: Color { (section ?? AppSection.current)?.fill ?? DS.Color.actionNavy }
    /// وضع العرض: البطاقة أعرض (فتقصر)، ولا تتجاوز الارتفاع المتاح — إن طال محتواها يتمرّر داخلها
    @Environment(\.dsLandscape) private var landscape

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture { onBackgroundTap?() }

            VStack(spacing: 0) {
                if let title {
                    // الرأس المضغوط: نفس تدرّج رأس العمل وتعتيمه في الداكن، المجسّم والعنوان بالأبيض
                    DSComposerHeader(title: title, subtitle: "",
                                     icon: icon ?? DSBox.defaultIcon(for: section ?? AppSection.current),
                                     tint: DS.Color.actionNavy, compact: true)
                }
                // أفقياً: على قدر محتواه، وإن لم يتّسع يتمرّر داخل البطاقة
                if scrollsContent {
                    cardBody
                        .dsLandscapeFitScroll()
                } else {
                    cardBody
                }
            }
            .frame(maxWidth: landscape ? DS.Landscape.alertMaxWidth : DSBox.alertMaxWidth)
            .background(DS.Color.background)
            // بلا رأس: شريط رفيع بلون القسم أعلى البطاقة
            .overlay(alignment: .top) {
                if title == nil {
                    Rectangle()
                        .fill(LinearGradient(colors: [accentTint, accentTint.dsHeroLight],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: DSBox.accentHeight)
                        .allowsHitTesting(false)
                }
            }
            .dsBoxChrome()
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.vertical, landscape ? DS.Landscape.panelMargin : 0)
            .scaleEffect(appeared || reduceMotion ? 1 : DSMotion.panelScale)
            // نفس فتح المربّعات: يصعد قليلاً إلى مكانه وهو يكبر
            .offset(y: appeared || reduceMotion ? 0 : DSMotion.panelRise)
            .opacity(appeared ? 1 : 0)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear { withAnimation(reduceMotion ? DSMotion.fade : DSMotion.panel) { appeared = true } }
    }

    /// محتوى البطاقة تحت رأسها
    private var cardBody: some View {
        VStack(alignment: .leading, spacing: DSBox.alertSpacing) {
            content()
        }
        .environment(\.dsInCenterBox, true)
        // نفس لغة المربّعات: البطاقة تكبر، ثم محتواها يصعد بهدوء داخلها
        .dsEntrance(delay: 0.05, y: 8, animation: DSMotion.text, active: animatesContent)
        .padding(DSBox.alertPadding)
        .padding(.top, title == nil ? DSBox.accentHeight : 0)
    }
}

/// تعتيم ما خلف المربّع بالمنتصف (`DSCenterPanel(dim:)`)
enum DSCenterPanelDim {
    static let standard: Double = 0.45
    /// مربّعا تفاصيل المشروع والمكتبة (طلب المالك ٢٠٢٦-١٠-٢٣ «الخلفية أغمق شوي») — القائمة خلفه بوضوح
    static let strong: Double = 0.6
}

/// لوح كبير بمنتصف الشاشة — لمحتوى طويل (نموذج) بدل الورقة السفلية.
/// نفس روح `DSCenterCard` لكنه أوسع وأطول، ومحتواه يتمرّر داخله.
struct DSCenterPanel<Content: View>: View {
    /// «تقليل الحركة» (توصية أبل): تلاشٍ فقط بلا تكبير ولا انزلاق
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onBackgroundTap: (() -> Void)?
    /// يجعل ارتفاع اللوح على قدر محتواه (يقرأ `SheetContentHeightKey` من الداخل)
    /// بدل الارتفاع الكامل — طلب المالك لمربّعات «طلب تعديل».
    var hugsContent: Bool = false
    /// تعتيم ما خلف المربّع — ٠٫٤٥ للكل؛ مربّعا تفاصيل المشروع والمكتبة أغمق (`DSCenterPanelDim.strong`)
    var dim: Double = DSCenterPanelDim.standard
    @ViewBuilder let content: () -> Content
    @State private var appeared = false
    @State private var contentHeight: CGFloat = 0
    /// لون القسم داخل المربّع — من الواجهة التي فتحته، واحتياطاً القسم المختار
    @Environment(\.dsSection) private var section
    /// وضع العرض: المربّع أعرض ويأخذ الارتفاع كله تقريباً (الشاشة ~٤٠٠ نقطة)
    @Environment(\.dsLandscape) private var landscape
    /// `dsCenterBox` يُغلق: المربّع يصغر وينزل قليلاً ويتلاشى التعتيم قبل إغلاق الغطاء
    @Environment(\.dsPanelDismissing) private var dismissing

    /// ارتفاع اللوح: على قدر المحتوى (+ شريط العنوان) وبحدّ أقصى 86% من الشاشة
    /// (أفقياً: الارتفاع المتاح ناقص هامش صغير — يبقى الرأس والأزرار ظاهرين والوسط يتمرّر)
    private func panelHeight(_ geo: GeometryProxy) -> CGFloat {
        let cap = landscape ? geo.size.height - DS.Landscape.panelMargin * 2
                            : min(geo.size.height * 0.86, geo.size.height - DS.Spacing.xxl)
        guard hugsContent, contentHeight > 0 else { return cap }
        return min(contentHeight + DS.Spacing.lg, cap)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(appeared ? dim : 0)
                    .ignoresSafeArea()
                    .onTapGesture { onBackgroundTap?() }

                content()
                    .environment(\.dsInCenterBox, true)
                    .dsSection(section ?? AppSection.current)
                    .onPreferenceChange(SheetContentHeightKey.self) { h in
                        guard h > 0 else { return }
                        contentHeight = h
                        // أول قياس: يظهر بعده مباشرة (الإطار التالي) وبحجمه الصحيح
                        if !appeared { DispatchQueue.main.async { reveal() } }
                    }
                    .frame(
                        width: min(geo.size.width - DS.Spacing.lg * 2, landscape ? DS.Landscape.panelMaxWidth : 520),
                        height: panelHeight(geo)
                    )
                    // الهيكل الموحّد: زوايا + إطار + ظلّ (أعمق للوح الكبير)
                    .dsBoxChrome(strong: true)
                    // يكبر من ٠٫٩٤ صاعداً قليلاً مع تلاشٍ — ثم يبدأ تسلسل محتواه (DSMotion)؛
                    // وعند الإغلاق يصغر وينزل قليلاً
                    .scaleEffect(appeared || reduceMotion ? 1 : (dismissing ? DSMotion.panelOutScale : DSMotion.panelScale))
                    .offset(y: appeared || reduceMotion ? 0 : (dismissing ? DSMotion.panelOutDrop : DSMotion.panelRise))
                    .opacity(appeared ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear {
            // المربّع المحتضن لمحتواه ينتظر قياس ارتفاعه (إطاراً أو اثنين) فلا يُرى
            // يتغيّر حجمه وهو يظهر — واحتياطاً يظهر بعد لحظة إن لم يصل قياس
            if hugsContent {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { reveal() }
            } else {
                reveal()
            }
        }
        .onChange(of: dismissing) { out in
            if out {
                withAnimation(reduceMotion ? DSMotion.fade : DSMotion.panelOut) { appeared = false }
            } else {
                reveal()
            }
        }
    }

    private func reveal() {
        guard !appeared, !dismissing else { return }
        withAnimation(reduceMotion ? DSMotion.fade : DSMotion.panel) { appeared = true }
    }
}

extension View {
    /// يبلّغ DSCenterPanel(hugsContent:) بارتفاع المحتوى القابل للتمرير — ضعه على
    /// الـVStack داخل ScrollView، و[extra] لشريط العنوان فوقه.
    func dsPanelContentHeight(extra: CGFloat = 60) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: SheetContentHeightKey.self, value: geo.size.height + extra)
        })
    }
}

/// إغلاق المربّع بحركة — يستدعيه المحتوى بدل dismiss() المباشر
private struct DSPanelCloseKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var dsPanelClose: (() -> Void)? {
        get { self[DSPanelCloseKey.self] }
        set { self[DSPanelCloseKey.self] = newValue }
    }
}

/// `dsCenterBox` يُغلق — `DSCenterPanel` يؤدّي حركة الخروج قبل إغلاق الغطاء
private struct DSPanelDismissingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var dsPanelDismissing: Bool {
        get { self[DSPanelDismissingKey.self] }
        set { self[DSPanelDismissingKey.self] = newValue }
    }
}

/// ارتفاع الجزء الظاهر في المربّع المصغّر (يُبلِّغه المحتوى)
struct DSPanelCollapsedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// لوح بمنتصف الشاشة قابل للتوسّع مثل الشيت (طلب المالك): يبدأ مضغوطاً،
/// ويتوسّع ويتصغّر عبر `isExpanded` (زر داخل المحتوى)، ويُغلق بالضغط خارجه.
struct DSExpandableCenterPanel<Content: View>: View {
    /// «تقليل الحركة» (توصية أبل): تلاشٍ فقط بلا تكبير ولا انزلاق
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isExpanded: Bool
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var appeared = false
    /// أثناء الإغلاق: حركة أخف (تصغير بسيط) من حركة الفتح
    @State private var closing = false
    /// ارتفاع المحتوى كاملاً (`SheetContentHeightKey`) — للموسّع
    @State private var contentHeight: CGFloat = 0
    /// ارتفاع الرأس فقط (`DSPanelCollapsedHeightKey`) — للمصغّر؛ المحتوى يبقى ويُقصّ
    @State private var collapsedHeight: CGFloat = 0
    /// لون القسم داخل المربّع — من الواجهة التي فتحته، واحتياطاً القسم المختار
    @Environment(\.dsSection) private var section
    /// وضع العرض: أعرض، والارتفاع المتاح ناقص هامش صغير
    @Environment(\.dsLandscape) private var landscape

    var body: some View {
        GeometryReader { geo in
            // المصغّر والموسّع كلاهما على قدر المحتوى بلا فراغ زائد (طلب المالك)،
            // وبحد أقصى 90% من الشاشة — والباقي يتمرّر داخل المربّع
            let cap = landscape ? geo.size.height - DS.Landscape.panelMargin * 2 : geo.size.height * 0.9
            let fallback = isExpanded ? cap : min(geo.size.height * 0.52, 470)
            let measured = isExpanded ? contentHeight
                                      : (collapsedHeight > 0 ? collapsedHeight : contentHeight)
            let height = measured > 0 ? min(measured, cap) : fallback

            ZStack {
                Color.black.opacity(appeared ? 0.45 : 0)
                    .ignoresSafeArea()
                    .onTapGesture(perform: animatedClose)

                VStack(spacing: 0) {
                    // بلا مقبض ولا ×: التوسيع بزر داخل المحتوى، والإغلاق بالضغط خارجه (طلب المالك)
                    content()
                        .environment(\.dsInCenterBox, true)
                        .dsSection(section ?? AppSection.current)
                        .onPreferenceChange(SheetContentHeightKey.self) { h in
                            if h > 0 { contentHeight = h }
                        }
                        .onPreferenceChange(DSPanelCollapsedHeightKey.self) { h in
                            if h > 0 { collapsedHeight = h }
                        }
                        // المحتوى تحت رأس ملوّن (تفاصيل العضو) — أقسامه تدخل بعد الرأس (DSMotion)
                        .environment(\.dsStaggerBase, DSMotion.sectionsAfterHeader)
                }
                .frame(width: min(geo.size.width - DS.Spacing.lg * 2, landscape ? DS.Landscape.panelMaxWidth : 520),
                       height: height)
                .background(DS.Color.background)
                .dsBoxChrome(strong: true)
                // فتح/إغلاق بحركة: يكبر من أصغر وأسفل قليلاً مع تلاشٍ (طلب المالك)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.9)
                .offset(y: appeared || reduceMotion ? 0 : (closing ? 18 : 20))
                .opacity(appeared ? 1 : 0)
                // الارتفاع الفعلي يتحرّك بسلاسة — يصل بعد قياس المحتوى الجديد
                // («تقليل الحركة»: يتبدّل مباشرة بلا تمدّد)
                .animation(reduceMotion ? nil : DS.Anim.smooth, value: height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .environment(\.dsPanelClose, animatedClose)
        .onAppear {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2)
                                       : .spring(response: 0.4, dampingFraction: 0.8)) { appeared = true }
        }
    }

    /// يصغّر المربّع ويخفيه ثم يغلقه — والإغلاق نفسه بلا انزلاق النظام من
    /// الأسفل (كانت الطبقة الفارغة تنزلق بعد اختفاء المربّع فيبدو الإغلاق مكسوراً)
    private func animatedClose() {
        guard appeared else { return }
        closing = true
        // هادئة وأوضح (طلب المالك): تلاشٍ مع تصغير ونزول ملحوظين
        withAnimation(.easeInOut(duration: 0.42)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { onClose() }
        }
    }
}

/// محتوى رسالة: رأس مضغوط (عنوان + مجسّم) + نص + أزرار (أو «حسناً» إن لم تُمرَّر أزرار) — على
/// الهيكل الموحّد: نفس بطاقة مربّع العمل ورأسه بأصغر
private struct DSAlertBody<A: View, M: View>: View {
    let title: String
    let actions: A
    let message: M?
    let onDismiss: () -> Void
    /// لحظة فرح فوق العنوان (طلب المالك ٢٠٢٦-١٠-٠٥) — nil = الرسالة كما كانت
    var moment: FTMoments.Moment? = nil
    /// أيقونة الرأس — nil = أيقونة القسم (`DSBox.defaultIcon`)
    var icon: String? = nil
    @Environment(\.dsSection) private var section

    var body: some View {
        // نفس لغة المربّعات: البطاقة تكبر ← العنوان ← النص ← الأزرار آخراً
        // الرأس المضغوط (عنوان + مجسّم القسم أو `icon`) من البطاقة نفسها — ثم النص والأزرار
        DSCenterCard(onBackgroundTap: nil, animatesContent: false, title: title, icon: icon, scrollsContent: false) {
            if let moment {
                FTMomentView(moment: moment, tint: section?.fill ?? DS.Color.actionNavy)
                    .frame(height: 112)
                    .frame(maxWidth: .infinity)
            }

            if let message {
                message
                    .font(DSBox.alertBodyFont)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    // وضع العرض: النص الطويل يتمرّر والأزرار تحته ثابتة
                    .dsLandscapeFitScroll()
                    .dsEntrance(delay: 0.09, y: 8, animation: DSMotion.text)
            }

            DSAlertButtonsLayout {
                if A.self == EmptyView.self {
                    Button(L10n.t("حسناً", "OK")) {}
                } else {
                    actions
                }
            }
            .textFieldStyle(.plain)
            .buttonStyle(DSAlertButtonStyle())
            .environment(\.dsAlertDismiss, onDismiss)
            .padding(.top, DS.Spacing.xs)
            .dsEntrance(delay: 0.14, y: DSMotion.footerRise, animation: DSMotion.footer)
        }
    }
}

extension DSBox {
    /// أيقونة قرص التنبيه حين لا تُمرَّر: رمز القسم (ويرسمه «مجسّمات» بمجسّم القسم)
    static func defaultIcon(for section: AppSection?) -> String {
        // مجسّم القسم من مكانه الواحد (`AppSection.artIcon` — الديوانيات «مجلس»)
        section?.artIcon ?? "bell.fill"
    }
}

/// صفّ أزرار المربّعات لبطاقات خارج `dsAlert` (تاريخ، اختيار…): نفس الترتيب والشكل —
/// ضع الأزرار بأدوارها (`.cancel`/`.destructive`) وسيأخذ كلٌّ شكله من `DSBoxButtonStyle`
struct DSBoxButtons<Content: View>: View {
    /// مقاس الصفّ — ٤٠ في المربّعات والصفحات، و`.large` (٤٨) للإجراء الرئيسي في شاشات ملء الشاشة
    var size: DSButtonSize = .regular
    @ViewBuilder let content: () -> Content

    var body: some View {
        DSAlertButtonsLayout { content() }
            .buttonStyle(DSBoxRoleButtonStyle(size: size))
    }
}

/// يمرّر دور الزر إلى `DSBoxButtonStyle` ويعلّم «إلغاء» للترتيب الموحّد
private struct DSBoxRoleButtonStyle: PrimitiveButtonStyle {
    var size: DSButtonSize = .regular

    func makeBody(configuration: Configuration) -> some View {
        Button(action: configuration.trigger) { configuration.label }
            .buttonStyle(DSBoxButtonStyle(role: configuration.role, size: size))
            .layoutValue(key: DSAlertIsCancelKey.self, value: configuration.role == .cancel)
    }
}

// MARK: نافذة العرض — فوق كل شيء

@MainActor
final class DSPopupPresenter {
    static let shared = DSPopupPresenter()
    private var window: UIWindow?
    private var token = UUID()
    /// النافذة الرئيسية قبل العرض — تعود «مفتاحاً» بعد الإغلاق (للوحة المفاتيح والتركيز)
    private weak var previousKey: UIWindow?

    /// يعرض في النافذة المستقلّة بلون القسم المختار (`AppSection.current`)
    func show<V: View>(_ view: V) -> UUID {
        show(view, section: AppSection.current)
    }

    /// `section`: لون القسم داخل النافذة المستقلّة (لا تصلها بيئة التطبيق)
    func show<V: View>(_ view: V, section: AppSection?) -> UUID {
        let id = UUID()
        token = id
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return id }
        if window == nil { previousKey = scene.windows.first(where: \.isKeyWindow) }
        let host = UIHostingController(rootView: AnyView(view.environment(\.dsInCenterBox, true).dsSection(section)))
        host.view.backgroundColor = .clear
        let w = window ?? UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear
        w.rootViewController = host
        // نافذة المربّع منفصلة عن نافذة التطبيق، فلازم تأخذ نفس المظهر
        // (كانت تنسخه من النافذة «المفتاح» — وهي قد تكون نافذة شيت بلا نمط،
        // فيظهر المربّع أبيض والتطبيق داكن)
        w.overrideUserInterfaceStyle = DSPopupPresenter.appInterfaceStyle(in: scene)
        w.makeKeyAndVisible()
        window = w
        return id
    }

    /// مظهر التطبيق: إعداد المستخدم أولاً، وإلا نمط نافذة التطبيق الرئيسية
    static func appInterfaceStyle(in scene: UIWindowScene) -> UIUserInterfaceStyle {
        let chosen = AppAppearance.style(for: UserDefaults.standard.string(forKey: AppAppearance.storageKey))
        if chosen != .unspecified { return chosen }
        // «تلقائي»: اتبع نافذة التطبيق (قد تكون مفروضة من مكان آخر)
        if let main = scene.windows.first(where: { $0.rootViewController is UIHostingController<AnyView> == false }),
           main.overrideUserInterfaceStyle != .unspecified {
            return main.overrideUserInterfaceStyle
        }
        return .unspecified
    }

    /// يُخفي النافذة إن كانت ما زالت تعرض المربّع صاحب هذا المعرّف — بتلاشٍ قصير (طلب المالك
    /// ٢٠٢٦-١٠-٢٤ «حركات بالإغلاق»)؛ عرض جديد أثناء التلاشي يأخذ نافذة جديدة
    func hide(_ id: UUID) {
        guard id == token, let w = window else { return }
        window = nil
        previousKey?.makeKey()
        w.isUserInteractionEnabled = false
        UIView.animate(withDuration: DSMotion.popupOutDuration, delay: 0, options: [.curveEaseIn]) {
            w.alpha = 0
        } completion: { _ in
            w.isHidden = true
            w.rootViewController = nil
        }
    }
}

private final class DSAlertLatest<A: View, M: View> {
    /// العنوان أيضاً من أحدث رسم (م-١ فحص ٢٠٢٦-١٠-٠٧): كان يُقرأ من الرسم السابق فيظهر فارغاً
    /// («تجميد حساب فلان؟» بلا اسم) أو قديماً («تم الربط بنجاح» فوق رسالة فشل)
    var title: String?
    /// ولحظة الفرح والأيقونة كذلك — لا تظهر لحظة «نجاح» فوق نتيجة فشل
    var moment: FTMoments.Moment??
    var icon: String??
    var actions: (() -> A)?
    var message: (() -> M)??
}

private struct DSAlertModifier<A: View, M: View>: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let actions: () -> A
    let message: (() -> M)?
    var moment: FTMoments.Moment? = nil
    var icon: String? = nil
    @State private var shownID: UUID?
    /// أحدث نسخة من الأزرار والنص — onChange يلتقط قيم الرسم السابق، فالرسالة
    /// المبنية من بيانات (presenting) كانت تظهر بالعنوان فقط لأن البيانات nil وقتها
    @State private var latest = DSAlertLatest<A, M>()
    /// زر الإجراء في الرسالة بلون قسم الواجهة التي أظهرتها
    @Environment(\.dsSection) private var section

    func body(content: Content) -> some View {
        latest.title = title
        latest.moment = .some(moment)
        latest.icon = .some(icon)
        latest.actions = actions
        latest.message = message
        return content
            .onChange(of: isPresented) { presented in
                presented ? present() : dismissWindow()
            }
            .onAppear { if isPresented { present() } }
            .onDisappear { dismissWindow() }
    }

    private func present() {
        let binding = $isPresented
        let view = DSAlertBody(
            title: latest.title ?? title,
            actions: (latest.actions ?? actions)(),
            message: (latest.message ?? message)?(),
            onDismiss: {
                // بعد ظهور أثر الضغط — ثم تُغلق النافذة عبر onChange
                DispatchQueue.main.async { binding.wrappedValue = false }
            },
            moment: latest.moment ?? moment,
            icon: latest.icon ?? icon
        )
        shownID = DSPopupPresenter.shared.show(view, section: section ?? AppSection.current)
    }

    private func dismissWindow() {
        guard let id = shownID else { return }
        DSPopupPresenter.shared.hide(id)
        shownID = nil
    }
}

extension View {
    /// بديل `.alert` بتصميم التطبيق الموحّد (عنوان + أزرار). `icon`: أيقونة القرص الصغير
    /// (nil = أيقونة القسم)
    func dsAlert<A: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        moment: FTMoments.Moment? = nil,
        icon: String? = nil,
        @ViewBuilder actions: @escaping () -> A
    ) -> some View {
        modifier(DSAlertModifier<A, EmptyView>(title: title, isPresented: isPresented,
                                                actions: actions, message: nil, moment: moment, icon: icon))
    }

    /// بديل `.alert` بتصميم التطبيق الموحّد (عنوان + أزرار + نص)
    func dsAlert<A: View, M: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        moment: FTMoments.Moment? = nil,
        icon: String? = nil,
        @ViewBuilder actions: @escaping () -> A,
        @ViewBuilder message: @escaping () -> M
    ) -> some View {
        modifier(DSAlertModifier(title: title, isPresented: isPresented,
                                 actions: actions, message: message, moment: moment, icon: icon))
    }

    /// بديل `.alert(presenting:)` — الأزرار والنص يُبنيان من البيانات المعروضة
    func dsAlert<T, A: View, M: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> A,
        @ViewBuilder message: @escaping (T) -> M
    ) -> some View {
        modifier(DSAlertModifier(title: title, isPresented: isPresented,
                                 actions: { data.map(actions) },
                                 message: { data.map(message) }))
    }

    /// بديل `.alert(presenting:)` بلا نص
    func dsAlert<T, A: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> A
    ) -> some View {
        modifier(DSAlertModifier<A?, EmptyView>(title: title, isPresented: isPresented,
                                                 actions: { data.map(actions) }, message: nil))
    }
}
