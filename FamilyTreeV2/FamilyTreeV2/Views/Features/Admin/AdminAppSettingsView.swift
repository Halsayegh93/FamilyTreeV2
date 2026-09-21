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

    /// المالك يعدّل، باقي المدراء يتصفّحون فقط.
    private var canEdit: Bool { authVM.canManageSettings }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.xxl) {
                    // الوضع الأفقي: الأقسام على عمودين
                    AdaptiveCardStack(spacing: DS.Spacing.xxl, landscapeMinimum: 340) {

                    // إشعار وضع القراءة فقط (لغير المالك)
                    if !canEdit {
                        readOnlyBanner
                            .padding(.top, DS.Spacing.md)
                    }

                    // معلومات النظام
                    systemInfoSection
                        .padding(.top, canEdit ? DS.Spacing.md : 0)

                    // لغة التطبيق الرسمية
                    languageSection
                        .disabled(!canEdit)

                    // التصنيفات — الأخبار والمكتبة
                    categoriesSection

                    // التسجيل والعضوية
                    registrationSection
                        .disabled(!canEdit)

                    // الأخبار والمحتوى
                    contentSection
                        .disabled(!canEdit)

                    // الميزات
                    featuresSection
                        .disabled(!canEdit)

                    // عداد التعديل
                    cooldownSection
                        .disabled(!canEdit)

                    // الأمان
                    securitySection
                        .disabled(!canEdit)

                    // إعادة تعيين — يبقى مرئيّ بس مُعطّل لغير المالك
                    resetSection
                        .disabled(!canEdit)
                    }

                    Spacer(minLength: DS.Spacing.xxxl)
                }
            }
        }
        .navigationTitle(L10n.t("إعدادات التطبيق", "App Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            await appSettingsVM.fetchSettings()
        }
        .dsAlert(
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
        .dsAlert(
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
    // MARK: - التصنيفات (طلب المالك)
    private var categoriesSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("التصنيفات", "Categories"),
                icon: "tag.fill",
                iconColor: DS.Color.accent
            )
            NavigationLink {
                CategoriesManagerView()
                    .environmentObject(authVM)
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("تصنيفات الأخبار والمكتبة", "News & library categories"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(L10n.t("الاسم والأيقونة واللون، والإخفاء والترتيب",
                                    "Name, icon, colour, hide and order"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.textTertiary)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - لغة التطبيق الرسمية (طلب المالك)
    //
    // تُطبَّق على كل مستخدم لم يختر لغته بنفسه. من يغيّر اللغة من «الإعدادات»
    // تبقى لغته هو.
    private var languageSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("لغة التطبيق الرسمية", "Official App Language"),
                icon: "character.bubble.fill",
                iconColor: DS.Color.secondary
            )

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Picker("", selection: Binding(
                    get: { appSettingsVM.settings.defaultLanguage ?? "ar" },
                    set: { newValue in
                        Task {
                            await appSettingsVM.updateSetting(
                                "default_language",
                                value: newValue,
                                updatedBy: authVM.currentUser?.id
                            )
                        }
                    }
                )) {
                    Text("العربية").tag("ar")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)

                Text(L10n.t(
                    "لغة التطبيق لكل الأعضاء. من يغيّر لغته من «الإعدادات» تبقى لغته هو.",
                    "The app language for all members. Anyone who picks a language in Settings keeps their own."
                ))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.lg)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

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
        }
        .padding(.horizontal, DS.Spacing.lg)
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
                    Text(L10n.t("السماح بالتعديل بدون حد (عادةً 3 تعديلات ثم موافقة الإدارة)", "Allow unlimited edits (normally 3 edits, then admin approval)"))
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
                        Text(L10n.t("إعادة عدّاد التعديلات من الصفر", "Reset edit counters"))
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
