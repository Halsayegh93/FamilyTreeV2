import SwiftUI
import UserNotifications

struct MainTabView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var langManager = LanguageManager.shared
    @State private var selectedTab = 0
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showNotificationAlert = false
    @AppStorage("notificationAlertDismissCount") private var dismissCount = 0
    /// الموافقة على شروط الاستخدام لمرة واحدة (Guideline 1.2) — للأعضاء الحاليين
    @State private var showTermsGate = false

    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab {
                    NotificationCenter.default.post(name: .didReselectTab, object: nil, userInfo: ["tab": newValue])
                } else {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                selectedTab = newValue
                // جلسات الاستخدام: التبويب الجديد قبل ظهور صفحاته (`AppUsageTracker`)
                AppUsageTracker.shared.setTab(newValue)
                NotificationCenter.default.post(name: Notification.Name("TabChanged"), object: nil)
                let tabs = ["home", "tree", "diwaniyas", "profile", "admin"]
                if newValue < tabs.count {
                    AppAnalytics.trackTabSwitch(tab: tabs[newValue])
                    MemberActivityTracker.report(tabs[newValue])
                }
            }
        )
    }
    
    private func tabTitle(_ ar: String, _ en: String) -> String {
        verticalSizeClass == .compact ? "" : L10n.t(ar, en)
    }

    /// «كل قسم بلونه» (طلب المالك ٢٠٢٦-١٠-٠٤): قسم التبويب المختار — أرقام التبويبات
    /// نفس ترتيب AppSection (٠ الرئيسية … ٤ الإدارة)
    private var selectedSection: AppSection { AppSection(rawValue: selectedTab) ?? .home }

    /// iOS 18+: واجهة Tab الحديثة — تأخذ شكل شريط iOS 26/27 الكامل (زجاج سائل عائم
    /// بفقاعة اختيار). الأقدم: tabItem كما كان.
    /// رموز التبويبات من مكان واحد: `AppSection.symbol` (المختار) و`.symbolOutline` — الديوانيات «مجلس»
    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: tabSelection) {
                // كل تبويب يلوّن ما بداخله بلونه (البيئة + tint) — حتى الصفحات المدفوعة والمربّعات
                Tab(value: 0) {
                    HomeNewsView(selectedTab: $selectedTab)
                        .dsSection(.home)
                } label: {
                    Label(tabTitle("الرئيسية", "Home"), systemImage: AppSection.home.symbol)
                }

                Tab(value: 1) {
                    TreeTabContainer(selectedTab: $selectedTab)
                        .dsSection(.tree)
                } label: {
                    Label(tabTitle("الشجرة", "Tree"), systemImage: AppSection.tree.symbol)
                }

                if appSettingsVM.settings.diwaniyasEnabled ?? true {
                    Tab(value: 2) {
                        DiwaniyasView(selectedTab: $selectedTab)
                            .dsSection(.diwaniyas)
                    } label: {
                        Label(tabTitle("الديوانيات", "Diwaniyas"), systemImage: AppSection.diwaniyas.symbol)
                    }
                }

                Tab(value: 3) {
                    ProfileView(selectedTab: $selectedTab)
                        .dsSection(.profile)
                } label: {
                    Label(tabTitle("حسابي", "Profile"), systemImage: AppSection.profile.symbol)
                }

                if authVM.canModerate {
                    Tab(value: 4) {
                        AdminDashboardView(selectedTab: $selectedTab)
                            .dsSection(.admin)
                    } label: {
                        Label(tabTitle("الإدارة", "Admin"), systemImage: AppSection.admin.symbol)
                    }
                }
            }
        } else {
        TabView(selection: tabSelection) {
            HomeNewsView(selectedTab: $selectedTab)
                .dsSection(.home)
                .tabItem {
                    Image(systemName: selectedTab == 0 ? AppSection.home.symbol : AppSection.home.symbolOutline)
                    Text(verticalSizeClass == .compact ? "" : L10n.t("الرئيسية", "Home"))
                }
                .tag(0)

            // مغلّف يسمح بالتبديل بين الواجهة الكلاسيكية والتجربة الجديدة
            TreeTabContainer(selectedTab: $selectedTab)
                .dsSection(.tree)
                .tabItem {
                    Image(systemName: selectedTab == 1 ? AppSection.tree.symbol : AppSection.tree.symbolOutline)
                    Text(verticalSizeClass == .compact ? "" : L10n.t("الشجرة", "Tree"))
                }
                .tag(1)

            if appSettingsVM.settings.diwaniyasEnabled ?? true {
                DiwaniyasView(selectedTab: $selectedTab)
                    .dsSection(.diwaniyas)
                    .tabItem {
                        Image(systemName: selectedTab == 2 ? AppSection.diwaniyas.symbol : AppSection.diwaniyas.symbolOutline)
                        Text(verticalSizeClass == .compact ? "" : L10n.t("الديوانيات", "Diwaniyas"))
                    }
                    .tag(2)
            }

            ProfileView(selectedTab: $selectedTab)
                .dsSection(.profile)
                .tabItem {
                    Image(systemName: selectedTab == 3 ? AppSection.profile.symbol : AppSection.profile.symbolOutline)
                    Text(verticalSizeClass == .compact ? "" : L10n.t("حسابي", "Profile"))
                }
                .tag(3)

            if authVM.canModerate {
                AdminDashboardView(selectedTab: $selectedTab)
                    .dsSection(.admin)
                    .tabItem {
                        Image(systemName: selectedTab == 4 ? AppSection.admin.symbol : AppSection.admin.symbolOutline)
                        Text(verticalSizeClass == .compact ? "" : L10n.t("الإدارة", "Admin"))
                    }
                    .tag(4)
            }
        }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
        tabs
        // أيقونة التبويب المختار بلون قسمه
        .tint(selectedSection.ink)
        .dsTabBarBackground()
        .onReceive(NotificationCenter.default.publisher(for: .openAdminRequests)) { _ in
            guard authVM.canModerate else { return }
            withAnimation { selectedTab = 4 }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAdminReviewForKind)) { _ in
            guard authVM.canModerate else { return }
            withAnimation { selectedTab = 4 }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openHomeNotificationsCenter)) { _ in
            withAnimation { selectedTab = 0 }
        }
        // «شجرة النساء» من «العائلة» في لوحة الإدارة — تبويب الشجرة يفتح على النساء
        .onReceive(NotificationCenter.default.publisher(for: .openWomenTree)) { _ in
            withAnimation { selectedTab = 1 }
        }
        // صلة القرابة من أي مكان (تفاصيل العضو، الرابط، الرمز): تاب الشجرة ← شجرة العائلة ← المسار.
        // كان الطلب يضيع خارج تاب الشجرة أو في تبويب النساء (طلب المالك ٢٠٢٦-١٠-٠٢)
        .onReceive(NotificationCenter.default.publisher(for: .requestKinshipPath)) { note in
            let info = note.userInfo
            let alreadyOnTree = selectedTab == 1
            withAnimation { selectedTab = 1 }
            // داخل تاب الشجرة: بلا انتظار يُذكر (مثل السابق) — من تاب آخر: حتى تُبنى الشجرة
            DispatchQueue.main.asyncAfter(deadline: .now() + (alreadyOnTree ? 0.15 : 0.6)) {
                NotificationCenter.default.post(name: .showKinshipPath, object: nil, userInfo: info)
            }
        }
        }
        // القسم المختار لما يُعرض في نافذة مستقلّة (الرسائل، مربّع التاريخ، النعي) — ولا قسم خارج
        // التبويبات: عند الخروج (الدخول، الانتظار، التجميد) يرجع كحلي العلامة. لا نصفّره إن اختفت
        // التبويبات تحت مربّع يغطي الشاشة فقط (الحساب ما زال داخلاً)
        // وجلسات الاستخدام (`AppUsageTracker` → `log_app_session`): للحساب المفعّل فقط — تبدأ مع التبويبات
        // وتُترك بلا إرسال عند الخروج منها
        .onAppear {
            AppSection.current = selectedSection
            AppUsageTracker.shared.start(tab: selectedTab)
        }
        .onChange(of: selectedTab) { tab in
            AppSection.current = selectedSection
            AppUsageTracker.shared.setTab(tab)
        }
        .onDisappear {
            if authVM.status != .fullyAuthenticated {
                AppSection.current = nil
                AppUsageTracker.shared.stop()
            }
        }
        // الحظر والموافقة على الشروط لكل مستخدم — تُربط بالحساب الحالي
        .onAppear { refreshUserSafetyState() }
        .onChange(of: authVM.currentUser?.id) { _ in refreshUserSafetyState() }
        // مربّع الشروط لمرة واحدة — لا يُغلق بالضغط خارجه، «أوافق وأتابع» ضغطة واحدة
        .dsCenterBox(isPresented: $showTermsGate) {
            TermsAgreementBox(
                onAccept: {
                    TermsAgreement.accept([authVM.currentUser?.id, AccountIdentity.authUserId])
                    showTermsGate = false
                },
                onSignOut: {
                    showTermsGate = false
                    Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        await authVM.signOut()
                    }
                }
            )
        }
        .task {
            // تتبع أول شاشة عند الفتح
            MemberActivityTracker.report("home")
            // كتالوج العوائل — ليعرض كل اسم بآخره العائلة المختارة
            await FamilyNamesViewModel().fetch()
            // أول مرة: النظام يطلب تلقائي من PushNotificationDelegate
            // ننتظر 3 ثواني عشان المستخدم يرد على طلب النظام أول
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            // مربّع الشروط مفتوح — لا نغطيه برسالة الإشعارات (تظهر في فتحة لاحقة)
            guard !showTermsGate else { return }
            // تحقق إذا رفض — أقصى مرتين بعد طلب النظام
            guard dismissCount < 2 else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .denied {
                showNotificationAlert = true
            }
        }
        .dsAlert(
            L10n.t("تفعيل الإشعارات", "Enable Notifications"),
            isPresented: $showNotificationAlert
        ) {
            Button(L10n.t("فتح الإعدادات", "Open Settings")) {
                dismissCount += 1
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(L10n.t("لاحقاً", "Later"), role: .cancel) {
                dismissCount += 1
            }
        } message: {
            Text(L10n.t(
                "فعّل الإشعارات عشان توصلك أخبار العائلة والتحديثات المهمة",
                "Enable notifications to receive family news and important updates"
            ))
        }
    }

    /// يربط قائمة المحظورين بالحساب الحالي، ويعرض مربّع الشروط مرة واحدة لمن لم يوافق
    /// بعد على هذا الجهاز (من وافق عند التسجيل لا يراه).
    private func refreshUserSafetyState() {
        let userId = authVM.currentUser?.id
        BlockedMembersStore.shared.activate(for: userId)
        guard let userId else { return }
        let ids: [UUID?] = [userId, AccountIdentity.authUserId]
        if TermsAgreement.hasAccepted(ids) {
            // وافق بمعرّف الدخول عند التسجيل — نسجّلها بمعرّف الملف أيضاً
            TermsAgreement.accept(ids)
            return
        }
        Task {
            // بعد استقرار الواجهة — العرض أثناء أول رسم قد لا يظهر
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard authVM.currentUser?.id == userId, !TermsAgreement.hasAccepted(ids) else { return }
            showTermsGate = true
        }
    }
}

extension Notification.Name {
    static let didReselectTab       = Notification.Name("didReselectTab")
    /// يعرض صلة القرابة في الشجرة من أي مكان — نفس userInfo لـ `showKinshipPath`
    static let requestKinshipPath   = Notification.Name("requestKinshipPath")
    /// زر التحديد في هيدر الصفحة الفرعية — userInfo: ["page": "archive" | "projects"]
    static let subPageStartSelection = Notification.Name("subPageStartSelection")
    static let openAdminRequests    = Notification.Name("openAdminRequests")
    /// userInfo: ["kind": String] — يفتح تاب الإدارة + يدفع شاشة المراجعة المناسبة
    static let openAdminReviewForKind = Notification.Name("openAdminReviewForKind")
    /// يفتح تاب الرئيسية ويدفع مركز الإشعارات + يفتح شيت تفاصيل الطلب لو فيه deep-link
    static let openHomeNotificationsCenter = Notification.Name("openHomeNotificationsCenter")
}
