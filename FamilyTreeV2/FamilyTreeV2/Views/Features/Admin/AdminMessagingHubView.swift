import SwiftUI

// MARK: - الإشعارات والتحديثات — صفحة واحدة بدل صفحتين (طلب المالك)
//
// «إرسال إشعارات» و«تحديثات التطبيق» كانتا صفحتين منفصلتين لنفس المهمة
// (إرسال رسالة للأعضاء). الآن مبدّل واحد أعلى الصفحة.
// التصميم الموحّد (٢٠٢٦-٠٩-٢٧): بطاقة رأس بأرقام حيّة + شريط اختيار بنفس فلاتر الصفحات.
// بطاقة الرأس تنطوي وقت الكتابة (الكيبورد ظاهر) حتى يبقى المكان كله للرسالة.

struct AdminMessagingHubView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel

    private enum Mode: Hashable { case notification, appUpdate }
    @State private var mode: Mode = .notification
    /// الكيبورد ظاهر — تنطوي بطاقة الرأس
    @State private var keyboardVisible = false
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
                if !keyboardVisible {
                    DSPageHero(
                        title: L10n.t("الإشعارات والتحديثات", "Notifications & Updates"),
                        subtitle: L10n.t("إشعار موجّه للأعضاء، أو إعلان عن تحديث التطبيق للجميع",
                                         "Notify selected members, or announce an app update to everyone"),
                        icon: "bell.badge.fill",
                        tint: DS.Color.composerDiwaniya,
                        stats: [
                            DSHeroStat(value: "\(recipientsCount)",
                                       label: L10n.t("المستلمون", "Recipients"), icon: "person.3.fill"),
                            DSHeroStat(value: reachableValue,
                                       label: L10n.t("تصلهم الإشعارات", "Reachable"), icon: "iphone.radiowaves.left.and.right"),
                            DSHeroStat(value: "\(notificationVM.scheduledNotifications.count)",
                                       label: L10n.t("مجدول", "Scheduled"), icon: "clock.badge.checkmark.fill")
                        ]
                    )
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }

                DSFilterChips(
                    options: [
                        DSFilterOption(id: Mode.notification,
                                       title: L10n.t("إشعار للأعضاء", "Notify members"),
                                       icon: "bell.fill"),
                        DSFilterOption(id: Mode.appUpdate,
                                       title: L10n.t("تحديث التطبيق", "App update"),
                                       icon: "megaphone.fill")
                    ],
                    selection: $mode,
                    tint: DS.Color.composerDiwaniya
                )
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
        .background(DS.Color.background.ignoresSafeArea())
        .navigationTitle(L10n.t("الإشعارات والتحديثات", "Notifications & Updates"))
        .navigationBarTitleDisplayMode(.inline)
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
