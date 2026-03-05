import SwiftUI
import UserNotifications

struct PrivacySettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var langManager = LanguageManager.shared

    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @State private var badgeEnabled: Bool = true
    @State private var isPhoneHidden: Bool = false
    @State private var isBirthDateHidden: Bool = false
    @State private var showUpdateError: Bool = false


    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) {
                    notificationsCard
                    badgeCard
                    phonePrivacyCard
                    birthDatePrivacyCard
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.xxxl)
            }
        }
        .navigationTitle(L10n.t("الخصوصية", "Privacy"))
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
                    if let token = authVM.pushToken {
                        await authVM.registerPushToken(token)
                    }
                } else {
                    await authVM.unregisterPushToken()
                }
            }
        }
        .onChange(of: badgeEnabled) { _, newValue in
            Task {
                await authVM.updateBadgeEnabled(newValue)
                if !newValue {
                    try? await UNUserNotificationCenter.current().setBadgeCount(0)
                } else {
                    let unread = authVM.notifications.filter { !$0.read }.count
                    try? await UNUserNotificationCenter.current().setBadgeCount(unread)
                }
            }
        }
        .onChange(of: isPhoneHidden) { _, newValue in
            Task {
                let success = await authVM.updatePhoneHidden(newValue)
                if !success {
                    isPhoneHidden = !newValue
                    showUpdateError = true
                }
            }
        }
        .onChange(of: isBirthDateHidden) { _, newValue in
            Task {
                let success = await authVM.updateBirthDateHidden(newValue)
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

    // MARK: - Notifications Card
    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("الإشعارات", "Notifications"),
                    icon: "bell.badge.fill"
                )

                HStack(spacing: DS.Spacing.md) {
                    DSIcon("bell.badge.fill", color: DS.Color.success)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("تفعيل الإشعارات", "Enable Notifications"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(notificationsEnabled ? L10n.t("مفعلة", "Enabled") : L10n.t("متوقفة", "Disabled"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }

                    Spacer()

                    Toggle("", isOn: $notificationsEnabled)
                        .labelsHidden()
                        .tint(DS.Color.success)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)


            }
        }
    }

    // MARK: - Badge Card
    private var badgeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                HStack(spacing: DS.Spacing.md) {
                    DSIcon("app.badge", color: DS.Color.error)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("رقم الإشعارات على الأيقونة", "App Icon Badge"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(L10n.t("عرض عدد الإشعارات غير المقروءة على أيقونة التطبيق", "Show unread count on the app icon"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }

                    Spacer()

                    Toggle("", isOn: $badgeEnabled)
                        .labelsHidden()
                        .tint(DS.Color.error)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
            }
        }
    }

    // MARK: - Birth Date Privacy Card
    private var birthDatePrivacyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("تاريخ الميلاد", "Birth Date"),
                    icon: "calendar"
                )

                HStack(spacing: DS.Spacing.md) {
                    DSIcon("calendar.badge.minus", color: DS.Color.warning)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("إخفاء تاريخ الميلاد", "Hide Birth Date"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(L10n.t("إخفاء تاريخ ميلادك عن الأعضاء الآخرين", "Hide your birth date from other members"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }

                    Spacer()

                    Toggle("", isOn: $isBirthDateHidden)
                        .labelsHidden()
                        .tint(DS.Color.warning)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
            }
        }
    }

    // MARK: - Phone Privacy Card
    private var phonePrivacyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("رقم الهاتف", "Phone Number"),
                    icon: "phone.fill"
                )

                HStack(spacing: DS.Spacing.md) {
                    DSIcon("eye.slash.fill", color: DS.Color.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("إخفاء رقم الهاتف", "Hide Phone Number"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(L10n.t("إخفاء رقمك عن الأعضاء الآخرين", "Hide your number from other members"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }

                    Spacer()

                    Toggle("", isOn: $isPhoneHidden)
                        .labelsHidden()
                        .tint(DS.Color.primary)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
            }
        }
    }
}
