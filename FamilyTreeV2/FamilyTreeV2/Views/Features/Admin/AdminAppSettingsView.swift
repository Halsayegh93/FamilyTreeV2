import SwiftUI

// MARK: - Admin App Settings — إعدادات التطبيق
struct AdminAppSettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel

    @State private var showResetConfirmation = false
    @State private var showResetCooldownAlert = false
    @State private var cooldownDisabled = ProfileEditCooldown.shared.isDisabled
    @State private var showUpdateMessageEditor = false
    @State private var editingUpdateMessage = ""
    @State private var showUpdateURLEditor = false
    @State private var editingUpdateURL = ""
    @State private var showHomeSections = false
    @State private var showSendUpdateConfirm = false

    /// المالك يعدّل، باقي المدراء يتصفّحون فقط.
    private var canEdit: Bool { authVM.canManageSettings }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.xxl) {

                    // إشعار وضع القراءة فقط (لغير المالك)
                    if !canEdit {
                        readOnlyBanner
                            .padding(.top, DS.Spacing.md)
                    }

                    // معلومات النظام
                    systemInfoSection
                        .padding(.top, canEdit ? DS.Spacing.md : 0)

                    // التسجيل والعضوية
                    registrationSection

                    // الأخبار والمحتوى
                    contentSection

                    // الميزات
                    featuresSection

                    updateSection

                    // عداد التعديل
                    cooldownSection

                    // الأمان
                    securitySection

                    // إعادة تعيين — يبقى مرئيّ بس مُعطّل لغير المالك
                    resetSection

                    Spacer(minLength: DS.Spacing.xxxl)
                }
                .disabled(!canEdit)
            }
        }
        .navigationTitle(L10n.t("إعدادات التطبيق", "App Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            await appSettingsVM.fetchSettings()
        }
        .alert(
            L10n.t("إعادة تعيين", "Reset Settings"),
            isPresented: $showResetConfirmation
        ) {
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            Button(L10n.t("إعادة تعيين", "Reset"), role: .destructive) {
                Task {
                    await appSettingsVM.resetToDefaults(updatedBy: authVM.currentUser?.id)
                }
            }
        } message: {
            Text(L10n.t(
                "سيتم إرجاع جميع الإعدادات إلى القيم الافتراضية",
                "All settings will be restored to default values"
            ))
        }
        .alert(
            L10n.t("تصفير العداد", "Reset Cooldown"),
            isPresented: $showResetCooldownAlert
        ) {
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            Button(L10n.t("تصفير", "Reset"), role: .destructive) {
                ProfileEditCooldown.shared.resetAllCooldowns()
            }
        } message: {
            Text(L10n.t(
                "سيتم إعادة تعيين جميع فترات الانتظار وسيصبح بإمكانك التعديل فوراً",
                "All cooldown timers will be reset and you can edit immediately"
            ))
        }
    }

    // MARK: - Registration & Membership
    private var registrationSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("التسجيل والعضوية", "Registration & Membership"),
                icon: "person.badge.key.fill",
                iconColor: DS.Color.primary
            )

            // السماح بالتسجيل الجديد
            settingToggle(
                icon: "person.badge.plus",
                color: DS.Color.success,
                title: L10n.t("السماح بالتسجيل", "Allow Registrations"),
                subtitle: L10n.t("السماح لأعضاء جدد بالتسجيل في التطبيق", "Allow new registrations"),
                isOn: appSettingsVM.settings.allowNewRegistrations,
                key: "allow_new_registrations"
            )

            DSDivider()

            // الحد الأقصى للأجهزة
            HStack(spacing: DS.Spacing.md) {
                DSIcon("iphone.gen3.badge.play", color: DS.Color.info)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("الحد الأقصى للأجهزة", "Max Devices"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(L10n.t("عدد الأجهزة المسموحة لكل مستخدم", "Devices allowed per user"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }

                Spacer()

                Stepper(
                    "\(appSettingsVM.settings.maxDevicesPerUser)",
                    value: Binding(
                        get: { appSettingsVM.settings.maxDevicesPerUser },
                        set: { newVal in
                            appSettingsVM.settings.maxDevicesPerUser = newVal
                            Task {
                                await appSettingsVM.updateSetting(
                                    "max_devices_per_user",
                                    value: newVal,
                                    updatedBy: authVM.currentUser?.id
                                )
                            }
                        }
                    ),
                    in: 1...10
                )
                .labelsHidden()
                .frame(width: 100)

                Text("\(appSettingsVM.settings.maxDevicesPerUser)")
                    .font(DS.Font.headline)
                    .fontWeight(.black)
                    .foregroundColor(DS.Color.primary)
                    .frame(width: 24)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Content Settings
    private var contentSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("الأخبار والمحتوى", "News & Content"),
                icon: "newspaper.fill",
                iconColor: DS.Color.accent
            )

            // موافقة الأخبار
            settingToggle(
                icon: "checkmark.shield.fill",
                color: DS.Color.warning,
                title: L10n.t("موافقة الأخبار", "News Approval"),
                subtitle: L10n.t("يتطلب موافقة المدير قبل نشر الأخبار", "Require admin approval"),
                isOn: appSettingsVM.settings.newsRequiresApproval,
                key: "news_requires_approval"
            )

            DSDivider()

            // الاستطلاعات
            settingToggle(
                icon: "chart.bar.fill",
                color: DS.Color.info,
                title: L10n.t("الاستطلاعات", "Polls"),
                subtitle: L10n.t("السماح بإضافة استطلاعات في الأخبار", "Allow polls in news posts"),
                isOn: appSettingsVM.settings.pollsEnabled ?? true,
                key: "polls_enabled"
            )

            DSDivider()

            // القصص
            settingToggle(
                icon: "book.pages.fill",
                color: DS.Color.secondary,
                title: L10n.t("قصص العائلة", "Family Stories"),
                subtitle: L10n.t("السماح لأفراد العائلة بنشر القصص", "Allow family members to post stories"),
                isOn: appSettingsVM.settings.storiesEnabled ?? true,
                key: "stories_enabled"
            )
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Features
    private var featuresSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("الميزات", "Features"),
                icon: "star.fill",
                iconColor: DS.Color.warning
            )

            settingToggle(
                icon: "map.fill",
                color: DS.Color.primary,
                title: L10n.t("الديوانيات", "Diwaniyas"),
                subtitle: L10n.t("إظهار تاب الديوانيات للأعضاء", "Show Diwaniyas tab to members"),
                isOn: appSettingsVM.settings.diwaniyasEnabled ?? true,
                key: "diwaniyas_enabled"
            )

            DSDivider()

            settingToggle(
                icon: "briefcase.fill",
                color: DS.Color.accent,
                title: L10n.t("مشاريع العائلة", "Family Projects"),
                subtitle: L10n.t("إظهار قسم المشاريع في الرئيسية", "Show Projects section on Home"),
                isOn: appSettingsVM.settings.projectsEnabled ?? true,
                key: "projects_enabled"
            )

            DSDivider()

            settingToggle(
                icon: "photo.on.rectangle.angled.fill",
                color: DS.Color.info,
                title: L10n.t("ألبوم الصور", "Photo Albums"),
                subtitle: L10n.t("إظهار قسم الصور في الرئيسية", "Show Photos section on Home"),
                isOn: appSettingsVM.settings.albumsEnabled ?? true,
                key: "albums_enabled"
            )

            DSDivider()

            settingToggle(
                icon: "person.2.fill",
                color: DS.Color.secondary,
                title: L10n.t("شجرة النساء", "Women's Tree"),
                subtitle: L10n.t("إظهار اختصار شجرة العائلة (النساء) في الرئيسية",
                                 "Show Women's Tree shortcut on Home"),
                isOn: appSettingsVM.settings.womenTreeEnabled ?? true,
                key: "women_tree_enabled"
            )

            DSDivider()

            Button { showHomeSections = true } label: {
                HStack(spacing: DS.Spacing.md) {
                    DSIcon("square.grid.2x2.fill", color: DS.Color.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("أقسام الرئيسية", "Home Sections"))
                            .font(DS.Font.calloutBold).foregroundColor(DS.Color.textPrimary)
                        Text(L10n.t("إضافة/تعديل أقسام تظهر مع الوصول السريع",
                                    "Add/edit sections shown with quick access"))
                            .font(DS.Font.caption1).foregroundColor(DS.Color.textSecondary)
                    }
                    Spacer()
                    Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                        .foregroundColor(DS.Color.textTertiary)
                }
                .padding(DS.Spacing.md)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .sheet(isPresented: $showHomeSections) { AdminHomeSectionsView() }
    }

    // MARK: - التحديث (server-driven)
    private var updateSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("التحديث", "Update"),
                icon: "arrow.down.circle.fill",
                iconColor: DS.Color.primary
            )

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("أحدث رقم بناء", "Latest build"))
                        .font(DS.Font.calloutBold).foregroundColor(DS.Color.textPrimary)
                    Text(L10n.t("بناء التطبيق الحالي: \(kAppBuild)", "Current build: \(kAppBuild)"))
                        .font(DS.Font.caption1).foregroundColor(DS.Color.textSecondary)
                }
                Spacer()
                Button {
                    let v = max(0, (appSettingsVM.settings.latestBuild ?? 0) - 1)
                    Task { await appSettingsVM.updateSetting("latest_build", value: v, updatedBy: authVM.currentUser?.id) }
                } label: { Image(systemName: "minus.circle").foregroundColor(DS.Color.textTertiary) }
                Text("\(appSettingsVM.settings.latestBuild ?? 0)")
                    .font(DS.Font.bodyBold).foregroundColor(DS.Color.textPrimary)
                    .frame(minWidth: 28)
                Button {
                    let v = (appSettingsVM.settings.latestBuild ?? 0) + 1
                    Task { await appSettingsVM.updateSetting("latest_build", value: v, updatedBy: authVM.currentUser?.id) }
                } label: { Image(systemName: "plus.circle").foregroundColor(DS.Color.primary) }
            }
            .padding(DS.Spacing.md)

            DSDivider()

            settingToggle(
                icon: "lock.fill",
                color: DS.Color.error,
                title: L10n.t("تحديث إجباري", "Force update"),
                subtitle: L10n.t("يوقف الاستخدام حتى التحديث", "Blocks the app until updated"),
                isOn: appSettingsVM.settings.forceUpdate ?? false,
                key: "force_update"
            )

            DSDivider()

            Button { editingUpdateMessage = appSettingsVM.settings.updateMessage ?? ""; showUpdateMessageEditor = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("رسالة التحديث", "Update message"))
                            .font(DS.Font.calloutBold).foregroundColor(DS.Color.textPrimary)
                        Text((appSettingsVM.settings.updateMessage?.isEmpty == false)
                             ? appSettingsVM.settings.updateMessage!
                             : L10n.t("غير محددة", "Not set"))
                            .font(DS.Font.caption1).foregroundColor(DS.Color.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "pencil").foregroundColor(DS.Color.textTertiary)
                }
                .padding(DS.Spacing.md)
            }
            .buttonStyle(.plain)

            DSDivider()

            Button { editingUpdateURL = appSettingsVM.settings.updateUrl ?? ""; showUpdateURLEditor = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("رابط التحديث", "Update URL"))
                            .font(DS.Font.calloutBold).foregroundColor(DS.Color.textPrimary)
                        Text((appSettingsVM.settings.updateUrl?.isEmpty == false)
                             ? appSettingsVM.settings.updateUrl!
                             : L10n.t("غير محدد", "Not set"))
                            .font(DS.Font.caption1).foregroundColor(DS.Color.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "pencil").foregroundColor(DS.Color.textTertiary)
                }
                .padding(DS.Spacing.md)
            }
            .buttonStyle(.plain)

            DSDivider()

            // دفع إشعار التحديث لكل الأجهزة (push) — «نرسل للأجهزة إن في تحديث».
            Button { showSendUpdateConfirm = true } label: {
                HStack(spacing: DS.Spacing.md) {
                    DSIcon("bell.badge.fill", color: DS.Color.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("إرسال إشعار التحديث", "Send update notification"))
                            .font(DS.Font.calloutBold).foregroundColor(DS.Color.textPrimary)
                        Text(L10n.t("يدفع إشعاراً لكل الأجهزة بوجود تحديث",
                                    "Pushes an update alert to all devices"))
                            .font(DS.Font.caption1).foregroundColor(DS.Color.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "paperplane.fill").foregroundColor(DS.Color.primary)
                }
                .padding(DS.Spacing.md)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .alert(L10n.t("إرسال إشعار التحديث", "Send update notification"), isPresented: $showSendUpdateConfirm) {
            Button(L10n.t("إرسال", "Send")) {
                let msg = appSettingsVM.settings.updateMessage
                let body = (msg?.isEmpty == false) ? msg! :
                    L10n.t("يتوفّر تحديث جديد للتطبيق. حدّثه للحصول على أحدث الميزات.",
                           "A new app update is available. Update for the latest features.")
                Task {
                    await notificationVM.sendNotification(
                        title: L10n.t("يوجد تحديث", "Update available"),
                        body: body, targetMemberIds: nil, sendPush: true, kind: "app_update")
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("سيصل إشعار لكل الأعضاء بأن هناك تحديثاً للتطبيق.",
                        "All members will receive an alert that an app update is available."))
        }
        .alert(L10n.t("رسالة التحديث", "Update message"), isPresented: $showUpdateMessageEditor) {
            TextField(L10n.t("الرسالة", "Message"), text: $editingUpdateMessage)
            Button(L10n.t("حفظ", "Save")) {
                Task { await appSettingsVM.updateSetting("update_message", value: editingUpdateMessage, updatedBy: authVM.currentUser?.id) }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        }
        .alert(L10n.t("رابط التحديث", "Update URL"), isPresented: $showUpdateURLEditor) {
            TextField("https://...", text: $editingUpdateURL)
            Button(L10n.t("حفظ", "Save")) {
                Task { await appSettingsVM.updateSetting("update_url", value: editingUpdateURL, updatedBy: authVM.currentUser?.id) }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        }
    }

    // MARK: - Security
    private var securitySection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("الأمان والصيانة", "Security & Maintenance"),
                icon: "lock.shield.fill",
                iconColor: DS.Color.error
            )

            // وضع الصيانة
            settingToggle(
                icon: "wrench.and.screwdriver.fill",
                color: DS.Color.error,
                title: L10n.t("وضع الصيانة", "Maintenance Mode"),
                subtitle: L10n.t("إيقاف التطبيق مؤقتاً للصيانة (المدراء فقط)", "Maintenance mode (admin only)"),
                isOn: appSettingsVM.settings.maintenanceMode,
                key: "maintenance_mode"
            )
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Edit Cooldown
    private var cooldownSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("عداد التعديل", "Edit Cooldown"),
                icon: "timer",
                iconColor: DS.Color.warning
            )

            // إيقاف / تشغيل العداد
            HStack(spacing: DS.Spacing.md) {
                DSIcon("pause.circle.fill", color: DS.Color.warning)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("إيقاف العداد", "Disable Cooldown"))
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(L10n.t("السماح بالتعديل بدون حد (3 تعديلات ثم 24 ساعة)", "Allow unlimited edits (normally 3 edits then 24h lock)"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }

                Spacer()

                Toggle("", isOn: $cooldownDisabled)
                    .labelsHidden()
                    .tint(DS.Color.warning)
                    .onChange(of: cooldownDisabled) { newValue in
                        ProfileEditCooldown.shared.isDisabled = newValue
                    }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)

            DSDivider()

            // تصفير العداد
            Button { showResetCooldownAlert = true } label: {
                HStack(spacing: DS.Spacing.md) {
                    DSIcon("arrow.counterclockwise.circle.fill", color: DS.Color.warning)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("تصفير العداد", "Reset Cooldown"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.warning)
                        Text(L10n.t("إعادة تعيين جميع فترات الانتظار", "Reset cooldowns"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSBoldButtonStyle())
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Read-Only Banner
    /// شارة "وضع القراءة فقط" — تظهر للمدير غير المالك
    private var readOnlyBanner: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "eye.fill")
                .font(DS.Font.scaled(14, weight: .bold))
                .foregroundColor(DS.Color.info)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("وضع القراءة فقط", "Read-only mode"))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t(
                    "تقدر تتصفّح الإعدادات. التعديل متاح للمالك فقط.",
                    "You can browse settings. Editing is owner-only."
                ))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
            }
            Spacer()
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.info.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Color.info.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - System Info
    private var systemInfoSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("معلومات النظام", "System Info"),
                icon: "info.circle.fill",
                iconColor: DS.Color.info
            )

            VStack(spacing: 0) {
                infoRow(
                    label: L10n.t("إصدار التطبيق", "App Version"),
                    value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") + " (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))"
                )
                DSDivider()
                infoRow(
                    label: L10n.t("المنصة", "Platform"),
                    value: UIDevice.current.systemName + " " + UIDevice.current.systemVersion
                )
                DSDivider()
                infoRow(
                    label: L10n.t("أعضاء العائلة", "Family Members"),
                    value: "\(memberVM.allMembers.filter(\.isCountable).count)"
                )
                DSDivider()
                infoRow(
                    label: L10n.t("مستخدمين مسجلين", "Registered Users"),
                    value: "\(memberVM.allMembers.filter { $0.isCountable && $0.phoneNumber != nil && !($0.phoneNumber ?? "").isEmpty }.count)"
                )
                DSDivider()
                infoRow(
                    label: L10n.t("السيرفر", "Server"),
                    value: "Supabase · Stockholm"
                )
                DSDivider()
                infoRow(
                    label: L10n.t("آخر تحديث", "Last Update"),
                    value: formatDate(appSettingsVM.settings.updatedAt)
                )
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Reset
    private var resetSection: some View {
        Button {
            showResetConfirmation = true
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "arrow.counterclockwise")
                    .font(DS.Font.scaled(14, weight: .bold))
                Text(L10n.t("إعادة تعيين الإعدادات", "Reset Settings"))
                    .font(DS.Font.calloutBold)
            }
            .foregroundColor(DS.Color.error)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .background(DS.Color.error.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Color.error.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Helpers

    private func settingToggle(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        isOn: Bool,
        key: String
    ) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                Text(subtitle)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isOn },
                set: { newVal in
                    Task {
                        await appSettingsVM.updateSetting(
                            key,
                            value: newVal,
                            updatedBy: authVM.currentUser?.id
                        )
                    }
                }
            ))
            .labelsHidden()
            .tint(DS.Color.primary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
            Spacer()
            Text(value)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }

    private func formatDate(_ isoString: String?) -> String {
        guard let isoString, !isoString.isEmpty else {
            return L10n.t("غير محدد", "N/A")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else {
            // try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: isoString) else {
                return isoString
            }
            return formatDisplayDate(date)
        }
        return formatDisplayDate(date)
    }

    private func formatDisplayDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}

