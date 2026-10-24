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
                        .foregroundStyle(DS.Color.error, DS.Color.headerGlyph)
                    if #available(iOS 17.0, *) {
                        bell.symbolEffect(.bounce, value: notificationVM.unreadNotificationsCount)
                    } else {
                        bell
                    }
                } else {
                    Image(systemName: "bell")
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(DS.Color.headerGlyph)
                }
            }
            .dsGlyph(DS.Glyph.xxl, weight: .semibold)
            .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
            .animation(DS.Anim.smooth, value: hasUnread)
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityLabel(L10n.t("الإشعارات", "Notifications"))
        .accessibilityValue(hasUnread ? L10n.t("توجد إشعارات غير مقروءة", "Unread notifications") : "")
    }
}
