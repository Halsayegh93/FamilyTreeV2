import SwiftUI
import UserNotifications
import Supabase

// MARK: - Main Settings View (iOS-style with semantic groups)
struct SettingsView: View {
    /// لون القسم («حسابي») — كحلي «الإطار» يتبعه، وبلا قسم يبقى كحلي العلامة
    @Environment(\.dsSection) private var section
    private var chromeInk: Color { DS.Color.primary.dsChrome(in: section) }
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
    /// كل مربّعات الإعدادات تفتح بمنتصف الشاشة (طلب المالك) بدل صفحة جديدة —
    /// «مربّعات بمجموعات» (اختيار المالك ٢٠٢٦-١٠-٠٧): كل مربّع يفتح جزءه وحده
    @State private var showNotifications = false
    @State private var showPrivacy = false
    @State private var showAppearance = false
    @State private var showLanguage = false
    @State private var showAbout = false
    @State private var showTerms = false
    @State private var showDeleteConfirmation = false
    /// حذف الحساب جارٍ — طبقة انتظار حتى يكتمل ويُسجَّل الخروج
    @State private var isDeletingAccount = false
    /// وضع العرض: المربّعات الصغيرة بشبكة تكيّفية (`DS.Landscape.compactTileMinWidth`) — العمودي ثلاثة في الصف
    @Environment(\.dsLandscape) private var landscape

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    /// ثلاثة مربّعات صغيرة في الصف عمودياً (طلب المالك ٢٠٢٦-١٠-٠٧ «صغّر المربّعات») — كثافة مربّعات
    /// أدوات لوحة الإدارة الصغيرة
    private static let portraitColumns = 3

