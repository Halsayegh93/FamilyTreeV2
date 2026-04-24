import SwiftUI

struct DeviceLimitView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }
    private var maxDevices: Int { appSettingsVM.settings.maxDevicesPerUser }

    @State private var showDevicesSheet = false

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

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
                        "وصلت للعدد الأقصى من الأجهزة (\(maxDevices)).\nاحذف جهازاً من القائمة للمتابعة.",
                        "Maximum device limit reached (\(maxDevices)).\nRemove a device from the list to continue."
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

                DSSecondaryButton(
                    t("تسجيل الخروج", "Sign Out"),
                    icon: "rectangle.portrait.and.arrow.right",
                    color: DS.Color.error
                ) {
                    Task { await authVM.signOut() }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxxxl)
            }
        }
        .sheet(isPresented: $showDevicesSheet) {
            LinkedDevicesSheet()
                .environmentObject(appSettingsVM)
        }
    }
}

// MARK: - Device Over Limit View
/// يظهر لما المستخدم مسجّل لكن عدد أجهزته تجاوز الحد الجديد الذي حدده المدير
struct DeviceOverLimitView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }
    private var maxDevices: Int { appSettingsVM.settings.maxDevicesPerUser }
    private var excessCount: Int { max(0, notificationVM.linkedDevices.count - maxDevices) }

    @State private var showDevicesSheet = false

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: DS.Spacing.xxl) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(DS.Color.warning.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Image(systemName: "iphone.gen3.badge.exclamationmark")
                        .font(DS.Font.scaled(42, weight: .bold))
                        .foregroundColor(DS.Color.warning)
                }

                VStack(spacing: DS.Spacing.md) {
                    Text(t("تم تقليل حد الأجهزة", "Device Limit Reduced"))
                        .font(DS.Font.title2)
                        .fontWeight(.black)
                        .foregroundColor(DS.Color.textPrimary)

                    Text(t(
                        "الحد الأقصى أصبح \(maxDevices) \(maxDevices == 1 ? "جهاز" : "أجهزة").\nأزل \(excessCount == 1 ? "جهازاً" : "\(excessCount) أجهزة") للمتابعة.",
                        "The device limit is now \(maxDevices). Please remove \(excessCount) device\(excessCount == 1 ? "" : "s") to continue."
                    ))
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xxl)
                }

                Spacer()

                DSPrimaryButton(
                    t("إدارة الأجهزة", "Manage Devices"),
                    icon: "iphone.gen3"
                ) {
                    showDevicesSheet = true
                }
                .padding(.horizontal, DS.Spacing.lg)

                DSSecondaryButton(
                    t("تسجيل الخروج", "Sign Out"),
                    icon: "rectangle.portrait.and.arrow.right",
                    color: DS.Color.error
                ) {
                    Task { await authVM.signOut() }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxxxl)
            }
        }
        .sheet(isPresented: $showDevicesSheet) {
            OverLimitDevicesSheet()
                .environmentObject(authVM)
                .environmentObject(notificationVM)
                .environmentObject(appSettingsVM)
        }
        .task {
            await notificationVM.fetchLinkedDevices()
        }
    }
}

