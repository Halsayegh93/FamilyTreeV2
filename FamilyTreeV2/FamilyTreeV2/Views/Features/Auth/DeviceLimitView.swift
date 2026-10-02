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

                // Icon — تقفز أولاً مثل أيقونة رأس المربّعات («تقليل الحركة»: تلاشٍ)
                ZStack {
                    Circle()
                        .fill(DS.Color.error.opacity(0.15))
                        .frame(width: 100, height: 100)

                    Image(systemName: "iphone.gen3.badge.exclamationmark")
                        .font(DS.Font.scaled(42, weight: .bold))
                        .foregroundColor(DS.Color.error)
                }
                .modifier(DSIconPop())

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
                .dsStaggerIn(0)

                Spacer()

                // Button to open devices sheet
                DSPrimaryButton(
                    t("إدارة الأجهزة", "Manage Devices"),
                    icon: "iphone.gen3"
                ) {
                    showDevicesSheet = true
                }
                .padding(.horizontal, DS.Spacing.lg)
                .dsStaggerIn(1)

                DSSecondaryButton(
                    t("تسجيل الخروج", "Sign Out"),
                    icon: "rectangle.portrait.and.arrow.right",
                    color: DS.Color.error
                ) {
                    Task { await authVM.signOut() }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxxxl)
                .dsStaggerIn(2)
            }
            // بعد الأيقونة: النص ← الأزرار تباعاً (نفس «بعد الرأس» في المربّعات)
            .environment(\.dsStaggerBase, DSMotion.sectionsAfterHeader)
        }
        .dsCenterBox(isPresented: $showDevicesSheet) {
            LinkedDevicesSheet()
                .environmentObject(appSettingsVM)
        }
        .task {
            await notificationVM.fetchLinkedDevices()
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

                // الأيقونة تقفز أولاً مثل أيقونة رأس المربّعات («تقليل الحركة»: تلاشٍ)
                ZStack {
                    Circle()
                        .fill(DS.Color.warning.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Image(systemName: "iphone.gen3.badge.exclamationmark")
                        .font(DS.Font.scaled(42, weight: .bold))
                        .foregroundColor(DS.Color.warning)
                }
                .modifier(DSIconPop())

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
                .dsStaggerIn(0)

                Spacer()

                DSPrimaryButton(
                    t("إدارة الأجهزة", "Manage Devices"),
                    icon: "iphone.gen3"
                ) {
                    showDevicesSheet = true
                }
                .padding(.horizontal, DS.Spacing.lg)
                .dsStaggerIn(1)

                DSSecondaryButton(
                    t("تسجيل الخروج", "Sign Out"),
                    icon: "rectangle.portrait.and.arrow.right",
                    color: DS.Color.error
                ) {
                    Task { await authVM.signOut() }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxxxl)
                .dsStaggerIn(2)
            }
            // بعد الأيقونة: النص ← الأزرار تباعاً (نفس «بعد الرأس» في المربّعات)
            .environment(\.dsStaggerBase, DSMotion.sectionsAfterHeader)
        }
        .dsCenterBox(isPresented: $showDevicesSheet) {
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
        // نفس هيكل المربّعات الموحّد (طلب المالك): رأس ملوّن + قسم الأجهزة +
        // شريط سفلي — «متابعة» كحلي يمين (يظهر فقط لما وصل للحد) و«إغلاق» يسار
        DSComposer(
            title: t("إدارة الأجهزة", "Manage Devices"),
            subtitle: t("تم تقليل حد الأجهزة", "Device Limit Reduced"),
            icon: "iphone.gen3",
            tint: DS.Color.actionNavy,
            actionTitle: t("متابعة", "Continue"),
            actionIcon: "checkmark",
            showsAction: excessCount == 0,
            cancelTitle: t("إغلاق", "Close"),
            canSubmit: excessCount == 0,
            onSubmit: {
                authVM.status = .fullyAuthenticated
                dismiss()
            },
            onCancel: { dismiss() }
        ) {
            DSComposerSection(
                title: t("أجهزتك المرتبطة", "Your Linked Devices"),
                icon: "iphone.gen3",
                tint: DS.Color.warning,
                index: 0
            ) {
                VStack(spacing: DS.Spacing.sm) {
                    // شريط تقدم الحذف
                    limitProgressRow

                    ForEach(notificationVM.linkedDevices) { device in
                        overLimitDeviceRow(device)
                    }
                }
            }
        }
        .animation(DS.Anim.smooth, value: excessCount)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .dsAlert(
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

    /// الحد الأقصى — كم جهازاً بقي للإزالة، أو «وصلت للحد» (صف قراءة بنفس صفوف المربّعات)
    private var limitProgressRow: some View {
        let over = excessCount > 0
        let tint = over ? DS.Color.warning : DS.Color.success
        return HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: over ? "exclamationmark.triangle.fill" : "checkmark.circle.fill", tint: tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(t("الحد الأقصى", "Limit"))
                    .dsFieldFont(12, weight: .heavy)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(over
                     ? t("أزل \(excessCount == 1 ? "جهازاً" : "\(excessCount) أجهزة") للمتابعة", "Remove \(excessCount) device\(excessCount == 1 ? "" : "s") to continue")
                     : t("وصلت للحد — اضغط متابعة", "At limit — tap Continue"))
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(tint)
            }
            Spacer(minLength: 0)
        }
        .dsRowBox()
        .accessibilityElement(children: .combine)
    }

    /// صف جهاز: أيقونة الحقل + الاسم (+ «هذا الجهاز») + آخر ظهور + «إزالة» (أو «الحالي»)
    private func overLimitDeviceRow(_ device: NotificationViewModel.LinkedDevice) -> some View {
        let isCurrent = device.isCurrent(currentDeviceId: notificationVM.currentDeviceId)
        return HStack(spacing: DS.Spacing.sm) {
            // «iphone.gen3.badge.checkmark» ليس رمزاً في النظام (كان يظهر فارغاً) —
            // الجهاز الحالي بلون النجاح مثل مربّع الأجهزة في الإعدادات
            DSFieldIcon(name: "iphone.gen3",
                        tint: isCurrent ? DS.Color.success : DS.Color.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Spacing.xs) {
                    DeviceNameText(name: device.displayName)
                    if isCurrent {
                        Text(t("هذا الجهاز", "This device"))
                            .font(DS.Font.plex(10.5, weight: .bold))
                            .foregroundColor(DS.Color.success)
                            .padding(.horizontal, DS.Spacing.xs + 2)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(DS.Color.success.opacity(0.12)))
                            .fixedSize()
                    }
                }
                DeviceLastSeenText(text: formattedDate(device.updatedAt))
            }
            .accessibilityElement(children: .combine)   // اسم الجهاز وآخر ظهور معاً

            Spacer(minLength: 0)

            if isCurrent {
                // لا يمكن حذف الجهاز الحالي
                Text(t("الحالي", "Current"))
                    .font(DS.Font.plex(11, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.horizontal, DS.Spacing.md)
                    .frame(height: 30)
                    .background(Capsule().fill(DS.Color.mutedBackground))
                    .fixedSize()
            } else {
                // يفتح تأكيد الإزالة فقط — لا يحذف مباشرة
                DeviceRemoveChip {
                    deviceToRemove = device
                }
                .disabled(isRemoving)
            }
        }
        .dsRowBox()
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
        // نفس هيكل المربّعات الموحّد (طلب المالك): رأس ملوّن + قسم الأجهزة + «إغلاق»
        DSComposer(
            title: t("الأجهزة المرتبطة", "Linked Devices"),
            subtitle: t("احذف جهازاً من القائمة للمتابعة", "Remove a device from the list to continue"),
            icon: "iphone.gen3",
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            cancelTitle: t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { dismiss() }
        ) {
            DSComposerSection(
                title: t("أجهزتك المرتبطة", "Your Linked Devices"),
                icon: "iphone.gen3",
                tint: DS.Color.error,
                index: 0
            ) {
                VStack(spacing: DS.Spacing.sm) {
                    // Device count info cell
                    limitRow
                    devicesContent
                }
            }
        }
        .animation(DS.Anim.smooth, value: notificationVM.linkedDevices.count)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            await notificationVM.fetchLinkedDevices()
        }
        .dsAlert(
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

    /// الحد الأقصى — صف قراءة بنفس صفوف المربّعات
    private var limitRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "exclamationmark.triangle.fill", tint: DS.Color.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(t("الحد الأقصى", "Limit"))
                    .dsFieldFont(12, weight: .heavy)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(t(
                    "\(notificationVM.linkedDevices.count) من \(maxDevices) أجهزة",
                    "\(notificationVM.linkedDevices.count) of \(maxDevices) devices"
                ))
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(DS.Color.error)
            }
            Spacer(minLength: 0)
        }
        .dsRowBox()
        .accessibilityElement(children: .combine)
    }

    /// تحميل ← لا أجهزة / تعذّر التحميل ← صفوف الأجهزة
    @ViewBuilder
    private var devicesContent: some View {
        if notificationVM.isLoadingLinkedDevices && notificationVM.linkedDevices.isEmpty {
            ProgressView()
                .tint(DS.Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.lg)
        } else if notificationVM.linkedDevices.isEmpty {
            emptyState
        } else {
            // Device rows
            ForEach(notificationVM.linkedDevices) { device in
                deviceRow(device)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: notificationVM.linkedDevicesLoadFailed
                  ? "wifi.exclamationmark"
                  : "iphone.slash")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)

            Text(notificationVM.linkedDevicesLoadFailed
                 ? t("تعذّر تحميل الأجهزة", "Couldn't Load Devices")
                 : t("لا توجد أجهزة مرتبطة", "No Linked Devices"))
                .font(DS.Font.plex(14, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)

            Button {
                Task { await notificationVM.fetchLinkedDevices() }
            } label: {
                Label(t("إعادة المحاولة", "Try Again"), systemImage: "arrow.clockwise")
                    .font(DS.Font.plex(12.5, weight: .bold))
                    .foregroundColor(DS.Color.primary)
                    .padding(.horizontal, DS.Spacing.md)
                    .frame(height: 32)
                    .background(Capsule().fill(DS.Color.primary.opacity(0.1)))
                    // مساحة ضغط ٤٤ (توصية أبل) — الكبسولة ومكانها كما هما
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .padding(.vertical, -6)
            }
            .buttonStyle(DSScaleButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.sm)
        .dsRowBox()
    }

    /// صف جهاز: أيقونة الحقل + الاسم + آخر ظهور + «إزالة»
    private func deviceRow(_ device: NotificationViewModel.LinkedDevice) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "iphone.gen3", tint: DS.Color.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                DeviceNameText(name: device.displayName)
                DeviceLastSeenText(text: formattedDate(device.updatedAt))
            }
            .accessibilityElement(children: .combine)   // اسم الجهاز وآخر ظهور معاً

            Spacer(minLength: 0)

            // يفتح تأكيد الإزالة فقط — لا يحذف مباشرة
            DeviceRemoveChip {
                deviceToRemove = device
            }
            .disabled(isRemoving)
        }
        .dsRowBox()
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

