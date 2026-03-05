import SwiftUI

struct DeviceLimitView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel

    private var isArabic: Bool { LanguageManager.shared.selectedLanguage == "ar" }
    private func t(_ ar: String, _ en: String) -> String { isArabic ? ar : en }

    @State private var showDevicesSheet = false

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            VStack(spacing: DS.Spacing.xxl) {

                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(DS.Color.error.opacity(0.15))
                        .frame(width: 100, height: 100)

                    Image(systemName: "iphone.gen3.badge.exclamationmark")
                        .font(DS.Font.scaled(42, weight: .bold))
                        .foregroundColor(DS.Color.error)
                }

                // Title & Description
                VStack(spacing: DS.Spacing.md) {
                    Text(t("تم تجاوز حد الأجهزة", "Device Limit Reached"))
                        .font(DS.Font.title2)
                        .fontWeight(.black)
                        .foregroundColor(DS.Color.textPrimary)

                    Text(t(
                        "حسابك مرتبط بـ \(AuthViewModel.maxDevicesPerAccount) أجهزة.\nأزل جهاز من القائمة لتتمكن من استخدام هذا الجهاز.",
                        "Your account is linked to \(AuthViewModel.maxDevicesPerAccount) devices.\nRemove a device from the list to use this device."
                    ))
                        .font(DS.Font.body)
                        .foregroundColor(DS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Spacing.xxl)
                }

                Spacer()

                // Button to open devices sheet
                DSPrimaryButton(
                    t("إدارة الأجهزة", "Manage Devices"),
                    icon: "iphone.gen3"
                ) {
                    showDevicesSheet = true
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxxxl)
            }
        }
        .sheet(isPresented: $showDevicesSheet) {
            LinkedDevicesSheet()
        }
        .task {
            await notificationVM.fetchLinkedDevices()
        }
    }
}

// MARK: - Linked Devices Sheet (Device Limit Context)
struct LinkedDevicesSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel

    private var isArabic: Bool { LanguageManager.shared.selectedLanguage == "ar" }
    private func t(_ ar: String, _ en: String) -> String { isArabic ? ar : en }

    @State private var deviceToRemove: NotificationViewModel.LinkedDevice?
    @State private var isRemoving = false

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()
                DSDecorativeBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {

                        // Devices Card
                        DSCard(padding: 0) {
                            DSSectionHeader(
                                title: t("الأجهزة المرتبطة", "Linked Devices"),
                                icon: "iphone.gen3",
                                iconColor: DS.Color.error
                            )

                            // Device count info cell
                            HStack(spacing: DS.Spacing.sm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(DS.Font.scaled(16, weight: .bold))
                                    .foregroundColor(DS.Color.warning)
                                    .frame(width: 36, height: 36)
                                    .background(DS.Color.warning.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t("الحد الأقصى", "Limit"))
                                        .font(DS.Font.caption2)
                                        .foregroundColor(DS.Color.textTertiary)
                                    Text(t(
                                        "\(notificationVM.linkedDevices.count) من \(AuthViewModel.maxDevicesPerAccount) أجهزة",
                                        "\(notificationVM.linkedDevices.count) of \(AuthViewModel.maxDevicesPerAccount) devices"
                                    ))
                                        .font(DS.Font.caption1)
                                        .fontWeight(.bold)
                                        .foregroundColor(DS.Color.error)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.vertical, DS.Spacing.sm)

                            DSDivider()

                            // Device rows
                            VStack(spacing: 0) {
                                ForEach(Array(notificationVM.linkedDevices.enumerated()), id: \.element.id) { index, device in
                                    if index > 0 { DSDivider() }
                                    deviceRow(device)
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                    }
                    .padding(.top, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.xxl)
                }
            }
            .navigationTitle(t("الأجهزة المرتبطة", "Linked Devices"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .alert(
            t("إزالة الجهاز", "Remove Device"),
            isPresented: .init(
                get: { deviceToRemove != nil },
                set: { if !$0 { deviceToRemove = nil } }
            )
        ) {
            Button(t("إلغاء", "Cancel"), role: .cancel) { deviceToRemove = nil }
            Button(t("إزالة", "Remove"), role: .destructive) {
                if let device = deviceToRemove {
                    Task {
                        isRemoving = true
                        await notificationVM.removeDevice(device)
                        if notificationVM.linkedDevices.count < AuthViewModel.maxDevicesPerAccount {
                            notificationVM.isDeviceLimitExceeded = false
                            authVM.status = .fullyAuthenticated
                            dismiss()
                        }
                        isRemoving = false
                    }
                }
                deviceToRemove = nil
            }
        } message: {
            Text(t(
                "سيتم إلغاء ربط هذا الجهاز وستتوقف الإشعارات عليه.",
                "This device will be unlinked and will no longer receive notifications."
            ))
        }
    }

    private func deviceRow(_ device: NotificationViewModel.LinkedDevice) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon("iphone.gen3", color: DS.Color.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)

                Text(formattedDate(device.updatedAt))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
            }

            Spacer()

            Button {
                deviceToRemove = device
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "trash.fill")
                        .font(DS.Font.scaled(11, weight: .bold))
                    Text(t("إزالة", "Remove"))
                        .font(DS.Font.scaled(11, weight: .bold))
                }
                .foregroundColor(DS.Color.error)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs + 2)
                .background(DS.Color.error.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isRemoving)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }

    private func formattedDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            let df = DateFormatter()
            df.locale = Locale(identifier: isArabic ? "ar" : "en")
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: isoString) {
            let df = DateFormatter()
            df.locale = Locale(identifier: isArabic ? "ar" : "en")
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
        return isoString
    }
}