// MARK: - Over Limit Devices Sheet
/// يسمح للمستخدم بحذف أجهزته الزائدة حتى يصل للحد المسموح
struct OverLimitDevicesSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }
    private var maxDevices: Int { appSettingsVM.settings.maxDevicesPerUser }
    private var excessCount: Int { max(0, notificationVM.linkedDevices.count - maxDevices) }

    @State private var deviceToRemove: NotificationViewModel.LinkedDevice?
    @State private var isRemoving = false

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {
                        DSCard(padding: 0) {
                            DSSectionHeader(
                                title: t("أجهزتك المرتبطة", "Your Linked Devices"),
                                icon: "iphone.gen3",
                                iconColor: DS.Color.warning
                            )

                            // شريط تقدم الحذف
                            HStack(spacing: DS.Spacing.sm) {
                                Image(systemName: excessCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                    .font(DS.Font.scaled(16, weight: .bold))
                                    .foregroundColor(excessCount > 0 ? DS.Color.warning : DS.Color.success)
                                    .frame(width: 36, height: 36)
                                    .background((excessCount > 0 ? DS.Color.warning : DS.Color.success).opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t("الحد الأقصى", "Limit"))
                                        .font(DS.Font.caption2)
                                        .foregroundColor(DS.Color.textTertiary)
                                    Text(excessCount > 0
                                         ? t("أزل \(excessCount == 1 ? "جهازاً" : "\(excessCount) أجهزة") للمتابعة", "Remove \(excessCount) device\(excessCount == 1 ? "" : "s") to continue")
                                         : t("وصلت للحد — اضغط متابعة", "At limit — tap Continue"))
                                        .font(DS.Font.caption1)
                                        .fontWeight(.bold)
                                        .foregroundColor(excessCount > 0 ? DS.Color.warning : DS.Color.success)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.vertical, DS.Spacing.xs)

                            DSDivider()

                            VStack(spacing: 0) {
                                ForEach(Array(notificationVM.linkedDevices.enumerated()), id: \.element.id) { index, device in
                                    if index > 0 { DSDivider() }
                                    overLimitDeviceRow(device)
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // زر متابعة — يظهر فقط لما وصل للحد
                        if excessCount == 0 {
                            DSPrimaryButton(t("متابعة", "Continue"), icon: "checkmark") {
                                authVM.status = .fullyAuthenticated
                                dismiss()
                            }
                            .padding(.horizontal, DS.Spacing.lg)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.top, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.xxl)
                    .animation(DS.Anim.smooth, value: excessCount)
                }
            }
            .navigationTitle(t("إدارة الأجهزة", "Manage Devices"))
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
                guard let device = deviceToRemove else { deviceToRemove = nil; return }
                deviceToRemove = nil
                Task {
                    isRemoving = true
                    await notificationVM.removeDevice(device)
                    // إذا وصلنا للحد → أدخل التطبيق مباشرة
                    if notificationVM.linkedDevices.count <= maxDevices {
                        authVM.status = .fullyAuthenticated
                        dismiss()
                    }
                    isRemoving = false
                }
            }
        } message: {
            Text(t(
                "سيتم إلغاء ربط هذا الجهاز وستتوقف الإشعارات عليه.",
                "This device will be unlinked and will no longer receive notifications."
            ))
        }
    }

    private func overLimitDeviceRow(_ device: NotificationViewModel.LinkedDevice) -> some View {
        let isCurrent = device.isCurrent(currentDeviceId: notificationVM.currentDeviceId)
        return HStack(spacing: DS.Spacing.md) {
            DSIcon(isCurrent ? "iphone.gen3.badge.checkmark" : "iphone.gen3",
                   color: isCurrent ? DS.Color.success : DS.Color.accent)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(device.displayName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                    if isCurrent {
                        Text(t("هذا الجهاز", "This device"))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.success)
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(DS.Color.success.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text(formattedDate(device.updatedAt))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
            }

            Spacer()

            if isCurrent {
                // لا يمكن حذف الجهاز الحالي
                Text(t("الحالي", "Current"))
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs + 2)
                    .background(DS.Color.surface)
                    .clipShape(Capsule())
            } else {
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
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }

    private func formattedDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            let df = DateFormatter()
            df.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: isoString) {
            let df = DateFormatter()
            df.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
        return isoString
    }
}

// MARK: - Linked Devices Sheet (Device Limit Context)
struct LinkedDevicesSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }
    private var maxDevices: Int { appSettingsVM.settings.maxDevicesPerUser }

    @State private var deviceToRemove: NotificationViewModel.LinkedDevice?
    @State private var isRemoving = false

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

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
                                        "\(notificationVM.linkedDevices.count) من \(maxDevices) أجهزة",
                                        "\(notificationVM.linkedDevices.count) of \(maxDevices) devices"
                                    ))
                                        .font(DS.Font.caption1)
                                        .fontWeight(.bold)
                                        .foregroundColor(DS.Color.error)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.vertical, DS.Spacing.xs)

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
                        // بعد الحذف: سجّل الجهاز الحالي وانتقل للتطبيق
                        if notificationVM.linkedDevices.count < maxDevices {
                            await notificationVM.registerDevice()
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
        .padding(.vertical, DS.Spacing.xs)
    }

    private func formattedDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            let df = DateFormatter()
            df.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: isoString) {
            let df = DateFormatter()
            df.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
        return isoString
    }
}
