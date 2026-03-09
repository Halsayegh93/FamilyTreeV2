import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel

    @ObservedObject var langManager = LanguageManager.shared
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @State private var showDeleteConfirmation = false
    @State private var showAbout = false
    @State private var showTerms = false
    @State private var showLinkedDevices = false

    private var isArabic: Bool { langManager.selectedLanguage == "ar" }
    private func t(_ ar: String, _ en: String) -> String { isArabic ? ar : en }

    var body: some View {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                DSDecorativeBackground()

                ScrollView {
                    VStack(spacing: DS.Spacing.xxl) {

                        // MARK: - App Preferences Section
                            DSCard(padding: 0) {
                                DSSectionHeader(
                                    title: t("تفضيلات التطبيق", "App Preferences"),
                                    icon: "gearshape.2.fill"
                                )

                                // Appearance Row
                                HStack(spacing: DS.Spacing.md) {
                                    DSIcon("circle.lefthalf.filled", color: DS.Color.gridTree)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t("مظهر التطبيق", "Appearance"))
                                            .font(DS.Font.calloutBold)
                                        Text(appearanceLabel)
                                            .font(DS.Font.caption1)
                                            .foregroundColor(DS.Color.textSecondary)
                                    }

                                    Spacer()

                                    Picker("", selection: $appearanceMode) {
                                        Text(t("حسب الجهاز", "System")).tag("system")
                                        Text(t("فاتح", "Light")).tag("light")
                                        Text(t("داكن", "Dark")).tag("dark")
                                    }
                                    .pickerStyle(.menu)
                                    .tint(DS.Color.gridTree)
                                }
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.xs)

                                DSDivider()

                                // Language Row
                                HStack(spacing: DS.Spacing.md) {
                                    DSIcon("character.bubble.fill", color: DS.Color.primary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t("لغة التطبيق", "App Language"))
                                            .font(DS.Font.calloutBold)
                                        Text(languageLabel)
                                            .font(DS.Font.caption1)
                                            .foregroundColor(DS.Color.textSecondary)
                                    }

                                    Spacer()

                                    Picker("", selection: $langManager.selectedLanguage) {
                                        Text(t("الإنجليزية", "English")).tag("en")
                                        Text("العربية").tag("ar")
                                    }
                                    .pickerStyle(.menu)
                                    .tint(DS.Color.primary)
                                }
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.xs)

                                DSDivider()

                                // Linked Devices Row
                                Button { showLinkedDevices = true } label: {
                                    settingActionRow(
                                        title: t("الأجهزة المرتبطة", "Linked Devices"),
                                        subtitle: t(
                                            "\(notificationVM.linkedDevices.count) جهاز مرتبط",
                                            "\(notificationVM.linkedDevices.count) linked device\(notificationVM.linkedDevices.count == 1 ? "" : "s")"
                                        ),
                                        icon: "iphone.gen3",
                                        color: DS.Color.neonBlue
                                    )
                                }
                                .buttonStyle(DSBoldButtonStyle())
                            }
                        .padding(.horizontal, DS.Spacing.lg)

                        // MARK: - Information Section
                            DSCard(padding: 0) {
                                DSSectionHeader(
                                    title: t("معلومات", "Information"),
                                    icon: "info.circle.fill"
                                )

                                Button(action: { showAbout = true }) {
                                    settingActionRow(
                                        title: t("عن التطبيق", "About FamilyTree"),
                                        icon: "app.badge.fill",
                                        color: DS.Color.warning
                                    )
                                }
                                .buttonStyle(DSBoldButtonStyle())

                                DSDivider()

                                Button(action: { showTerms = true }) {
                                    settingActionRow(
                                        title: t("سياسة الخصوصية والشروط", "Privacy Policy & Terms"),
                                        icon: "doc.text.fill",
                                        color: DS.Color.accent
                                    )
                                }
                                .buttonStyle(DSBoldButtonStyle())
                            }
                        .padding(.horizontal, DS.Spacing.lg)

                        // MARK: - Danger Zone (Delete Account)
                            DSCard(padding: 0) {
                                DSSectionHeader(
                                    title: t("منطقة الخطر", "Danger Zone"),
                                    icon: "exclamationmark.triangle.fill",
                                    iconColor: DS.Color.error
                                )

                                Button(action: { showDeleteConfirmation = true }) {
                                    HStack(spacing: DS.Spacing.md) {
                                        DSIcon("trash.fill", color: DS.Color.error)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(t("حذف الحساب", "Delete Account"))
                                                .font(DS.Font.calloutBold)
                                                .foregroundColor(DS.Color.error)
                                            Text(t("حذف جميع بياناتك نهائياً", "Permanently delete all your data"))
                                                .font(DS.Font.caption1)
                                                .foregroundColor(DS.Color.textSecondary)
                                        }

                                        Spacer()

                                        Image(systemName: isArabic ? "chevron.left" : "chevron.right")
                                            .font(DS.Font.scaled(13, weight: .bold))
                                            .foregroundColor(DS.Color.textTertiary)
                                    }
                                    .padding(.horizontal, DS.Spacing.lg)
                                    .padding(.vertical, DS.Spacing.xs)
                                }
                                .buttonStyle(DSBoldButtonStyle())
                            }
                        .padding(.horizontal, DS.Spacing.lg)

                        // Version text (dynamic from Bundle)
                        Text(t(
                            "إصدار التطبيق \(appVersion)",
                            "App Version \(appVersion)"
                        ))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textTertiary)
                            .padding(.top, DS.Spacing.md)
                    }
                    .padding(.top, DS.Spacing.xl)
                }
            }
            .navigationTitle(t("الإعدادات", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, langManager.layoutDirection)
        .alert(
            t("حذف الحساب", "Delete Account"),
            isPresented: $showDeleteConfirmation
        ) {
            Button(t("إلغاء", "Cancel"), role: .cancel) {}
            Button(t("حذف نهائي", "Delete Permanently"), role: .destructive) {
                Task {
                    let success = await authVM.deleteAccount()
                    if success { dismiss() }
                }
            }
        } message: {
            Text(t(
                "هل أنت متأكد؟ سيتم حذف حسابك وجميع بياناتك نهائياً ولا يمكن التراجع عن هذا الإجراء.",
                "Are you sure? Your account and all data will be permanently deleted. This action cannot be undone."
            ))
        }
        .alert(
            t("خطأ", "Error"),
            isPresented: .init(
                get: { authVM.deleteAccountError != nil },
                set: { if !$0 { authVM.deleteAccountError = nil } }
            )
        ) {
            Button(t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(authVM.deleteAccountError ?? "")
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .sheet(isPresented: $showTerms) {
            PrivacyPolicyView()
        }
        .sheet(isPresented: $showLinkedDevices) {
            LinkedDevicesSettingsSheet()
        }
        .task {
            await notificationVM.fetchLinkedDevices()
        }
    }

    // MARK: - Action Row
    private func settingActionRow(title: String, subtitle: String? = nil, icon: String, color: Color) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }

            Spacer()

            Image(systemName: isArabic ? "chevron.left" : "chevron.right")
                .font(DS.Font.scaled(13, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
        .contentShape(Rectangle())
    }

    private var languageLabel: String {
        langManager.selectedLanguage == "ar" ? "العربية" : "English"
    }

    private var appearanceLabel: String {
        switch appearanceMode {
        case "light": return t("فاتح", "Light")
        case "dark": return t("داكن", "Dark")
        default: return t("حسب الجهاز", "System")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - About View
struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    private var isArabic: Bool { LanguageManager.shared.selectedLanguage == "ar" }
    private func t(_ ar: String, _ en: String) -> String { isArabic ? ar : en }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: DS.Spacing.xxl) {
                    Spacer()

                    ZStack {
                        Circle()
                            .fill(DS.Color.gradientPrimary)
                            .frame(width: 90, height: 90)
                            .dsGlowShadow()

                        Image(systemName: "tree.fill")
                            .font(DS.Font.scaled(38, weight: .bold))
                            .foregroundColor(DS.Color.textOnPrimary)
                    }

                    VStack(spacing: DS.Spacing.md) {
                        Text(t("شجرة العائلة", "FamilyTree"))
                            .font(DS.Font.title2)
                            .fontWeight(.black)
                            .foregroundColor(DS.Color.textPrimary)

                        Text(t(
                            "تطبيق شجرة العائلة يساعدك في بناء وإدارة شجرة عائلتك، التواصل مع أفراد العائلة، ومشاركة الأخبار والمناسبات العائلية.",
                            "FamilyTree helps you build and manage your family tree, connect with family members, and share family news and events."
                        ))
                        .font(DS.Font.body)
                        .foregroundColor(DS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Spacing.xxl)
                    }

                    Spacer()

                    Text(t("صُنع بحب 🤍", "Made with love 🤍"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                        .padding(.bottom, DS.Spacing.xxl)
                }
            }
            .navigationTitle(t("عن التطبيق", "About"))
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
    }
}

// MARK: - Privacy Policy View
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) var dismiss
    private var isArabic: Bool { LanguageManager.shared.selectedLanguage == "ar" }
    private func t(_ ar: String, _ en: String) -> String { isArabic ? ar : en }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.xl) {

                        policySection(
                            title: t("جمع البيانات", "Data Collection"),
                            content: t(
                                "نجمع فقط البيانات الضرورية لتشغيل التطبيق: الاسم، رقم الهاتف، تاريخ الميلاد، والصور التي تختار مشاركتها. لا نجمع بيانات الموقع أو جهات الاتصال.",
                                "We only collect data necessary to operate the app: name, phone number, date of birth, and photos you choose to share. We do not collect location data or contacts."
                            )
                        )

                        policySection(
                            title: t("استخدام البيانات", "Data Usage"),
                            content: t(
                                "تُستخدم بياناتك فقط داخل التطبيق لعرض شجرة العائلة والتواصل بين الأعضاء. لا نبيع أو نشارك بياناتك مع أطراف خارجية.",
                                "Your data is used only within the app to display the family tree and facilitate communication between members. We do not sell or share your data with third parties."
                            )
                        )

                        policySection(
                            title: t("تخزين البيانات", "Data Storage"),
                            content: t(
                                "تُخزن بياناتك بشكل آمن على خوادم Supabase المشفرة. نستخدم بروتوكول HTTPS لجميع الاتصالات.",
                                "Your data is securely stored on encrypted Supabase servers. We use HTTPS for all communications."
                            )
                        )

                        policySection(
                            title: t("حذف البيانات", "Data Deletion"),
                            content: t(
                                "يمكنك حذف حسابك وجميع بياناتك في أي وقت من صفحة الإعدادات. عند الحذف، تُزال جميع بياناتك الشخصية نهائياً من خوادمنا.",
                                "You can delete your account and all your data at any time from the Settings page. Upon deletion, all your personal data is permanently removed from our servers."
                            )
                        )

                        policySection(
                            title: t("الإشعارات", "Notifications"),
                            content: t(
                                "نرسل إشعارات حول الأخبار العائلية وطلبات الانضمام فقط. يمكنك تعطيل الإشعارات من إعدادات جهازك في أي وقت.",
                                "We send notifications about family news and join requests only. You can disable notifications from your device settings at any time."
                            )
                        )

                        policySection(
                            title: t("التواصل معنا", "Contact Us"),
                            content: t(
                                "إذا كانت لديك أي أسئلة حول سياسة الخصوصية، يمكنك التواصل معنا عبر مركز التواصل داخل التطبيق.",
                                "If you have any questions about the privacy policy, you can reach us through the Contact Center within the app."
                            )
                        )
                    }
                    .padding(DS.Spacing.xl)
                }
            }
            .navigationTitle(t("سياسة الخصوصية", "Privacy Policy"))
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
    }

    private func policySection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title)
                .font(DS.Font.headline)
                .fontWeight(.black)
                .foregroundColor(DS.Color.textPrimary)

            Text(content)
                .font(DS.Font.body)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.leading)
        }
    }
}

