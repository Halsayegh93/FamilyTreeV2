import SwiftUI

// MARK: - Admin System Health
// تصميم احترافي بتابين: الأجهزة + الإشعارات
struct AdminSystemHealthView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel

    @State private var selectedTab: HealthTab = .activity
    @Namespace private var tabNamespace

    enum HealthTab: Int, CaseIterable {
        case activity = 0
        case devices = 1
        case push = 2

        var titleAr: String {
            switch self {
            case .activity: return "النشاط"
            case .devices:  return "الأجهزة"
            case .push:     return "الإشعارات"
            }
        }
        var titleEn: String {
            switch self {
            case .activity: return "Activity"
            case .devices:  return "Devices"
            case .push:     return "Push"
            }
        }
        var icon: String {
            switch self {
            case .activity: return "bolt.heart.fill"
            case .devices:  return "iphone.gen3"
            case .push:     return "waveform.path.ecg"
            }
        }
        var color: Color {
            switch self {
            case .activity: return DS.Color.success
            case .devices:  return DS.Color.primary
            case .push:     return DS.Color.info
            }
        }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Premium segmented tab picker ──
                tabPicker
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xs)

                // ── Content ──
                ZStack {
                    switch selectedTab {
                    case .activity:
                        AdminActiveMembersView()
                            .environmentObject(authVM)
                            .environmentObject(memberVM)
                    case .devices:
                        AdminDevicesView()
                            .environmentObject(notificationVM)
                            .environmentObject(memberVM)
                    case .push:
                        AdminPushHealthView()
                            .environmentObject(authVM)
                            .environmentObject(notificationVM)
                    }
                }
                .animation(DS.Anim.snappy, value: selectedTab)
            }
        }
        .navigationTitle(L10n.t("صحة النظام", "System Health"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Tab Picker (premium glass + animated indicator)
    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(HealthTab.allCases, id: \.rawValue) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.textTertiary.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.textTertiary.opacity(0.10), lineWidth: 0.5)
        )
    }

    private func tabButton(_ tab: HealthTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(DS.Anim.snappy) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(DS.Font.scaled(13, weight: .bold))
                Text(L10n.t(tab.titleAr, tab.titleEn))
                    .font(DS.Font.scaled(13, weight: .heavy))
            }
            .foregroundColor(isSelected ? .white : DS.Color.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .fill(tab.color)
                            .matchedGeometryEffect(id: "selectedTabBg", in: tabNamespace)
                            .shadow(color: tab.color.opacity(0.30), radius: 8, x: 0, y: 3)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}
