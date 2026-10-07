import SwiftUI

// MARK: - Admin App Settings — إعدادات التطبيق
//
// تصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧): بطاقة رأس بأرقام حيّة، ثم أقسام
// `DSComposerSection` وصفوف `.dsRowBox()` (أيقونة حقل + عنوان + وصف + مفتاح). المالك يعدّل،
// والمدير يتصفّح للقراءة (الأقسام معطّلة له كما كانت).
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

    var body: some View { page }

    private var alerts: AppSettingsAlerts {
        AppSettingsAlerts(
            showReset: $showResetConfirmation,
            showResetCooldown: $showResetCooldownAlert,
            onReset: { Task { await appSettingsVM.resetToDefaults(updatedBy: authVM.currentUser?.id) } }
        )
    }

    private var page: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.lg) {
                hero

                // الوضع الأفقي: الأقسام على عمودين
                AdaptiveCardStack(spacing: DS.Spacing.md, alignment: .leading) {
                    sections
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xxxl)
        }
        // الرأس الملوّن الموحّد (كان شريط النظام + بطاقة رأس)
        .dsSubPageHeader(L10n.t("إعدادات التطبيق", "App Settings"),
                         subtitle: canEdit
                            ? L10n.t("اللغة · التسجيل · الميزات", "Language · Sign-up · Features")
                            : L10n.t("وضع القراءة فقط — التعديل للمالك", "Read-only — the owner edits"))
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            await appSettingsVM.fetchSettings()
        }
        .modifier(alerts)
    }

    // MARK: - بطاقة الرأس

    private var registeredUsersCount: Int {
        memberVM.allMembers.filter { $0.isCountable && $0.phoneNumber != nil && !($0.phoneNumber ?? "").isEmpty }.count
    }

    /// الميزات الظاهرة للأعضاء (الديوانيات، المشاريع، شجرة النساء)
    private var enabledFeaturesCount: Int {
        let s = appSettingsVM.settings
        // «ألبوم الصور» أُزيل — لا يوجد قسم ألبوم في التطبيق (طلب المالك ٢٠٢٦-١٠-٠٧)
        return [s.diwaniyasEnabled ?? true, s.projectsEnabled ?? true, s.womenTreeEnabled ?? true]
            .filter { $0 }.count
    }

    /// العنوان والوصف في الرأس الملوّن — الأرقام هنا
    private var hero: some View {
        DSStatsRow([
                DSHeroStat(value: "\(enabledFeaturesCount)/3",
                           label: L10n.t("ميزات مفعّلة", "Features on"), icon: "star.fill"),
                DSHeroStat(value: "\(appSettingsVM.settings.maxDevicesPerUser)",
                           label: L10n.t("أجهزة لكل عضو", "Devices / user"), icon: "iphone.gen3"),
                DSHeroStat(value: "\(registeredUsersCount)",
                           label: L10n.t("مستخدمين مسجلين", "Registered users"), icon: "person.crop.circle.badge.checkmark")
        ], tint: DS.Color.actionNavy)
    }

    @ViewBuilder private var sections: some View {
        // إشعار وضع القراءة فقط (لغير المالك)
        if !canEdit {
            readOnlyBanner
        }

        // معلومات النظام
        systemInfoSection

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

    // MARK: - التصنيفات (طلب المالك)
    private var categoriesSection: some View {
        DSComposerSection(title: L10n.t("التصنيفات", "Categories"),
                          icon: "tag.fill",
                          tint: DS.Color.composerLibrary,
                          index: 3) {
            NavigationLink {
                CategoriesManagerView()
                    .environmentObject(authVM)
            } label: {
                DSRow(icon: "tag.fill", tint: DS.Color.accent,
                       title: L10n.t("تصنيفات الأخبار والمكتبة", "News & library categories"),
                       subtitle: L10n.t("الاسم والأيقونة واللون، والإخفاء والترتيب",
                                        "Name, icon, colour, hide and order")) {
                    DSChevron()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(DSScaleButtonStyle())
        }
    }

    // MARK: - لغة التطبيق الرسمية (طلب المالك)
    //
    // تُطبَّق على كل مستخدم لم يختر لغته بنفسه. من يغيّر اللغة من «الإعدادات»
    // تبقى لغته هو.
    private var languageSection: some View {
        DSComposerSection(title: L10n.t("لغة التطبيق الرسمية", "Official App Language"),
                          icon: "character.bubble.fill",
                          tint: DS.Color.actionNavy,
                          trailing: (appSettingsVM.settings.defaultLanguage ?? "ar") == "ar" ? "العربية" : "English",
                          index: 2) {
            // المبدّل الواحد (`DSSegmentedSwitch`) بدل مبدّل النظام الرمادي
            DSSegmentedSwitch(options: [
                DSSegmentOption(id: "ar", title: "العربية", icon: "character.bubble.fill.ar"),
                DSSegmentOption(id: "en", title: "English", icon: "textformat.abc")
            ], selection: Binding(
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
            ), size: .regular)
            .accessibilityLabel(L10n.t("لغة التطبيق الرسمية", "Official App Language"))

            Text(L10n.t(
                "لغة التطبيق لكل الأعضاء. من يغيّر لغته من «الإعدادات» تبقى لغته هو.",
                "The app language for all members. Anyone who picks a language in Settings keeps their own."
            ))
            .dsFieldFont(.footnote)
            .foregroundColor(DS.Color.fieldValue)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Registration & Membership
    private var registrationSection: some View {
        DSComposerSection(title: L10n.t("التسجيل والعضوية", "Registration & Membership"),
                          icon: "person.badge.key.fill",
                          tint: DS.Color.composerProject,
                          index: 4) {
            // السماح بالتسجيل الجديد
            settingToggle(
                icon: "person.badge.plus",
                color: DS.Color.success,
                title: L10n.t("السماح بالتسجيل", "Allow Registrations"),
                subtitle: L10n.t("السماح لأعضاء جدد بالتسجيل في التطبيق", "Allow new registrations"),
                isOn: appSettingsVM.settings.allowNewRegistrations,
                key: "allow_new_registrations"
            )

            // الحد الأقصى للأجهزة
            DSRow(icon: "iphone.gen3.badge.play", tint: DS.Color.info,
                   title: L10n.t("الحد الأقصى للأجهزة", "Max Devices"),
                   subtitle: L10n.t("عدد الأجهزة المسموحة لكل مستخدم", "Devices allowed per user")) {
                HStack(spacing: DS.Spacing.sm) {
                    Text("\(appSettingsVM.settings.maxDevicesPerUser)")
                        .dsFont(.title)
                        .foregroundColor(AppSection.admin.ink)
                        .monospacedDigit()
                        .frame(minWidth: DS.Icon.section)
                        .accessibilityHidden(true)

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
                    .accessibilityLabel(L10n.t("الحد الأقصى للأجهزة", "Max Devices"))
                    .accessibilityValue("\(appSettingsVM.settings.maxDevicesPerUser)")
                }
            }
        }
    }

    // MARK: - Content Settings
    private var contentSection: some View {
        DSComposerSection(title: L10n.t("الأخبار والمحتوى", "News & Content"),
                          icon: "newspaper.fill",
                          tint: DS.Color.composerLibrary,
                          index: 5) {
            // موافقة الأخبار
            settingToggle(
                icon: "checkmark.shield.fill",
                color: DS.Color.warning,
                title: L10n.t("موافقة الأخبار", "News Approval"),
                subtitle: L10n.t("يتطلب موافقة المدير قبل نشر الأخبار", "Require admin approval"),
                isOn: appSettingsVM.settings.newsRequiresApproval,
                key: "news_requires_approval"
            )

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
    }

    // MARK: - Features
    private var featuresSection: some View {
        DSComposerSection(title: L10n.t("الميزات", "Features"),
                          icon: "star.fill",
                          tint: DS.Color.actionNavy,
                          trailing: "\(enabledFeaturesCount)/3",
                          index: 6) {
            settingToggle(
                icon: AppSection.diwaniyas.symbol,   // «مجلس»
                color: AppSection.admin.ink,
                title: L10n.t("الديوانيات", "Diwaniyas"),
                subtitle: L10n.t("إظهار تاب الديوانيات للأعضاء", "Show Diwaniyas tab to members"),
                isOn: appSettingsVM.settings.diwaniyasEnabled ?? true,
                key: "diwaniyas_enabled"
            )

            settingToggle(
                icon: "briefcase.fill",
                color: DS.Color.accent,
                title: L10n.t("مشاريع العائلة", "Family Projects"),
                subtitle: L10n.t("إظهار قسم المشاريع في الرئيسية", "Show Projects section on Home"),
                isOn: appSettingsVM.settings.projectsEnabled ?? true,
                key: "projects_enabled"
            )

            // إخفاء «شجرة النساء» من قسم الشجرة (طلب المالك ٢٠٢٦-١٠-٠٧) — للجميع حتى يُعاد تشغيلها من هنا
            settingToggle(
                icon: "person.2.fill",
                color: DS.Color.female,
                title: L10n.t("شجرة النساء", "Women's Tree"),
                subtitle: L10n.t("إظهار تبويب النساء في قسم الشجرة", "Show the Women tab in the Tree section"),
                isOn: appSettingsVM.settings.womenTreeEnabled ?? true,
                key: "women_tree_enabled"
            )
        }
    }

    // MARK: - Security
    private var securitySection: some View {
        DSComposerSection(title: L10n.t("الأمان والصيانة", "Security & Maintenance"),
                          icon: "lock.shield.fill",
                          tint: DS.Color.error,
                          trailing: appSettingsVM.settings.maintenanceMode ? L10n.t("مفعّل", "On") : nil,
                          index: 8) {
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
    }

    // MARK: - Edit Cooldown
    private var cooldownSection: some View {
        DSComposerSection(title: L10n.t("عداد التعديل", "Edit Cooldown"),
                          icon: "timer",
                          tint: DS.Color.composerProject,
                          index: 7) {
            // إيقاف / تشغيل العداد
            DSRow(icon: "pause.circle.fill", tint: DS.Color.warning,
                   title: L10n.t("إيقاف العداد", "Disable Cooldown"),
                   subtitle: L10n.t("السماح بالتعديل بدون حد (عادةً 3 تعديلات ثم موافقة الإدارة)",
                                    "Allow unlimited edits (normally 3 edits, then admin approval)")) {
                Toggle("", isOn: $cooldownDisabled)
                    .labelsHidden()
                    .tint(DS.Color.warning)
                    .accessibilityLabel(L10n.t("إيقاف العداد", "Disable Cooldown"))
                    .onChange(of: cooldownDisabled) { newValue in
                        ProfileEditCooldown.shared.isDisabled = newValue
                    }
            }

            // تصفير العداد
            Button { showResetCooldownAlert = true } label: {
                DSRow(icon: "arrow.counterclockwise.circle.fill", tint: DS.Color.warning,
                       title: L10n.t("تصفير العداد", "Reset Cooldown"),
                       subtitle: L10n.t("إعادة عدّاد التعديلات من الصفر", "Reset edit counters")) {
                    DSChevron()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(DSScaleButtonStyle())
        }
    }

    // MARK: - Read-Only Banner
    /// شارة "وضع القراءة فقط" — تظهر للمدير غير المالك
    private var readOnlyBanner: some View {
        DSNoteCard(L10n.t("تقدر تتصفّح الإعدادات. التعديل متاح للمالك فقط.",
                          "You can browse settings. Editing is owner-only."),
                   title: L10n.t("وضع القراءة فقط", "Read-only mode"),
                   icon: "eye.fill")
            .dsStaggerIn(0)
    }

    // MARK: - System Info
    private var systemInfoSection: some View {
        DSComposerSection(title: L10n.t("معلومات النظام", "System Info"),
                          icon: "info.circle.fill",
                          tint: DS.Color.actionNavy,
                          index: 1) {
            // حالة سريعة: التسجيل والصيانة
            HStack(spacing: DS.Spacing.xs) {
                DSStatusChip(
                    text: appSettingsVM.settings.allowNewRegistrations
                        ? L10n.t("التسجيل مفتوح", "Sign-up open")
                        : L10n.t("التسجيل مغلق", "Sign-up closed"),
                    icon: appSettingsVM.settings.allowNewRegistrations ? "person.badge.plus" : "person.fill.xmark",
                    tint: appSettingsVM.settings.allowNewRegistrations ? DS.Color.success : DS.Color.warning
                )
                if appSettingsVM.settings.maintenanceMode {
                    DSStatusChip(text: L10n.t("وضع الصيانة", "Maintenance"),
                                  icon: "wrench.and.screwdriver.fill", tint: DS.Color.error)
                }
                Spacer(minLength: 0)
            }

            infoRow(icon: "app.badge.fill",
                    label: L10n.t("إصدار التطبيق", "App Version"),
                    value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") + " (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
            infoRow(icon: "iphone",
                    label: L10n.t("المنصة", "Platform"),
                    value: UIDevice.current.systemName + " " + UIDevice.current.systemVersion)
            infoRow(icon: "person.3.fill",
                    label: L10n.t("أعضاء العائلة", "Family Members"),
                    value: "\(memberVM.allMembers.filter(\.isCountable).count)")
            infoRow(icon: "person.crop.circle.badge.checkmark",
                    label: L10n.t("مستخدمين مسجلين", "Registered Users"),
                    value: "\(registeredUsersCount)")
            infoRow(icon: "server.rack",
                    label: L10n.t("السيرفر", "Server"),
                    value: "Supabase · Stockholm")
            infoRow(icon: "clock.fill",
                    label: L10n.t("آخر تحديث", "Last Update"),
                    value: formatDate(appSettingsVM.settings.updatedAt))
        }
    }

    // MARK: - Reset
    private var resetSection: some View {
        // الزرّ الواحد بالأحمر (يسأل قبل التنفيذ)
        DSButton(L10n.t("إعادة تعيين الإعدادات", "Reset Settings"), icon: "arrow.counterclockwise",
                 role: .destructive) {
            showResetConfirmation = true
        }
        .dsStaggerIn(9)
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
        DSRow(icon: icon, tint: color, title: title, subtitle: subtitle) {
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
            .tint(AppSection.admin.ink)
            .accessibilityLabel(title)
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: DS.Color.actionNavy)
                .accessibilityHidden(true)
            Text(label)
                .dsFieldFont(.sectionTitle)
                .foregroundColor(DS.Color.fieldValue)
                .lineLimit(1)
            Spacer(minLength: DS.Spacing.sm)
            Text(value)
                .dsFieldFont(.rowTitleCompact)
                .foregroundColor(DS.Color.fieldLabel)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .dsRowBox()
        .accessibilityElement(children: .combine)
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


/// تنبيها «إعادة التعيين» و«تصفير العداد» — مشتركة بين الصفحة والنسخة المضمّنة
private struct AppSettingsAlerts: ViewModifier {
    @Binding var showReset: Bool
    @Binding var showResetCooldown: Bool
    let onReset: () -> Void

    func body(content: Content) -> some View {
        content
            .dsAlert(
                L10n.t("إعادة تعيين", "Reset Settings"),
                isPresented: $showReset
            ) {
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
                Button(L10n.t("إعادة تعيين", "Reset"), role: .destructive) { onReset() }
            } message: {
                Text(L10n.t(
                    "سيتم إرجاع جميع الإعدادات إلى القيم الافتراضية",
                    "All settings will be restored to default values"
                ))
            }
            .dsAlert(
                L10n.t("تصفير العداد", "Reset Cooldown"),
                isPresented: $showResetCooldown
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
}
