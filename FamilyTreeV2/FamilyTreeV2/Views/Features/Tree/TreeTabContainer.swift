import SwiftUI

/// مغلّف لتاب الشجرة — يسمح بالتبديل بين الواجهة الكلاسيكية (TreeView)
/// والتجربة الجديدة (DrillDownTreeView) عبر زر مدمج.
/// التفضيل محفوظ في AppStorage فيتذكّره التطبيق بين الجلسات.
struct TreeTabContainer: View {
    @Binding var selectedTab: Int
    @AppStorage("treeViewMode_useDrillDown") private var useDrillDown = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if useDrillDown {
                    DrillDownTreeView(selectedTab: $selectedTab)
                } else {
                    TreeView(selectedTab: $selectedTab)
                }
            }

            toggleButton
                .padding(.leading, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.lg)
        }
    }

    // MARK: - Toggle Pill

    private var toggleButton: some View {
        HStack(spacing: 0) {
            segment(
                label: L10n.t("الكلاسيكية", "Classic"),
                icon: "tree.fill",
                active: !useDrillDown
            ) {
                withAnimation(DS.Anim.snappy) { useDrillDown = false }
            }
            segment(
                label: L10n.t("التفرّع", "Drill"),
                icon: "rectangle.grid.2x2.fill",
                active: useDrillDown
            ) {
                withAnimation(DS.Anim.snappy) { useDrillDown = true }
            }
        }
        .padding(3)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(DS.Color.primary.opacity(0.20), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 2)
    }

    private func segment(label: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.Font.scaled(13, weight: .bold))
                .foregroundColor(active ? .white : DS.Color.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(active ? DS.Color.primary : Color.clear)
                )
                .accessibilityLabel(label)
        }
        .buttonStyle(DSScaleButtonStyle())
    }
}