    var body: some View {
        // «مربّعات بمجموعات» (اختيار المالك ٢٠٢٦-١٠-٠٧): بطاقة الهوية أعلى، ثم ثلاث مجموعات قصيرة
        // (التفضيلات · الحساب · المساعدة) كل مربّع فيها يعرض قيمته الحالية ويفتح جزءه وحده،
        // وحذف الحساب زر في الأسفل.
        ScrollView {
            VStack(spacing: DS.Spacing.xl) {
                profileCard

                // الحركة (طلب المالك ٢٠٢٦-٠٩-٢٧): عنوان المجموعة ثم مربّعاتها واحداً بعد الآخر
                // — نفس إيقاع المربّعات. «تقليل الحركة»: تلاشٍ فقط
                // شبكة واحدة بلا مجموعات، ٣ بالسطر، من الأكثر استخداماً للأقل (طلب المالك ٢٠٢٦-١٠-١٠؛
                // «دليل الاستخدام» أُزيل من هنا — يُفتح من زرّ (i) في الرئيسية)
                tileGrid(allTiles, startIndex: 1)

                // حذف الحساب — آخر الصفحة بعيداً عن الاستعمال اليومي: نصّ أحمر صغير بلا تعبئة مع سطر تحذير،
                // لا زرّ أحمر عريض مثبّت (كان يشبه «تسجيل الخروج» — طلب المالك ٢٠٢٦-١٠-١٠ «نفرّق بالشكل والحجم والمكان»)
                VStack(spacing: DS.Spacing.xxs) {
                    DSDangerTextButton(t("حذف الحساب", "Delete Account")) {
                        showDeleteConfirmation = true
                    }
                    Text(t("حذف نهائي لبياناتك ولا يمكن التراجع عنه.", "Permanently deletes your data — this can't be undone."))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                    versionLabel
                        .padding(.top, DS.Spacing.sm)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Spacing.lg)
                .dsStaggerIn(allTiles.count + 1)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xxxl)
        }
        // الرأس الملوّن الموحّد للصفحات الفرعية (بدل بطاقة الرأس و«إغلاق») — × في الطرف لأنها ورقة
        .dsSubPageHeader(t("الإعدادات", "Settings"), nav: .close)
        .environment(\.layoutDirection, langManager.layoutDirection)
        // نموذج طويل فيه كتابة وتمرير — مربّع طويل من الأسفل (توصية أبل)
        // (نفس المربّع من قلم بطاقة الهوية ومن مربّع «تعديل الملف»)
        .dsTallBox(isPresented: $showEditProfile) {
            if let c = authVM.currentUser { EditProfileView(member: c) }
        }
        .dsCenterBox(isPresented: $showLinkedDevices) {
            LinkedDevicesSettingsSheet().environmentObject(appSettingsVM)
        }
        .dsTallBox(isPresented: $showNotifications) {   // قائمة إعدادات طويلة — مربّع طويل (توصية أبل)
            NotificationsAndPrivacyView(focus: .notifications)
                .environmentObject(authVM)
                .environmentObject(memberVM)
                .environmentObject(notificationVM)
        }
        .dsCenterBox(isPresented: $showPrivacy) {
            NotificationsAndPrivacyView(focus: .privacy)
                .environmentObject(authVM)
                .environmentObject(memberVM)
                .environmentObject(notificationVM)
        }
        .dsCenterBox(isPresented: $showAppearance, onBackgroundTap: { showAppearance = false }) {
            AppearanceSettingsView(focus: .appearance).environmentObject(appSettingsVM)
        }
        .dsCenterBox(isPresented: $showLanguage, onBackgroundTap: { showLanguage = false }) {
            AppearanceSettingsView(focus: .language).environmentObject(appSettingsVM)
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
                "سيتم حذف نهائياً:\n• حسابك وبيانات تسجيل الدخول\n• صورتك وسيرتك وبياناتك الشخصية\n• أخبارك وتعليقاتك وما أضفته من محتوى\n\nيبقى اسمك وموضعك في شجرة العائلة حفاظاً على تسلسل النسب. لا يمكن التراجع عن هذا الإجراء.",
                "This will permanently delete:\n• Your account & login credentials\n• Your photo, life stations and personal details\n• Your posts, comments and other content you added\n\nYour name and place in the family tree stay to keep the lineage intact. This cannot be undone."
            ))
        }
        .overlay {
            if isDeletingAccount {
                // طبقة انتظار: نفس مجسّم التحميل الواحد يتنفّس + النص، فوق غطاء خافت
                ZStack {
                    DS.Color.hierarchicalSecondary.ignoresSafeArea()
                    DSPageLoader(t("جاري حذف الحساب…", "Deleting account…"), fillsSpace: false)
                        .padding(DS.Spacing.xl)
                        .dsCard(padding: nil)
                        .padding(.horizontal, DS.Spacing.xxxxl)
                }
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

    /// بطاقة هوية العائلة (طلب المالك): الصورة، الاسم والدور والرقم، وقلم التعديل في الطرف،
    /// وسطر سفلي: عضو منذ + الميلاد. صارت البطاقة الواحدة (`.dsCard`) تحت الرأس الملوّن الموحّد —
    /// عنوان الصفحة و× الإغلاق انتقلا إلى الرأس.
    private var profileCard: some View {
        let user = authVM.currentUser
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                Group {
                    if let avatar = user?.avatarUrl, let url = URL(string: avatar) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: { chromeInk.opacity(DS.Opacity.tintFill) }
                    } else {
                        ZStack {
                            chromeInk.opacity(DS.Opacity.tintFill)
                            Image(systemName: "person.fill")
                                .dsGlyph(DS.Glyph.xxl)
                                .foregroundColor(chromeInk)
                        }
                    }
                }
                .frame(width: DS.Icon.avatarLarge, height: DS.Icon.avatarLarge)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(chromeInk.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
                .accessibilityHidden(true)   // الصورة زخرفة — الاسم مكتوب بجانبها

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(L10n.t("عائلة المحمدعلي", "Al-Mohammad Ali family"))
                        .dsFont(.micro)
                        .foregroundColor(DS.Color.textTertiary)
                    Text(user?.displayName ?? "")
                        .dsFont(.title)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: DS.Spacing.sm) {
                        if let user {
                            DSStatusChip(text: user.roleName, tint: DS.Color.primary, size: .mini)
                        }
                        if let phone = user?.phoneNumber, !phone.isEmpty {
                            Text(KuwaitPhone.display(phone))
                                .dsFont(.caption)
                                .foregroundColor(DS.Color.textSecondary)
                                .monospacedDigit()
                                .environment(\.layoutDirection, .leftToRight)
                        }
                    }
                }
                Spacer(minLength: 0)

                // زرّ التعديل بشكل أزرار الرجوع/الإغلاق الموحّدة فوق السطح
                DSHeaderButton(symbol: "pencil", label: t("تعديل الملف الشخصي", "Edit Profile"),
                               context: .surface, size: .toolbar) { showEditProfile = true }
            }
            .padding(DS.Spacing.lg)

            // الشريط السفلي — مثل ظهر البطاقة
            HStack(spacing: DS.Spacing.xl) {
                cardFact(icon: "calendar", title: t("عضو منذ", "Member since"), value: shortDate(user?.createdAt))
                cardFact(icon: "gift.fill", title: t("الميلاد", "Born"), value: shortDate(user?.birthDate))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Color.background)
        }
        // البطاقة الواحدة
        .dsCard(padding: nil)
        .scaleEffect(heroAppeared || reduceMotion ? 1 : 0.94)
        .opacity(heroAppeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2)
                                       : .spring(response: 0.55, dampingFraction: 0.72)) { heroAppeared = true }
        }
    }

    @State private var heroAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - المجموعات: عنوان + شبكة مربّعات

    /// مربّع إعداد واحد في مجموعة
    private struct SettingsTile: Identifiable {
        let id: String
        let icon: String
        let color: Color
        let title: String
        let value: String
        /// قيمة رقمية تصل بعد الظهور (عدد الأجهزة) — تتبدّل بلفّة أرقام
        var liveNumber = false
        let action: () -> Void
    }

    /// شبكة المربّعات وحدها (بلا عنوان مجموعة) — نفس مقاس وأسلوب مربّعات المجموعات
    private func tileGrid(_ tiles: [SettingsTile], startIndex: Int) -> some View {
        LazyVGrid(columns: landscape
                    ? [GridItem(.adaptive(minimum: DS.Landscape.compactTileMinWidth), spacing: DS.Spacing.sm)]
                    : Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: Self.portraitColumns),
                  spacing: DS.Spacing.sm) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                Button(action: tile.action) {
                    valueTile(icon: tile.icon, color: tile.color, title: tile.title, value: tile.value,
                              liveNumber: tile.liveNumber)
                }
                .buttonStyle(DSScaleButtonStyle())
                .dsStaggerIn(startIndex + index)
            }
        }
    }

    /// كل المربّعات بترتيب الاستعمال (طلب المالك ٢٠٢٦-١٠-١٠ «بدون مجموعات»)
    private var allTiles: [SettingsTile] {
        let byId = Dictionary(uniqueKeysWithValues: (preferenceTiles + accountTiles + helpTiles).map { ($0.id, $0) })
        // «تعديل الملف» أُزيل ٢٠٢٦-١٠-١٠ — يبقى من قلم بطاقة الهوية أعلى الإعدادات
        let order = ["notifications", "privacy", "appearance", "language", "devices", "terms", "about"]
        return order.compactMap { byId[$0] }
    }

    /// «التفضيلات»: الإشعارات · الخصوصية · المظهر · اللغة — كلٌّ يفتح جزءه من مربّعه
    private var preferenceTiles: [SettingsTile] {
        [SettingsTile(id: "notifications", icon: "bell.badge.fill", color: DS.Color.warning,
                      title: t("الإشعارات", "Notifications"),
                      value: notificationsEnabled ? t("مفعّلة", "On") : t("موقوفة", "Off")) { showNotifications = true },
         SettingsTile(id: "privacy", icon: "lock.fill", color: DS.Color.secondary,
                      title: t("الخصوصية", "Privacy"), value: privacyLabel) { showPrivacy = true },
         SettingsTile(id: "appearance", icon: "circle.lefthalf.filled", color: DS.Color.accent,
                      title: t("المظهر", "Appearance"), value: appearanceLabel) { showAppearance = true },
         SettingsTile(id: "language", icon: "character.bubble.fill", color: chromeInk,
                      title: t("اللغة", "Language"), value: languageLabel) { showLanguage = true }]
    }

    /// «الحساب»: الأجهزة المرتبطة («تعديل الملف» من قلم بطاقة الهوية)
    private var accountTiles: [SettingsTile] {
        [SettingsTile(id: "devices", icon: "iphone.gen3", color: DS.Color.info,
                      title: t("الأجهزة المرتبطة", "Linked Devices"),
                      value: t("\(notificationVM.linkedDevices.count) جهاز", "\(notificationVM.linkedDevices.count) devices"),
                      // العدد يصل بعد الجلب — يتبدّل بلفّة أرقام بدل القفز
                      liveNumber: true) { showLinkedDevices = true }]
    }

    /// عن التطبيق · الخصوصية والشروط («دليل الاستخدام» و«تواصل مع الإدارة» أُزيلا ٢٠٢٦-١٠-١٠ —
    /// الدليل من زرّ (i) والتواصل من مربّع «التواصل» في الرئيسية)
    private var helpTiles: [SettingsTile] {
        [SettingsTile(id: "about", icon: "app.badge.fill", color: DS.Color.secondary,
                      title: t("عن التطبيق", "About"), value: AppVersion.string) { showAbout = true },
         SettingsTile(id: "terms", icon: "doc.text.fill", color: chromeInk,
                      title: t("الخصوصية والشروط", "Privacy & Terms"),
                      value: t("كيف نحمي بياناتك", "How we protect you")) { showTerms = true }]
    }

    private func cardFact(icon: String, title: String, value: String) -> some View {
        HStack(spacing: DS.Spacing.xsm) {
            Image(dsSymbol: icon)
                .dsGlyph(DS.Glyph.smCompact)
                .foregroundColor(chromeInk)
                .accessibilityHidden(true)   // زخرفة
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .dsFont(.microCompact)
                    .foregroundColor(DS.Color.textTertiary)
                Text(value)
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.textPrimary)
            }
        }
    }

    /// مربّع إعداد صغير (طلب المالك ٢٠٢٦-١٠-٠٧ «صغّر المربّعات»): قرص مجسّم بحجم أيقونة الصف، العنوان
    /// بدور مضغوط، والقيمة الحالية تحته بدور التلميح — حشوة أضيق، نفس كثافة مربّعات أدوات لوحة الإدارة.
    /// `liveNumber`: قيمة رقمية تصل بعد الظهور (مثل عدد الأجهزة) — تتبدّل بلفّة أرقام
    private func valueTile(icon: String, color: Color, title: String, value: String,
                           liveNumber: Bool = false) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            DSStateIcon(icon, tint: color, size: DS.Icon.row)
                .accessibilityHidden(true)   // زخرفة — العنوان والقيمة يكفيان
            Text(title)
                .dsFont(.rowTitleCompact)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            // القيمة تلتفّ لسطرين بالخط الكبير في الجهاز بدل «…» (والمربّعات في الصف بارتفاع أطولها)
            Text(value)
                .dsFont(.caption)
                .foregroundColor(color.dsChrome(in: section).dsReadableGlyph)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(SettingsLiveNumber(active: liveNumber, value: value))
        }
        .padding(.horizontal, DS.Spacing.xs)
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsCard(padding: nil)
    }

    // MARK: - القيم الحالية (كل مربّع يعرض قيمته — بنفس أسماء الاختيارات داخل مربّعه)
    private var appearanceLabel: String {
        switch appearanceMode {
        case "dark": return t("داكن", "Dark")
        case "light": return t("فاتح", "Light")
        default: return t("حسب الجهاز", "System")
        }
    }

    private var languageLabel: String {
        langManager.selectedLanguage == "ar" ? "العربية" : "English"
    }

    /// ملخّص الخصوصية: ما المخفي عن الأعضاء (الرقم، الميلاد) — يتحدّث مع المفتاح لأن الحفظ يحدّث الحساب
    private var privacyLabel: String {
        let phoneHidden = authVM.currentUser?.isPhoneHidden ?? false
        let birthHidden = authVM.currentUser?.isBirthDateHidden ?? false
        switch (phoneHidden, birthHidden) {
        case (true, true): return t("الرقم والميلاد مخفيان", "Phone & birth date hidden")
        case (true, false): return t("رقمك مخفي", "Phone hidden")
        case (false, true): return t("ميلادك مخفي", "Birth date hidden")
        case (false, false): return t("رقمك ظاهر", "Phone visible")
        }
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

    private var versionLabel: some View {
        Text(t("إصدار التطبيق \(AppVersion.string)", "App Version \(AppVersion.string)"))
            .dsFont(.footnote)
            .foregroundColor(DS.Color.textTertiary)
            .frame(maxWidth: .infinity)
    }
}

