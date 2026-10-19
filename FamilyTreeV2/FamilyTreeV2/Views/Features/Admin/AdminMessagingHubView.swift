import SwiftUI

// MARK: - الإشعارات والتحديثات — صفحة واحدة بدل صفحتين (طلب المالك)
//
// «إرسال إشعارات» و«تحديثات التطبيق» كانتا صفحتين منفصلتين لنفس المهمة
// (إرسال رسالة للأعضاء). الآن مبدّل واحد أعلى الصفحة.
// «أسلوب واحد» (٢٠٢٦-١٠-٠٧): الرأس الملوّن الموحّد (`dsSubPageHeader`) + صفّ أرقام حيّة + مبدّل
// الوضعين (`DSSegmentedSwitch` مثل أقسام اللوحة). صفّ الأرقام ينطوي وقت الكتابة (الكيبورد ظاهر)
// حتى يبقى المكان كله للرسالة.

struct AdminMessagingHubView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel

    private enum Mode: Hashable { case notification, appUpdate }
    @State private var mode: Mode = .notification

    /// «رسالة تحديث التطبيق» من صفّها في قسم «الإعلانات» تفتح على وضع التحديث (إعادة تصميم اللوحة ٢٠٢٦-١٠-٢٠)
    init(startsWithUpdate: Bool = false) {
        _mode = State(initialValue: startsWithUpdate ? .appUpdate : .notification)
    }
    /// الكيبورد ظاهر — تنطوي بطاقة الرأس
    @State private var keyboardVisible = false
    /// بالعرض (ارتفاع مضغوط) نخفي بطاقة الرأس حتى يبقى للنموذج مكان
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: DS.Spacing.sm) {
                if !keyboardVisible && verticalSizeClass != .compact {
                    // العنوان والوصف في الرأس الملوّن — الأرقام هنا
                    DSStatsRow([
                        DSHeroStat(value: "\(recipientsCount)",
                                   label: L10n.t("المستلمون", "Recipients"), icon: "person.3.fill"),
                        DSHeroStat(value: reachableValue,
                                   label: L10n.t("تصلهم الإشعارات", "Reachable"), icon: "iphone.radiowaves.left.and.right"),
                        DSHeroStat(value: "\(notificationVM.scheduledNotifications.count)",
                                   label: L10n.t("مجدول", "Scheduled"), icon: "clock.badge.checkmark.fill")
                    ], tint: DS.Color.composerDiwaniya)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }

                // مبدّل الوضعين — نفس مبدّل أقسام لوحة الإدارة
                DSSegmentedSwitch(
                    options: [
                        DSSegmentOption(id: Mode.notification,
                                        title: L10n.t("إشعار للأعضاء", "Notify members"),
                                        icon: "bell.fill"),
                        DSSegmentOption(id: Mode.appUpdate,
                                        title: L10n.t("تحديث التطبيق", "App update"),
                                        icon: "megaphone.fill")
                    ],
                    selection: $mode, size: .regular)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)
            .padding(.bottom, DS.Spacing.xs)
            .background(DS.Color.background)
            .zIndex(1)

            switch mode {
            case .notification:
                AdminNotificationsView()
                    .environmentObject(authVM)
                    .environmentObject(memberVM)
                    .environmentObject(notificationVM)
            case .appUpdate:
                AdminAppUpdateView(embedded: true)
                    .environmentObject(authVM)
                    .environmentObject(notificationVM)
            }
        }
        // الرأس الملوّن الموحّد (كان شريط النظام + بطاقة رأس)
        .dsSubPageHeader(L10n.t("الإشعارات والتحديثات", "Notifications & Updates"),
                         subtitle: L10n.t("إشعار موجّه للأعضاء، أو إعلان عن تحديث التطبيق للجميع",
                                          "Notify selected members, or announce an app update to everyone"))
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            setKeyboard(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            setKeyboard(false)
        }
    }

    private func setKeyboard(_ visible: Bool) {
        guard keyboardVisible != visible else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) {
            keyboardVisible = visible
        }
    }
}
