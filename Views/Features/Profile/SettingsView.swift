import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel

    @ObservedObject var langManager = LanguageManager.shared
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @State private var showDeleteConfirmation = false
    @State private var showAbout = false
    @State private var showTerms = false

    private var isArabic: Bool { langManager.selectedLanguage == "ar" }
    private func t(_ ar: String, _ en: String) -> String { isArabic ? ar : en }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                DSDecorativeBackground()

                ScrollView {
                    VStack(spacing: DS.Spacing.xxl) {

                        // MARK: - App Preferences Section
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            DSSectionHeader(
                                title: t("تفضيلات التطبيق", "App Preferences"),
                                icon: "gearshape.2.fill"
                            )

                            DSCard(padding: 0) {
                                // Gradient accent line at top
                                

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
                                .padding(.vertical, DS.Spacing.md)

                                DSDivider()

                                // Language Row
                                HStack(spacing: DS.Spacing.md) {
                                    DSIcon("character.bubble.fill", color: DS.Color.primary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t("لغة التطبيق", "App Language"))
                                            .font(DS.Font.calloutBold)
                                        Text(t("العربية", "Arabic") + " / " + t("الإنجليزية", "English"))
                                            .font(DS.Font.caption1)
                                            .foregroundColor(DS.Color.textSecondary)
                                    }

                                    Spacer()

                                    Picker("", selection: $langManager.selectedLanguage) {
                                        Text(t("الإنجليزية", "English")).tag("en")
                                        Text("العربية").tag("ar")
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 160)
                                }
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.md)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // MARK: - Information Section
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            DSSectionHeader(
                                title: t("معلومات", "Information"),
                                icon: "info.circle.fill"
                            )

                            DSCard(padding: 0) {
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
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // MARK: - Danger Zone (Delete Account)
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            DSSectionHeader(
                                title: t("منطقة الخطر", "Danger Zone"),
                                icon: "exclamationmark.triangle.fill"
                            )

                            DSCard(padding: 0) {
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
                                    .padding(.vertical, DS.Spacing.md)
                                }
                                .buttonStyle(DSBoldButtonStyle())
                            }
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                }
            }
        }
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
    }

    // MARK: - Action Row
    private func settingActionRow(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: color)

            Text(title)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)

            Spacer()

            Image(systemName: isArabic ? "chevron.left" : "chevron.right")
                .font(DS.Font.scaled(13, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .contentShape(Rectangle())
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
                            .foregroundColor(.white)
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

#Preview {
    SettingsView()
        .environmentObject(AuthViewModel())
}