// MARK: - إدارة أقسام الرئيسية الديناميكية
struct AdminHomeSectionsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var sections: [HomeSection] = []
    @State private var isLoading = true
    @State private var editing: HomeSection? = nil
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sections.isEmpty {
                    DSEmptyState(icon: "square.grid.2x2",
                                 title: L10n.t("لا توجد أقسام مضافة", "No sections yet"))
                } else {
                    List {
                        ForEach(sections) { s in
                            Button { editing = s } label: {
                                HStack(spacing: DS.Spacing.md) {
                                    Image(systemName: homeSectionSFSymbol(s.icon))
                                        .foregroundColor(Color(hex: s.color))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.title).foregroundColor(DS.Color.textPrimary)
                                        Text((s.type == "link" ? L10n.t("رابط","Link") : L10n.t("محتوى","Content"))
                                             + (s.isActive ? "" : " • " + L10n.t("مخفي","Hidden")))
                                            .font(DS.Font.caption1).foregroundColor(DS.Color.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "pencil").foregroundColor(DS.Color.textTertiary)
                                }
                            }
                        }
                        .onDelete { idx in
                            Task {
                                for i in idx { try? await HomeSectionsStore.delete(id: sections[i].id) }
                                await load()
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.t("أقسام الرئيسية", "Home Sections"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .task { await load() }
        .sheet(item: $editing) { s in
            AdminHomeSectionEditView(section: s) { Task { await load() } }
        }
        .sheet(isPresented: $showNew) {
            AdminHomeSectionEditView(section: nil) { Task { await load() } }
        }
    }

    private func load() async {
        isLoading = true
        sections = (try? await HomeSectionsStore.fetchAll()) ?? []
        isLoading = false
    }
}

struct AdminHomeSectionEditView: View {
    let section: HomeSection?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var type = "link"
    @State private var url = ""
    @State private var contentText = ""
    @State private var imageUrl = ""
    @State private var icon = "link"
    @State private var color = "#2B7A9F"
    @State private var sortOrder = 0
    @State private var isActive = true
    @State private var isSaving = false

    private let presetColors = ["#2B7A9F","#516F80","#B88E33","#2F5C3E","#8C2A2A","#89A6B1"]

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField(L10n.t("العنوان","Title"), text: $title) }
                Section {
                    Picker(L10n.t("النوع","Type"), selection: $type) {
                        Text(L10n.t("رابط","Link")).tag("link")
                        Text(L10n.t("محتوى","Content")).tag("content")
                    }.pickerStyle(.segmented)
                    if type == "link" {
                        TextField(L10n.t("الرابط","URL (https://...)"), text: $url)
                            .keyboardType(.URL).autocapitalization(.none)
                    } else {
                        TextField(L10n.t("النص","Text"), text: $contentText, axis: .vertical).lineLimit(3...6)
                        TextField(L10n.t("رابط الصورة (اختياري)","Image URL (optional)"), text: $imageUrl)
                            .keyboardType(.URL).autocapitalization(.none)
                    }
                }
                Section(L10n.t("الأيقونة","Icon")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Spacing.md) {
                            ForEach(kHomeSectionIconKeys, id: \.self) { k in
                                Image(systemName: homeSectionSFSymbol(k))
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill((icon == k ? DS.Color.primary : DS.Color.textTertiary).opacity(0.15)))
                                    .foregroundColor(icon == k ? DS.Color.primary : DS.Color.textSecondary)
                                    .onTapGesture { icon = k }
                            }
                        }
                    }
                }
                Section(L10n.t("اللون","Color")) {
                    HStack(spacing: DS.Spacing.md) {
                        ForEach(presetColors, id: \.self) { c in
                            Circle().fill(Color(hex: c)).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(color == c ? DS.Color.textPrimary : .clear, lineWidth: 2))
                                .onTapGesture { color = c }
                        }
                    }
                }
                Section {
                    Stepper(L10n.t("الترتيب: \(sortOrder)", "Order: \(sortOrder)"), value: $sortOrder, in: 0...99)
                    Toggle(L10n.t("ظاهر","Visible"), isOn: $isActive).tint(DS.Color.primary)
                }
            }
            .navigationTitle(section == nil ? L10n.t("إضافة قسم","Add Section") : L10n.t("تعديل القسم","Edit Section"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(L10n.t("إلغاء","Cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("حفظ","Save")) { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .onAppear {
            if let s = section {
                title = s.title; type = s.type; url = s.url ?? ""
                contentText = s.contentText ?? ""; imageUrl = s.imageUrl ?? ""
                icon = s.icon; color = s.color; sortOrder = s.sortOrder; isActive = s.isActive
            }
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        isSaving = true
        let payload: [String: AnyEncodable] = [
            "title": AnyEncodable(t),
            "icon": AnyEncodable(icon),
            "color": AnyEncodable(color),
            "type": AnyEncodable(type),
            "url": AnyEncodable(type == "link" ? url : Optional<String>.none),
            "content_text": AnyEncodable(type == "content" ? contentText : Optional<String>.none),
            "image_url": AnyEncodable(type == "content" ? imageUrl : Optional<String>.none),
            "sort_order": AnyEncodable(sortOrder),
            "is_active": AnyEncodable(isActive)
        ]
        Task {
            try? await HomeSectionsStore.upsert(payload, id: section?.id)
            await MainActor.run { isSaving = false; onSaved(); dismiss() }
        }
    }
}
