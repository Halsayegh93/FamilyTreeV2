import SwiftUI
import UserNotifications
import Supabase

// MARK: - Main Settings View (iOS-style with semantic groups)
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    @ObservedObject var langManager = LanguageManager.shared
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true

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
                VStack(spacing: DS.Spacing.xl) {
                    // تصميم جديد (طلب المالك): بطاقة هوية للعائلة، ثم مجموعات قصيرة
                    // كل سطر فيها يعرض قيمته الحالية — تشوف إعداداتك بدون ما تفتحها.
                    profileCard

                    // مربّعات بدل القائمة (طلب المالك) — كل مربّع يعرض قيمته الحالية
                    HStack(spacing: DS.Spacing.md) {
                        NavigationLink(destination: NotificationsAndPrivacyView()) {
                            valueTile(icon: "bell.badge.fill", color: DS.Color.warning,
                                      title: t("الإشعارات والخصوصية", "Notifications & Privacy"),
                                      value: notificationsEnabled ? t("مفعّلة", "On") : t("موقوفة", "Off"))
                        }
                        NavigationLink(destination: AppearanceSettingsView()) {
                            valueTile(icon: "paintbrush.fill", color: DS.Color.accent,
                                      title: t("المظهر واللغة", "Appearance & Language"),
                                      value: "\(appearanceLabel) · \(langManager.selectedLanguage == "ar" ? "العربية" : "English")")
                        }
                        Button { showLinkedDevices = true } label: {
                            valueTile(icon: "iphone.gen3", color: DS.Color.info,
                                      title: t("الأجهزة المرتبطة", "Linked Devices"),
                                      value: t("\(notificationVM.linkedDevices.count) جهاز", "\(notificationVM.linkedDevices.count) devices"))
                        }
                    }
                    .buttonStyle(DSScaleButtonStyle())

                    HStack(spacing: DS.Spacing.md) {
                        Button { showAbout = true } label: {
                            valueTile(icon: "app.badge.fill", color: DS.Color.secondary,
                                      title: t("عن التطبيق", "About"),
                                      value: AppVersion.string)
                        }
                        Button { showTerms = true } label: {
                            valueTile(icon: "doc.text.fill", color: DS.Color.primary,
                                      title: t("الخصوصية والشروط", "Privacy & Terms"),
                                      value: t("كيف نحمي بياناتك", "How we protect you"))
                        }
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxxl)
            }
            // حذف الحساب — زر عريض مثبّت أسفل الشاشة (طلب المالك) + رقم الإصدار
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: DS.Spacing.xs) {
                    Button { showDeleteConfirmation = true } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "trash")
                                .font(DS.Font.scaled(13, weight: .bold))
                            Text(t("حذف الحساب", "Delete Account"))
                                .font(DS.Font.plex(14, weight: .bold))
                        }
                        .foregroundColor(DS.Color.error)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(DS.Color.error.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    }
                    .buttonStyle(DSScaleButtonStyle())
                    versionLabel
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.sm)
                .background(DS.Color.background)
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
    /// بطاقة هوية العائلة (طلب المالك — تصميم جديد): صورة مربّعة مدوّرة، الاسم
    /// والدور والرقم، شجرة باهتة في الخلفية، وسطر سفلي: عضو منذ + الميلاد.
    /// التعديل أيقونة قلم صغيرة في زاوية البطاقة.
    private var profileCard: some View {
        let user = authVM.currentUser
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                Group {
                    if let avatar = user?.avatarUrl, let url = URL(string: avatar) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: { Color.white.opacity(0.2) }
                    } else {
                        ZStack {
                            Color.white.opacity(0.18)
                            Image(systemName: "person.fill")
                                .font(DS.Font.scaled(26, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 2))

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("عائلة المحمدعلي", "Al-Mohammad Ali Family"))
                        .font(DS.Font.plex(10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                    Text(user?.displayName ?? "")
                        .font(DS.Font.plex(18, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: DS.Spacing.sm) {
                        if let user {
                            Text(user.roleName)
                                .font(DS.Font.plex(10.5, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.22)))
                        }
                        if let phone = user?.phoneNumber, !phone.isEmpty {
                            Text(KuwaitPhone.display(phone))
                                .font(DS.Font.plex(11.5, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                                .monospacedDigit()
                                .environment(\.layoutDirection, .leftToRight)
                        }
                    }
                }
                Spacer(minLength: 0)

                Button { showEditProfile = true } label: {
                    Image(systemName: "pencil")
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(t("تعديل الملف الشخصي", "Edit Profile"))
            }
            .padding(DS.Spacing.lg)

            // الشريط السفلي — مثل ظهر البطاقة
            HStack(spacing: DS.Spacing.xl) {
                cardFact(icon: "calendar", title: t("عضو منذ", "Member since"), value: shortDate(user?.createdAt))
                cardFact(icon: "gift.fill", title: t("الميلاد", "Born"), value: shortDate(user?.birthDate))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm + 2)
            .background(Color.black.opacity(0.12))
        }
        .background(
            ZStack(alignment: .bottomLeading) {
                DS.Color.gradientPrimary
                Image(systemName: "tree.fill")
                    .font(.system(size: 130, weight: .regular))
                    .foregroundColor(.white.opacity(0.07))
                    .offset(x: -14, y: 22)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
        .shadow(color: DS.Color.primary.opacity(0.25), radius: 12, y: 6)
    }

    private func cardFact(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(.white.opacity(0.75))
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(DS.Font.plex(9.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Text(value)
                    .font(DS.Font.plex(12, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    /// مربّع إعداد (طلب المالك): أيقونة ملوّنة، العنوان، والقيمة الحالية تحته
    private func valueTile(icon: String, color: Color, title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(DS.Font.scaled(16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(color))
            Text(title)
                .font(DS.Font.plex(11.5, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(DS.Font.plex(10.5, weight: .semibold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, DS.Spacing.xs)
        .frame(maxWidth: .infinity)
        .frame(height: 118)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
            .strokeBorder(color.opacity(0.15), lineWidth: 1))
        .dsSubtleShadow()
    }

    // MARK: - المجموعات (كل سطر يعرض قيمته الحالية)
    private var appearanceLabel: String {
        switch appearanceMode {
        case "dark": return t("داكن", "Dark")
        case "light": return t("فاتح", "Light")
        default: return t("تلقائي", "Auto")
        }
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title)
                .font(DS.Font.plex(12, weight: .bold))
                .foregroundColor(DS.Color.textSecondary)
                .padding(.horizontal, DS.Spacing.sm)
            VStack(spacing: 0) { content() }
                .buttonStyle(DSBoldButtonStyle())
                .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                .dsSubtleShadow()
        }
    }

    private func groupRow(icon: String, color: Color, title: String, value: String?) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(DS.Font.scaled(14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm + 1, style: .continuous).fill(color))
            Text(title)
                .font(DS.Font.plex(14, weight: .semibold))
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: DS.Spacing.sm)
            if let value {
                Text(value)
                    .font(DS.Font.plex(12.5, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(DS.Color.textTertiary.opacity(0.7))
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(height: 56)
        .contentShape(Rectangle())
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(DS.Color.textTertiary.opacity(0.15))
            .frame(height: 1)
            .padding(.leading, 60)
    }

    /// «١٩٩٣/٠٣/٢٥» → «مارس ١٩٩٣» — التاريخ مختصر بالشهر نصاً
    private func shortDate(_ raw: String?) -> String {
        guard let raw, raw.count >= 10 else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: String(raw.prefix(10))) else { return "—" }
        let out = DateFormatter()
        out.locale = LanguageManager.shared.locale
        out.dateFormat = "MMMM yyyy"
        return out.string(from: d)
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

    @State private var badgeEnabled: Bool = true
    @State private var isPhoneHidden: Bool = false
    @State private var isBirthDateHidden: Bool = false
    @State private var showUpdateError: Bool = false
    /// أنواع الإشعارات — محفوظة بالسيرفر ويقرأها مُطلِق الدفع (طلب المالك)
    @State private var prefs: [String: Bool] = [:]
    @State private var systemStatus: UNAuthorizationStatus = .notDetermined
    @State private var testState: TestState = .idle

    private enum TestState { case idle, sending, sent, failed }

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    /// نوع واحد من الإشعارات (مفتاحه في notification_prefs)
    private struct Kind: Identifiable {
        let key: String, icon: String, color: Color, title: String, subtitle: String
        var id: String { key }
    }

    private var kinds: [Kind] {
        var list: [Kind] = [
            Kind(key: "news", icon: "newspaper.fill", color: DS.Color.primary,
                 title: t("الأخبار الجديدة", "New posts"), subtitle: t("عند نشر خبر في العائلة", "When a family post is published")),
            Kind(key: "comments", icon: "bubble.left.fill", color: DS.Color.info,
                 title: t("التعليقات", "Comments"), subtitle: t("عند تعليق أحد على خبرك", "When someone comments on your post")),
            Kind(key: "likes", icon: "heart.fill", color: DS.Color.error,
                 title: t("الإعجابات", "Likes"), subtitle: t("عند إعجاب أحد بخبرك", "When someone likes your post")),
            Kind(key: "requests", icon: "checkmark.seal.fill", color: DS.Color.success,
                 title: t("الرد على طلباتي", "Replies to my requests"), subtitle: t("قبول أو رفض طلباتك، تفعيل حسابك", "Approvals, rejections, activation")),
            Kind(key: "profile", icon: "person.crop.circle.badge.checkmark", color: DS.Color.accent,
                 title: t("تحديثات ملفي", "My profile updates"), subtitle: t("عند تعديل الإدارة لبياناتك", "When admins edit your profile"))
        ]
        if authVM.canModerate {
            list.append(Kind(key: "admin_activity", icon: "sparkles", color: DS.Color.warning,
                             title: t("مستجدات الإدارة", "Admin activity"),
                             subtitle: t("طلبات الشجرة والانضمام والتعديلات", "Tree, join and edit requests")))
        }
        return list
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DS.Spacing.xl) {
                    statusCard

                    group(t("أنواع الإشعارات", "Notification types"),
                          footer: t("إعلانات الإدارة وتحديثات التطبيق تصلك دائماً. النوع المطفأ يبقى داخل التطبيق بدون تنبيه.",
                                    "Admin announcements and app updates always arrive. Muted types stay in the app without an alert.")) {
                        ForEach(Array(kinds.enumerated()), id: \.element.id) { idx, kind in
                            if idx > 0 { rowDivider }
                            switchRow(icon: kind.icon, color: kind.color, title: kind.title, subtitle: kind.subtitle,
                                      isOn: Binding(
                                        get: { prefs[kind.key] ?? true },
                                        set: { newValue in
                                            prefs[kind.key] = newValue
                                            Task {
                                                let ok = await memberVM.updateNotificationPrefs(prefs)
                                                if !ok { prefs[kind.key] = !newValue; showUpdateError = true }
                                            }
                                        }))
                        }
                    }
                    .disabled(!notificationsEnabled)
                    .opacity(notificationsEnabled ? 1 : 0.45)

                    group(t("الأيقونة", "App icon"), footer: nil) {
                        switchRow(icon: "app.badge.fill", color: DS.Color.primary,
                                  title: t("شارة الأيقونة", "App badge"),
                                  subtitle: t("عدد غير المقروء على أيقونة التطبيق", "Unread count on the app icon"),
                                  isOn: $badgeEnabled)
                    }

                    group(t("الخصوصية", "Privacy"),
                          footer: t("بياناتك تبقى محفوظة في الشجرة، بس ما تظهر للأعضاء. الإدارة تشوفها.",
                                    "Your data stays in the tree but is hidden from members. Admins can still see it.")) {
                        switchRow(icon: "phone.down.fill", color: DS.Color.gridContact,
                                  title: t("إخفاء رقم الهاتف", "Hide phone number"),
                                  subtitle: t("ما يظهر رقمك للأعضاء", "Members won't see your number"),
                                  isOn: $isPhoneHidden)
                        rowDivider
                        switchRow(icon: "calendar.badge.minus", color: DS.Color.gridContact,
                                  title: t("إخفاء تاريخ الميلاد", "Hide birth date"),
                                  subtitle: t("ما يظهر تاريخ ميلادك للأعضاء", "Members won't see your birth date"),
                                  isOn: $isBirthDateHidden)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.lg)
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
        .task {
            prefs = await memberVM.fetchNotificationPrefs()
            await refreshSystemStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await refreshSystemStatus() }
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

    // MARK: - بطاقة الحالة: الجهاز + المفتاح الرئيسي + التجربة
    private var systemBlocked: Bool { systemStatus == .denied }

    private var statusCard: some View {
        let on = notificationsEnabled && !systemBlocked
        let tint = on ? DS.Color.success : DS.Color.warning
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.md) {
                ZStack {
                    Circle().fill(tint.opacity(0.16)).frame(width: 46, height: 46)
                    Image(systemName: on ? "bell.badge.fill" : "bell.slash.fill")
                        .font(DS.Font.scaled(19, weight: .semibold))
                        .foregroundColor(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(on ? t("الإشعارات شغّالة", "Notifications are on")
                            : (systemBlocked ? t("موقوفة من إعدادات الجهاز", "Blocked in device settings")
                                             : t("الإشعارات موقوفة", "Notifications are off")))
                        .font(DS.Font.plex(15, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                    Text(on ? t("توصلك تنبيهات العائلة على هذا الجهاز", "Family alerts reach this device")
                            : t("ما توصلك تنبيهات على هذا الجهاز", "No alerts on this device"))
                        .font(DS.Font.plex(11.5, weight: .medium))
                        .foregroundColor(DS.Color.textSecondary)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $notificationsEnabled)
                    .labelsHidden()
                    .tint(DS.Color.success)
            }

            if systemBlocked {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label(t("افتح إعدادات الجهاز", "Open device settings"), systemImage: "gearshape.fill")
                        .font(DS.Font.plex(13, weight: .bold))
                        .foregroundColor(DS.Color.warning)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(DS.Color.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.md))
                }
                .buttonStyle(DSScaleButtonStyle())
            } else if notificationsEnabled {
                // «جرّب الإشعار» — يمر بنفس طريق الإرسال الحقيقي حتى جهازك
                Button { Task { await sendTest() } } label: {
                    HStack(spacing: 6) {
                        switch testState {
                        case .sending: ProgressView().scaleEffect(0.8)
                        case .sent: Image(systemName: "checkmark.circle.fill")
                        case .failed: Image(systemName: "exclamationmark.triangle.fill")
                        case .idle: Image(systemName: "paperplane.fill")
                        }
                        Text(testLabel)
                    }
                    .font(DS.Font.plex(13, weight: .bold))
                    .foregroundColor(testState == .failed ? DS.Color.error : DS.Color.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background((testState == .failed ? DS.Color.error : DS.Color.primary).opacity(0.10),
                                in: RoundedRectangle(cornerRadius: DS.Radius.md))
                }
                .buttonStyle(DSScaleButtonStyle())
                .disabled(testState == .sending)
            }
        }
        .padding(DS.Spacing.lg)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
            .strokeBorder(tint.opacity(0.25), lineWidth: 1))
        .dsSubtleShadow()
    }

    private var testLabel: String {
        switch testState {
        case .idle: return t("جرّب الإشعار", "Send a test notification")
        case .sending: return t("جاري الإرسال…", "Sending…")
        case .sent: return t("أُرسل — يوصلك خلال ثواني", "Sent — it should arrive in seconds")
        case .failed: return t("تعذّر الإرسال، حاول مرة ثانية", "Couldn't send, try again")
        }
    }

    private func sendTest() async {
        guard let me = authVM.currentUser?.id else { return }
        testState = .sending
        do {
            let row: [String: AnyEncodable] = [
                "target_member_id": AnyEncodable(me.uuidString),
                "title": AnyEncodable(t("إشعار تجربة ✓", "Test notification ✓")),
                "body": AnyEncodable(t("إذا وصلك هذا، فالإشعارات شغّالة على جهازك.",
                                       "If you got this, notifications work on your device.")),
                "kind": AnyEncodable("test"),
                "created_by": AnyEncodable(me.uuidString)
            ]
            try await SupabaseConfig.client.from("notifications").insert(row).execute()
            testState = .sent
        } catch {
            Log.error("[NotifTest] \(error.localizedDescription)")
            testState = .failed
        }
    }

    private func refreshSystemStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        systemStatus = settings.authorizationStatus
    }

    // MARK: - مجموعات وصفوف بنفس أسلوب صفحة الإعدادات
    private func group<Content: View>(_ title: String, footer: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title)
                .font(DS.Font.plex(12, weight: .bold))
                .foregroundColor(DS.Color.textSecondary)
                .padding(.horizontal, DS.Spacing.sm)
            VStack(spacing: 0) { content() }
                .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                .dsSubtleShadow()
            if let footer {
                Text(footer)
                    .font(DS.Font.plex(10.5, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Spacing.sm)
            }
        }
    }

    private func switchRow(icon: String, color: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(DS.Font.scaled(14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm + 1, style: .continuous).fill(color))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.Font.plex(14, weight: .semibold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(subtitle)
                    .font(DS.Font.plex(10.5, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: DS.Spacing.sm)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(DS.Color.primary)
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(minHeight: 60)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(DS.Color.textTertiary.opacity(0.15))
            .frame(height: 1)
            .padding(.leading, 60)
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
