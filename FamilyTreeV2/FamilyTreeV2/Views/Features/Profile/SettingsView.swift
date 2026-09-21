import SwiftUI
import UserNotifications

// MARK: - Main Settings View (iOS-style with semantic groups)
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    @ObservedObject var langManager = LanguageManager.shared

    @State private var showEditProfile = false
    @State private var showLinkedDevices = false
    @State private var showAbout = false
    @State private var showTerms = false
    @State private var showDeleteConfirmation = false

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            // تصميم مرتب (طلب المالك): بطاقة الحساب أعلى، ثم شبكة الإعدادات
            // السريعة، ثم المعلومات، وحذف الحساب زر هادئ في الأسفل.
            ScrollView {
                VStack(spacing: DS.Spacing.lg) {
                    profileCard

                    // ── الإعدادات السريعة: شبكة ٢×٢ ──
                    sectionTitle(t("التفضيلات", "Preferences"))
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Spacing.sm),
                                        GridItem(.flexible(), spacing: DS.Spacing.sm)],
                              spacing: DS.Spacing.sm) {
                        NavigationLink(destination: NotificationsAndPrivacyView()) {
                            settingsTile(icon: "bell.badge.fill", color: DS.Color.warning,
                                         title: t("الإشعارات والخصوصية", "Notifications & Privacy"),
                                         subtitle: t("التنبيهات وإخفاء بياناتك", "Alerts & data visibility"))
                        }
                        .buttonStyle(DSScaleButtonStyle())

                        NavigationLink(destination: AppearanceSettingsView()) {
                            settingsTile(icon: "paintbrush.fill", color: DS.Color.accent,
                                         title: t("المظهر واللغة", "Appearance & Language"),
                                         subtitle: t("الوضع الداكن واللغة", "Dark mode & language"))
                        }
                        .buttonStyle(DSScaleButtonStyle())

                        Button { showLinkedDevices = true } label: {
                            settingsTile(icon: "iphone.gen3", color: DS.Color.info,
                                         title: t("الأجهزة المرتبطة", "Linked Devices"),
                                         subtitle: t("\(notificationVM.linkedDevices.count) جهاز نشط",
                                                     "\(notificationVM.linkedDevices.count) active"))
                        }
                        .buttonStyle(DSScaleButtonStyle())

                        Button { showAbout = true } label: {
                            settingsTile(icon: "app.badge.fill", color: DS.Color.secondary,
                                         title: t("عن التطبيق", "About"),
                                         subtitle: t("الإصدار \(AppVersion.string)", "Version \(AppVersion.string)"))
                        }
                        .buttonStyle(DSScaleButtonStyle())
                    }

                    // ── معلومات ──
                    sectionTitle(t("معلومات", "Information"))
                    DSCard(padding: 0) {
                        Button { showTerms = true } label: {
                            settingsActionRow(
                                icon: "doc.text.fill",
                                color: DS.Color.info,
                                title: t("سياسة الخصوصية والشروط", "Privacy Policy & Terms"),
                                subtitle: t("كيف نحمي بياناتك وشروط الاستخدام", "How we protect your data & usage terms")
                            )
                        }
                        .buttonStyle(DSBoldButtonStyle())
                    }

                    // ── حذف الحساب: زر هادئ بدل بطاقة تحذير كاملة ──
                    Button { showDeleteConfirmation = true } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "trash")
                                .font(DS.Font.scaled(12, weight: .bold))
                            Text(t("حذف الحساب", "Delete Account"))
                                .font(DS.Font.plex(13, weight: .bold))
                        }
                        .foregroundColor(DS.Color.error)
                        .padding(.horizontal, DS.Spacing.lg)
                        .frame(height: 40)
                        .background(Capsule().fill(DS.Color.error.opacity(0.08)))
                    }
                    .buttonStyle(DSScaleButtonStyle())
                    .padding(.top, DS.Spacing.sm)

                    versionLabel
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxxl)
            }
        }
        .navigationTitle(t("الإعدادات", "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, langManager.layoutDirection)
        .toolbar {
            ToolbarItem(placement: DSToolbar.cancelPlacement) {
                DSToolbarCancelButton(title: t("إغلاق", "Close")) { dismiss() }
            }
        }
        .sheet(isPresented: $showEditProfile) {
            if let c = authVM.currentUser { EditProfileView(member: c) }
        }
        .sheet(isPresented: $showLinkedDevices) {
            LinkedDevicesSettingsSheet().environmentObject(appSettingsVM)
        }
        .sheet(isPresented: $showAbout) { AboutView() }
        .sheet(isPresented: $showTerms) { PrivacyPolicyView() }
        .dsAlert(t("حذف الحساب", "Delete Account"), isPresented: $showDeleteConfirmation) {
            Button(t("إلغاء", "Cancel"), role: .cancel) {}
            Button(t("حذف نهائي", "Delete Permanently"), role: .destructive) {
                Task { _ = await authVM.deleteAccount() }
            }
        } message: {
            Text(t(
                "سيتم حذف:\n• حسابك وبيانات تسجيل الدخول\n• صورتك الشخصية\n• سيرتك الذاتية\n\nستبقى بياناتك في شجرة العائلة. لا يمكن التراجع عن هذا الإجراء.",
                "This will permanently delete:\n• Your account & login credentials\n• Your profile photo\n• Your life stations\n\nYour family tree data will remain. This cannot be undone."
            ))
        }
        .dsAlert(t("خطأ", "Error"), isPresented: .init(
            get: { authVM.deleteAccountError != nil },
            set: { if !$0 { authVM.deleteAccountError = nil } }
        )) {
            Button(t("حسناً", "OK")) {}
        } message: {
            Text(authVM.deleteAccountError ?? "")
        }
        .task { await notificationVM.fetchLinkedDevices() }
    }

    @ViewBuilder
    private func navRow<Destination: View>(
        destination: Destination,
        icon: String,
        color: Color,
        title: String,
        subtitle: String
    ) -> some View {
        NavigationLink(destination: destination) {
            settingsActionRow(icon: icon, color: color, title: title, subtitle: subtitle)
        }
        .buttonStyle(DSBoldButtonStyle())
    }

    /// بطاقة الحساب: الصورة والاسم والدور والرقم + زر تعديل الملف
    private var profileCard: some View {
        let user = authVM.currentUser
        return HStack(spacing: DS.Spacing.md) {
            Group {
                if let avatar = user?.avatarUrl, let url = URL(string: avatar) {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: { DS.Color.mutedBackground }
                } else {
                    ZStack {
                        DS.Color.primary.opacity(0.14)
                        Image(systemName: "person.fill")
                            .font(DS.Font.scaled(22, weight: .bold))
                            .foregroundColor(DS.Color.primary)
                    }
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(DS.Color.primary.opacity(0.18), lineWidth: 2))

            VStack(alignment: .leading, spacing: 3) {
                Text(user?.displayName ?? "")
                    .font(DS.Font.plex(16, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                if let user {
                    Text(user.roleName)
                        .font(DS.Font.plex(10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(user.role == .owner ? FamilyMember.UserRole.admin.color : user.role.color))
                }
                if let phone = user?.phoneNumber, !phone.isEmpty {
                    Text(KuwaitPhone.display(phone))
                        .font(DS.Font.plex(11, weight: .medium))
                        .foregroundColor(DS.Color.textSecondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)

            Button { showEditProfile = true } label: {
                Text(t("تعديل", "Edit"))
                    .font(DS.Font.plex(13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, DS.Spacing.md)
                    .frame(height: 34)
                    .background(Capsule().fill(DS.Color.primary))
            }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityLabel(t("تعديل الملف الشخصي", "Edit Profile"))
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .dsSubtleShadow()
    }

    /// مربّع إعداد في الشبكة — أصغر ومرتّب (طلب المالك): أيقونة وعنوان في سطر،
    /// والوصف تحت؛ ارتفاع موحّد لكل المربّعات حتى تصطفّ الشبكة.
    private func settingsTile(icon: String, color: Color, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: DS.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(color)
                }
                Spacer(minLength: 0)
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .font(DS.Font.scaled(10, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
            }
            Text(title)
                .font(DS.Font.plex(12.5, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(DS.Font.plex(10, weight: .medium))
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(DS.Spacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 92)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(color.opacity(0.14), lineWidth: 1)
        )
        .dsSubtleShadow()
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.plex(12, weight: .bold))
            .foregroundColor(DS.Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.bottom, -DS.Spacing.sm)
    }

    private var versionLabel: some View {
        Text(t("إصدار التطبيق \(AppVersion.string)", "App Version \(AppVersion.string)"))
            .font(DS.Font.caption2)
            .foregroundColor(DS.Color.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Spacing.md)
    }
}

// MARK: - Settings Sub-Views

// MARK: 1) Notifications & Privacy (combined)
struct NotificationsAndPrivacyView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @ObservedObject var langManager = LanguageManager.shared

    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("notif_comments") private var notifComments: Bool = true
    @AppStorage("notif_likes") private var notifLikes: Bool = true
    @AppStorage("notif_profile_updates") private var notifProfileUpdates: Bool = true
    @AppStorage("notif_admin_activity") private var notifAdminActivity: Bool = true

    @State private var badgeEnabled: Bool = true
    @State private var isPhoneHidden: Bool = false
    @State private var isBirthDateHidden: Bool = false
    @State private var showUpdateError: Bool = false

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView {
                AdaptiveCardStack(spacing: DS.Spacing.md, landscapeMinimum: 330) {
                    // ── Notifications: Master ──
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: t("الإشعارات", "Notifications"),
                            icon: "bell.badge.fill",
                            iconColor: DS.Color.warning
                        )

                        toggleRow(
                            icon: "bell.badge.fill",
                            color: DS.Color.primary,
                            title: t("تفعيل الإشعارات", "Enable Notifications"),
                            subtitle: t("استقبال الإشعارات داخل وخارج التطبيق", "Receive push and in-app notifications"),
                            isOn: $notificationsEnabled
                        )
                    }

                    // ── Notifications: Sub-types ──
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: t("أنواع الإشعارات", "Notification Types"),
                            icon: "slider.horizontal.3"
                        )

                        toggleRow(
                            icon: "app.badge",
                            color: DS.Color.primary,
                            title: t("شارة الأيقونة", "App Badge"),
                            subtitle: t("عدد الإشعارات غير المقروءة على الأيقونة", "Show unread count on app icon"),
                            isOn: $badgeEnabled,
                            disabled: !notificationsEnabled
                        )
                        DSDivider()
                        toggleRow(
                            icon: "bubble.left.fill",
                            color: DS.Color.info,
                            title: t("التعليقات", "Comments"),
                            subtitle: t("عند تعليق أحد على أخبارك", "When someone comments on your post"),
                            isOn: $notifComments,
                            disabled: !notificationsEnabled
                        )
                        DSDivider()
                        toggleRow(
                            icon: "heart.fill",
                            color: DS.Color.error,
                            title: t("الإعجابات", "Likes"),
                            subtitle: t("عند إعجاب أحد بأخبارك", "When someone likes your post"),
                            isOn: $notifLikes,
                            disabled: !notificationsEnabled
                        )
                        DSDivider()
                        toggleRow(
                            icon: "person.crop.circle.badge.checkmark",
                            color: DS.Color.accent,
                            title: t("تحديثات الملف الشخصي", "Profile Updates"),
                            subtitle: t("عند تعديل بياناتك من قِبل الإدارة", "When admin updates your profile"),
                            isOn: $notifProfileUpdates,
                            disabled: !notificationsEnabled
                        )

                        if authVM.canModerate {
                            DSDivider()
                            toggleRow(
                                icon: "sparkles",
                                color: DS.Color.accent,
                                title: t("إشعارات المستجدات", "Activity Notifications"),
                                subtitle: t("طلبات الانضمام والتعديلات ومستجدات التطبيق", "Join requests, edits, and app activity"),
                                isOn: $notifAdminActivity,
                                disabled: !notificationsEnabled
                            )
                        }
                    }
                    .opacity(notificationsEnabled ? 1.0 : 0.45)
                    .animation(DS.Anim.snappy, value: notificationsEnabled)

                    // ── Privacy ──
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: t("الخصوصية", "Privacy"),
                            icon: "lock.shield.fill",
                            iconColor: DS.Color.gridContact
                        )

                        toggleRow(
                            icon: "eye.slash.fill",
                            color: DS.Color.primary,
                            title: t("إخفاء رقم الهاتف", "Hide Phone Number"),
                            subtitle: t("لن يظهر رقمك للأعضاء الآخرين", "Your number won't be visible to others"),
                            isOn: $isPhoneHidden
                        )
                        DSDivider()
                        toggleRow(
                            icon: "calendar.badge.minus",
                            color: DS.Color.primary,
                            title: t("إخفاء تاريخ الميلاد", "Hide Birth Date"),
                            subtitle: t("لن يظهر تاريخ ميلادك للأعضاء الآخرين", "Your birth date won't be visible to others"),
                            isOn: $isBirthDateHidden
                        )
                    }

                    // Info note
                    HStack(alignment: .top, spacing: DS.Spacing.sm) {
                        Image(systemName: "info.circle.fill")
                            .font(DS.Font.scaled(13, weight: .bold))
                            .foregroundColor(DS.Color.info)
                        Text(t(
                            "بياناتك تبقى محفوظة في شجرة العائلة، لكن لن تظهر للأعضاء الآخرين عند التفعيل.",
                            "Your data remains in the family tree but won't be visible to others when enabled."
                        ))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.info.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.xxxl)
            }
        }
        .navigationTitle(t("الإشعارات والخصوصية", "Notifications & Privacy"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, langManager.layoutDirection)
        .onAppear {
            badgeEnabled = authVM.currentUser?.badgeEnabled ?? true
            isPhoneHidden = authVM.currentUser?.isPhoneHidden ?? false
            isBirthDateHidden = authVM.currentUser?.isBirthDateHidden ?? false
        }
        .onChange(of: notificationsEnabled) { newValue in
            handleMasterNotificationToggle(newValue)
        }
        .onChange(of: badgeEnabled) { newValue in
            Task {
                await memberVM.updateBadgeEnabled(newValue)
                if !newValue {
                    try? await UNUserNotificationCenter.current().setBadgeCount(0)
                } else {
                    let unread = notificationVM.notifications.filter { !$0.read }.count
                    try? await UNUserNotificationCenter.current().setBadgeCount(unread)
                }
            }
        }
        .onChange(of: isPhoneHidden) { newValue in
            Task {
                let success = await memberVM.updatePhoneHidden(newValue)
                if !success { isPhoneHidden = !newValue; showUpdateError = true }
            }
        }
        .onChange(of: isBirthDateHidden) { newValue in
            Task {
                let success = await memberVM.updateBirthDateHidden(newValue)
                if !success { isBirthDateHidden = !newValue; showUpdateError = true }
            }
        }
        .dsAlert(t("خطأ", "Error"), isPresented: $showUpdateError) {
            Button(t("حسناً", "OK")) {}
        } message: {
            Text(t("تعذر تحديث الإعداد. حاول مرة أخرى.", "Failed to update setting. Please try again."))
        }
    }

    private func handleMasterNotificationToggle(_ newValue: Bool) {
        Task {
            if newValue {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                if settings.authorizationStatus == .denied {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        await MainActor.run { UIApplication.shared.open(url) }
                    }
                } else if settings.authorizationStatus == .notDetermined {
                    let granted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                    if granted == true {
                        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
                    }
                } else {
                    await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
                    if let token = notificationVM.pushToken {
                        await notificationVM.registerPushToken(token)
                    }
                }
            } else {
                await notificationVM.unregisterPushToken()
            }
        }
    }
}