// MARK: - Linked Devices Settings Sheet
struct LinkedDevicesSettingsSheet: View {
    @Environment(\.dismiss) var dismiss
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
                                iconColor: DS.Color.neonBlue
                            )

                            // Device count info cell
                            HStack(spacing: DS.Spacing.sm) {
                                Image(systemName: "info.circle.fill")
                                    .font(DS.Font.scaled(16, weight: .bold))
                                    .foregroundColor(DS.Color.info)
                                    .frame(width: 36, height: 36)
                                    .background(DS.Color.info.opacity(0.12))
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
                                        .foregroundColor(DS.Color.textPrimary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.vertical, DS.Spacing.xs)

                            DSDivider()

                            // Device rows
                            if notificationVM.linkedDevices.isEmpty {
                                HStack(spacing: DS.Spacing.sm) {
                                    Image(systemName: "iphone.slash")
                                        .font(DS.Font.scaled(16, weight: .bold))
                                        .foregroundColor(DS.Color.textTertiary)
                                        .frame(width: 36, height: 36)
                                        .background(DS.Color.textTertiary.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                                    Text(t("لا توجد أجهزة مرتبطة", "No linked devices"))
                                        .font(DS.Font.callout)
                                        .foregroundColor(DS.Color.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.xs)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(notificationVM.linkedDevices.enumerated()), id: \.element.id) { index, device in
                                        if index > 0 { DSDivider() }
                                        deviceRow(device)
                                    }
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
        .task {
            await notificationVM.fetchLinkedDevices()
        }
    }

    private func deviceRow(_ device: NotificationViewModel.LinkedDevice) -> some View {
        let isCurrent = device.isCurrent(currentDeviceId: notificationVM.currentDeviceId)
        return HStack(spacing: DS.Spacing.md) {
            DSIcon(
                "iphone.gen3",
                color: isCurrent ? DS.Color.success : DS.Color.accent
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Spacing.sm) {
                    Text(device.displayName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)

                    if isCurrent {
                        Text(t("الحالي", "Current"))
                            .font(DS.Font.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.textOnPrimary)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(DS.Color.success)
                            .clipShape(Capsule())
                    }
                }

                Text(formattedDate(device.updatedAt))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
            }

            Spacer()

            if !isCurrent {
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

#Preview {
    SettingsView()
        .environmentObject(AuthViewModel())
        .environmentObject(NotificationViewModel())
}