/// قيمة مربّع رقمية تصل بعد ظهور الصفحة (عدد الأجهزة): تتبدّل بلفّة أرقام بدل القفز.
/// بقية المربّعات كما هي تماماً. «تقليل الحركة»: تتبدّل مباشرة.
private struct SettingsLiveNumber: ViewModifier {
    let active: Bool
    let value: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active {
            content
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : DS.Anim.smooth, value: value)
        } else {
            content
        }
    }
}

// MARK: - Settings Sub-Views

// MARK: 1) Notifications & Privacy (combined)
struct NotificationsAndPrivacyView: View {
    /// لون القسم («حسابي») — كحلي «الإطار» يتبعه، وبلا قسم يبقى كحلي العلامة
    @Environment(\.dsSection) private var section
    private var chromeInk: Color { DS.Color.primary.dsChrome(in: section) }
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @ObservedObject var langManager = LanguageManager.shared
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true

    @State private var badgeEnabled: Bool = true
    @State private var isPhoneHidden: Bool = false
    @State private var isBirthDateHidden: Bool = false
    /// تغيير برمجي (التعبئة من الملف أو التراجع بعد فشل) — لا يُكتب للسيرفر.
    /// كان كل فتح يكتب، والتراجع يُطلق onChange من جديد (حلقة قد تُظهر رقماً مخفياً)
    @State private var skipPhoneHiddenWrite = false
    @State private var skipBirthHiddenWrite = false
    @State private var showUpdateError: Bool = false
    /// أنواع الإشعارات — محفوظة بالسيرفر ويقرأها مُطلِق الدفع (طلب المالك)
    @State private var prefs: [String: Bool] = [:]
    @State private var systemStatus: UNAuthorizationStatus = .notDetermined
    @State private var testState: TestState = .idle

    private enum TestState { case idle, sending, sent, failed }

    /// الجزء المعروض — «مربّعات بمجموعات» (اختيار المالك ٢٠٢٦-١٠-٠٧): مربّع «الإشعارات» ومربّع «الخصوصية»
    /// في الإعدادات يفتح كلٌّ منهما جزءه وحده من هذه الشاشة نفسها (`all` = الجزآن معاً)
    enum Focus { case all, notifications, privacy }
    let focus: Focus

    init(focus: Focus = .all) { self.focus = focus }

    private var showsNotifications: Bool { focus != .privacy }
    private var showsPrivacy: Bool { focus != .notifications }
    /// رقم قسم الخصوصية في تسلسل الدخول — أول قسم حين يُعرض وحده
    private var privacyIndex: Int { showsNotifications ? 3 : 0 }

    private var boxTitle: String {
        switch focus {
        case .all: return t("الإشعارات والخصوصية", "Notifications & Privacy")
        case .notifications: return t("الإشعارات", "Notifications")
        case .privacy: return t("الخصوصية", "Privacy")
        }
    }

