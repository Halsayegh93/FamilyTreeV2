import SwiftUI

// MARK: - الإشعارات والتحديثات — صفحة واحدة بدل صفحتين (طلب المالك)
//
// «إرسال إشعارات» و«تحديثات التطبيق» كانتا صفحتين منفصلتين لنفس المهمة
// (إرسال رسالة للأعضاء). الآن مبدّل واحد أعلى الصفحة.
// بشكل «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠، `AdminPageKit`): الرأس الكحلي (العنوان يتبع الوضع) بأرقامه الحيّة
// (المستلمون · تصلهم الإشعارات · مجدول ← يفتح المجدولة) وشريحتي الوضعين، ثم مربّعات الكتابة كما هي.
// الرأس يتمرّر مع الصفحة، فلا حاجة لطيّه وقت الكتابة.

struct AdminMessagingHubView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel

    enum Mode: Hashable { case notification, appUpdate }
    @State private var mode: Mode = .notification

    /// «رسالة تحديث التطبيق» من صفّها في قسم «الإعلانات» تفتح على وضع التحديث (إعادة تصميم اللوحة ٢٠٢٦-١٠-٢٠)
    init(startsWithUpdate: Bool = false) {
        _mode = State(initialValue: startsWithUpdate ? .appUpdate : .notification)
    }

    /// المستلمون المحتملون — نفس فلتر «إرسال إشعار»: بلا المعلّقين والمتوفّين والمجمّدين
    private var recipientsCount: Int {
        memberVM.allMembers
            .filter { $0.role != .pending && !($0.isDeceased ?? false) && $0.status != .frozen }
            .count
    }

    /// من تصلهم الإشعارات فعلاً (رقم + جهاز: فعّال + خامل) — آخر قيمة محفوظة، بلا طلب جديد
    private var reachableValue: String {
        guard let u = AppUsageStats.cached else { return "—" }
        return "\(u.active + u.idle)"
    }

    /// عنوان رقم «مجدول» — صفحة الإشعار تضيف له ضغطة تفتح المجدولة
    static let scheduledKPILabel = L10n.t("مجدول", "Scheduled")

    var body: some View {
        Group {
            switch mode {
            case .notification:
                AdminNotificationsView(pageHeader: header)
                    .environmentObject(authVM)
                    .environmentObject(memberVM)
                    .environmentObject(notificationVM)
            case .appUpdate:
                AdminAppUpdateView(embedded: true, pageHeader: header)
                    .environmentObject(authVM)
                    .environmentObject(notificationVM)
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private var header: AdminPageHeader {
        let notify = mode == .notification
        let scheduled = notificationVM.scheduledNotifications.count
        return AdminPageHeader(
            title: notify ? L10n.t("إشعار للأعضاء", "Notify members")
                          : L10n.t("رسالة تحديث التطبيق", "App update message"),
            subtitle: notify ? L10n.t("للجميع أو لدولة أو لأعضاء — الآن أو بجدولة",
                                      "Everyone, a country or people — now or later")
                             : L10n.t("رسالة نظام لكل الأعضاء — تظهر في «المستجدات» ويصل معها إشعار.",
                                      "A system message to everyone — shows in Updates with a push."),
            glyph: notify ? "bell.badge.fill" : "megaphone.fill",
            kpis: [
                AdminPageKPI(memberVM.allMembers.isEmpty ? "—" : "\(recipientsCount)",
                             L10n.t("المستلمون", "Recipients"), icon: "person.3.fill"),
                AdminPageKPI(reachableValue, L10n.t("تصلهم الإشعارات", "Reachable"),
                             icon: "iphone.radiowaves.left.and.right", tint: DS.Hub.kpiMine),
                AdminPageKPI("\(scheduled)", Self.scheduledKPILabel, icon: "clock.badge.checkmark.fill",
                             tint: scheduled > 0 ? DS.Hub.kpiLate : DS.Color.textOnPrimary)
            ],
            // مبدّل الوضعين — شريحتان في الرأس (المختارة ذهبية)
            chips: [
                AdminPageChip(id: "notification", title: L10n.t("إشعار للأعضاء", "Notify members"),
                              icon: "bell.fill", selected: notify) { mode = .notification },
                AdminPageChip(id: "appUpdate", title: L10n.t("تحديث التطبيق", "App update"),
                              icon: "megaphone.fill", selected: !notify) { mode = .appUpdate }
            ])
    }
}
