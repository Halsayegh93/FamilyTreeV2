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

    /// iOS 18+: واجهة Tab الحديثة — تأخذ شكل شريط iOS 26/27 الكامل (زجاج سائل عائم
    /// بفقاعة اختيار). الأقدم: tabItem كما كان.
    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: tabSelection) {
                Tab(value: 0) {
                    HomeNewsView(selectedTab: $selectedTab)
                } label: {
                    Label(tabTitle("الرئيسية", "Home"), systemImage: "house.fill")
                }

                Tab(value: 1) {
                    TreeTabContainer(selectedTab: $selectedTab)
                } label: {
                    Label(tabTitle("الشجرة", "Tree"), systemImage: "tree.fill")
                }

                if appSettingsVM.settings.diwaniyasEnabled ?? true {
                    Tab(value: 2) {
                        DiwaniyasView(selectedTab: $selectedTab)
                    } label: {
                        Label(tabTitle("الديوانيات", "Diwaniyas"), systemImage: "map.fill")
                    }
                }

                Tab(value: 3) {
                    ProfileView(selectedTab: $selectedTab)
                } label: {
                    Label(tabTitle("حسابي", "Profile"), systemImage: "person.crop.circle.fill")
                }

                if authVM.canModerate {
                    Tab(value: 4) {
                        AdminDashboardView(selectedTab: $selectedTab)
                    } label: {
                        Label(tabTitle("الإدارة", "Admin"), systemImage: "gearshape.2.fill")
                    }
                }
            }
        } else {
        TabView(selection: tabSelection) {
            HomeNewsView(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                    Text(verticalSizeClass == .compact ? "" : L10n.t("الرئيسية", "Home"))
                }
                .tag(0)

            // مغلّف يسمح بالتبديل بين الواجهة الكلاسيكية والتجربة الجديدة
            TreeTabContainer(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "tree.fill" : "tree")
                    Text(verticalSizeClass == .compact ? "" : L10n.t("الشجرة", "Tree"))
                }
                .tag(1)

            if appSettingsVM.settings.diwaniyasEnabled ?? true {
                DiwaniyasView(selectedTab: $selectedTab)
                    .tabItem {
                        Image(systemName: selectedTab == 2 ? "map.fill" : "map")
                        Text(verticalSizeClass == .compact ? "" : L10n.t("الديوانيات", "Diwaniyas"))
                    }
                    .tag(2)
            }

            ProfileView(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: selectedTab == 3 ? "person.crop.circle.fill" : "person.crop.circle")
                    Text(verticalSizeClass == .compact ? "" : L10n.t("حسابي", "Profile"))
                }
                .tag(3)

            if authVM.canModerate {
                AdminDashboardView(selectedTab: $selectedTab)
                    .tabItem {
                        Image(systemName: selectedTab == 4 ? "gearshape.2.fill" : "gearshape.2")
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
        .tint(DS.Color.primary)
        .dsTabBarBackground()
        .overlay(alignment: .top) {
            OfflineBanner()
                .padding(.top, DS.Spacing.xs)
                .zIndex(999)
        }
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
