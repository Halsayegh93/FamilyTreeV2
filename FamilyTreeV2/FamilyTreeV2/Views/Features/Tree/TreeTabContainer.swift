import SwiftUI

/// مغلّف تاب الشجرة — تبويب علوي [شجرة العائلة / النساء] فقط.
///  - شجرة العائلة دائمًا كلاسيكية (TreeView).
///  - النساء: WomenTreeView.
struct TreeTabContainer: View {
    @Binding var selectedTab: Int
    /// تبويب الشجرة: 0 = شجرة العائلة (كلاسيكية)، 1 = النساء.
    @State private var treeTab = 0

    var body: some View {
        Group {
            if treeTab == 1 {
                WomenTreeView(selectedTab: $selectedTab, treeTab: $treeTab)
            } else {
                TreeView(selectedTab: $selectedTab, treeTab: $treeTab)
            }
        }
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
        .background(DS.Color.surface.opacity(0.55), in: Capsule())  // مخفف — مائل للشفاف
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
