import SwiftUI

// MARK: - Admin App Settings — إعدادات التطبيق
struct AdminAppSettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel

    // إعدادات محلية (AppStorage) يمكن للمدير تغييرها
    @AppStorage("admin_newsRequiresApproval") private var newsRequiresApproval = true
    @AppStorage("admin_allowNewRegistrations") private var allowNewRegistrations = true
    @AppStorage("admin_trialEnabled") private var trialEnabled = true
    @AppStorage("admin_maintenanceMode") private var maintenanceMode = false
    @AppStorage("admin_maxDevicesPerUser") private var maxDevicesPerUser = 3

    @State private var showResetConfirmation = false

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.xxl) {

                    // التسجيل والعضوية
                    registrationSection
                        .padding(.top, DS.Spacing.md)

                    // الأخبار والمحتوى
                    contentSection

                    // الأمان
                    securitySection

                    // معلومات النظام
                    systemInfoSection

                    // إعادة تعيين
                    resetSection

                    Spacer(minLength: DS.Spacing.xxxl)
                }
            }
        }
        .navigationTitle(L10n.t("إعدادات التطبيق", "App Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .alert(
            L10n.t("إعادة تعيين", "Reset Settings"),
            isPresented: $showResetConfirmation
        ) {
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            Button(L10n.t("إعادة تعيين", "Reset"), role: .destructive) {
                resetToDefaults()
            }
        } message: {
            Text(L10n.t(
                "سيتم إرجاع جميع الإعدادات إلى القيم الافتراضية",
                "All settings will be restored to default values"
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
                subtitle: L10n.t("السماح لأعضاء جدد بالتسجيل في التطبيق", "Allow new members to register in the app"),
                isOn: $allowNewRegistrations
            )

            DSDivider()

            // الفترة التجريبية
            settingToggle(
                icon: "clock.badge.checkmark",
                color: DS.Color.warning,
                title: L10n.t("الفترة التجريبية", "Trial Period"),
                subtitle: L10n.t("تفعيل فترة ٧ أيام تجريبية للأعضاء الجدد", "Enable 7-day trial for new members"),
                isOn: $trialEnabled
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
                    "\(maxDevicesPerUser)",
                    value: $maxDevicesPerUser,
                    in: 1...10
                )
                .labelsHidden()
                .frame(width: 100)

                Text("\(maxDevicesPerUser)")
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
                subtitle: L10n.t("يتطلب موافقة المدير قبل نشر الأخبار", "Require admin approval before publishing news"),
                isOn: $newsRequiresApproval
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
                subtitle: L10n.t("إيقاف التطبيق مؤقتاً للصيانة (المدراء فقط)", "Temporarily disable app for maintenance (admins only)"),
                isOn: $maintenanceMode
            )
        }
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
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                )
                DSDivider()
                infoRow(
                    label: L10n.t("رقم البناء", "Build Number"),
                    value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
                )
                DSDivider()
                infoRow(
                    label: L10n.t("إجمالي الأعضاء", "Total Members"),
                    value: "\(memberVM.allMembers.count)"
                )
                DSDivider()
                infoRow(
                    label: L10n.t("الإشعارات", "Notifications"),
                    value: authVM.notificationsFeatureAvailable
                        ? L10n.t("مفعّلة", "Enabled")
                        : L10n.t("معطّلة", "Disabled")
                )
                DSDivider()
                infoRow(
                    label: L10n.t("موافقات الأخبار", "News Approvals"),
                    value: authVM.newsApprovalFeatureAvailable
                        ? L10n.t("مفعّلة", "Enabled")
                        : L10n.t("معطّلة", "Disabled")
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
        isOn: Binding<Bool>
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

            Toggle("", isOn: isOn)
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

    private func resetToDefaults() {
        newsRequiresApproval = true
        allowNewRegistrations = true
        trialEnabled = true
        maintenanceMode = false
        maxDevicesPerUser = 3
    }
}
