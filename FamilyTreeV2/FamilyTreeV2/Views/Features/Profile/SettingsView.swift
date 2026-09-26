import SwiftUI
import UserNotifications
import Supabase

// MARK: - Main Settings View (iOS-style with semantic groups)
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @EnvironmentObject var memberVM: MemberViewModel

    @ObservedObject var langManager = LanguageManager.shared
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true

    @State private var showEditProfile = false
    @State private var showLinkedDevices = false
    /// كل مربّعات الإعدادات تفتح بمنتصف الشاشة (طلب المالك) بدل صفحة جديدة
    @State private var showNotifications = false
    @State private var showAppearance = false
    @State private var showAbout = false
    @State private var showTerms = false
    @State private var showDeleteConfirmation = false
    /// حذف الحساب جارٍ — طبقة انتظار حتى يكتمل ويُسجَّل الخروج
    @State private var isDeletingAccount = false

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
                    sectionTitle(t("التفضيلات", "Preferences"), icon: "slider.horizontal.3")
                        .dsStaggerIn(1)
                    HStack(spacing: DS.Spacing.md) {
                        Button { showNotifications = true } label: {
                            valueTile(icon: "bell.badge.fill", color: DS.Color.warning,
                                      title: t("الإشعارات والخصوصية", "Notifications & Privacy"),
                                      value: notificationsEnabled ? t("مفعّلة", "On") : t("موقوفة", "Off"))
                        }
                        Button { showAppearance = true } label: {
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
                    .dsStaggerIn(2)

                    sectionTitle(t("عن التطبيق", "About"), icon: "info.circle.fill")
                        .dsStaggerIn(3)
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
                    .dsStaggerIn(4)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xxxl)
            }
            // حذف الحساب — زر عريض مثبّت أسفل الشاشة (طلب المالك) + رقم الإصدار
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: DS.Spacing.xs) {
                    Button { showDeleteConfirmation = true } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "trash")
                                .font(DS.Font.scaled(13, weight: .bold))
                                .accessibilityHidden(true)   // زخرفة — النص يكفي
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
                .dsStaggerIn(5)
            }
        }
        .navigationTitle(t("الإعدادات", "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        // رأس مخصّص بتصميم مربّعات الإضافة (طلب المالك) — «إغلاق» داخله
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.layoutDirection, langManager.layoutDirection)
        // نموذج طويل فيه كتابة وتمرير — مربّع طويل من الأسفل (توصية أبل)
        .dsTallBox(isPresented: $showEditProfile) {
            if let c = authVM.currentUser { EditProfileView(member: c) }
        }
        .dsCenterBox(isPresented: $showLinkedDevices) {
            LinkedDevicesSettingsSheet().environmentObject(appSettingsVM)
        }
        .dsTallBox(isPresented: $showNotifications) {   // قائمة إعدادات طويلة — مربّع طويل (توصية أبل)
            NotificationsAndPrivacyView()
                .environmentObject(authVM)
                .environmentObject(memberVM)
                .environmentObject(notificationVM)
        }
        .dsCenterBox(isPresented: $showAppearance, onBackgroundTap: { showAppearance = false }) {
            AppearanceSettingsView().environmentObject(appSettingsVM)
        }
        .dsCenterBox(isPresented: $showAbout, onBackgroundTap: { showAbout = false }) { AboutView() }
        .dsTallBox(isPresented: $showTerms) { PrivacyPolicyView() }   // قراءة طويلة — مربّع طويل (توصية أبل)
        .dsAlert(t("حذف الحساب", "Delete Account"), isPresented: $showDeleteConfirmation) {
            Button(t("إلغاء", "Cancel"), role: .cancel) {}
            Button(t("حذف نهائي", "Delete Permanently"), role: .destructive) {
                Task {
                    isDeletingAccount = true
                    _ = await authVM.deleteAccount()
                    isDeletingAccount = false
                }
            }
        } message: {
            // مطابق لما يحذفه السيرفر فعلاً (delete-account)
            Text(t(
                "سيتم حذف نهائياً:\n• حسابك وبيانات تسجيل الدخول\n• صورتك وسيرتك وبياناتك الشخصية\n• أخبارك وتعليقاتك وما أضفته من محتوى\n\nيبقى موضعك في شجرة العائلة باسم «عضو محذوف» حفاظاً على تسلسل النسب. لا يمكن التراجع عن هذا الإجراء.",
                "This will permanently delete:\n• Your account & login credentials\n• Your photo, life stations and personal details\n• Your posts, comments and other content you added\n\nYour place in the family tree stays as “Deleted member” to keep the lineage intact. This cannot be undone."
            ))
        }
        .overlay {
            if isDeletingAccount {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: DS.Spacing.md) {
                        ProgressView().tint(DS.Color.error).scaleEffect(1.2)
                        Text(t("جاري حذف الحساب…", "Deleting account…"))
                            .font(DS.Font.plex(14, weight: .bold))
                            .foregroundColor(DS.Color.textPrimary)
                    }
                    .padding(DS.Spacing.xl)
                    .background(DS.Color.background,
                                in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                }
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
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
            // عنوان الشاشة و«إغلاق» داخل الرأس (بدل شريط التنقل)
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.18)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    .rotationEffect(.degrees(heroAppeared || reduceMotion ? 0 : -120))
                    .accessibilityHidden(true)   // زخرفة
                Text(t("الإعدادات", "Settings"))
                    .font(DS.Font.plex(15, weight: .bold))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Text(t("إغلاق", "Close"))
                        .font(DS.Font.plex(13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(Color.white.opacity(0.2)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                        // مساحة ضغط ٤٤ نقطة (حد أبل) داخل هامش البطاقة — الحبّة ومكانها كما هما
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .padding(.vertical, -7)
                }
                .buttonStyle(DSScaleButtonStyle())
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)

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
                .accessibilityHidden(true)   // الصورة زخرفة — الاسم مكتوب بجانبها

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
                        // مساحة ضغط ٤٤ نقطة (حد أبل) داخل هامش البطاقة — الدائرة ومكانها كما هما
                        .padding(6)
                        .contentShape(Rectangle())
                        .padding(-6)
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
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 170, height: 170)
                    .blur(radius: 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: 40, y: -70)
                Image(systemName: "tree.fill")
                    .font(.system(size: 130, weight: .regular))
                    .foregroundColor(.white.opacity(0.07))
                    .offset(x: -14, y: 22)
                    .accessibilityHidden(true)   // علامة مائية
                DSShineSweep(delay: 0.35)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
        .shadow(color: DS.Color.primary.opacity(0.25), radius: 12, y: 6)
        .scaleEffect(heroAppeared || reduceMotion ? 1 : 0.94)
        .opacity(heroAppeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2)
                                       : .spring(response: 0.55, dampingFraction: 0.72)) { heroAppeared = true }
        }
    }

    @State private var heroAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// عنوان مجموعة صغير بأيقونة — نفس عناوين أقسام المربّعات
    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(DS.Color.primary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(DS.Color.primary.opacity(0.13)))
                .accessibilityHidden(true)   // زخرفة
            Text(title)
                .font(DS.Font.plex(12.5, weight: .bold))
                .foregroundColor(DS.Color.fieldLabel)
            Spacer(minLength: 0)
        }
        .padding(.bottom, -DS.Spacing.sm)
    }

    private func cardFact(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(.white.opacity(0.75))
                .accessibilityHidden(true)   // زخرفة
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
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom)))
                .shadow(color: color.opacity(0.35), radius: 6, y: 3)
                .accessibilityHidden(true)   // زخرفة — العنوان والقيمة يكفيان
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

    @Environment(\.dismiss) private var dismiss

    /// مربّع بمنتصف الشاشة بتصميم المربّعات الموحّد (طلب المالك) — التغييرات تُحفظ فوراً
    /// كما كانت، فالشريط السفلي «إغلاق» فقط.
    var body: some View {
        DSComposer(
            title: t("الإشعارات والخصوصية", "Notifications & Privacy"),
            subtitle: t("تحكّم بالتنبيهات ومن يشوف بياناتك", "Control alerts and who sees your data"),
            icon: "bell.badge.fill",
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            cancelTitle: t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { dismiss() }
        ) {
            statusSection
            typesSection
            badgeSection
            privacySection
            // الأعضاء المحظورون — إلغاء الحظر من هنا (Guideline 1.2)
            BlockedMembersSection(index: 4)
        }
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

    // MARK: - الأقسام

    private var typesSection: some View {
        DSComposerSection(title: t("أنواع الإشعارات", "Notification types"),
                          icon: "slider.horizontal.3", tint: DS.Color.primary, index: 1) {
            VStack(spacing: DS.Spacing.sm) {
                ForEach(kinds) { kind in
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
                sectionNote(t("إعلانات الإدارة وتحديثات التطبيق تصلك دائماً. النوع المطفأ يبقى داخل التطبيق بدون تنبيه.",
                              "Admin announcements and app updates always arrive. Muted types stay in the app without an alert."))
            }
            .disabled(!notificationsEnabled)
            .opacity(notificationsEnabled ? 1 : 0.45)
        }
    }

    private var badgeSection: some View {
        DSComposerSection(title: t("الأيقونة", "App icon"), icon: "app.badge.fill",
                          tint: DS.Color.primary, index: 2) {
            switchRow(icon: "app.badge.fill", color: DS.Color.primary,
                      title: t("شارة الأيقونة", "App badge"),
                      subtitle: t("عدد غير المقروء على أيقونة التطبيق", "Unread count on the app icon"),
                      isOn: $badgeEnabled)
        }
    }

    private var privacySection: some View {
        DSComposerSection(title: t("الخصوصية", "Privacy"), icon: "lock.fill",
                          tint: DS.Color.accent, index: 3) {
            VStack(spacing: DS.Spacing.sm) {
                switchRow(icon: "phone.down.fill", color: DS.Color.accent,
                          title: t("إخفاء رقم الهاتف", "Hide phone number"),
                          subtitle: t("ما يظهر رقمك للأعضاء", "Members won't see your number"),
                          isOn: $isPhoneHidden)
                switchRow(icon: "calendar.badge.minus", color: DS.Color.accent,
                          title: t("إخفاء تاريخ الميلاد", "Hide birth date"),
                          subtitle: t("ما يظهر تاريخ ميلادك للأعضاء", "Members won't see your birth date"),
                          isOn: $isBirthDateHidden)
                sectionNote(t("بياناتك تبقى محفوظة في الشجرة، بس ما تظهر للأعضاء. الإدارة تشوفها.",
                              "Your data stays in the tree but is hidden from members. Admins can still see it."))
            }
        }
    }

    // MARK: - قسم الحالة: الجهاز + المفتاح الرئيسي + التجربة
    private var systemBlocked: Bool { systemStatus == .denied }

    private var statusSection: some View {
        let on = notificationsEnabled && !systemBlocked
        let tint = on ? DS.Color.success : DS.Color.warning
        return DSComposerSection(title: t("حالة الإشعارات", "Notification status"),
                                 icon: on ? "bell.badge.fill" : "bell.slash.fill",
                                 tint: tint, index: 0) {
          VStack(spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: on ? "bell.badge.fill" : "bell.slash.fill", tint: tint)
                    .accessibilityHidden(true)   // زخرفة
                VStack(alignment: .leading, spacing: 2) {
                    Text(on ? t("الإشعارات شغّالة", "Notifications are on")
                            : (systemBlocked ? t("موقوفة من إعدادات الجهاز", "Blocked in device settings")
                                             : t("الإشعارات موقوفة", "Notifications are off")))
                        .font(DS.Font.plex(13.5, weight: .bold))
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(on ? t("توصلك تنبيهات العائلة على هذا الجهاز", "Family alerts reach this device")
                            : t("ما توصلك تنبيهات على هذا الجهاز", "No alerts on this device"))
                        .font(DS.Font.plex(11))
                        .foregroundColor(DS.Color.textTertiary)
                }
                Spacer(minLength: DS.Spacing.sm)
                Toggle("", isOn: $notificationsEnabled)
                    .labelsHidden()
                    .tint(DS.Color.success)
                    // القارئ الصوتي: المفتاح بلا نص ظاهر — اسمه صراحةً
                    .accessibilityLabel(t("الإشعارات", "Notifications"))
            }
            .dsRowBox()

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
                        Group {
                            switch testState {
                            case .sending: ProgressView().scaleEffect(0.8)
                            case .sent: Image(systemName: "checkmark.circle.fill")
                            case .failed: Image(systemName: "exclamationmark.triangle.fill")
                            case .idle: Image(systemName: "paperplane.fill")
                            }
                        }
                        .accessibilityHidden(true)   // زخرفة — النص يصف الحالة
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
        }
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

    // MARK: - صفوف بنفس صفوف المربّعات
    private func switchRow(icon: String, color: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: color)
                .accessibilityHidden(true)   // زخرفة
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                Text(subtitle)
                    .font(DS.Font.plex(11))
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // يُقرأ اسماً ووصفاً للمفتاح نفسه (لا يُكرَّر)
            .accessibilityHidden(true)
            Spacer(minLength: DS.Spacing.sm)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(DS.Color.primary)
                // القارئ الصوتي: المفتاح بلا نص ظاهر — اسمه ووصفه صراحةً
                .accessibilityLabel(title)
                .accessibilityHint(subtitle)
        }
        .dsRowBox()
    }

    private func sectionNote(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.plex(10.5, weight: .medium))
            .foregroundColor(DS.Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
/// مربّع بمنتصف الشاشة (طلب المالك): اختيار المظهر واللغة بمربّعات بدل شرائح —
/// يتطبّق فوراً كما كان، والشريط السفلي «إغلاق».
struct AppearanceSettingsView: View {
    @ObservedObject var langManager = LanguageManager.shared
    /// للرجوع للغة التطبيق الرسمية
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @Environment(\.dismiss) private var dismiss
    /// «تقليل الحركة» (توصية أبل): علامة الاختيار تظهر بتلاشٍ فقط بلا تكبير
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    private struct Option: Identifiable {
        let id: String
        let icon: String
        let title: String
    }

    private var appearanceOptions: [Option] {
        [Option(id: "system", icon: "iphone", title: t("حسب الجهاز", "System")),
         Option(id: "light", icon: "sun.max.fill", title: t("فاتح", "Light")),
         Option(id: "dark", icon: "moon.stars.fill", title: t("داكن", "Dark"))]
    }

    private var languageOptions: [Option] {
        [Option(id: "ar", icon: "character.book.closed.fill", title: "العربية"),
         Option(id: "en", icon: "textformat.abc", title: "English")]
    }

    var body: some View {
        DSComposer(
            title: t("المظهر واللغة", "Appearance & Language"),
            subtitle: t("شكل التطبيق ولغته", "How the app looks and reads"),
            icon: "paintbrush.fill",
            tint: DS.Color.composerLibrary,
            actionTitle: "",
            showsAction: false,
            cancelTitle: t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { dismiss() }
        ) {
            DSComposerSection(title: t("المظهر", "Appearance"), icon: "circle.lefthalf.filled",
                              tint: DS.Color.accent, index: 0) {
                VStack(spacing: DS.Spacing.sm) {
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(appearanceOptions) { option in
                            optionCard(option, selected: appearanceMode == option.id, tint: DS.Color.accent) {
                                guard appearanceMode != option.id else { return }
                                withAnimation(DS.Anim.snappy) { appearanceMode = option.id }
                            }
                        }
                    }
                    note(appearanceDescription)
                }
            }

            DSComposerSection(title: t("اللغة", "Language"), icon: "character.bubble.fill",
                              tint: DS.Color.primary, index: 1) {
                VStack(spacing: DS.Spacing.sm) {
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(languageOptions) { option in
                            optionCard(option, selected: langManager.selectedLanguage == option.id,
                                       tint: DS.Color.primary) {
                                // اختيار المستخدم يثبّت لغته — ولا تغيّرها اللغة الرسمية بعدها
                                // (نفس سلوك الشرائح: اختيار اللغة الحالية لا يغيّر شيئاً)
                                guard langManager.selectedLanguage != option.id else { return }
                                langManager.chooseLanguage(option.id)
                            }
                        }
                    }
                    note(langManager.languageChosenByUser
                         ? t("اخترت لغتك بنفسك — لا تتأثر بلغة التطبيق الرسمية.",
                             "You chose your language — the app's official language won't change it.")
                         : t("تتبع لغة التطبيق الرسمية التي تحددها الإدارة.",
                             "Following the app's official language set by the admins."))

                    if langManager.languageChosenByUser {
                        Button {
                            langManager.followOfficialLanguage(appSettingsVM.settings.defaultLanguage)
                        } label: {
                            Label(t("الرجوع للغة التطبيق الرسمية", "Use the app's official language"),
                                  systemImage: "arrow.uturn.backward")
                                .font(DS.Font.plex(13, weight: .bold))
                                .foregroundColor(DS.Color.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(DS.Color.primary.opacity(0.10),
                                            in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        }
                        .buttonStyle(DSScaleButtonStyle())
                    }
                }
            }
        }
        .environment(\.layoutDirection, langManager.layoutDirection)
    }

    /// مربّع اختيار: أيقونة بدائرة + الاسم، والمختار بإطار ولون ممتلئ وعلامة ✓
    private func optionCard(_ option: Option, selected: Bool, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: option.icon)
                    .font(.system(size: 17, weight: .bold))
                    // المختار: رمز بلون الخلفية فوق لون القسم — واضح بالوضعين
                    .foregroundColor(selected ? DS.Color.background : tint)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(selected ? tint : tint.opacity(0.14)))
                    .accessibilityHidden(true)   // زخرفة — الاسم يكفي
                Text(option.title)
                    .font(DS.Font.plex(12.5, weight: .bold))
                    .foregroundColor(selected ? DS.Color.fieldLabel : DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.sm + 2)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(selected ? tint.opacity(0.08) : DS.Color.background))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(selected ? tint.opacity(0.7) : DS.Color.textTertiary.opacity(0.15),
                              lineWidth: selected ? 1.5 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(tint)
                        .padding(6)
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                        .accessibilityHidden(true)   // الاختيار يُقرأ من حالة الزر
                }
            }
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.plex(11))
            .foregroundColor(DS.Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
/// «عن التطبيق» — مربّع عرض بمنتصف الشاشة بتصميم المربّعات الموحّد (طلب المالك)
struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) private var openURL
    /// «راسل الإدارة» — نموذج التواصل داخل التطبيق (Guideline 1.5)
    @State private var showContactForm = false
    private var isArabic: Bool { LanguageManager.shared.selectedLanguage == "ar" }
    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    private var appVersion: String { AppVersion.string }

    var body: some View {
        DSComposer(
            title: t("عن التطبيق", "About"),
            subtitle: t("الإصدار \(appVersion)", "Version \(appVersion)"),
            icon: "tree.fill",
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            cancelTitle: t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { dismiss() }
        ) {
            hero
                .dsStaggerIn(0)

            DSComposerSection(title: t("مزايا التطبيق", "Features"), icon: "sparkles",
                              tint: DS.Color.primary, index: 1) {
                VStack(spacing: DS.Spacing.sm) {
                    aboutItem(
                        icon: "person.3.fill",
                        color: DS.Color.primary,
                        title: t("شجرة العائلة", "Family Tree"),
                        desc: t("استعرض أفراد عائلتك وأنسابهم بشكل تفاعلي", "Browse your family members and lineage interactively")
                    )
                    aboutItem(
                        icon: "newspaper.fill",
                        color: DS.Color.info,
                        title: t("أخبار العائلة", "Family News"),
                        desc: t("شارك الأخبار وتفاعل بالتعليقات والإعجابات", "Share news and interact with comments & likes")
                    )
                    aboutItem(
                        icon: "bell.badge.fill",
                        color: DS.Color.warning,
                        title: t("الإشعارات", "Notifications"),
                        desc: t("إشعارات فورية داخل التطبيق وعلى جهازك", "Instant alerts inside the app and on your device")
                    )
                    aboutItem(
                        icon: "lock.shield.fill",
                        color: DS.Color.success,
                        title: t("الخصوصية والأمان", "Privacy & Security"),
                        desc: t("بياناتك محمية بالكامل وتتحكّم بمن يراها", "Your data is fully protected — you control visibility")
                    )
                }
            }

            // تواصل معنا — معلومات تواصل منشورة (Guideline 1.5)
            DSComposerSection(title: t("تواصل معنا", "Contact Us"), icon: "envelope.fill",
                              tint: DS.Color.actionNavy, index: 2) {
                VStack(spacing: DS.Spacing.sm) {
                    SafetyLinkRow(icon: "bubble.left.and.text.bubble.right.fill", tint: DS.Color.primary,
                                  title: t("راسل الإدارة", "Message the admins"),
                                  subtitle: t("من داخل التطبيق — ويصلك الرد", "Inside the app — you'll get a reply")) {
                        showContactForm = true
                    }
                    SafetyLinkRow(icon: "envelope.fill", tint: DS.Color.info,
                                  title: t("البريد الإلكتروني", "Email"),
                                  subtitle: FamilyLinks.supportEmail,
                                  external: true) {
                        openURL(FamilyLinks.supportEmailURL)
                    }
                    SafetyLinkRow(icon: "globe", tint: DS.Color.success,
                                  title: t("موقع العائلة", "Family website"),
                                  subtitle: FamilyLinks.websiteDisplay,
                                  external: true) {
                        openURL(FamilyLinks.website)
                    }
                }
            }

            VStack(spacing: DS.Spacing.xs) {
                Text(t("صُنع بحب لعائلة آل محمد علي 🤍", "Made with love for Al-Mohammad Ali family 🤍"))
                    .font(DS.Font.plex(12, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                Text("© 2026 FamilyTree")
                    .font(DS.Font.plex(10.5))
                    .foregroundColor(DS.Color.textTertiary.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xs)
            .dsStaggerIn(3)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        // نموذج التواصل مع الإدارة — مربّع بمنتصف الشاشة
        .dsCenterBox(isPresented: $showContactForm) {
            MemberContactFormView()
        }
    }

    /// أيقونة التطبيق + الاسم + الإصدار
    private var hero: some View {
        VStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 76, height: 76)
                    .dsGlowShadow()
                Image(systemName: "tree.fill")
                    .font(DS.Font.scaled(32, weight: .bold))
                    .foregroundColor(DS.Color.textOnPrimary)
            }
            .accessibilityHidden(true)   // أيقونة زخرفية — الاسم تحتها
            Text(t("عائلة المحمدعلي", "Al-Mohammadali Family"))
                .font(DS.Font.plex(18, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)
            Text(t("الإصدار \(appVersion)", "Version \(appVersion)"))
                .font(DS.Font.plex(11.5, weight: .semibold))
                .foregroundColor(DS.Color.textSecondary)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
                .background(DS.Color.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.Color.textTertiary.opacity(0.25), lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.sm)
    }

    /// صف ميزة — نفس صفوف المربّعات
    private func aboutItem(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: color)
                .accessibilityHidden(true)   // زخرفة
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                Text(desc)
                    .font(DS.Font.plex(12))
                    .foregroundColor(DS.Color.fieldValue)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .dsRowBox()
    }
}

// MARK: - Privacy Policy & Terms View
/// «الخصوصية والشروط» — مربّع عرض بمنتصف الشاشة بتصميم المربّعات الموحّد (طلب المالك)
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) private var openURL
    private var isArabic: Bool { LanguageManager.shared.selectedLanguage == "ar" }
    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    private struct Policy: Identifiable {
        /// ثابت بين إعادات الرسم — حتى لا تُعاد حركة دخول الأقسام
        var id: String { title }
        let icon: String
        let color: Color
        let title: String
        let points: [String]
    }

    private var policies: [Policy] {
        [
            Policy(icon: "tray.and.arrow.down.fill", color: DS.Color.primary,
                   title: t("جمع البيانات", "Data Collection"),
                   points: [
                    t("نجمع الاسم ورقم الهاتف وتاريخ الميلاد، والبريد الإلكتروني إن أضفته، والصور والمحتوى الذي تنشره (الأخبار والتعليقات والمشاريع والديوانيات ومواد المكتبة).",
                      "We collect your name, phone number, birth date, your email if you add it, and the photos and content you post (news, comments, projects, diwaniyas and library items)."),
                    t("نحفظ معرّف جهازك ونوعه لإدارة الأجهزة المرتبطة وإرسال الإشعارات، وآخر نشاط لك داخل التطبيق لأغراض الإدارة وإحصاءات الاستخدام.",
                      "We store your device identifier and model to manage linked devices and deliver notifications, and your last in-app activity for administration and usage statistics."),
                    t("لا نجمع بيانات الموقع أو جهات الاتصال أو سجل التصفح.", "We don't collect location, contacts, or browsing history."),
                    t("يتم التحقق من هويتك عبر رمز OTP يُرسل لهاتفك.", "Your identity is verified via an OTP code sent to your phone.")
                   ]),
            Policy(icon: "hand.raised.fill", color: DS.Color.accent,
                   title: t("استخدام البيانات", "Data Usage"),
                   points: [
                    t("بياناتك تُستخدم فقط لعرض الشجرة والتواصل بين الأعضاء.", "Your data is only used for the family tree and communication."),
                    t("لا نبيع بياناتك ولا نستخدمها للإعلانات أو التتبّع، ولا نشاركها إلا مع مزوّدي الخدمة الذين يشغّلون التطبيق (الاستضافة ورسائل التحقق والإشعارات).",
                      "We never sell your data or use it for ads or tracking; it is shared only with the service providers that run the app (hosting, verification messages and notifications)."),
                    t("يمكن للمدراء فقط الاطلاع على البيانات لأغراض الإدارة.", "Only admins can view data for management purposes.")
                   ]),
            Policy(icon: "server.rack", color: DS.Color.info,
                   title: t("التخزين والأمان", "Storage & Security"),
                   points: [
                    t("بياناتك مخزّنة على خوادم مشفرة وآمنة.", "Your data is stored on encrypted and secure servers."),
                    t("جميع الاتصالات محمية عبر بروتوكول HTTPS.", "All connections are protected via HTTPS protocol."),
                    t("نستخدم حماية على مستوى كل مستخدم.", "We apply per-user level data protection.")
                   ]),
            Policy(icon: "trash.fill", color: DS.Color.error,
                   title: t("حذف البيانات", "Data Deletion"),
                   points: [
                    t("يمكنك حذف حسابك في أي وقت من الإعدادات ← «حذف الحساب».", "You can delete your account at any time from Settings → “Delete Account”."),
                    t("عند الحذف تُحذف من خوادمنا بياناتك الشخصية وصورك وما نشرته من أخبار وتعليقات ومحتوى، ويبقى موضعك في شجرة العائلة باسم «عضو محذوف» حفاظاً على تسلسل النسب.",
                      "Deletion removes your personal details, photos and the news, comments and content you posted from our servers; your place in the family tree stays as “Deleted member” to keep the lineage intact."),
                    t("لا يمكن استرجاع البيانات بعد الحذف النهائي.", "Data cannot be recovered after permanent deletion.")
                   ]),
            Policy(icon: "bell.badge.fill", color: DS.Color.warning,
                   title: t("الإشعارات", "Notifications"),
                   points: [
                    t("نرسل إشعارات عن التعليقات والإعجابات والتحديثات.", "We send alerts for comments, likes, and updates."),
                    t("تتحكّم بأنواع الإشعارات من إعدادات الخصوصية.", "Control notification types from Privacy settings."),
                    t("يمكنك تعطيل الإشعارات بالكامل من الإعدادات.", "You can fully disable notifications from Settings.")
                   ]),
            Policy(icon: "doc.text.fill", color: DS.Color.neonPurple,
                   title: t("شروط الاستخدام", "Terms of Use"),
                   points: [
                    t("التطبيق مخصص حصرياً لأفراد عائلة آل محمد علي، واستخدامه يعني الموافقة على هذه الشروط.",
                      "The app is exclusively for Al-Mohammad Ali family members; using it means you agree to these terms."),
                    t("لا تسامح مطلقاً مع المحتوى المسيء أو المستخدمين المسيئين: يُمنع نشر أي محتوى مسيء أو مهين أو بذيء أو عنصري أو مخالف للآداب، أو التحرّش بأي عضو أو انتحال شخصيته.",
                      "Zero tolerance for objectionable content or abusive users: posting offensive, insulting, obscene, hateful or indecent content, harassing any member or impersonating anyone is prohibited."),
                    t("يمكنك الإبلاغ عن أي خبر أو تعليق أو عضو أو محتوى بزر «إبلاغ»، وحظر أي عضو فيختفي عنك محتواه.",
                      "You can report any post, comment, member or content with the “Report” button, and block any member to hide their content from you."),
                    t("تراجع الإدارة كل بلاغ خلال ٢٤ ساعة، وتحذف المحتوى المخالف وتوقف حساب صاحبه.",
                      "Admins review every report within 24 hours, remove the violating content and suspend the account that posted it."),
                    t("يجب استخدام التطبيق بمسؤولية واحترام خصوصية الآخرين.", "Use the app responsibly and respect others' privacy."),
                    t("يحق للإدارة تجميد أو حذف الحسابات المخالفة.", "Admins may freeze or delete accounts that violate policies.")
                   ])
        ]
    }

    var body: some View {
        DSComposer(
            title: t("الخصوصية والشروط", "Privacy & Terms"),
            subtitle: t("كيف نحمي بياناتك", "How we protect your data"),
            icon: "lock.shield.fill",
            tint: DS.Color.composerProject,
            actionTitle: "",
            showsAction: false,
            cancelTitle: t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { dismiss() }
        ) {
            Text(t(
                "نحرص على حماية خصوصيتك وبياناتك. تعرّف على سياستنا وشروط الاستخدام.",
                "We protect your privacy and data. Learn about our policy and terms of use."
            ))
            .font(DS.Font.plex(13))
            .foregroundColor(DS.Color.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .dsStaggerIn(0)

            ForEach(Array(policies.enumerated()), id: \.element.id) { index, policy in
                DSComposerSection(title: policy.title, icon: policy.icon, tint: policy.color, index: index + 1) {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        ForEach(policy.points, id: \.self) { point in
                            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                                Circle()
                                    .fill(policy.color.opacity(0.7))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 7)
                                Text(point)
                                    .font(DS.Font.plex(13))
                                    .foregroundColor(DS.Color.fieldValue)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }

            // النص الكامل على الموقع الرسمي (Guideline 5.1.1)
            DSComposerSection(title: t("على موقع العائلة", "On our website"), icon: "globe",
                              tint: DS.Color.info, index: policies.count + 1) {
                VStack(spacing: DS.Spacing.sm) {
                    SafetyLinkRow(icon: "hand.raised.fill", tint: DS.Color.accent,
                                  title: t("سياسة الخصوصية", "Privacy Policy"),
                                  subtitle: "\(FamilyLinks.websiteDisplay)/privacy",
                                  external: true) {
                        openURL(FamilyLinks.privacyPolicy)
                    }
                    SafetyLinkRow(icon: "doc.text.fill", tint: DS.Color.neonPurple,
                                  title: t("شروط الاستخدام", "Terms of Use"),
                                  subtitle: "\(FamilyLinks.websiteDisplay)/terms",
                                  external: true) {
                        openURL(FamilyLinks.termsOfUse)
                    }
                }
            }

            // تواصل معنا (Guideline 1.5)
            DSComposerSection(title: t("تواصل معنا", "Contact Us"), icon: "envelope.fill",
                              tint: DS.Color.primary, index: policies.count + 2) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text(t("لأي استفسار أو بلاغ، استخدم «التواصل» في الصفحة الرئيسية داخل التطبيق، أو راسلنا على البريد الرسمي.",
                           "For any question or report, use “Contact” on the Home screen inside the app, or email us."))
                        .font(DS.Font.plex(13))
                        .foregroundColor(DS.Color.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                    SafetyLinkRow(icon: "envelope.fill", tint: DS.Color.info,
                                  title: t("البريد الإلكتروني", "Email"),
                                  subtitle: FamilyLinks.supportEmail,
                                  external: true) {
                        openURL(FamilyLinks.supportEmailURL)
                    }
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}

// MARK: - Linked Devices Settings Sheet
/// الأجهزة المرتبطة — مربّع عرض بمنتصف الشاشة بتصميم المربّعات الموحّد (طلب المالك):
/// رأس ملوّن + قسم الأجهزة + «إغلاق». للعرض فقط — لا إزالة أجهزة من هنا.
struct LinkedDevicesSettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    private var maxDevices: Int { appSettingsVM.settings.maxDevicesPerUser }
    private var isArabic: Bool { LanguageManager.shared.selectedLanguage == "ar" }
    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }


    var body: some View {
        DSComposer(
            title: t("الأجهزة المرتبطة", "Linked Devices"),
            subtitle: t("الأجهزة التي سجّلت الدخول بحسابك", "Devices signed in to your account"),
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
                tint: DS.Color.primary,
                index: 0
            ) {
                VStack(spacing: DS.Spacing.sm) {
                    limitRow

                    if notificationVM.linkedDevices.isEmpty {
                        emptyRow
                    } else {
                        ForEach(notificationVM.linkedDevices) { device in
                            deviceRow(device)
                        }
                    }
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            await notificationVM.fetchLinkedDevices()
        }
    }

    /// الحد الأقصى — صف قراءة بنفس صفوف المربّعات
    private var limitRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "info.circle.fill", tint: DS.Color.info)
                .accessibilityHidden(true)   // زخرفة
            VStack(alignment: .leading, spacing: 2) {
                Text(t("الحد الأقصى", "Limit"))
                    .font(DS.Font.plex(12, weight: .heavy))
                    .foregroundColor(DS.Color.fieldLabel)
                Text(t(
                    "\(notificationVM.linkedDevices.count) من \(maxDevices) أجهزة",
                    "\(notificationVM.linkedDevices.count) of \(maxDevices) devices"
                ))
                    .font(DS.Font.plex(14.5, weight: .bold))
                    .foregroundColor(DS.Color.fieldValue)
            }
            Spacer(minLength: 0)
        }
        .dsRowBox()
    }

    private var emptyRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "iphone.slash", tint: DS.Color.textTertiary)
                .accessibilityHidden(true)   // زخرفة
            Text(t("لا توجد أجهزة مرتبطة", "No linked devices"))
                .font(DS.Font.plex(14))
                .foregroundColor(DS.Color.textSecondary)
            Spacer(minLength: 0)
        }
        .dsRowBox()
    }

    /// صف جهاز: أيقونة الحقل + اسم الجهاز (+ «الحالي») + آخر ظهور
    private func deviceRow(_ device: NotificationViewModel.LinkedDevice) -> some View {
        let isCurrent = device.isCurrent(currentDeviceId: notificationVM.currentDeviceId)
        return HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "iphone.gen3", tint: isCurrent ? DS.Color.success : DS.Color.accent)
                .accessibilityHidden(true)   // زخرفة

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Spacing.xs + 2) {
                    Text(device.displayName)
                        .font(DS.Font.plex(13.5, weight: .bold))
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if isCurrent {
                        Text(t("الحالي", "Current"))
                            .font(DS.Font.plex(10.5, weight: .bold))
                            .foregroundColor(DS.Color.success)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(DS.Color.success.opacity(0.15)))
                            .fixedSize()
                    }
                }

                Text(formattedDate(device.updatedAt))
                    .font(DS.Font.plex(12.5))
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .dsRowBox()
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
