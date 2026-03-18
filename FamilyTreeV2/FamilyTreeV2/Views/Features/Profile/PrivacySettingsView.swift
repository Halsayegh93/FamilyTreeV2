import SwiftUI
import UserNotifications

struct PrivacySettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var langManager = LanguageManager.shared

    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("notif_comments") private var notifComments: Bool = true
    @AppStorage("notif_likes") private var notifLikes: Bool = true
    @AppStorage("notif_profile_updates") private var notifProfileUpdates: Bool = true
    @State private var badgeEnabled: Bool = true
    @State private var isPhoneHidden: Bool = false
    @State private var isBirthDateHidden: Bool = false
    @State private var showUpdateError: Bool = false
    @State private var appeared: Bool = false


    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) {
                    // مجموعة الإشعارات
                    allNotificationsCard
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)

                    // مجموعة البيانات الشخصية
                    personalDataCard
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 28)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.xxxl)
                .onAppear {
                    guard !appeared else { return }
                    withAnimation(DS.Anim.smooth.delay(0.1)) { appeared = true }
                }
            }
        }
        .navigationTitle(L10n.t("الإشعارات والخصوصية", "Notifications & Privacy"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, langManager.layoutDirection)
        .onAppear {
            isPhoneHidden = authVM.currentUser?.isPhoneHidden ?? false
            isBirthDateHidden = authVM.currentUser?.isBirthDateHidden ?? false
            badgeEnabled = authVM.currentUser?.badgeEnabled ?? true
        }
        .onChange(of: notificationsEnabled) { _, newValue in
            Task {
                if newValue {
                    if let token = notificationVM.pushToken {
                        await notificationVM.registerPushToken(token)
                    }
                } else {
                    await notificationVM.unregisterPushToken()
                }
            }
        }
        .onChange(of: badgeEnabled) { _, newValue in
            Task {
                await memberVM.updateBadgeEnabled(newValue)
                if !newValue {
                    try? await UNUserNotificationCenter.current().setBadgeCount(0)
                } else {
                    let unread = notificationVM.notifications.filter { !$0.read }.count
                    try? await UNUserNotificationCenter.current().setBadgeCount(unread)
                }
            }
        }
        .onChange(of: isPhoneHidden) { _, newValue in
            Task {
                let success = await memberVM.updatePhoneHidden(newValue)
                if !success {
                    isPhoneHidden = !newValue
                    showUpdateError = true
                }
            }
        }
        .onChange(of: isBirthDateHidden) { _, newValue in
            Task {
                let success = await memberVM.updateBirthDateHidden(newValue)
                if !success {
                    isBirthDateHidden = !newValue
                    showUpdateError = true
                }
            }
        }
        .alert(L10n.t("خطأ", "Error"), isPresented: $showUpdateError) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.t("تعذر تحديث الإعداد. حاول مرة أخرى.", "Failed to update setting. Please try again."))
        }
    }

    // MARK: - All Notifications Card (مجموعة واحدة)
    private var allNotificationsCard: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("الإشعارات", "Notifications"),
                icon: "bell.badge.fill"
            )

            // تفعيل الإشعارات — الزر الرئيسي
            privacyToggleRow(
                icon: "bell.badge.fill",
                color: DS.Color.primary,
                title: L10n.t("تفعيل الإشعارات", "Enable Notifications"),
                subtitle: L10n.t("استقبال الإشعارات داخل وخارج التطبيق", "Receive push and in-app notifications"),
                isOn: $notificationsEnabled
            )

            DSDivider()

            // الخيارات الفرعية — تعتمد على الزر الرئيسي
            Group {
                // رقم الإشعارات على الأيقونة
                privacyToggleRow(
                    icon: "app.badge",
                    color: DS.Color.primary,
                    title: L10n.t("شارة الأيقونة", "App Badge"),
                    subtitle: L10n.t("عدد الإشعارات غير المقروءة على الأيقونة", "Show unread count on app icon"),
                    isOn: $badgeEnabled,
                    disabled: !notificationsEnabled
                )

                DSDivider()

                // التعليقات
                privacyToggleRow(
                    icon: "bubble.left.fill",
                    color: DS.Color.primary,
                    title: L10n.t("التعليقات", "Comments"),
                    subtitle: L10n.t("عند تعليق أحد على أخبارك", "When someone comments on your post"),
                    isOn: $notifComments,
                    disabled: !notificationsEnabled
                )

                DSDivider()

                // الإعجابات
                privacyToggleRow(
                    icon: "heart.fill",
                    color: DS.Color.primary,
                    title: L10n.t("الإعجابات", "Likes"),
                    subtitle: L10n.t("عند إعجاب أحد بأخبارك", "When someone likes your post"),
                    isOn: $notifLikes,
                    disabled: !notificationsEnabled
                )

                DSDivider()

                // تحديثات البيانات
                privacyToggleRow(
                    icon: "person.crop.circle.badge.checkmark",
                    color: DS.Color.primary,
                    title: L10n.t("التحديثات", "Updates"),
                    subtitle: L10n.t("عند تعديل بياناتك من قِبل الإدارة", "When admin updates your profile"),
                    isOn: $notifProfileUpdates,
                    disabled: !notificationsEnabled
                )
            }
            .opacity(notificationsEnabled ? 1.0 : 0.45)
            .animation(DS.Anim.snappy, value: notificationsEnabled)
        }
    }

    // MARK: - Personal Data Card (مجموعة واحدة)
    private var personalDataCard: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("البيانات الشخصية", "Personal Data"),
                icon: "lock.shield.fill"
            )

            // إخفاء رقم الهاتف
            privacyToggleRow(
                icon: "eye.slash.fill",
                color: DS.Color.primary,
                title: L10n.t("إخفاء رقم الهاتف", "Hide Phone Number"),
                subtitle: L10n.t("لن يظهر رقمك للأعضاء الآخرين", "Your number won't be visible to others"),
                isOn: $isPhoneHidden
            )

            DSDivider()

            // إخفاء تاريخ الميلاد
            privacyToggleRow(
                icon: "calendar.badge.minus",
                color: DS.Color.primary,
                title: L10n.t("إخفاء تاريخ الميلاد", "Hide Birth Date"),
                subtitle: L10n.t("لن يظهر تاريخ ميلادك للأعضاء الآخرين", "Your birth date won't be visible to others"),
                isOn: $isBirthDateHidden
            )
        }
    }

    // MARK: - Reusable Toggle Row
    private func privacyToggleRow(icon: String, color: Color, title: String, subtitle: String, isOn: Binding<Bool>, disabled: Bool = false) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                Text(subtitle)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(color)
                .disabled(disabled)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }
}