// MARK: 4) Appearance & Language
struct AppearanceSettingsView: View {
    @ObservedObject var langManager = LanguageManager.shared
    /// للرجوع للغة التطبيق الرسمية
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView {
                AdaptiveCardStack(spacing: DS.Spacing.md, landscapeMinimum: 330) {
                    // Appearance picker (segmented)
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: t("المظهر", "Appearance"),
                            icon: "circle.lefthalf.filled",
                            iconColor: DS.Color.accent
                        )

                        VStack(spacing: DS.Spacing.md) {
                            Picker("", selection: $appearanceMode) {
                                Text(t("حسب الجهاز", "System")).tag("system")
                                Text(t("فاتح", "Light")).tag("light")
                                Text(t("داكن", "Dark")).tag("dark")
                            }
                            .pickerStyle(.segmented)

                            Text(appearanceDescription)
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.lg)
                    }

                    // Language picker (segmented)
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: t("اللغة", "Language"),
                            icon: "character.bubble.fill",
                            iconColor: DS.Color.secondary
                        )

                        VStack(spacing: DS.Spacing.md) {
                            // اختيار المستخدم يثبّت لغته — ولا تغيّرها اللغة الرسمية بعدها
                            Picker("", selection: Binding(
                                get: { langManager.selectedLanguage },
                                set: { langManager.chooseLanguage($0) }
                            )) {
                                Text("العربية").tag("ar")
                                Text("English").tag("en")
                            }
                            .pickerStyle(.segmented)

                            Text(langManager.languageChosenByUser
                                 ? t("اخترت لغتك بنفسك — لا تتأثر بلغة التطبيق الرسمية.",
                                     "You chose your language — the app's official language won't change it.")
                                 : t("تتبع لغة التطبيق الرسمية التي تحددها الإدارة.",
                                     "Following the app's official language set by the admins."))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if langManager.languageChosenByUser {
                                Button {
                                    langManager.followOfficialLanguage(appSettingsVM.settings.defaultLanguage)
                                } label: {
                                    Label(t("الرجوع للغة التطبيق الرسمية", "Use the app's official language"),
                                          systemImage: "arrow.uturn.backward")
                                        .font(DS.Font.calloutBold)
                                        .foregroundColor(DS.Color.primary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.lg)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.xxxl)
            }
        }
        .navigationTitle(t("المظهر واللغة", "Appearance & Language"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, langManager.layoutDirection)
    }

    private var appearanceDescription: String {
        switch appearanceMode {
        case "light": return t("الوضع الفاتح يبقى مفعّل دائماً.", "Light mode is always active.")
        case "dark": return t("الوضع الداكن يبقى مفعّل دائماً.", "Dark mode is always active.")
        default: return t("يتغيّر تلقائياً حسب إعدادات جهازك.", "Changes automatically with your device settings.")
        }
    }
}

