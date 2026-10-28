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
                DSStateIcon("iphone.gen3.badge.exclamationmark", tint: DS.Color.error, size: DS.Icon.stateArt)
                .modifier(DSIconPop())

                // Title & Description
                VStack(spacing: DS.Spacing.md) {
                    Text(t("تم تجاوز حد الأجهزة", "Device Limit Reached"))
                        .dsFont(.emptyTitle)
                        .foregroundColor(DS.Color.textPrimary)

                    Text(t(
                        "وصلت للعدد الأقصى من الأجهزة (\(maxDevices)).\nاحذف جهازاً من القائمة للمتابعة.",
                        "Maximum device limit reached (\(maxDevices)).\nRemove a device from the list to continue."
                    ))
                        .dsFont(.body)
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
            // وضع العرض: تتمرّر بدل أن يُقصّ النص
            .dsLandscapeScroll()
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
                DSStateIcon("iphone.gen3.badge.exclamationmark", tint: DS.Color.warning, size: DS.Icon.stateArt)
                .modifier(DSIconPop())

                VStack(spacing: DS.Spacing.md) {
                    Text(t("تم تقليل حد الأجهزة", "Device Limit Reduced"))
                        .dsFont(.emptyTitle)
                        .foregroundColor(DS.Color.textPrimary)

                    Text(t(
                        "الحد الأقصى أصبح \(maxDevices) \(maxDevices == 1 ? "جهاز" : "أجهزة").\nأزل \(excessCount == 1 ? "جهازاً" : "\(excessCount) أجهزة") للمتابعة.",
                        "The device limit is now \(maxDevices). Please remove \(excessCount) device\(excessCount == 1 ? "" : "s") to continue."
                    ))
                    .dsFont(.body)
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
            // وضع العرض: تتمرّر بدل أن يُقصّ النص
            .dsLandscapeScroll()
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
                authVM.releaseDeviceGate()
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
                        authVM.releaseDeviceGate()
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
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(t("الحد الأقصى", "Limit"))
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(over
                     ? t("أزل \(excessCount == 1 ? "جهازاً" : "\(excessCount) أجهزة") للمتابعة", "Remove \(excessCount) device\(excessCount == 1 ? "" : "s") to continue")
                     : t("وصلت للحد — اضغط متابعة", "At limit — tap Continue"))
                    .dsFieldFont(.rowTitle)
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

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xs) {
                    DeviceNameText(name: device.displayName)
                    if isCurrent {
                        DSStatusChip(text: t("هذا الجهاز", "This device"), tint: DS.Color.success, size: .mini)
                            .fixedSize()
                    }
                }
                DeviceLastSeenText(text: formattedDate(device.updatedAt))
            }
            .accessibilityElement(children: .combine)   // اسم الجهاز وآخر ظهور معاً

            Spacer(minLength: 0)

            if isCurrent {
                // لا يمكن حذف الجهاز الحالي — كبسولة الحالة المشتركة
                DSStatusChip(text: t("الحالي", "Current"), tint: DS.Color.textTertiary)
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
                            authVM.releaseDeviceGate()
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
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(t("الحد الأقصى", "Limit"))
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(t(
                    "\(notificationVM.linkedDevices.count) من \(maxDevices) أجهزة",
                    "\(notificationVM.linkedDevices.count) of \(maxDevices) devices"
                ))
                    .dsFieldFont(.rowTitle)
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
            // التحميل الواحد: المجسّم يتنفّس
            DSPageLoader(fillsSpace: false)
                .padding(.vertical, DS.Spacing.sm)
        } else if notificationVM.linkedDevices.isEmpty {
            emptyState
        } else {
            // Device rows
            ForEach(notificationVM.linkedDevices) { device in
                deviceRow(device)
            }
        }
    }

    /// الحالة الفاضية الواحدة (مضغوطة) + «إعادة المحاولة» بالزرّ الواحد
    private var emptyState: some View {
        DSEmptyView(notificationVM.linkedDevicesLoadFailed
                    ? t("تعذّر تحميل الأجهزة", "Couldn't Load Devices")
                    : t("لا توجد أجهزة مرتبطة", "No Linked Devices"),
                    icon: notificationVM.linkedDevicesLoadFailed ? "wifi.exclamationmark" : "iphone.slash",
                    actionTitle: t("إعادة المحاولة", "Try Again"), actionIcon: "arrow.clockwise",
                    compact: true) {
            Task { await notificationVM.fetchLinkedDevices() }
        }
    }

    /// صف جهاز: أيقونة الحقل + الاسم + آخر ظهور + «إزالة»
    private func deviceRow(_ device: NotificationViewModel.LinkedDevice) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "iphone.gen3", tint: DS.Color.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
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
            .dsFieldFont(.rowTitle)
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
            .dsFieldFont(.subtitle)
            .foregroundColor(DS.Color.fieldValue)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// زر «إزالة» الصغير بجانب الجهاز — يفتح تأكيد الإزالة فقط (لا يحذف مباشرة)
fileprivate struct DeviceRemoveChip: View {
    let action: () -> Void
    var body: some View {
        // الشريحة الواحدة بلون الحذف
        DSChipButton(L10n.t("إزالة", "Remove"), icon: "trash.fill", tint: DS.Color.error, size: .small, action: action)
            .fixedSize()
    }
}
