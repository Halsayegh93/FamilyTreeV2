import SwiftUI

/// مغلّف تبويب الشجرة — تبويبان أعلى الشاشة:
/// «شجرة العائلة» (TreeView على بيانات profiles) و«النساء» (WomenTreeView على
/// بيانات women_members المنفصلة). أي تعديل في النساء لا يؤثر على الكلاسيكية.
/// التبويب المختار محفوظ في AppStorage فيتذكّره التطبيق بين الجلسات.
struct TreeTabContainer: View {
    @Binding var selectedTab: Int
    @AppStorage("familyTreeTab") private var familyTreeTab = 0  // 0=العائلة، 1=النساء

    var body: some View {
        Group {
            if familyTreeTab == 1 {
                WomenTreeView(treeTab: $familyTreeTab)
            } else {
                TreeView(selectedTab: $selectedTab, treeTab: $familyTreeTab)
            }
        }
    }
}

/// شريط تبويبات [شجرة العائلة | النساء] — يُعرض داخل صف الأدوات العلوي.
struct FamilyTreeTabBar: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 2) {
            segment(L10n.t("شجرة العائلة", "Family"), 0)
            segment(L10n.t("النساء", "Women"), 1)
        }
        .padding(3)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(DS.Color.primary.opacity(0.20), lineWidth: 1))
        .dynamicTypeSize(.large)   // التبويبات ثابتة الحجم — لا تكبر مع إعداد الهاتف
    }

    private func segment(_ label: String, _ idx: Int) -> some View {
        Button {
            withAnimation(DS.Anim.snappy) { selection = idx }
        } label: {
            Text(label)
                .font(DS.Font.scaled(12, weight: .bold))
                .foregroundColor(selection == idx ? .white : DS.Color.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, DS.Spacing.md)
                .frame(height: 34)
                .background(Capsule().fill(selection == idx ? DS.Color.primary : Color.clear))
        }
        .buttonStyle(.plain)
    }
}
