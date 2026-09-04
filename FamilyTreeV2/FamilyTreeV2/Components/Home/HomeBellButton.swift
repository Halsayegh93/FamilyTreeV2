import SwiftUI

/// جرس الرئيسية بشكله الأصلي: الشارة من الرمز نفسه (bell.badge.fill) بلونين،
/// وارتداد خفيف عند وصول إشعار جديد — بلا كبسولة عدّاد.
struct HomeBellButton: View {
    @EnvironmentObject private var notificationVM: NotificationViewModel

    var body: some View {
        let hasUnread = notificationVM.unreadNotificationsCount > 0
        NavigationLink(destination: NotificationsCenterView()) {
            Group {
                if hasUnread {
                    // palette: اللون الأول للشارة (أحمر) والثاني للجرس (أبيض)
                    let bell = Image(systemName: "bell.badge.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(DS.Color.error, DS.Color.textOnPrimary)
                    if #available(iOS 17.0, *) {
                        bell.symbolEffect(.bounce, value: notificationVM.unreadNotificationsCount)
                    } else {
                        bell
                    }
                } else {
                    Image(systemName: "bell")
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(DS.Color.textOnPrimary)
                }
            }
            .font(DS.Font.scaled(22, weight: .semibold))
            .frame(width: 44, height: 44)
            .animation(DS.Anim.smooth, value: hasUnread)
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityLabel(L10n.t("الإشعارات", "Notifications"))
        .accessibilityValue(hasUnread ? L10n.t("توجد إشعارات غير مقروءة", "Unread notifications") : "")
    }
}
