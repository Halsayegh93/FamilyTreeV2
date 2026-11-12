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
    /// «أيقونة التطبيق» (طلب المالك ٢٠٢٦-١٠-٣١)
    @State private var showAppIcon = false
    @State private var showAbout = false
    @State private var showTerms = false
    @State private var showPrivacyDoc = false
    @State private var showDeleteConfirmation = false
    @State private var showCancelDeletion = false
    /// حذف الحساب جارٍ — طبقة انتظار حتى يكتمل ويُسجَّل الخروج
    @State private var isDeletingAccount = false

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    var body: some View {
        // «مربّعات بمجموعات» (اختيار المالك ٢٠٢٦-١٠-٠٧): بطاقة الهوية أعلى، ثم ثلاث مجموعات قصيرة
        // (التفضيلات · الحساب · المساعدة) كل مربّع فيها يعرض قيمته الحالية ويفتح جزءه وحده،
        // وحذف الحساب زر في الأسفل.
        // قوائم مجمّعة (العيّنة «هـ» بلا البحث، اختيار المالك ٢٠٢٦-١١-١١): صفّ الملف، ثم «التفضيلات» و«الحساب»
        // و«عن التطبيق» — كل صفّ بمربّع رمز ممتلئ وعنوان وقيمته الحالية وسهم، ثم «حذف الحساب» صفّاً أحمر وحده
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                profileRow
                    .dsStaggerIn(0)
                settingsGroup(t("التفضيلات", "Preferences"), preferenceTiles)
                    .dsStaggerIn(1)
                settingsGroup(t("الحساب", "Account"), accountTiles)
                    .dsStaggerIn(2)
                settingsGroup(t("عن التطبيق", "About"), helpTiles)
                    .dsStaggerIn(3)

                // حذف الحساب — آخر الصفحة وحده (طلب المالك ٢٠٢٦-١٠-١٠ «نفرّق بالشكل والحجم والمكان»)،
                // طلبٌ تنفّذه الإدارة خلال سبعة أيام (سياسة الخصوصية ٢٠٢٦-١٠-٢٨)
                VStack(spacing: DS.Spacing.xs) {
                    if let pending = authVM.pendingDeletionRequest {
                        Text(t("طلب حذف حسابك قيد المعالجة منذ \(pending.dateText)",
                               "Your account deletion request is being processed since \(pending.dateText)"))
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        deleteRow(t("إلغاء طلب الحذف", "Cancel deletion request")) { showCancelDeletion = true }
                    } else {
                        deleteRow(t("حذف الحساب", "Delete Account")) { showDeleteConfirmation = true }
                    }
                    Text(t("يُنفَّذ الحذف خلال سبعة أيام من طلبك.", "Deletion is carried out within seven days of your request."))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    versionLabel
                        .padding(.top, DS.Spacing.xs)
                }
                .padding(.top, DS.Spacing.xs)
                .dsStaggerIn(4)
            }
            .dsPageMargin()
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xxxl)
            .dsLandscapeReadable()
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
            LinkedDevicesSettingsSheet().environmentObject(appSettingsVM).environmentObject(authVM)
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
        .dsCenterBox(isPresented: $showAppIcon, onBackgroundTap: { showAppIcon = false }) { AppIconSettingsView() }
        .dsCenterBox(isPresented: $showAbout, onBackgroundTap: { showAbout = false }) { AboutView() }
        // قراءة طويلة — مربّع طويل (توصية أبل)؛ وثيقتان منفصلتان (طلب المالك ٢٠٢٦-١٠-٢٨)
        .dsTallBox(isPresented: $showPrivacyDoc) { PrivacyPolicyView(only: "privacy") }
        .dsTallBox(isPresented: $showTerms) { PrivacyPolicyView(only: "terms") }
        .dsAlert(t("حذف الحساب", "Delete Account"), isPresented: $showDeleteConfirmation) {
            Button(t("إلغاء", "Cancel"), role: .cancel) {}
            Button(t("إرسال طلب الحذف", "Send deletion request"), role: .destructive) {
                Task {
                    isDeletingAccount = true
                    await authVM.requestAccountDeletion()
                    isDeletingAccount = false
                }
            }
        } message: {
            Text(t(
                "سيُرسل طلب حذف حسابك إلى إدارة التطبيق، ويُنفَّذ خلال سبعة أيام كحد أقصى. يُحذف رقمك وبريدك وصورتك ومنشوراتك وتعليقاتك، ويبقى اسمك وموقعك في شجرة العائلة.",
                "Your deletion request will be sent to the app administration and carried out within seven days at most. Your number, email, photo, posts and comments are deleted; your name and place in the family tree remain."
            ))
        }
        .dsAlert(t("إلغاء طلب الحذف؟", "Cancel the deletion request?"), isPresented: $showCancelDeletion) {
            Button(t("رجوع", "Back"), role: .cancel) {}
            Button(t("إلغاء طلب الحذف", "Cancel deletion request")) {
                Task {
                    isDeletingAccount = true
                    await authVM.cancelAccountDeletionRequest()
                    isDeletingAccount = false
                }
            }
        } message: {
            Text(t("يبقى حسابك كما هو ولن يُحذف.", "Your account stays as it is and won't be deleted."))
        }
        .overlay {
            if isDeletingAccount {
                // طبقة انتظار: نفس مجسّم التحميل الواحد يتنفّس + النص، فوق غطاء خافت
                ZStack {
                    DS.Color.hierarchicalSecondary.ignoresSafeArea()
                    DSPageLoader(t("جارٍ الإرسال…", "Sending…"), fillsSpace: false)
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
        .task { await authVM.loadAccountDeletionRequest() }
    }

    /// صفّ الملف أعلى الإعدادات (العيّنة «هـ»): الصورة الدائرية، الاسم، و«تعديل الملف الشخصي» — الصفّ كله يفتح التعديل
    private var profileRow: some View {
        let user = authVM.currentUser
        return Button { showEditProfile = true } label: {
            HStack(spacing: DS.Spacing.md) {
                Group {
                    if let avatar = user?.avatarUrl, let url = URL(string: avatar) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: { chromeInk.opacity(DS.Opacity.tintFill) }
                    } else {
                        ZStack {
                            chromeInk.opacity(DS.Opacity.tintFill)
                            Image(systemName: "person.fill")
                                .dsGlyph(DS.Glyph.xl)
                                .foregroundColor(chromeInk)
                        }
                    }
                }
                .frame(width: DS.Icon.avatar + DS.Spacing.md, height: DS.Icon.avatar + DS.Spacing.md)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(DS.Color.accentLight, lineWidth: DS.Border.width))
                .accessibilityHidden(true)   // الصورة زخرفة — الاسم مكتوب بجانبها

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(user?.displayName ?? "")
                        .dsFont(.headline)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(t("تعديل الملف الشخصي", "Edit profile"))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                }
                Spacer(minLength: DS.Spacing.sm)
                SettingsChevron()
            }
            .padding(DS.Spacing.md)
            .contentShape(Rectangle())
            .dsGroupedRow(.single, dividerInset: 0)
        }
        .buttonStyle(DSNoticePressStyle())
    }

    // MARK: - المجموعات: عنوان صغير + بطاقة صفوف

    /// صفّ إعداد واحد في مجموعة
    private struct SettingsTile: Identifiable {
        let id: String
        let icon: String
        /// لون تعبئة مربّع الرمز (`DS.Color.*Fill`)
        let fill: Color
        let title: String
        let value: String
        /// قيمة رقمية تصل بعد الظهور (عدد الأجهزة) — تتبدّل بلفّة أرقام
        var liveNumber = false
        let action: () -> Void
    }

    /// مجموعة: عنوانها الصغير ثم صفوفها في بطاقة واحدة (كل صفّ جزء منها بخطّ فاصل رفيع)
    private func settingsGroup(_ title: String, _ tiles: [SettingsTile]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title)
                .dsFont(.sectionTitle)
                .foregroundColor(DS.Color.textTertiary)
                .padding(.horizontal, DS.Spacing.sm)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                    Button(action: tile.action) {
                        SettingsGroupRow(icon: tile.icon, fill: tile.fill, title: tile.title) {
                            Text(tile.value)
                                .dsFont(.footnote)
                                .foregroundColor(DS.Color.textTertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .modifier(SettingsLiveNumber(active: tile.liveNumber, value: tile.value))
                            SettingsChevron()
                        }
                        .dsGroupedRow(DSGroupPosition(index: index, count: tiles.count),
                                      dividerInset: SettingsGroupRow<EmptyView>.dividerInset)
                    }
                    .buttonStyle(DSNoticePressStyle())
                }
            }
        }
    }

    /// صفّ «حذف الحساب» / «إلغاء طلب الحذف» — أحمر وحده في آخر الصفحة
    private func deleteRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .dsFont(.rowTitle)
                .foregroundColor(DS.Color.error)
                .frame(maxWidth: .infinity, minHeight: DSBox.commandRowHeight)
                .contentShape(Rectangle())
                .dsGroupedRow(.single, dividerInset: 0)
        }
        .buttonStyle(DSNoticePressStyle())
    }

    /// «التفضيلات»: الإشعارات · الخصوصية · المظهر · اللغة — كلٌّ يفتح جزءه من مربّعه
    private var preferenceTiles: [SettingsTile] {
        [SettingsTile(id: "notifications", icon: "bell.badge.fill", fill: DS.Color.goldFill,
                      title: t("الإشعارات", "Notifications"),
                      value: notificationsEnabled ? t("مفعّلة", "On") : t("موقوفة", "Off")) { showNotifications = true },
         SettingsTile(id: "privacy", icon: "lock.fill", fill: DS.Color.palmFill,
                      title: t("الخصوصية", "Privacy"), value: privacyLabel) { showPrivacy = true },
         SettingsTile(id: "appearance", icon: "circle.lefthalf.filled", fill: DS.Color.navyFill,
                      title: t("المظهر", "Appearance"), value: appearanceLabel) { showAppearance = true },
         SettingsTile(id: "language", icon: "character.bubble.fill", fill: DS.Color.seaFill,
                      title: t("اللغة", "Language"), value: languageLabel) { showLanguage = true }]
    }

    /// «الحساب»: الأجهزة المرتبطة · أيقونة التطبيق («تعديل الملف» من صفّ الملف أعلى الصفحة)
    private var accountTiles: [SettingsTile] {
        [SettingsTile(id: "devices", icon: "iphone.gen3", fill: DS.Color.seaFill,
                      title: t("الأجهزة المرتبطة", "Linked Devices"),
                      value: t("\(notificationVM.linkedDevices.count) جهاز", "\(notificationVM.linkedDevices.count) devices"),
                      // العدد يصل بعد الجلب — يتبدّل بلفّة أرقام بدل القفز
                      liveNumber: true) { showLinkedDevices = true },
         SettingsTile(id: "appIcon", icon: "apps.iphone", fill: DS.Color.saduFill,
                      title: t("أيقونة التطبيق", "App Icon"),
                      value: AppIconChoice.current.title) { showAppIcon = true }]
    }

    /// «عن التطبيق»: سياسة الخصوصية · قواعد الاستخدام · عن التطبيق
    private var helpTiles: [SettingsTile] {
        [SettingsTile(id: "privacyDoc", icon: "hand.raised.fill", fill: DS.Color.slateFill,
                      title: t("سياسة الخصوصية", "Privacy Policy"), value: "") { showPrivacyDoc = true },
         SettingsTile(id: "terms", icon: "doc.text.fill", fill: DS.Color.slateFill,
                      title: t("قواعد الاستخدام", "Terms of Use"), value: "") { showTerms = true },
         SettingsTile(id: "about", icon: "info.circle.fill", fill: DS.Color.slateFill,
                      title: t("عن التطبيق", "About"), value: AppVersion.string) { showAbout = true }]
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

    /// ملخّص الخصوصية: المفاتيح الأربعة نفسها (الرقم · الصورة · الميلاد · آخر ظهور) — يتحدّث مع المفتاح لأن الحفظ يحدّث الحساب
    private var privacyLabel: String {
        let u = authVM.currentUser
        let hidden: [String] = [
            (u?.isPhoneHidden ?? false) ? t("الرقم", "Phone") : nil,
            (u?.isPhotoHidden ?? false) ? t("الصورة", "Photo") : nil,
            (u?.isBirthDateHidden ?? false) ? t("الميلاد", "Birth date") : nil,
            (u?.activityVisible ?? true) ? nil : t("آخر ظهور", "Last seen")
        ].compactMap { $0 }
        switch hidden.count {
        case 0: return t("الكل ظاهر", "All visible")
        case 1: return t("\(hidden[0]) مخفي", "\(hidden[0]) hidden")
        case 4: return t("الكل مخفي", "All hidden")
        default: return t("\(hidden.count) مخفية", "\(hidden.count) hidden")
        }
    }

    /// «1993-03-25» → «25/03/1993» — الصيغة الموحّدة (`DateHelper.displayDate`)
    private func shortDate(_ raw: String?) -> String {
        guard let raw, raw.count >= 10 else { return "—" }
        return DateHelper.displayDate(raw) ?? "—"
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
    @State private var isPhotoHidden: Bool = false
    @State private var skipPhotoHiddenWrite = false
    /// «إظهار آخر ظهوري ونشاطي» (`set_activity_visibility`، ٢٠٢٦-١٠-٢٩)
    @State private var isActivityVisible: Bool = true
    @State private var skipActivityWrite = false
    /// «بياناتي في الشجرة»: طلب إخفاء/حذف/تصحيح (`request_privacy_change`)
    @State private var treeDataRequest: TreeDataRequestKind?
    @State private var treeDataResult: String?
    @State private var treeDataFailed = false
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
        case .all: return t("التحكم بالتنبيهات ومن يرى البيانات", "Control alerts and who sees your data")
        case .notifications: return t("تحكّم بالتنبيهات التي تصلك", "Control the alerts you get")
        case .privacy: return t("ما يراه الأعضاء، وطلبات بياناتك، والمحظورون", "What members see, data requests and blocked members")
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
                 title: t("الرد على الطلبات", "Replies to my requests"), subtitle: t("قبول أو رفض طلباتك، تفعيل حسابك", "Approvals, rejections, activation")),
            Kind(key: "profile", icon: "person.crop.circle.badge.checkmark", color: DS.Color.palm,
                 title: t("تحديثات الملف الشخصي", "My profile updates"), subtitle: t("عند تعديل الإدارة لبياناتك", "When admins edit your profile"))
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
                BlockedMembersSection(index: privacyIndex + 2)
            }
        }
        .environment(\.layoutDirection, langManager.layoutDirection)
        .onAppear {
            badgeEnabled = authVM.currentUser?.badgeEnabled ?? true
            setPhoneHiddenSilently(authVM.currentUser?.isPhoneHidden ?? false)
            setBirthHiddenSilently(authVM.currentUser?.isBirthDateHidden ?? false)
            setPhotoHiddenSilently(authVM.currentUser?.isPhotoHidden ?? false)
            setActivityVisibleSilently(authVM.currentUser?.activityVisible ?? true)
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
        .onChange(of: isActivityVisible) { newValue in
            if skipActivityWrite { skipActivityWrite = false; return }
            guard NetworkMonitor.shared.requireOnline() else {
                setActivityVisibleSilently(!newValue)
                return
            }
            Task {
                let success = await memberVM.updateActivityVisible(newValue)
                if !success {
                    if isActivityVisible == newValue { setActivityVisibleSilently(!newValue) }
                    showUpdateError = true
                }
            }
        }
        .onChange(of: isPhotoHidden) { newValue in
            if skipPhotoHiddenWrite { skipPhotoHiddenWrite = false; return }
            guard NetworkMonitor.shared.requireOnline() else {
                setPhotoHiddenSilently(!newValue)
                return
            }
            Task {
                let success = await memberVM.updatePhotoHidden(newValue)
                if !success {
                    if isPhotoHidden == newValue { setPhotoHiddenSilently(!newValue) }
                    showUpdateError = true
                }
            }
        }
        .dsAlert(t("خطأ", "Error"), isPresented: $showUpdateError) {
            Button(t("حسناً", "OK")) {}
        } message: {
            Text(t("تعذر تحديث الإعداد. حاول مرة أخرى.", "Failed to update setting. Please try again."))
        }
        .dsExtraBox(item: $treeDataRequest) { kind in
            TreeDataRequestBox(kind: kind,
                               onSend: { note in
                                   dsCloseExtra { treeDataRequest = nil }
                                   Task {
                                       let result = await PrivacyRequestService.send(kind, note: note)
                                       treeDataFailed = !result.ok
                                       treeDataResult = result.message
                                   }
                               },
                               onCancel: { dsCloseExtra { treeDataRequest = nil } })
        }
        .dsAlert(treeDataFailed ? t("تعذّر الإرسال", "Not sent") : t("أُرسل طلبك", "Request sent"),
                 isPresented: Binding(get: { treeDataResult != nil }, set: { if !$0 { treeDataResult = nil } })) {
            Button(t("حسناً", "OK")) { treeDataResult = nil }
        } message: {
            Text(treeDataResult ?? "")
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

    private func setActivityVisibleSilently(_ value: Bool) {
        guard isActivityVisible != value else { return }
        skipActivityWrite = true
        isActivityVisible = value
    }

    private func setPhotoHiddenSilently(_ value: Bool) {
        guard isPhotoHidden != value else { return }
        skipPhotoHiddenWrite = true
        isPhotoHidden = value
    }

    @ViewBuilder private var privacySection: some View {
        // مفتاح واحد لكل معلومة (العيّنة «هـ»، اختيار المالك ٢٠٢٦-١١-١١ «نبي ابسط»): مفعّل = ظاهر لأفراد العائلة،
        // مطفأ = مخفي — نفس القيم المخزّنة والحفظ كما كان (عند تغيّر القيمة)
        DSComposerSection(title: t("يظهر لأفراد العائلة", "Shown to family members"), icon: "eye.fill",
                          tint: DS.Color.primary, index: privacyIndex) {
            VStack(spacing: DS.Spacing.sm) {
                switchGroup([
                    PrivacySwitch(id: "phone", icon: "phone.fill", title: t("رقم الهاتف", "Phone number"),
                                  shown: Binding(get: { !isPhoneHidden }, set: { isPhoneHidden = !$0 })),
                    PrivacySwitch(id: "photo", icon: "camera.fill", title: t("الصورة الشخصية", "Profile photo"),
                                  shown: Binding(get: { !isPhotoHidden }, set: { isPhotoHidden = !$0 })),
                    PrivacySwitch(id: "birth", icon: "calendar", title: t("تاريخ الميلاد", "Birth date"),
                                  shown: Binding(get: { !isBirthDateHidden }, set: { isBirthDateHidden = !$0 })),
                    // المخزّن «إظهار» نفسه
                    PrivacySwitch(id: "activity", icon: "person.badge.clock.fill", title: t("آخر ظهور", "Last seen"),
                                  shown: $isActivityVisible)
                ])
                sectionNote(t("المطفأ لا يراه الأعضاء، ويبقى ظاهراً لك وللإدارة.",
                              "Members don't see what's off; you and the admins still do."))
            }
        }
        if DaughterFamilyAPI.enabled && isFemaleUser { treeShowSection }
        treeDataSection
    }

    // MARK: - «ما يظهر في الشجرة» (طلب المالك ٢٠٢٦-١١-٠٩ «كله اختياري») — عيّنة قبل دوال السيرفر

    @State private var showSpouse = false
    @State private var showMyself = true
    @State private var showChildren = false
    /// القيم وصلت من السيرفر — قبلها التغيير لا يُحفظ (فلا يكتب التحميل نفسه)
    @State private var treeShowLoaded = false

    /// عقدتها في شجرة النساء (من آخر جلب، أو عقدة التجربة في نسخة التطوير)
    private var myTreeNode: FamilyMember? {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["DAUGHTER_PROFILE_TEST"], let id = UUID(uuidString: raw) {
            return WomenStore.cache.first { $0.id == id }
        }
        #endif
        guard let uid = authVM.currentUser?.id else { return nil }
        return WomenStore.node(forAccount: uid)
    }

    private func loadTreeShow() async {
        if WomenStore.cache.isEmpty { _ = try? await WomenStore.fetch() }
        guard let node = myTreeNode else { return }
        showMyself = !node.isHiddenFromTree
        showSpouse = WomenStore.spouseShownIds.contains(node.id)
        showChildren = WomenStore.childrenShownIds.contains(node.id)
        treeShowLoaded = true
    }

    private func saveTreeShow(me: Bool? = nil, spouse: Bool? = nil, children: Bool? = nil) {
        guard treeShowLoaded, WomenStore.visibilitySupported, let node = myTreeNode else { return }
        // نفس المحفوظ (التحميل نفسه، أو الرجوع بعد خطأ) — لا كتابة
        if let me, me == !node.isHiddenFromTree { return }
        if let spouse, spouse == WomenStore.spouseShownIds.contains(node.id) { return }
        if let children, children == WomenStore.childrenShownIds.contains(node.id) { return }
        Task {
            do {
                try await DaughterFamilyAPI.setVisibility(me: me, spouse: spouse, children: children)
                _ = try? await WomenStore.fetch()
            } catch {
                Log.warning("[DaughterFamily] privacy: \(error.localizedDescription)")
                await loadTreeShow()   // يرجع المفتاح لحالته المحفوظة
            }
        }
    }

    private var isFemaleUser: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["DAUGHTER_PROFILE_TEST"] != nil { return true }
        #endif
        return authVM.currentUser?.isWomanAccount ?? false
    }

    private var treeShowSection: some View {
        // نفس كتل «الخصوصية» الموحّدة — «ظاهر في الشجرة / مخفي» (المخزّن «يظهر»، والمخفي عكسه)
        DSComposerSection(title: t("الظهور في شجرة النساء", "What shows in the women's tree"), icon: "eye.fill",
                          tint: DS.Color.primary, index: privacyIndex + 1) {
            VStack(spacing: DS.Spacing.sm) {
                // مفاتيح بسيطة كبقية «الخصوصية» (العيّنة «هـ»): مفعّل = يظهر في شجرة النساء.
                // البنت تتحكم في ظهورها هي في الشجرة (طلب المالك ٢٠٢٦-١١-٠٩)
                switchGroup((isFemaleUser ? [PrivacySwitch(id: "me", icon: "person.fill", title: t("الاسم", "Name"),
                                                           shown: $showMyself)] : [])
                            + [PrivacySwitch(id: "spouse", icon: "heart.fill",
                                             title: isFemaleUser ? t("الزوج", "Husband") : t("الزوجة", "Wife"),
                                             shown: $showSpouse)]
                            + (isFemaleUser ? [PrivacySwitch(id: "children", icon: "person.2.fill",
                                                             title: t("الأبناء", "Children"), shown: $showChildren)] : []))
                sectionNote(t("جميع الخيارات اختيارية ويمكن تغييرها في أي وقت.",
                              "All optional and can be changed at any time."))
            }
        }
        .task { await loadTreeShow() }
        .onChange(of: showMyself) { v in saveTreeShow(me: v) }
        .onChange(of: showSpouse) { v in saveTreeShow(spouse: v) }
        .onChange(of: showChildren) { v in saveTreeShow(children: v) }
    }

    /// «بياناتك في الشجرة» — طلب إخفاء أو حذف تراجعه الإدارة (سياسة الخصوصية ٢٠٢٦-١٠-٢٨).
    /// «تصحيح البيانات» أُزيل (طلب المالك ٢٠٢٦-١١-١١)؛ صفوف القائمة المجمّعة نفسها (العيّنة «هـ»)
    private var treeDataSection: some View {
        let kinds: [TreeDataRequestKind] = [.hide, .delete]
        return DSComposerSection(title: t("بياناتك في الشجرة", "Your data in the tree"),
                                 icon: "tree.fill", tint: DS.Color.primary, index: privacyIndex + 1) {
            VStack(spacing: DS.Spacing.sm) {
                VStack(spacing: 0) {
                    ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
                        Button { treeDataRequest = kind } label: {
                            SettingsGroupRow(icon: kind.icon,
                                             fill: kind == .delete ? DS.Color.errorFill : DS.Color.slateFill,
                                             title: kind == .delete ? t("حذف بياناتي من الشجرة", "Delete my data from the tree")
                                                                    : t("إخفاء بياناتي", "Hide my data"),
                                             titleColor: kind == .delete ? DS.Color.error : DS.Color.textPrimary) {
                                SettingsChevron()
                            }
                            .dsGroupedRow(DSGroupPosition(index: index, count: kinds.count),
                                          dividerInset: SettingsGroupRow<EmptyView>.dividerInset)
                        }
                        .buttonStyle(DSNoticePressStyle())
                        .accessibilityHint(kind.subtitle)
                    }
                }
                sectionNote(t("يصل طلبك إلى الإدارة، ويصلك الرد في الإشعارات.",
                              "Your request goes to the administration; the reply arrives in notifications."))
            }
        }
    }

    /// مفتاح خصوصية واحد في مجموعة
    private struct PrivacySwitch: Identifiable {
        let id: String
        let icon: String
        let title: String
        /// مفعّل = ظاهر
        let shown: Binding<Bool>
    }

    /// مفاتيح الخصوصية في بطاقة واحدة — كل صفّ جزء منها بخطّ فاصل رفيع (العيّنة «هـ»)
    private func switchGroup(_ items: [PrivacySwitch]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                SettingsGroupRow(icon: item.icon, fill: DS.Color.navyFill, title: item.title) {
                    Toggle(item.title, isOn: item.shown)
                        .labelsHidden()
                        .tint(DS.Color.toggleOn)
                        .accessibilityLabel(item.title)
                        .accessibilityValue(item.shown.wrappedValue ? t("ظاهر لأفراد العائلة", "Shown to family")
                                                                    : t("مخفي عن أفراد العائلة", "Hidden from family"))
                }
                .dsGroupedRow(DSGroupPosition(index: index, count: items.count),
                              dividerInset: SettingsGroupRow<EmptyView>.dividerInset)
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
                    Text(on ? t("الإشعارات مفعّلة", "Notifications are on")
                            : (systemBlocked ? t("موقوفة من إعدادات الجهاز", "Blocked in device settings")
                                             : t("الإشعارات موقوفة", "Notifications are off")))
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(on ? t("تصل تنبيهات العائلة إلى هذا الجهاز", "Family alerts reach this device")
                            : t("لا تصل التنبيهات إلى هذا الجهاز", "No alerts on this device"))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                }
                Spacer(minLength: DS.Spacing.sm)
                Toggle(t("الإشعارات", "Notifications"), isOn: $notificationsEnabled)
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
        case .sent: return t("أُرسل، ويصل خلال ثوانٍ", "Sent — it should arrive in seconds")
        case .failed: return t("تعذّر الإرسال، يرجى المحاولة مرة أخرى", "Couldn't send, try again")
        }
    }

    private func sendTest() async {
        guard let me = authVM.currentUser?.id else { return }
        testState = .sending
        do {
            let row: [String: AnyEncodable] = [
                "target_member_id": AnyEncodable(me.uuidString),
                "title": AnyEncodable(t("إشعار تجربة ✓", "Test notification ✓")),
                "body": AnyEncodable(t("عند وصول هذا الإشعار، تكون الإشعارات مفعّلة على هذا الجهاز.",
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
            Toggle(title, isOn: isOn)
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
        NotificationMasterSwitch.apply(newValue, notificationVM: notificationVM)
    }
}

/// تشغيل الإشعارات وإيقافها — مكان واحد لمربّع «الإشعارات» ولسطر «الإعدادات» السريع
enum NotificationMasterSwitch {
    static func apply(_ newValue: Bool, notificationVM: NotificationViewModel) {
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
                        // ثلاثة خيارات = الاختيار الموحّد (`DSChoiceTiles`، طلب المالك ٢٠٢٦-١١-١٠)
                        DSChoiceTiles(options: [
                            DSChoiceOption(id: "system", title: t("حسب الجهاز", "System"), icon: "iphone"),
                            DSChoiceOption(id: "light", title: t("فاتح", "Light"), icon: "sun.max.fill"),
                            DSChoiceOption(id: "dark", title: t("داكن", "Dark"), icon: "moon.stars.fill")
                        ], selection: $appearanceMode)
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
                        DSChoiceTiles(options: [
                            DSChoiceOption(id: "ar", title: "العربية", icon: "character.book.closed.fill"),
                            DSChoiceOption(id: "en", title: "English", icon: "textformat.abc")
                        ], selection: languageSelection)
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
    /// ارتفاع المشهد — ١١٢ في مربّع «المظهر»، أصغر في سطر الإعدادات السريع
    var height: CGFloat = 112
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
        .frame(height: height)
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
    /// الإصدار الرسمي فقط بلا رقم البناء (طلب المالك ٢٠٢٦-١٠-٣١)
    static var string: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
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
/// «الخصوصية والاستخدام» (طلب المالك ٢٠٢٦-١٠-٢٧: اسم أوضح ونص أخف وأدق) — مربّع بمنتصف الشاشة بتصميم المربّعات:
/// رأس بالعنوان وسطر «سياسة الخصوصية وشروط الاستخدام»، تبويبان («بياناتك وخصوصيتك» · «قواعد الاستخدام»)، وكل نقطة
/// بطاقة صغيرة (رمز + عنوان + سطران)، ثم «آخر تحديث» ورابط النسخة على الموقع، وزرّ «فهمت». النص من السيرفر
/// (`LegalContentStore`، `app_config_public` ← `legal_content`) — يُقرأ قبل الدخول ويُعدَّل بلا تحديث؛ وإلا النص المدمج.
/// الاسم القديم للنوع باقٍ (يفتحه «الدخول» و«الإعدادات»).
struct PrivacyPolicyView: View {
    @Environment(\.dsSection) private var section
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var store = LegalContentStore.shared
    /// تغيير اللغة يبدّل النص للنسخة الإنجليزية/العربية فوراً
    @ObservedObject private var langManager = LanguageManager.shared
    /// يبدأ بالخصوصية (أو بالقواعد إن طُلب)
    var startsWithTerms: Bool = false
    /// وثيقة واحدة فقط (`privacy` أو `terms`) بلا تبويبين — صفحتان منفصلتان (طلب المالك ٢٠٢٦-١٠-٢٨)
    var only: String? = nil
    /// شاشة الموافقة عند الدخول (`termsAcceptanceGate`): «أوافق» بدل «فهمت» و«تسجيل الخروج» بدل «إغلاق»
    var acceptance: Acceptance? = nil
    /// شاشة الموافقة تبدأ صغيرة (طلب المالك ٢٠٢٦-١٠-٢٨): السطر والزرّان، والنص كاملاً عند الطلب
    @State private var showsFullText = false
    /// المواد المفتوحة (الملخّص ← النص كاملاً)
    @State private var openItems: Set<String> = []
    @State private var tab = "privacy"

    struct Acceptance {
        var isAccepting: Bool
        var errorMessage: String?
        var onAccept: () -> Void
        var onSignOut: () -> Void
    }

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    private var fullContent: LegalContent { store.content }
    private var content: LegalContent {
        guard let only, let doc = fullContent.sections.first(where: { $0.key == only }) else { return fullContent }
        return LegalContent(title: doc.title, subtitle: fullContent.title, updated: fullContent.updated, sections: [doc])
    }
    private var current: LegalContent.Section? {
        content.sections.first { $0.key == tab } ?? content.sections.first
    }

    var body: some View {
        DSComposer(
            title: content.title,
            subtitle: content.subtitle,
            icon: "lock.shield.fill",
            tint: DS.Color.actionNavy,
            actionTitle: acceptance == nil ? t("فهمت", "Got it") : t("أوافق", "I Agree"),
            actionIcon: "checkmark",
            showsAction: true,
            cancelTitle: acceptance == nil ? t("إغلاق", "Close") : t("تسجيل الخروج", "Sign Out"),
            canSubmit: true,
            isBusy: acceptance?.isAccepting ?? false,
            onSubmit: { if let acceptance { acceptance.onAccept() } else { dismiss() } },
            onCancel: { if let acceptance { acceptance.onSignOut() } else { dismiss() } }
        ) {
            if let acceptance {
                Text(t("للمتابعة، يُرجى الموافقة على سياسة الخصوصية وقواعد الاستخدام. ولا نتسامح مع المحتوى المسيء أو المستخدمين المسيئين.",
                       "To continue, please agree to the privacy policy and rules of use. We have no tolerance for objectionable content or abusive users."))
                    .dsReadingFont()
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                if let error = acceptance.errorMessage {
                    DSNoteCard(error, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                }
                Label(showsFullText ? t("إخفاء النص", "Hide the text") : t("اقرأ النص كاملاً", "Read the full text"),
                      systemImage: showsFullText ? "chevron.up" : "chevron.down")
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.info)
                    .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(DS.Anim.snappy) { showsFullText.toggle() } }
                    .accessibilityAddTraits(.isButton)
            }
            if acceptance == nil || showsFullText {
            if content.sections.count > 1 {
                DSSegmentedSwitch(options: content.sections.map {
                    DSSegmentOption(id: $0.key, title: $0.title,
                                    icon: $0.key == "terms" ? "doc.text.fill" : "hand.raised.fill")
                }, selection: $tab.animation(DS.Anim.snappy), size: .regular)
            }

            // كل النقاط صفوف خفيفة في بطاقة واحدة بخط رفيع بينها (طلب المالك «تخفيف زحمة» — كانت بطاقة لكل نقطة)
            if let current {
                VStack(spacing: 0) {
                    ForEach(Array(current.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider().padding(.leading, DS.Icon.row + DS.Spacing.md)
                        }
                        itemRow(item)
                            .dsStaggerIn(index)
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
                .dsCard()
                .id(current.key)   // تبويب جديد ← دخول صفوفه من جديد
            }

            VStack(spacing: DS.Spacing.xs) {
                if !content.updated.isEmpty {
                    Text(t("آخر تحديث: ", "Last updated: ") + content.updated)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                }
                Button {
                    openURL(current?.key == "terms" ? FamilyLinks.termsOfUse : FamilyLinks.privacyPolicy)
                } label: {
                    Text(t("النسخة الكاملة على الموقع", "Full version on the website"))
                        .dsFont(.footnote)
                        .underline()
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(minHeight: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            }
        }
        .onAppear { tab = only ?? (startsWithTerms ? "terms" : "privacy") }
        .task { await store.refresh() }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        // النص الطويل يبدأ من أول السطر في اللغتين (الإنجليزي كان ينزاح لليمين)
        .environment(\.multilineTextAlignment, .leading)
    }

    /// مادة واحدة: رمز بلون القسم + العنوان + ملخّصها في سطر، والضغط يفتح المادة كاملة (طلب المالك ٢٠٢٦-١٠-٢٨
    /// «نختصر النص بالتطبيق… مرتب مع السيرفر»: الملخّص `summary` والنص `lines` كلاهما من السيرفر)
    private func itemRow(_ item: LegalContent.Item) -> some View {
        let open = item.summary == nil || openItems.contains(item.id)
        return HStack(alignment: .top, spacing: DS.Spacing.md) {
            Image(systemName: LegalContent.icon(for: item.id))
                .dsGlyph(DS.Glyph.md, weight: .semibold)
                .foregroundColor(DS.Color.primary.dsChrome(in: section))
                .frame(width: DS.Icon.row, height: DS.Icon.row)
                .background(Circle().fill(DS.Color.primary.dsChrome(in: section).opacity(DS.Opacity.tintFill)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                // مقاس نص التطبيق نفسه (طلب المالك ٢٠٢٦-١٠-٢٨ — كان أصغر من بقية التطبيق)
                Text(item.title)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                // نص القراءة: Plex العادي بسطور مريحة (قرار المالك ٢٠٢٦-١٠-٢٨) — العنوان فوقه بخط التطبيق
                if let summary = item.summary, !open {
                    Text(summary)
                        .dsReadingFont()
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(item.lines, id: \.self) { line in
                        Text(line)
                            .dsReadingFont()
                            .foregroundColor(DS.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
            if item.summary != nil {
                Image(systemName: open ? "chevron.up" : "chevron.down")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.top, DS.Spacing.xxs)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .contentShape(Rectangle())
        .onTapGesture {
            guard item.summary != nil else { return }
            withAnimation(DS.Anim.snappy) {
                if openItems.contains(item.id) { openItems.remove(item.id) } else { openItems.insert(item.id) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(item.summary != nil ? .isButton : [])
        .accessibilityHint(item.summary == nil ? "" : (open ? t("يطوي المادة", "Collapses the article") : t("يفتح المادة كاملة", "Opens the full article")))
    }
}

// MARK: - Linked Devices Settings Sheet
/// الأجهزة المرتبطة — مربّع عرض بمنتصف الشاشة بتصميم المربّعات الموحّد (طلب المالك):
/// رأس ملوّن + قسم الأجهزة + «إغلاق». للعرض فقط — لا إزالة أجهزة من هنا.
struct LinkedDevicesSettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @EnvironmentObject var authVM: AuthViewModel

    private var maxDevices: Int { appSettingsVM.deviceLimit(isOwner: authVM.isOwner) }
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
        DateHelper.displayDateTime(isoString) ?? isoString
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environmentObject(AuthViewModel())
        .environmentObject(NotificationViewModel())
}

/// مربّع أيقونة عادي للإعدادات: لون خفيف وأيقونة رفيعة (الذهبي لرؤوس المربّعات المنبثقة فقط)
struct SettingsIconSquare: View {
    let icon: String
    let tint: Color
    var side: CGFloat = DS.Icon.rowLarge
    /// مربّع ممتلئ بلونه ورمز أبيض (قوائم الإعدادات المجمّعة — العيّنة «هـ»، اختيار المالك ٢٠٢٦-١١-١١)؛
    /// `tint` هنا لون التعبئة (`DS.Color.*Fill`)
    var filled: Bool = false
    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
            .fill(filled ? tint : tint.opacity(DS.Opacity.tintFill))
            .frame(width: side, height: side)
            .overlay(Image(dsSymbol: filled ? icon : icon.dsLightSymbol)
                .dsGlyph(side * (filled ? 0.48 : 0.5), weight: filled ? .medium : .light)
                .foregroundColor(filled ? DS.Color.textOnPrimary : tint))
            .accessibilityHidden(true)
    }
}

/// صفّ في قائمة مجمّعة (الإعدادات والخصوصية — العيّنة «هـ»): مربّع الرمز الممتلئ + العنوان + القيمة/المفتاح في الطرف.
/// يُلبس `.dsGroupedRow` ليصير جزءاً من بطاقة مجموعته
struct SettingsGroupRow<Trailing: View>: View {
    let icon: String
    let fill: Color
    let title: String
    var titleColor: Color = DS.Color.textPrimary
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            SettingsIconSquare(icon: icon, tint: fill, side: DS.Icon.row, filled: true)
            Text(title)
                .dsFont(.rowTitle)
                .foregroundColor(titleColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Spacing.sm)
            trailing()
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .frame(minHeight: DSBox.commandRowHeight)
        .contentShape(Rectangle())
    }

    /// بداية الخطّ الفاصل تحت الصفّ — من بعد مربّع الرمز
    static var dividerInset: CGFloat { DS.Spacing.md + DS.Icon.row + DS.Spacing.md }
}

/// سهم «فتح» في طرف الصفّ باتجاه القراءة
struct SettingsChevron: View {
    var body: some View {
        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
            .dsGlyph(DS.Glyph.xs, weight: .semibold)
            .foregroundColor(DS.Color.textTertiary)
            .accessibilityHidden(true)
    }
}
