import SwiftUI

struct PrivacySettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var langManager = LanguageManager.shared

    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @State private var isPhoneHidden: Bool = false
    @State private var isBirthDateHidden: Bool = false
    @State private var testPushResult: String?
    @State private var isSendingTestPush = false

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) {
                    notificationsCard
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
        .onChange(of: isPhoneHidden) { _, newValue in
            Task { await authVM.updatePhoneHidden(newValue) }
        }
        .onChange(of: isBirthDateHidden) { _, newValue in
            Task { await authVM.updateBirthDateHidden(newValue) }
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

                if notificationsEnabled {
                    DSDivider()

                    Button {
                        isSendingTestPush = true
                        testPushResult = nil
                        Task {
                            let result = await authVM.sendTestPush()
                            await MainActor.run {
                                isSendingTestPush = false
                                testPushResult = result.success
                                    ? L10n.t("تم الإرسال بنجاح ✓", "Sent successfully ✓")
                                    : L10n.t("فشل: \(result.message)", "Failed: \(result.message)")
                            }
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.md) {
                            DSIcon("paperplane.fill", color: DS.Color.info)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t("إرسال إشعار تجريبي", "Send Test Notification"))
                                    .font(DS.Font.calloutBold)
                                    .foregroundColor(DS.Color.textPrimary)
                                if let result = testPushResult {
                                    Text(result)
                                        .font(DS.Font.caption1)
                                        .foregroundColor(result.contains("✓") ? DS.Color.success : DS.Color.error)
                                } else {
                                    Text(L10n.t("اختبر وصول الإشعارات الخارجية", "Test external push delivery"))
                                        .font(DS.Font.caption1)
                                        .foregroundColor(DS.Color.textSecondary)
                                }
                            }

                            Spacer()

                            if isSendingTestPush {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(DS.Font.scaled(20))
                                    .foregroundColor(DS.Color.info)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.md)
                    }
                    .buttonStyle(DSBoldButtonStyle())
                    .disabled(isSendingTestPush)
                }
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
