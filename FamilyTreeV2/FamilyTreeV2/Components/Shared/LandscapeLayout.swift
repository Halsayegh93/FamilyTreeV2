import SwiftUI

/// أدوات تخطيط الوضع الأفقي (Landscape)
///
/// كل ما في هذا الملف مشروط بأن يكون `verticalSizeClass == .compact`
/// (أي جوال بوضع أفقي). في الوضع العمودي يرجع التخطيط الأصلي حرفياً
/// بدون أي تغيير بالبكسل.
enum LandscapeLayout {

    /// أعمدة شبكة: في الوضع الأفقي نستخدم شبكة تكيّفية (أعمدة أكثر)
    /// وفي الوضع العمودي نرجّع نفس الأعمدة الأصلية بلا أي تعديل.
    static func columns(isLandscape: Bool,
                        portrait: [GridItem],
                        minimum: CGFloat,
                        spacing: CGFloat? = nil) -> [GridItem] {
        guard isLandscape else { return portrait }
        return [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .top)]
    }
}

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

    init(spacing: CGFloat = DS.Spacing.md,
         landscapeMinimum: CGFloat = 330,
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

    init(spacing: CGFloat = DS.Spacing.md,
         landscapeMinimum: CGFloat = 330,
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

/// يلفّ المحتوى بـ`ScrollView` في الوضع الأفقي فقط — الوضع العمودي يبقى كما هو.
struct LandscapeScrollWrapper: ViewModifier {
    let isLandscape: Bool

    func body(content: Content) -> some View {
        if isLandscape {
            ScrollView(showsIndicators: false) { content }
        } else {
            content
        }
    }
}

extension View {
    /// يحدّ عرض المحتوى ويوسّطه في الوضع الأفقي فقط (للنماذج الطويلة على شاشة عريضة).
    /// لا يؤثر على الوضع العمودي إطلاقاً.
    @ViewBuilder
    func landscapeReadableWidth(_ isLandscape: Bool, maxWidth: CGFloat = 720) -> some View {
        if isLandscape {
            self.frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            self
        }
    }
}
