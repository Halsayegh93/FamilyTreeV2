import SwiftUI

// MARK: - الإشعارات والتحديثات — صفحة واحدة بدل صفحتين (طلب المالك)
//
// «إرسال إشعارات» و«تحديثات التطبيق» كانتا صفحتين منفصلتين لنفس المهمة
// (إرسال رسالة للأعضاء). الآن مبدّل واحد أعلى الصفحة.

struct AdminMessagingHubView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel

    private enum Mode: Hashable { case notification, appUpdate }
    @State private var mode: Mode = .notification

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text(L10n.t("إشعار للأعضاء", "Notify members")).tag(Mode.notification)
                Text(L10n.t("تحديث التطبيق", "App update")).tag(Mode.appUpdate)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Color.background)

            switch mode {
            case .notification:
                AdminNotificationsView()
                    .environmentObject(authVM)
                    .environmentObject(memberVM)
                    .environmentObject(notificationVM)
            case .appUpdate:
                AdminAppUpdateView()
                    .environmentObject(authVM)
                    .environmentObject(notificationVM)
            }
        }
        .background(DS.Color.background.ignoresSafeArea())
        .navigationTitle(L10n.t("الإشعارات والتحديثات", "Notifications & Updates"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}
