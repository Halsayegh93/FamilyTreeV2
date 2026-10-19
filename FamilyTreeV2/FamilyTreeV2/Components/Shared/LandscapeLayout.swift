import SwiftUI

/// حاوية تعرض المحتوى:
/// - عمودياً (VStack) في الوضع العمودي — مطابق تماماً للسلوك السابق.
/// - على شكل شبكة تكيّفية (عمودين أو أكثر) في الوضع الأفقي لاستغلال العرض.
///
/// تُستخدم للبطاقات/الأقسام الطويلة في الشاشات الإدارية والملف الشخصي.
struct AdaptiveCardStack<Content: View>: View {
    @Environment(\.verticalSizeClass) private var vSizeClass

    private let spacing: CGFloat
    /// أقل عرض للعمود في الوضع الأفقي — يحدد عدد الأعمدة تلقائياً حسب الجهاز
    private let landscapeMinimum: CGFloat
    private let alignment: HorizontalAlignment
    private let content: () -> Content

    init(spacing: CGFloat = DS.Landscape.columnSpacing,
         landscapeMinimum: CGFloat = DS.Landscape.columnMinWidth,
         alignment: HorizontalAlignment = .center,
         @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.landscapeMinimum = landscapeMinimum
        self.alignment = alignment
        self.content = content
    }

    private var isLandscape: Bool { vSizeClass == .compact }

    var body: some View {
        if isLandscape {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: landscapeMinimum), spacing: spacing, alignment: .top)],
                alignment: alignment,
                spacing: spacing
            ) {
                content()
            }
        } else {
            VStack(alignment: alignment, spacing: spacing) {
                content()
            }
        }
    }
}

/// نسخة كسولة من `AdaptiveCardStack` للقوائم الطويلة:
/// - `LazyVStack` في الوضع العمودي (مطابق تماماً للسابق).
/// - `LazyVGrid` تكيّفية (عمودان أو أكثر) في الوضع الأفقي.
struct AdaptiveLazyStack<Content: View>: View {
    @Environment(\.verticalSizeClass) private var vSizeClass

    private let spacing: CGFloat
    private let landscapeMinimum: CGFloat
    private let alignment: HorizontalAlignment
    private let content: () -> Content

    init(spacing: CGFloat = DS.Landscape.columnSpacing,
         landscapeMinimum: CGFloat = DS.Landscape.columnMinWidth,
         alignment: HorizontalAlignment = .center,
         @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.landscapeMinimum = landscapeMinimum
        self.alignment = alignment
        self.content = content
    }

    private var isLandscape: Bool { vSizeClass == .compact }

    var body: some View {
        if isLandscape {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: landscapeMinimum), spacing: spacing, alignment: .top)],
                alignment: alignment,
                spacing: spacing
            ) {
                content()
            }
        } else {
            LazyVStack(alignment: alignment, spacing: spacing) {
                content()
            }
        }
    }
}

// MARK: - عمود القراءة (يقرأ الوضع من البيئة)

private struct DSLandscapeReadable: ViewModifier {
    var maxWidth: CGFloat
    @Environment(\.dsLandscape) private var landscape

    func body(content: Content) -> some View {
        if landscape {
            content.frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    /// أفقياً: المحتوى بعمود قراءة متوسّط (`DS.Landscape.maxContentWidth`) بدل التمدّد عبر الشاشة.
    /// العمودي كما هو تماماً.
    func dsLandscapeReadable(maxWidth: CGFloat = DS.Landscape.maxContentWidth) -> some View {
        modifier(DSLandscapeReadable(maxWidth: maxWidth))
    }
}

// MARK: - صفحة كاملة تتمرّر أفقياً

private struct DSLandscapeScroll: ViewModifier {
    @Environment(\.dsLandscape) private var landscape

    func body(content: Content) -> some View {
        if landscape {
            ScrollView(showsIndicators: false) {
                content.padding(.vertical, DS.Spacing.lg)
            }
        } else {
            content
        }
    }
}

extension View {
    /// أفقياً: الصفحة الثابتة (أيقونة + نص + أزرار بفراغات مرنة) تتمرّر بدل أن يُقصّ نصّها أو أزرارها.
    /// العمودي كما هو تماماً.
    func dsLandscapeScroll() -> some View {
        modifier(DSLandscapeScroll())
    }
}

// MARK: - محتوى مربّع يتمرّر إن لم يتّسع الارتفاع

private struct DSLandscapeFitScroll: ViewModifier {
    @Environment(\.dsLandscape) private var landscape
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        if landscape {
            // نسخة واحدة من المحتوى (حقول الكتابة وتركيزها كما هي): على قدر ارتفاعه، ويتمرّر إن ضاق المكان
            ScrollView(showsIndicators: false) {
                content.readHeight($height)
            }
            .frame(maxHeight: height)
        } else {
            content
        }
    }
}

extension View {
    /// أفقياً: محتوى البطاقة/المربّع على قدر ارتفاعه ويتمرّر داخلها إن لم يتّسع (الرأس والأزرار حولها ثابتة).
    /// العمودي كما هو تماماً.
    func dsLandscapeFitScroll() -> some View {
        modifier(DSLandscapeFitScroll())
    }
}

// MARK: - فراغ فوق شريط التبويبات العائم (مكان واحد)

private struct DSTabBarClearance: ViewModifier {
    @Environment(\.dsLandscape) private var landscape

    func body(content: Content) -> some View {
        // حشوة صفر عمودياً (لا تغيّر التخطيط ولا هوية العرض عند التدوير)
        content.padding(.bottom, landscape ? DS.Landscape.tabBarClearance : 0)
    }
}

extension View {
    /// أفقياً: فراغ `DS.Landscape.tabBarClearance` أسفل محتوى صفحة التبويب المتمرّر — آخر صفّ لا يختفي تحت
    /// شريط التبويبات العائم (الرئيسية، الديوانيات، حسابي، الإدارة). العمودي كما هو تماماً.
    func dsTabBarClearance() -> some View {
        modifier(DSTabBarClearance())
    }
}