    private var boxSubtitle: String {
        switch focus {
        case .all: return t("تحكّم بالتنبيهات ومن يشوف بياناتك", "Control alerts and who sees your data")
        case .notifications: return t("تحكّم بالتنبيهات التي تصلك", "Control the alerts you get")
        case .privacy: return t("من يشوف بياناتك ومن حظرته", "Who sees your data, and who you blocked")
        }
    }

    private var boxIcon: String { focus == .privacy ? "lock.fill" : "bell.badge.fill" }

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    /// نوع واحد من الإشعارات (مفتاحه في notification_prefs)
    private struct Kind: Identifiable {
        let key: String, icon: String, color: Color, title: String, subtitle: String
        var id: String { key }
    }

    private var kinds: [Kind] {
        var list: [Kind] = [
            Kind(key: "news", icon: "newspaper.fill", color: DS.Color.accent,
                 title: t("الأخبار الجديدة", "New posts"), subtitle: t("عند نشر خبر في العائلة", "When a family post is published")),
            Kind(key: "comments", icon: "bubble.left.fill", color: DS.Color.sea,
                 title: t("التعليقات", "Comments"), subtitle: t("عند تعليق أحد على خبرك", "When someone comments on your post")),
            Kind(key: "likes", icon: "heart.fill", color: DS.Color.sadu,
                 title: t("الإعجابات", "Likes"), subtitle: t("عند إعجاب أحد بخبرك", "When someone likes your post")),
            Kind(key: "requests", icon: "checkmark.seal.fill", color: DS.Color.success,
                 title: t("الرد على طلباتي", "Replies to my requests"), subtitle: t("قبول أو رفض طلباتك، تفعيل حسابك", "Approvals, rejections, activation")),
            Kind(key: "profile", icon: "person.crop.circle.badge.checkmark", color: DS.Color.palm,
                 title: t("تحديثات ملفي", "My profile updates"), subtitle: t("عند تعديل الإدارة لبياناتك", "When admins edit your profile"))
        ]
        if authVM.canModerate {
            list.append(Kind(key: "admin_activity", icon: "sparkles", color: DS.Color.primary,
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
            title: boxTitle,
            subtitle: boxSubtitle,
            icon: boxIcon,
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            cancelTitle: t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { dismiss() }
        ) {
            if showsNotifications {
                statusSection
                typesSection
                badgeSection
            }
            if showsPrivacy {
                privacySection
                // الأعضاء المحظورون — إلغاء الحظر من هنا (Guideline 1.2)
                BlockedMembersSection(index: privacyIndex + 1)
            }
        }
        .environment(\.layoutDirection, langManager.layoutDirection)
        .onAppear {
            badgeEnabled = authVM.currentUser?.badgeEnabled ?? true
            setPhoneHiddenSilently(authVM.currentUser?.isPhoneHidden ?? false)
            setBirthHiddenSilently(authVM.currentUser?.isBirthDateHidden ?? false)
        }
        .task {
            // أنواع الإشعارات وحالة الجهاز لجزء الإشعارات فقط
            guard showsNotifications else { return }
            prefs = await memberVM.fetchNotificationPrefs()
            await refreshSystemStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            guard showsNotifications else { return }
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
            if skipPhoneHiddenWrite { skipPhoneHiddenWrite = false; return }
            // بلا اتصال: يرجع المفتاح بلا كتابة (requireOnline يعرض تنبيه الاتصال)
            guard NetworkMonitor.shared.requireOnline() else {
                setPhoneHiddenSilently(!newValue)
                return
            }
            Task {
                let success = await memberVM.updatePhoneHidden(newValue)
                if !success {
                    // التراجع للقيمة المحفوظة لا يُعاد كتابته
                    if isPhoneHidden == newValue { setPhoneHiddenSilently(!newValue) }
                    showUpdateError = true
                }
            }
        }
        .onChange(of: isBirthDateHidden) { newValue in
            if skipBirthHiddenWrite { skipBirthHiddenWrite = false; return }
            guard NetworkMonitor.shared.requireOnline() else {
                setBirthHiddenSilently(!newValue)
                return
            }
            Task {
                let success = await memberVM.updateBirthDateHidden(newValue)
                if !success {
                    if isBirthDateHidden == newValue { setBirthHiddenSilently(!newValue) }
                    showUpdateError = true
                }
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
            .opacity(notificationsEnabled ? 1 : DSActionFill.disabledOpacity)
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

    /// يضبط المفتاح بلا كتابة للسيرفر — العلامة تُرفع فقط لو تغيّرت القيمة فعلاً (وإلا لا onChange يمسحها)
    private func setPhoneHiddenSilently(_ value: Bool) {
        guard isPhoneHidden != value else { return }
        skipPhoneHiddenWrite = true
        isPhoneHidden = value
    }

    private func setBirthHiddenSilently(_ value: Bool) {
        guard isBirthDateHidden != value else { return }
        skipBirthHiddenWrite = true
        isBirthDateHidden = value
    }

    private var privacySection: some View {
        DSComposerSection(title: t("الخصوصية", "Privacy"), icon: "lock.fill",
                          tint: DS.Color.accent, index: privacyIndex) {
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
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(on ? t("الإشعارات شغّالة", "Notifications are on")
                            : (systemBlocked ? t("موقوفة من إعدادات الجهاز", "Blocked in device settings")
                                             : t("الإشعارات موقوفة", "Notifications are off")))
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(on ? t("توصلك تنبيهات العائلة على هذا الجهاز", "Family alerts reach this device")
                            : t("ما توصلك تنبيهات على هذا الجهاز", "No alerts on this device"))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                }
                Spacer(minLength: DS.Spacing.sm)
                Toggle("", isOn: $notificationsEnabled)
                    .labelsHidden()
                    .tint(DS.Color.primary)
                    // القارئ الصوتي: المفتاح بلا نص ظاهر — اسمه صراحةً
                    .accessibilityLabel(t("الإشعارات", "Notifications"))
            }
            .dsRowBox()

            if systemBlocked {
                // الزرّ الواحد بلون معناه (تنبيه)
                DSButton(t("افتح إعدادات الجهاز", "Open device settings"), icon: "gearshape.fill",
                         tint: DS.Color.warning) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } else if notificationsEnabled {
                // «جرّب الإشعار» — يمر بنفس طريق الإرسال الحقيقي حتى جهازك (الزرّ الواحد، أحمر عند الفشل)
                DSButton(testLabel, icon: testIcon, role: testState == .failed ? .destructive : nil,
                         isLoading: testState == .sending) {
                    Task { await sendTest() }
                }
            }
          }
        }
    }

    private var testIcon: String {
        switch testState {
        case .sent: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .idle, .sending: return "paperplane.fill"
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
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(subtitle)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // يُقرأ اسماً ووصفاً للمفتاح نفسه (لا يُكرَّر)
            .accessibilityHidden(true)
            Spacer(minLength: DS.Spacing.sm)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(chromeInk)
                // القارئ الصوتي: المفتاح بلا نص ظاهر — اسمه ووصفه صراحةً
                .accessibilityLabel(title)
                .accessibilityHint(subtitle)
        }
        .dsRowBox()
    }

    private func sectionNote(_ text: String) -> some View {
        Text(text)
            .dsFont(.footnoteCompact)
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
    /// لون القسم («حسابي») — كحلي «الإطار» يتبعه، وبلا قسم يبقى كحلي العلامة
    @Environment(\.dsSection) private var section
    private var chromeInk: Color { DS.Color.primary.dsChrome(in: section) }
    @ObservedObject var langManager = LanguageManager.shared
    /// للرجوع للغة التطبيق الرسمية
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @Environment(\.dismiss) private var dismiss
    /// «تقليل الحركة» (توصية أبل): علامة الاختيار تظهر بتلاشٍ فقط بلا تكبير
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// الجزء المعروض — «مربّعات بمجموعات» (اختيار المالك ٢٠٢٦-١٠-٠٧): مربّع «المظهر» ومربّع «اللغة»
    /// في الإعدادات يفتح كلٌّ منهما قسمه وحده من هذا المربّع نفسه (`all` = القسمان معاً)
    enum Focus { case all, appearance, language }
    let focus: Focus

    init(focus: Focus = .all) { self.focus = focus }

    private var showsAppearance: Bool { focus != .language }
    private var showsLanguage: Bool { focus != .appearance }

    private var boxTitle: String {
        switch focus {
        case .all: return t("المظهر واللغة", "Appearance & Language")
        case .appearance: return t("المظهر", "Appearance")
        case .language: return t("اللغة", "Language")
        }
    }

    private var boxSubtitle: String {
        switch focus {
        case .all: return t("شكل التطبيق ولغته", "How the app looks and reads")
        case .appearance: return t("فاتح أو داكن أو حسب جهازك", "Light, dark or like your device")
        case .language: return t("لغة التطبيق على جهازك", "The app's language on your device")
        }
    }

    private var boxIcon: String {
        switch focus {
        case .language: return "character.bubble.fill"
        case .all: return "paintbrush.fill"
        // مربّع «المظهر» وحده: المجسّم يتبع الاختيار — شمس / هلال / نصف دائرة
        case .appearance:
            switch appearanceMode {
            case "light": return "sun.max.fill"
            case "dark": return "moon.stars.fill"
            default: return "circle.lefthalf.filled"
            }
        }
    }

    /// لون المربّع — مربّع «المظهر» يتلوّن بالاختيار (طلب المالك ٢٠٢٦-١٠-١٠): أزرق الصباح للفاتح،
    /// نيلي الليل للداكن، بنفسجي الغسق لـ«حسب الجهاز»
    private var boxTint: Color {
        focus == .appearance ? AppearanceSkyScene.tint(for: appearanceMode) : DS.Color.composerLibrary
    }

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    private var appearanceOptions: [DSOptionTile<String>] {
        // كل خيار بلون مشهده (نفس لون المربّع حين يُختار)
        [DSOptionTile("system", title: t("حسب الجهاز", "System"), icon: "iphone",
                      tint: AppearanceSkyScene.tint(for: "system")),
         DSOptionTile("light", title: t("فاتح", "Light"), icon: "sun.max.fill",
                      tint: AppearanceSkyScene.tint(for: "light")),
         DSOptionTile("dark", title: t("داكن", "Dark"), icon: "moon.stars.fill",
                      tint: AppearanceSkyScene.tint(for: "dark"))]
    }

    private var languageOptions: [DSOptionTile<String>] {
        [DSOptionTile("ar", title: "العربية", icon: "character.book.closed.fill"),
         DSOptionTile("en", title: "English", icon: "textformat.abc")]
    }

    /// اختيار المستخدم يثبّت لغته — ولا تغيّرها اللغة الرسمية بعدها
    /// (اختيار اللغة الحالية لا يغيّر شيئاً — المربّعات لا تعيد اختيار المختار)
    private var languageSelection: Binding<String> {
        Binding(get: { langManager.selectedLanguage },
                set: { langManager.chooseLanguage($0) })
    }

    var body: some View {
        DSComposer(
            title: boxTitle,
            subtitle: boxSubtitle,
            icon: boxIcon,
            tint: boxTint,
            actionTitle: "",
            showsAction: false,
            cancelTitle: t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { dismiss() }
        ) {
            if showsAppearance {
                DSComposerSection(title: t("المظهر", "Appearance"), icon: "circle.lefthalf.filled",
                                  tint: boxTint, index: 0) {
                    VStack(spacing: DS.Spacing.sm) {
                        // مشهد صباح / ليل متحرّك يتبع الاختيار (طلب المالك ٢٠٢٦-١٠-١٠)
                        AppearanceSkyScene(mode: appearanceMode)
                        // مربّعات الاختيار الواحد المشتركة
                        DSOptionTiles(appearanceOptions, selection: $appearanceMode, columns: 3)
                            // التغيير لحظي على كل النوافذ — لا ينتظر إغلاق المربّع (طلب المالك ٢٠٢٦-١٠-٠٧)
                            .onChange(of: appearanceMode) { mode in AppAppearance.apply(mode) }
                        note(appearanceDescription)
                    }
                }
            }

            if showsLanguage {
                DSComposerSection(title: t("اللغة", "Language"), icon: "character.bubble.fill",
                                  tint: DS.Color.primary, index: showsAppearance ? 1 : 0) {
                    VStack(spacing: DS.Spacing.sm) {
                        DSOptionTiles(languageOptions, selection: languageSelection, columns: 2)
                        note(langManager.languageChosenByUser
                             ? t("اخترت لغتك بنفسك — لا تتأثر بلغة التطبيق الرسمية.",
                                 "You chose your language — the app's official language won't change it.")
                             : t("تتبع لغة التطبيق الرسمية التي تحددها الإدارة.",
                                 "Following the app's official language set by the admins."))

                        if langManager.languageChosenByUser {
                            // إجراء ثانوي — الزرّ الواحد الرمادي
                            DSButton(t("الرجوع للغة التطبيق الرسمية", "Use the app's official language"),
                                     icon: "arrow.uturn.backward", role: .cancel) {
                                langManager.followOfficialLanguage(appSettingsVM.settings.defaultLanguage)
                            }
                        }
                    }
                }
            }
        }
        .environment(\.layoutDirection, langManager.layoutDirection)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .dsFont(.footnote)
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

// MARK: - مشهد «المظهر» المتحرّك
/// سماء أعلى مربّع «المظهر» (طلب المالك ٢٠٢٦-١٠-١٠ «حط شكل الصباح أو الليل مع أنميشن»):
/// فاتح = صباح (شمس تدور أشعتها وغيوم تسير)، داكن = ليل (هلال يتمايل ونجوم تلمع وشبّاك البيت يضيء)،
/// «حسب الجهاز» = دورة نهار ↔ ليل متواصلة. التبديل بين الأوضاع غروب/شروق ناعم.
/// «تقليل الحركة» (توصية أبل): المشهد ثابت على حالته.
struct AppearanceSkyScene: View {
    let mode: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ftAnimationsPaused) private var animationsPaused

    /// الوضع المرسوم الآن، ومستوى الليل لحظة آخر تبديل — منه ينتقل المشهد للهدف الجديد
    @State private var shownMode: String?
    @State private var fromLevel: Double = 0
    @State private var changedAt = Date.distantPast

    private static let transition: TimeInterval = 1.4
    /// دورة «حسب الجهاز»: نهار ← ليل ← نهار
    private static let cyclePeriod: TimeInterval = 9

    /// لون كل وضع — للمربّع وخياره
    static func tint(for mode: String) -> Color {
        switch mode {
        case "light": return Color(red: 0.17, green: 0.48, blue: 0.75)   // أزرق الصباح
        case "dark": return Color(red: 0.29, green: 0.31, blue: 0.66)    // نيلي الليل
        default: return Color(red: 0.48, green: 0.31, blue: 0.63)        // بنفسجي الغسق
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion || animationsPaused)) { timeline in
            let now = timeline.date
            Canvas { ctx, size in
                draw(&ctx, size: size, night: level(at: now), time: now.timeIntervalSinceReferenceDate)
            }
        }
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .accessibilityHidden(true)
        .onAppear {
            guard shownMode == nil else { return }
            shownMode = mode
            fromLevel = target(mode, at: Date().timeIntervalSinceReferenceDate)
        }
        .onChange(of: mode) { newMode in
            // يبدأ الانتقال من حيث المشهد الآن (ولو في منتصف دورة أو انتقال سابق)
            let now = Date()
            fromLevel = level(at: now)
            shownMode = newMode
            changedAt = now
        }
    }

    // MARK: مستوى الليل (٠ نهار … ١ ليل)

    private func target(_ m: String?, at t: TimeInterval) -> Double {
        switch m {
        case "light": return 0
        case "dark": return 1
        default:
            if reduceMotion { return 0.5 }   // غسق ثابت
            return (1 - cos(t / Self.cyclePeriod * 2 * .pi)) / 2
        }
    }

    private func level(at date: Date) -> Double {
        let goal = target(shownMode ?? mode, at: date.timeIntervalSinceReferenceDate)
        let k = min(1, max(0, date.timeIntervalSince(changedAt) / Self.transition))
        let eased = k * k * (3 - 2 * k)
        return fromLevel + (goal - fromLevel) * eased
    }

    // MARK: الرسم

    private struct RGB {
        var r, g, b: Double
        func mix(_ o: RGB, _ k: Double) -> RGB { RGB(r: r + (o.r - r) * k, g: g + (o.g - g) * k, b: b + (o.b - b) * k) }
        var color: Color { Color(red: r, green: g, blue: b) }
    }

    private static let dayTop = RGB(r: 0.43, g: 0.73, b: 0.96), dayBottom = RGB(r: 1.00, g: 0.87, b: 0.64)
    private static let nightTop = RGB(r: 0.04, g: 0.07, b: 0.22), nightBottom = RGB(r: 0.21, g: 0.18, b: 0.45)
    private static let farHillDay = RGB(r: 0.55, g: 0.76, b: 0.52), farHillNight = RGB(r: 0.14, g: 0.15, b: 0.34)
    private static let nearHillDay = RGB(r: 0.36, g: 0.64, b: 0.40), nearHillNight = RGB(r: 0.08, g: 0.09, b: 0.22)
    private static let sunCore = RGB(r: 1.00, g: 0.93, b: 0.55), sunEdge = RGB(r: 1.00, g: 0.70, b: 0.20)
    private static let moonColor = RGB(r: 0.99, g: 0.95, b: 0.80)

    /// النجوم: موضع نسبي ونصف قطر
    private static let stars: [(x: Double, y: Double, r: Double)] = [
        (0.06, 0.14, 1.2), (0.14, 0.38, 0.9), (0.21, 0.10, 1.5), (0.33, 0.27, 1.0), (0.41, 0.08, 1.1),
        (0.47, 0.42, 0.8), (0.56, 0.18, 1.4), (0.63, 0.34, 0.9), (0.69, 0.07, 1.0), (0.80, 0.24, 1.3),
        (0.87, 0.45, 0.8), (0.93, 0.12, 1.1), (0.26, 0.52, 0.8), (0.75, 0.50, 0.9)
    ]
    /// الغيوم: موضع البداية النسبي، الارتفاع، الحجم، والسرعة (نقطة/ثانية)
    private static let clouds: [(x: Double, y: Double, scale: Double, speed: Double)] = [
        (0.05, 0.30, 1.0, 7), (0.50, 0.17, 0.72, 4.5), (0.82, 0.44, 0.6, 10)
    ]

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, night n: Double, time t: TimeInterval) {
        let w = size.width, h = size.height
        // ١) السماء
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [Self.dayTop.mix(Self.nightTop, n).color, Self.dayBottom.mix(Self.nightBottom, n).color]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

        // ٢) النجوم — تظهر مع الليل، وكلٌّ يلمع بإيقاعه
        for (i, s) in Self.stars.enumerated() {
            let twinkle = 0.5 + 0.5 * sin(t * (1.2 + Double(i % 4) * 0.45) + Double(i) * 1.7)
            let a = n * (0.35 + 0.65 * twinkle)
            guard a > 0.02 else { continue }
            let r = s.r * (0.85 + 0.3 * twinkle)
            ctx.fill(Path(ellipseIn: CGRect(x: s.x * w - r, y: s.y * h - r, width: r * 2, height: r * 2)),
                     with: .color(.white.opacity(a)))
        }

        // ٣) الشمس تغيب نزولاً مع الليل، و٤) الهلال يشرق صعوداً
        if n < 0.99 {
            drawSun(&ctx, at: CGPoint(x: w * 0.74, y: h * (0.34 + 0.95 * n)), radius: 16, spin: t * 0.4)
        }
        if n > 0.01 {
            drawMoon(&ctx, at: CGPoint(x: w * 0.27, y: h * (1.3 - 0.96 * n) + sin(t * 0.8) * 2), radius: 14, glow: n)
        }

        // ٥) الغيوم تسير، وتخفت ليلاً
        let cloudAlpha = 0.92 - 0.72 * n
        let span = w + 120
        for c in Self.clouds {
            let x = (c.x * span + t * c.speed).truncatingRemainder(dividingBy: span) - 60
            drawCloud(&ctx, at: CGPoint(x: x, y: c.y * h), scale: c.scale, alpha: cloudAlpha)
        }

        // ٦) التلال والبيت — شبّاكه يضيء ليلاً
        var far = Path()
        far.move(to: CGPoint(x: 0, y: h * 0.78))
        far.addQuadCurve(to: CGPoint(x: w * 0.52, y: h * 0.76), control: CGPoint(x: w * 0.24, y: h * 0.56))
        far.addQuadCurve(to: CGPoint(x: w, y: h * 0.70), control: CGPoint(x: w * 0.80, y: h * 0.94))
        far.addLine(to: CGPoint(x: w, y: h)); far.addLine(to: CGPoint(x: 0, y: h)); far.closeSubpath()
        ctx.fill(far, with: .color(Self.farHillDay.mix(Self.farHillNight, n).color))

        let houseX = w * 0.60, ground = h * 0.86
        drawHouse(&ctx, x: houseX, ground: ground, night: n)

        var near = Path()
        near.move(to: CGPoint(x: 0, y: h * 0.90))
        near.addQuadCurve(to: CGPoint(x: w, y: h * 0.88), control: CGPoint(x: w * 0.5, y: h * 0.74))
        near.addLine(to: CGPoint(x: w, y: h)); near.addLine(to: CGPoint(x: 0, y: h)); near.closeSubpath()
        ctx.fill(near, with: .color(Self.nearHillDay.mix(Self.nearHillNight, n).color))
    }

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    private func drawSun(_ ctx: inout GraphicsContext, at c: CGPoint, radius r: CGFloat, spin: Double) {
        ctx.fill(circle(c, r * 2.3), with: .color(Self.sunCore.color.opacity(0.14)))
        ctx.fill(circle(c, r * 1.6), with: .color(Self.sunCore.color.opacity(0.22)))
        var rays = ctx
        rays.translateBy(x: c.x, y: c.y)
        rays.rotate(by: .radians(spin))
        var p = Path()
        for i in 0..<10 {
            let a = Double(i) / 10 * 2 * .pi
            p.move(to: CGPoint(x: cos(a) * r * 1.3, y: sin(a) * r * 1.3))
            p.addLine(to: CGPoint(x: cos(a) * r * 1.72, y: sin(a) * r * 1.72))
        }
        rays.stroke(p, with: .color(Self.sunEdge.color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        ctx.fill(circle(c, r), with: .radialGradient(
            Gradient(colors: [Self.sunCore.color, Self.sunEdge.color]),
            center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3), startRadius: 0, endRadius: r * 1.3))
    }

    private func drawMoon(_ ctx: inout GraphicsContext, at c: CGPoint, radius r: CGFloat, glow: Double) {
        ctx.fill(circle(c, r * 2.2), with: .color(.white.opacity(0.07 * glow)))
        ctx.drawLayer { layer in
            layer.fill(circle(c, r), with: .color(Self.moonColor.color))
            layer.blendMode = .destinationOut
            layer.fill(circle(CGPoint(x: c.x + r * 0.55, y: c.y - r * 0.32), r * 0.9), with: .color(.black))
        }
    }

    private func drawCloud(_ ctx: inout GraphicsContext, at p: CGPoint, scale s: Double, alpha: Double) {
        var cloud = Path()
        cloud.addEllipse(in: CGRect(x: p.x - 22 * s, y: p.y - 5 * s, width: 46 * s, height: 15 * s))
        cloud.addEllipse(in: CGRect(x: p.x - 13 * s, y: p.y - 13 * s, width: 20 * s, height: 19 * s))
        cloud.addEllipse(in: CGRect(x: p.x - 1 * s, y: p.y - 10 * s, width: 18 * s, height: 15 * s))
        ctx.fill(cloud, with: .color(.white.opacity(alpha)))
    }

    private func drawHouse(_ ctx: inout GraphicsContext, x: CGFloat, ground: CGFloat, night n: Double) {
        let wall = CGRect(x: x - 11, y: ground - 15, width: 22, height: 15)
        let wallColor = RGB(r: 0.98, g: 0.94, b: 0.86).mix(RGB(r: 0.18, g: 0.19, b: 0.36), n)
        let roofColor = RGB(r: 0.80, g: 0.36, b: 0.27).mix(RGB(r: 0.12, g: 0.12, b: 0.26), n)
        ctx.fill(Path(wall), with: .color(wallColor.color))
        var roof = Path()
        roof.move(to: CGPoint(x: x - 14, y: ground - 14))
        roof.addLine(to: CGPoint(x: x, y: ground - 26))
        roof.addLine(to: CGPoint(x: x + 14, y: ground - 14))
        roof.closeSubpath()
        ctx.fill(roof, with: .color(roofColor.color))
        // الشبّاك: داكن نهاراً، دافئ مضيء ليلاً بهالة خفيفة
        let window = CGRect(x: x - 4, y: ground - 11, width: 8, height: 7)
        let lit = RGB(r: 1.0, g: 0.82, b: 0.38)
        ctx.fill(Path(window), with: .color(RGB(r: 0.55, g: 0.70, b: 0.85).mix(lit, n).color))
        if n > 0.05 {
            ctx.fill(circle(CGPoint(x: window.midX, y: window.midY), 9), with: .color(lit.color.opacity(0.18 * n)))
        }
    }
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
    /// لون القسم الحالي (داخل الملف الشخصي) — بدل الكحلي الثابت
    @Environment(\.dsSection) private var section
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
                        color: DS.Color.palm,
                        title: t("شجرة العائلة", "Family Tree"),
                        desc: t("استعرض أفراد عائلتك وأنسابهم بشكل تفاعلي", "Browse your family members and lineage interactively")
                    )
                    aboutItem(
                        icon: "newspaper.fill",
                        color: DS.Color.accent,
                        title: t("أخبار العائلة", "Family News"),
                        desc: t("شارك الأخبار وتفاعل بالتعليقات والإعجابات", "Share news and interact with comments & likes")
                    )
                    aboutItem(
                        icon: "bell.badge.fill",
                        color: DS.Color.sea,
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
                Text(t("صُنع بحب لعائلة المحمدعلي", "Made with love for the Al-Mohammad Ali family"))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                Text("© 2026 FamilyTree")
                    .dsFont(.footnoteCompact)
                    .foregroundColor(DS.Color.textTertiary)
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
            // المجسّم بدل الدائرة المتدرّجة والرمز المسطّح
            DSStateIcon("tree.fill", tint: DS.Color.primary, size: DSBox.logoSide)
                .accessibilityHidden(true)   // أيقونة زخرفية — الاسم تحتها
            Text(t("عائلة المحمدعلي", "Al-Mohammad Ali family"))
                .dsFont(.title)
                .foregroundColor(DS.Color.textPrimary)
            DSStatusChip(text: t("الإصدار \(appVersion)", "Version \(appVersion)"), tint: DS.Color.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.sm)
    }

    /// صف ميزة — نفس صفوف المربّعات
    private func aboutItem(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: color)
                .accessibilityHidden(true)   // زخرفة
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(desc)
                    .dsFieldFont(.subtitle)
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
    /// لون القسم («حسابي») — كحلي «الإطار» يتبعه، وبلا قسم يبقى كحلي العلامة
    @Environment(\.dsSection) private var section
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
                    t("يُتحقَّق من هويتك برمز تحقّق يُرسل إلى هاتفك.", "Your identity is verified with a verification code sent to your phone.")
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
                    t("عند الحذف تُحذف من خوادمنا بياناتك الشخصية وصورك وما نشرته من أخبار وتعليقات ومحتوى، ويبقى اسمك وموضعك في شجرة العائلة حفاظاً على تسلسل النسب.",
                      "Deletion removes your personal details, photos and the news, comments and content you posted from our servers; your name and place in the family tree stay to keep the lineage intact."),
                    t("لا يمكن استرجاع البيانات بعد الحذف النهائي.", "Data cannot be recovered after permanent deletion.")
                   ]),
            Policy(icon: "bell.badge.fill", color: DS.Color.warning,
                   title: t("الإشعارات", "Notifications"),
                   points: [
                    t("نرسل إشعارات عن التعليقات والإعجابات والتحديثات.", "We send alerts for comments, likes, and updates."),
                    t("يمكنك التحكم في أنواع الإشعارات من إعدادات الخصوصية.", "You can control notification types from Privacy settings."),
                    t("يمكنك تعطيل الإشعارات بالكامل من الإعدادات.", "You can fully disable notifications from Settings.")
                   ]),
            Policy(icon: "doc.text.fill", color: DS.Color.neonPurple,
                   title: t("شروط الاستخدام", "Terms of Use"),
                   points: [
                    t("التطبيق مخصص حصراً لأفراد عائلة المحمدعلي ومن توافق عليهم إدارة العائلة، ويُعدّ استخدامه موافقةً على هذه الشروط.",
                      "The app is exclusively for Al-Mohammad Ali family members and those approved by the family administration; using it constitutes acceptance of these terms."),
                    t("لا تهاون مطلقاً مع المحتوى المسيء أو المستخدمين المسيئين؛ إذ يُحظر نشر أي محتوى مسيء أو مهين أو خادش للحياء أو يحض على الكراهية، كما يُحظر التحرّش بأي عضو أو انتحال شخصيته.",
                      "Zero tolerance for objectionable content or abusive users: posting offensive, insulting, indecent or hateful content is prohibited, as is harassing any member or impersonating anyone."),
                    t("يحق لكل عضو الإبلاغ عن أي خبر أو تعليق أو محتوى أو عضو عبر زر «إبلاغ»، وحظر أي عضو فلا يظهر له محتواه.",
                      "Every member may report any post, comment, content or member with the “Report” button, and block any member so their content no longer appears."),
                    t("تراجع الإدارة كل بلاغ خلال ٢٤ ساعة، وتحذف المحتوى المخالف، وتوقف حساب ناشره.",
                      "The administration reviews every report within 24 hours, removes the violating content and suspends the account that posted it."),
                    t("يلتزم العضو باستخدام التطبيق بمسؤولية، واحترام خصوصية الآخرين، وعدم تداول بياناتهم خارج التطبيق.", "Members must use the app responsibly, respect others' privacy and not share their data outside the app."),
                    t("يحق للإدارة تجميد الحسابات المخالفة أو حذفها.", "The administration may freeze or delete accounts that violate these terms.")
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
                "نلتزم بحماية خصوصيتك وبياناتك. فيما يلي سياسة الخصوصية وشروط الاستخدام.",
                "We are committed to protecting your privacy and data. Below are our Privacy Policy and Terms of Use."
            ))
            .dsFont(.callout)
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
                                    .fill(policy.color.dsChrome(in: section).dsReadableGlyph)
                                    .frame(width: DS.Spacing.xsm, height: DS.Spacing.xsm)
                                    .padding(.top, DS.Spacing.xsm)
                                Text(point)
                                    .dsFieldFont(.callout)
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
                        .dsFieldFont(.callout)
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
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(t("الحد الأقصى", "Limit"))
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(t(
                    "\(notificationVM.linkedDevices.count) من \(maxDevices) أجهزة",
                    "\(notificationVM.linkedDevices.count) of \(maxDevices) devices"
                ))
                    .dsFieldFont(.headlineCompact)
                    .foregroundColor(DS.Color.fieldValue)
            }
            Spacer(minLength: 0)
        }
        .dsRowBox()
    }

    /// الحالة الفاضية الواحدة (مضغوطة داخل القسم)
    private var emptyRow: some View {
        DSEmptyView(t("لا توجد أجهزة مرتبطة", "No linked devices"), icon: "iphone.slash", style: .inline)
    }

    /// صف جهاز: أيقونة الحقل + اسم الجهاز (+ «الحالي») + آخر ظهور
    private func deviceRow(_ device: NotificationViewModel.LinkedDevice) -> some View {
        let isCurrent = device.isCurrent(currentDeviceId: notificationVM.currentDeviceId)
        return HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "iphone.gen3", tint: isCurrent ? DS.Color.success : DS.Color.accent)
                .accessibilityHidden(true)   // زخرفة

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xsm) {
                    Text(device.displayName)
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if isCurrent {
                        DSStatusChip(text: t("الحالي", "Current"), tint: DS.Color.success, size: .mini)
                            .fixedSize()
                    }
                }

                Text(formattedDate(device.updatedAt))
                    .dsFieldFont(.subtitle)
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
