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

    var body: some View {
        Group {
            if treeTab == 1 {
                WomenTreeView(selectedTab: $selectedTab, treeTab: $treeTab)
            } else {
                TreeView(selectedTab: $selectedTab, treeTab: $treeTab)
            }
        }
        .environment(\.treeChromeAppeared, chromeAppeared)
        .onAppear {
            guard !chromeAppeared else { return }
            chromeAppeared = true
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

/// تبويب علوي كبسولي [شجرة العائلة / النساء] — مطابق للأندرويد و iOS الأصلي.
struct FamilyTreeTabBar: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 2) {
            segment(L10n.t("شجرة العائلة", "Family"), 0)
            segment(L10n.t("النساء", "Women"), 1)
        }
        .padding(3)
        .background(DS.Color.surface.opacity(0.8), in: Capsule())   // أغمق (طلب المالك)
        .overlay(Capsule().strokeBorder(DS.Color.primary.opacity(0.25), lineWidth: 1))
        .dsSubtleShadow()
        .dynamicTypeSize(.large)
    }

    private func segment(_ label: String, _ idx: Int) -> some View {
        Button {
            withAnimation(DS.Anim.snappy) { selection = idx }
        } label: {
            Text(label)
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(selection == idx ? .white : DS.Color.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, DS.Spacing.sm)
                .frame(minHeight: 30)                       // مقاس مدمّج أصغر للبار العلوي
                .background(Capsule().fill(selection == idx ? DS.Color.primary : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