// MARK: - Shared Settings Helpers

private func settingsActionRow(icon: String, color: Color, title: String, subtitle: String?) -> some View {
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

        Image(systemName: "chevron.forward")
            .font(DS.Font.scaled(13, weight: .bold))
            .foregroundColor(DS.Color.textTertiary)
    }
    .padding(.horizontal, DS.Spacing.lg)
    .padding(.vertical, DS.Spacing.md)
    .contentShape(Rectangle())
}

private func toggleRow(icon: String, color: Color, title: String, subtitle: String, isOn: Binding<Bool>, disabled: Bool = false) -> some View {
    HStack(spacing: DS.Spacing.md) {
        DSIcon(icon, color: color)

        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.textPrimary)
            Text(subtitle)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
        }

        Spacer()

        Toggle("", isOn: isOn)
            .labelsHidden()
            .tint(color)
            .disabled(disabled)
    }
    .padding(.horizontal, DS.Spacing.lg)
    .padding(.vertical, DS.Spacing.md)
}

// MARK: - App Version Helper
private enum AppVersion {
    static var string: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - About View
struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    private var isArabic: Bool { LanguageManager.shared.selectedLanguage == "ar" }
    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    private var appVersion: String { AppVersion.string }

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
                            Text(t("عائلة المحمدعلي", "Al-Mohammadali Family"))
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
                                    color: DS.Color.gridContact,
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
                ToolbarItem(placement: DSToolbar.cancelPlacement) {
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

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
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
    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {

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
                ToolbarItem(placement: DSToolbar.cancelPlacement) {
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
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    private var maxDevices: Int { appSettingsVM.settings.maxDevicesPerUser }
    private var isArabic: Bool { LanguageManager.shared.selectedLanguage == "ar" }
    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }


    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {

                        DSCard(padding: 0) {
                            DSSectionHeader(
                                title: t("الأجهزة المرتبطة", "Linked Devices"),
                                icon: "iphone.gen3",
                                iconColor: DS.Color.primary
                            )

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
                                        "\(notificationVM.linkedDevices.count) من \(maxDevices) أجهزة",
                                        "\(notificationVM.linkedDevices.count) of \(maxDevices) devices"
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
                ToolbarItem(placement: DSToolbar.cancelPlacement) {
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
    NavigationStack { SettingsView() }
        .environmentObject(AuthViewModel())
        .environmentObject(NotificationViewModel())
}
