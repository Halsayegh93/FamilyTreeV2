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
    @State private var appeared = false

    private var isArabic: Bool { langManager.selectedLanguage == "ar" }
    private func t(_ ar: String, _ en: String) -> String { isArabic ? ar : en }

    var body: some View {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                DSDecorativeBackground()

                ScrollView {
                    VStack(spacing: DS.Spacing.md) {

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
                                            .foregroundColor(DS.Color.textPrimary)
                                        Text(t("اختر الوضع الفاتح أو الداكن أو حسب جهازك", "Choose light, dark, or follow device settings"))
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
                                    .fixedSize()
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
                                            .foregroundColor(DS.Color.textPrimary)
                                        Text(t("تبديل واجهة التطبيق بين العربية والإنجليزية", "Switch between Arabic and English"))
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
                                    .fixedSize()
                                }
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.md)

                                DSDivider()

                                // Linked Devices Row
                                Button { showLinkedDevices = true } label: {
                                    settingActionRow(
                                        title: t("الأجهزة المرتبطة", "Linked Devices"),
                                        subtitle: t(
                                            "إدارة الأجهزة المسجّلة — \(notificationVM.linkedDevices.count) جهاز",
                                            "Manage registered devices — \(notificationVM.linkedDevices.count) device\(notificationVM.linkedDevices.count == 1 ? "" : "s")"
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
                                        subtitle: t("تعرّف على التطبيق ومميزاته", "Learn about the app and its features"),
                                        icon: "app.badge.fill",
                                        color: DS.Color.warning
                                    )
                                }
                                .buttonStyle(DSBoldButtonStyle())

                                DSDivider()

                                Button(action: { showTerms = true }) {
                                    settingActionRow(
                                        title: t("سياسة الخصوصية والشروط", "Privacy Policy & Terms"),
                                        subtitle: t("كيف نحمي بياناتك وشروط الاستخدام", "How we protect your data & usage terms"),
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
                                    title: t("إدارة الحساب", "Account Management"),
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
                                            Text(t("حذف حسابك وجميع بياناتك نهائياً", "Permanently delete your account and data"))
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
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 25)
                    .onAppear {
                        guard !appeared else { return }
                        withAnimation(DS.Anim.smooth.delay(0.1)) { appeared = true }
                    }
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
        .padding(.vertical, DS.Spacing.md)
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

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xxl) {

                        // App Icon
                        ZStack {
                            Circle()
                                .fill(DS.Color.gradientPrimary)
                                .frame(width: 100, height: 100)
                                .dsGlowShadow()

                            Image(systemName: "tree.fill")
                                .font(DS.Font.scaled(42, weight: .bold))
                                .foregroundColor(DS.Color.textOnPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, DS.Spacing.xxxl)

                        // App Name & Version
                        VStack(spacing: DS.Spacing.sm) {
                            Text(t("شجرة العائلة", "FamilyTree"))
                                .font(DS.Font.title1)
                                .fontWeight(.black)
                                .foregroundColor(DS.Color.textPrimary)

                            Text(t("الإصدار \(appVersion)", "Version \(appVersion)"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textTertiary)
                                .padding(.horizontal, DS.Spacing.md)
                                .padding(.vertical, DS.Spacing.xs)
                                .background(DS.Color.surface)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(DS.Color.textTertiary.opacity(0.3), lineWidth: 1))
                        }
                        .frame(maxWidth: .infinity)

                        // Description
                        DSCard(padding: DS.Spacing.lg) {
                            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                                aboutItem(
                                    icon: "person.3.fill",
                                    color: DS.Color.primary,
                                    title: t("شجرة العائلة", "Family Tree"),
                                    desc: t("استعرض أفراد عائلتك وأنسابهم بشكل تفاعلي", "Browse your family members and lineage interactively")
                                )

                                DSDivider()

                                aboutItem(
                                    icon: "newspaper.fill",
                                    color: DS.Color.info,
                                    title: t("أخبار العائلة", "Family News"),
                                    desc: t("شارك الأخبار وتفاعل بالتعليقات والإعجابات", "Share news and interact with comments & likes")
                                )

                                DSDivider()

                                aboutItem(
                                    icon: "bell.badge.fill",
                                    color: DS.Color.warning,
                                    title: t("الإشعارات", "Notifications"),
                                    desc: t("إشعارات فورية داخل التطبيق وعلى جهازك", "Instant alerts inside the app and on your device")
                                )

                                DSDivider()

                                aboutItem(
                                    icon: "lock.shield.fill",
                                    color: DS.Color.success,
                                    title: t("الخصوصية والأمان", "Privacy & Security"),
                                    desc: t("بياناتك محمية بالكامل وتتحكّم بمن يراها", "Your data is fully protected — you control visibility")
                                )
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // Footer
                        VStack(spacing: DS.Spacing.sm) {
                            Text(t("صُنع بحب لعائلة آل محمد علي 🤍", "Made with love for Al-Mohammad Ali family 🤍"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textTertiary)

                            Text("© 2026 FamilyTree")
                                .font(DS.Font.caption2)
                                .foregroundColor(DS.Color.textTertiary.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, DS.Spacing.xxxl)
                    }
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

    private func aboutItem(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(DS.Font.scaled(18, weight: .bold))
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                Text(desc)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Privacy Policy & Terms View
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) var dismiss
    private var isArabic: Bool { LanguageManager.shared.selectedLanguage == "ar" }
    private func t(_ ar: String, _ en: String) -> String { isArabic ? ar : en }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {

                        // مقدمة
                        Text(t(
                            "نحرص على حماية خصوصيتك وبياناتك. تعرّف على سياستنا وشروط الاستخدام.",
                            "We protect your privacy and data. Learn about our policy and terms of use."
                        ))
                        .font(DS.Font.body)
                        .foregroundColor(DS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                        policyCard(
                            icon: "tray.and.arrow.down.fill",
                            color: DS.Color.primary,
                            title: t("جمع البيانات", "Data Collection"),
                            points: [
                                t("نجمع فقط الاسم، رقم الهاتف، تاريخ الميلاد، والصور التي تشاركها.", "We only collect your name, phone, birth date, and photos you share."),
                                t("لا نجمع بيانات الموقع أو جهات الاتصال أو سجل التصفح.", "We don't collect location, contacts, or browsing history."),
                                t("يتم التحقق من هويتك عبر رمز OTP يُرسل لهاتفك.", "Your identity is verified via an OTP code sent to your phone.")
                            ]
                        )

                        policyCard(
                            icon: "hand.raised.fill",
                            color: DS.Color.accent,
                            title: t("استخدام البيانات", "Data Usage"),
                            points: [
                                t("بياناتك تُستخدم فقط لعرض الشجرة والتواصل بين الأعضاء.", "Your data is only used for the family tree and communication."),
                                t("لا نبيع أو نشارك بياناتك مع أي طرف خارجي.", "We never sell or share your data with third parties."),
                                t("يمكن للمدراء فقط الاطلاع على البيانات لأغراض الإدارة.", "Only admins can view data for management purposes.")
                            ]
                        )

                        policyCard(
                            icon: "server.rack",
                            color: DS.Color.info,
                            title: t("التخزين والأمان", "Storage & Security"),
                            points: [
                                t("بياناتك مخزّنة على خوادم مشفرة وآمنة.", "Your data is stored on encrypted and secure servers."),
                                t("جميع الاتصالات محمية عبر بروتوكول HTTPS.", "All connections are protected via HTTPS protocol."),
                                t("نستخدم حماية على مستوى كل مستخدم.", "We apply per-user level data protection.")
                            ]
                        )

                        policyCard(
                            icon: "trash.fill",
                            color: DS.Color.error,
                            title: t("حذف البيانات", "Data Deletion"),
                            points: [
                                t("يمكنك حذف حسابك وجميع بياناتك من الإعدادات.", "You can delete your account and all data from Settings."),
                                t("عند الحذف تُزال بياناتك بالكامل من خوادمنا.", "Upon deletion, all your data is fully removed from servers."),
                                t("لا يمكن استرجاع البيانات بعد الحذف النهائي.", "Data cannot be recovered after permanent deletion.")
                            ]
                        )

                        policyCard(
                            icon: "bell.badge.fill",
                            color: DS.Color.warning,
                            title: t("الإشعارات", "Notifications"),
                            points: [
                                t("نرسل إشعارات عن التعليقات والإعجابات والتحديثات.", "We send alerts for comments, likes, and updates."),
                                t("تتحكّم بأنواع الإشعارات من إعدادات الخصوصية.", "Control notification types from Privacy settings."),
                                t("يمكنك تعطيل الإشعارات بالكامل من الإعدادات.", "You can fully disable notifications from Settings.")
                            ]
                        )

                        policyCard(
                            icon: "doc.text.fill",
                            color: DS.Color.neonPurple,
                            title: t("شروط الاستخدام", "Terms of Use"),
                            points: [
                                t("التطبيق مخصص حصرياً لأفراد عائلة آل محمد علي.", "The app is exclusively for Al-Mohammad Ali family members."),
                                t("يجب استخدام التطبيق بمسؤولية واحترام خصوصية الآخرين.", "Use the app responsibly and respect others' privacy."),
                                t("يحق للإدارة تجميد أو حذف الحسابات المخالفة.", "Admins may freeze or delete accounts that violate policies.")
                            ]
                        )

                        // التواصل
                        policyCard(
                            icon: "envelope.fill",
                            color: DS.Color.primary,
                            title: t("تواصل معنا", "Contact Us"),
                            points: [
                                t("لأي استفسار، تواصل عبر مركز التواصل داخل التطبيق.", "For any questions, reach us via the Contact Center in the app.")
                            ]
                        )
                        .padding(.bottom, DS.Spacing.lg)
                    }
                    .padding(DS.Spacing.xl)
                }
            }
            .navigationTitle(t("سياسة الخصوصية والشروط", "Privacy Policy & Terms"))
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

    private func policyCard(icon: String, color: Color, title: String, points: [String]) -> some View {
        DSCard(padding: 0) {
            // العنوان
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(18, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                Text(title)
                    .font(DS.Font.headline)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)

                Spacer()
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.sm)

            DSDivider()

            // النقاط
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                ForEach(points, id: \.self) { point in
                    HStack(alignment: .top, spacing: DS.Spacing.sm) {
                        Circle()
                            .fill(color.opacity(0.6))
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)

                        Text(point)
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)
            .padding(.bottom, DS.Spacing.lg)
        }
    }
}

// MARK: - Linked Devices Settings Sheet
struct LinkedDevicesSettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var notificationVM: NotificationViewModel

    private var isArabic: Bool { LanguageManager.shared.selectedLanguage == "ar" }
    private func t(_ ar: String, _ en: String) -> String { isArabic ? ar : en }


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