// MARK: - أجزاء صفوف الأجهزة (مربّعات إدارة الأجهزة أعلاه)

/// اسم الجهاز — السطر الأول في صف الجهاز
fileprivate struct DeviceNameText: View {
    let name: String
    var body: some View {
        Text(name)
            .dsFieldFont(13.5, weight: .bold)
            .foregroundColor(DS.Color.fieldLabel)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// آخر ظهور للجهاز — السطر الثاني في صف الجهاز
fileprivate struct DeviceLastSeenText: View {
    let text: String
    var body: some View {
        Text(text)
            .dsFieldFont(12.5)
            .foregroundColor(DS.Color.fieldValue)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// زر «إزالة» الصغير بجانب الجهاز — يفتح تأكيد الإزالة فقط (لا يحذف مباشرة)
fileprivate struct DeviceRemoveChip: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
                Text(L10n.t("إزالة", "Remove"))
                    .font(DS.Font.plex(11.5, weight: .bold))
            }
            .foregroundColor(DS.Color.error)
            .padding(.horizontal, DS.Spacing.md)
            .frame(height: 30)
            .background(Capsule().fill(DS.Color.error.opacity(0.1)))
            // مساحة ضغط ٤٤ (توصية أبل): الكبسولة ٣٠ كما هي، والحشوة السالبة تُبقي ارتفاع الصف
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .padding(.vertical, -7)
        }
        .buttonStyle(DSScaleButtonStyle())
        .fixedSize()
    }
}
