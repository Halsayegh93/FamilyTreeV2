import SwiftUI
import Supabase

// MARK: - Admin System Health
// تصميم احترافي بتابين: الأجهزة + الإشعارات
struct AdminSystemHealthView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel

    @State private var selectedTab: HealthTab = .errors
    @Namespace private var tabNamespace
    @State private var operations: OperationsHealth?
    @State private var operationsError: String?
    @State private var loadingOperations = false
    private struct OperationsHealth: Decodable {
        let cron_failures: Int
        let http_failures: Int
        let pending_deletions: Int
    }

    enum HealthTab: Int, CaseIterable {
        case errors = 3
        case activity = 0
        case devices = 1
        case push = 2

        var titleAr: String {
            switch self {
            case .errors: return "الأخطاء"
            case .activity: return "النشاط"
            case .devices:  return "الأجهزة"
            case .push:     return "الإشعارات"
            }
        }
        var titleEn: String {
            switch self {
            case .errors: return "Errors"
            case .activity: return "Activity"
            case .devices:  return "Devices"
            case .push:     return "Push"
            }
        }
        var icon: String {
            switch self {
            case .errors: return "exclamationmark.bubble.fill"
            case .activity: return "bolt.heart.fill"
            case .devices:  return "iphone.gen3"
            case .push:     return "waveform.path.ecg"
            }
        }
        var color: Color {
            switch self {
            case .errors: return DS.Color.warning
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
                if authVM.isAdmin {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        HStack {
                            Text(L10n.t("حالة التشغيل — آخر ٢٤ ساعة", "Operations — last 24 hours"))
                                .font(DS.Font.calloutBold)
                            Spacer()
                            Button { Task { await loadOperations() } } label: {
                                if loadingOperations { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                            }.disabled(loadingOperations)
                        }
                        if let operations {
                            Text(L10n.t("مهام فاشلة: \(operations.cron_failures) • اتصالات فاشلة: \(operations.http_failures) • حذف يحتاج متابعة: \(operations.pending_deletions)", "Failed jobs: \(operations.cron_failures) • Failed HTTP: \(operations.http_failures) • Pending deletions: \(operations.pending_deletions)"))
                                .font(DS.Font.caption1)
                        }
                        if let operationsError { Text(operationsError).font(DS.Font.caption1).foregroundStyle(DS.Color.textSecondary) }
                    }.padding(DS.Spacing.md)
                }
                // ── Premium segmented tab picker ──
                tabPicker
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xs)

                // ── Content ──
                ZStack {
                    switch selectedTab {
                    case .errors:
                        if authVM.isAdmin { AdminAppErrorsView() }
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
        .task {
            if authVM.isAdmin { await loadOperations() }
            else { selectedTab = .activity }
        }
        .navigationTitle(L10n.t("صحة النظام", "System Health"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    @MainActor private func loadOperations() async {
        guard !loadingOperations else { return }
        loadingOperations = true
        defer { loadingOperations = false }
        do {
            operations = try await SupabaseConfig.client.rpc("operational_health").execute().value
            operationsError = nil
        } catch {
            operationsError = L10n.t("تعذر تحديث حالة التشغيل. أعد المحاولة.", "Couldn't refresh operations. Please try again.")
        }
    }

    // MARK: - Tab Picker (premium glass + animated indicator)
    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(HealthTab.allCases.filter { authVM.isAdmin || $0 != .errors }, id: \.rawValue) { tab in
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
