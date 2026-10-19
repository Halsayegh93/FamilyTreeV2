import SwiftUI

/// مغلّف تاب الشجرة — تبويب علوي [شجرة العائلة / النساء] فقط.
///  - شجرة العائلة دائمًا كلاسيكية (TreeView).
///  - النساء: WomenTreeView.
struct TreeTabContainer: View {
    @Binding var selectedTab: Int
    /// تبويب الشجرة: 0 = شجرة العائلة (كلاسيكية)، 1 = النساء.
    @State private var treeTab = 0
    /// دخول أدوات الشجرة (شريط الأدوات، زر التحديث، الحالة الفارغة) مرة مع أول ظهور
    /// للتبويب — نمط الأخبار والديوانيات (طلب المالك ٢٠٢٦-٠٩-٢٧). يعيش هنا لا في الشجرة:
    /// التبديل «العائلة/النساء» يبني الشجرة من جديد، فلو عاش فيها لأعاد الدخول مع كل تبديل
    /// واختفى الشريط الذي ضُغط عليه لحظة — التبديل يبقى تلاشياً متقاطعاً كما هو.
    @State private var chromeAppeared = false
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel
    /// «شجرة النساء» من قسم «العائلة» في لوحة الإدارة (٢٠٢٦-١٠-٢٠) — يُقرأ عند ظهور التبويب إن لم يكن حياً
    static var openWomenOnAppear = false

    /// «شجرة النساء» ظاهرة؟ — مفتاح في «الإدارة ← إعدادات التطبيق ← الميزات» (طلب المالك ٢٠٢٦-١٠-٠٧)
    private var womenTreeEnabled: Bool { appSettingsVM.settings.womenTreeEnabled ?? true }

    var body: some View {
        Group {
            if treeTab == 1 && womenTreeEnabled {
                WomenTreeView(selectedTab: $selectedTab, treeTab: $treeTab)
            } else {
                // مخفية: شجرة العائلة وحدها بلا مبدّل «العائلة/النساء»
                TreeView(selectedTab: $selectedTab, treeTab: womenTreeEnabled ? $treeTab : nil)
            }
        }
        // أُخفيت والمستخدم على تبويب النساء → يرجع لشجرة العائلة
        .onChange(of: womenTreeEnabled) { enabled in
            if !enabled { treeTab = 0 }
        }
        .environment(\.treeChromeAppeared, chromeAppeared)
        // قسم الشجرة دائماً (العُدّة المشتركة تأخذ لونها من البيئة — هنا مرة لكل الشجرتين)
        .dsSection(.tree)
        .onAppear {
            if Self.openWomenOnAppear {
                Self.openWomenOnAppear = false
                if womenTreeEnabled { treeTab = 1 }
            }
            guard !chromeAppeared else { return }
            chromeAppeared = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openWomenTree)) { _ in
            Self.openWomenOnAppear = false
            if womenTreeEnabled { treeTab = 1 }
        }
        // طلب صلة القرابة يُرسم في شجرة العائلة — من تبويب النساء نرجع لها أولاً
        .onReceive(NotificationCenter.default.publisher(for: .requestKinshipPath)) { _ in
            if treeTab != 0 { treeTab = 0 }
        }
    }
}

/// هل دخلت أدوات الشجرة؟ `true` افتراضياً — الشجرة خارج التبويب تظهر أدواتها مباشرة بلا حركة
private struct TreeChromeAppearedKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var treeChromeAppeared: Bool {
        get { self[TreeChromeAppearedKey.self] }
        set { self[TreeChromeAppearedKey.self] = newValue }
    }
}

/// تبويب [شجرة العائلة / النساء] — المبدّل الواحد `DSSegmentedSwitch` بمقاسه المدمّج (`.compact`: ٣٠، نص ١١،
/// بعرض نصّه — مقاس شريط الأدوات قبل التوحيد). المختار بتعبئة قسم الشجرة (البيئة).
struct FamilyTreeTabBar: View {
    @Binding var selection: Int

    var body: some View {
        DSSegmentedSwitch(options: FamilyTreeTabs.options, selection: $selection, size: .compact)
    }
}

/// نفس التبويب في الشريط الجانبي العمودي (الوضع الأفقي) — شريحتان مصغّرتان من العُدّة (`DSChipButton(.mini)`)
/// فوق بعض بالعنوانين القصيرين «العائلة» / «النساء»
struct FamilyTreeSideTabs: View {
    @Binding var selection: Int

    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            ForEach(FamilyTreeTabs.shortOptions) { option in
                DSChipButton(option.title, isSelected: selection == option.id, size: .mini) {
                    guard selection != option.id else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(DS.Anim.snappy) { selection = option.id }
                }
            }
        }
    }
}

/// خيارا تبويب الشجرة — مكان واحد للنص والرمز
enum FamilyTreeTabs {
    static var options: [DSSegmentOption<Int>] {
        [DSSegmentOption(id: 0, title: L10n.t("شجرة العائلة", "Family"), icon: AppSection.tree.symbol),
         DSSegmentOption(id: 1, title: L10n.t("النساء", "Women"), icon: "person.2.fill")]
    }

    /// العنوانان القصيران للشريط الجانبي الضيّق (الوضع الأفقي): «العائلة» / «النساء»
    static var shortOptions: [DSSegmentOption<Int>] {
        [DSSegmentOption(id: 0, title: L10n.t("العائلة", "Family"), icon: AppSection.tree.symbol),
         DSSegmentOption(id: 1, title: L10n.t("النساء", "Women"), icon: "person.2.fill")]
    }
}

extension View {
    /// بطاقة أدوات الشجرة الزجاجية فوق الكانفس (شجرة العائلة والنساء، الشريط العلوي والجانبي) — مكان واحد:
    /// زجاج النظام + لمسة الطين (`DSClaySkin`) + إطار البطاقة الشعري + ظلّ خفيف.
    /// زواياها ١٦ (`DS.Radius.lg`) كما كانت قبل التوحيد — أنعم من بطاقات الصفحات (١٢) فوق الكانفس
    func treeToolbarCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        return self
            .dsGlass(shape)
            .modifier(DSClaySkin(radius: DS.Radius.lg, glassBacked: true, section: .tree))
            .overlay(shape.strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.cardStroke),
                                        lineWidth: DS.Card.strokeWidth))
            .dsSubtleShadow()
    }
}
