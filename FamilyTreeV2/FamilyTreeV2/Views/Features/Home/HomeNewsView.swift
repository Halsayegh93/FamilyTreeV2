import SwiftUI

struct HomeNewsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي على الجوال — نعيد توزيع البنتو على عمودين
    private var isLandscape: Bool { vSizeClass == .compact }
    @State private var contentWidth: CGFloat = 0

    @Binding var selectedTab: Int
    @State private var showingAddNews = false
    @State private var showingNotifications = false
    /// «التواصل» مربّع بمنتصف الشاشة (بدل الصفحة الفرعية)
    @State private var showingContactForm = false
    @State private var selectedNewsForComments: NewsPost? = nil
    @State private var postToDelete: NewsPost? = nil
    @State private var postToReport: NewsPost? = nil
    @State private var newsReportReason = ""
    @State private var newsReportSent = false
    /// حظر ناشر الخبر (Guideline 1.2) — أخبار المحظورين لا تظهر للحاظر
    @State private var blockTarget: BlockTarget? = nil
    @ObservedObject private var blockedStore = BlockedMembersStore.shared
    /// «النقاط الصفراء» على مربّعات الأقسام إذا فيها جديد
    @ObservedObject private var newDots = NewContentTracker.shared
    @State private var postToEdit: NewsPost? = nil
    @State private var showNewNewsAlert = false
    @State private var newNewsCount = 0
    @State private var selectedMemberForDetails: FamilyMember? = nil
    @State private var lastRefreshDate: Date? = nil
    /// فلتر نوع الخبر في صفحة الأخبار — nil يعني الكل
    @State private var selectedNewsTypeFilter: String? = nil
    @State private var newsSearchText = ""
    @State private var debouncedNewsSearch = ""
    @State private var newsSearchTask: Task<Void, Never>?
    /// دخول بطاقات الرئيسية تباعاً مرة عند ظهورها — نمط الأخبار والديوانيات
    /// (طلب المالك ٢٠٢٦-٠٩-٢٧: «طبّقه على البقية»)
    @State private var appeared = false
    /// أشكال مكتبة/مشاريع «مجسّمات» المخزّنة (اختيار المالك على جهازه) — تُمرَّر لمجسّمات المربّعات
    /// دخول بطاقات صفحة الأخبار — يُصفَّر قبل كل فتح للصفحة فتتوالى البطاقات مع كل دخول
    @State private var newsAppeared = false
    /// خبر ضُغط عليه في مربّع الرئيسية — تنزل إليه صفحة الأخبار وتبرزه لحظة (طلب المالك)
    @State private var focusNewsId: UUID?
    @State private var highlightedNewsId: UUID?

    private enum HomeSubPage: Hashable {
        case archive, projects, contact, news
    }

    /// الصفحة الفرعية المفتوحة — تُدفع كوجهة تنقّل حقيقية لتأخذ حركة iOS الأصلية
    @State private var activeSubPage: HomeSubPage? = nil

    /// مقاييس التخطيط المتجاوبة — تتكيّف مع عرض الجهاز الفعلي + size class
    private var layout: DS.Layout.Metrics {
        let w = contentWidth > 0 ? contentWidth : UIScreen.main.bounds.width
        return DS.Layout.metrics(width: w, isRegularWidth: hSizeClass == .regular)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                Group {
                    // Main home content — Bento Grid
                    VStack(spacing: 0) {
                        homeHeader

                        ScrollView(showsIndicators: false) {
                            bentoSection
                                // الرسوم خلف مربّع الخبر المفتوح تتوقّف (لا تُثقل الكتابة والنشر)
                                .environment(\.ftAnimationsPaused, showingAddNews || postToEdit != nil)
                                // البطاقات تتوالى مرة عند الظهور (الترحيب ← المربّعات ← الأخبار) —
                                // إزاحة وشفافية عند الرسم فقط، فلا يتغيّر القياس ولا التخطيط
                                .padding(.top, DS.Spacing.md)
                                .padding(.bottom, DS.Spacing.xxxxl)
                                .dsTabBarClearance()   // أفقياً فوق شريط التبويبات العائم
                                .onAppear {
                                    guard !appeared else { return }
                                    appeared = true
                                }
                        }
                        // القياس خارج التمرير: كان GeometryReader داخل ScrollView يقيس
                        // المحتوى الذي تحدّده مقاساتُه نفسها، فتنشأ حلقة إعادة قياس
                        // تجعل الشاشة تتحرك. الآن يقيس عرض الحاوية الثابت مرة واحدة.
                        .background(
                            GeometryReader { proxy in
                                SwiftUI.Color.clear
                                    .preference(key: HomeWidthKey.self, value: proxy.size.width)
                            }
                        )
                        .onPreferenceChange(HomeWidthKey.self) { newWidth in
                            // تجاهل التغيّرات الدقيقة حتى لا تُعاد الحسابات بلا داعٍ
                            if abs(newWidth - contentWidth) > 1 { contentWidth = newWidth }
                        }
                        // بلا ارتداد مطّاطي عند السحب باليد (متاح من iOS 16.4)
                        .modifier(NoBounceIfAvailable())
                        .refreshable {
                            await refreshNews(notifyIfNew: true, force: true)
                            await newDots.refresh(userId: authVM.currentUser?.id, force: true)
                        }
                    }
                }
            }
            // isPresented بدل مسار مُنمّط: المكدّس نفسه يحوي روابط بأنواع أخرى
            // (مركز الإشعارات) والمسار المُنمّط يتعارض معها.
            .navigationDestination(
                isPresented: Binding(
                    get: { activeSubPage != nil },
                    set: { if !$0 { activeSubPage = nil } }
                )
            ) {
                if let page = activeSubPage {
                    // هوية مرتبطة بالصفحة — بدونها يعيد SwiftUI استخدام الوجهة
                    // المبنيّة سابقاً فيفتح قسماً غير الذي ضُغط عليه
                    subPageContent(for: page)
                        .id(page)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            // بلا أنيميشن على تبديل الصفحات الفرعية
            .onChange(of: newsSearchText) { newValue in
                newsSearchTask?.cancel()
                if newValue.isEmpty {
                    debouncedNewsSearch = ""
                } else {
                    newsSearchTask = Task {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        if !Task.isCancelled { debouncedNewsSearch = newValue }
                    }
                }
            }
            .onChange(of: debouncedNewsSearch) { value in
                Task { await newsVM.setNewsFilter(search: value, type: selectedNewsTypeFilter) }
            }
            .onChange(of: selectedNewsTypeFilter) { value in
                Task { await newsVM.setNewsFilter(search: debouncedNewsSearch, type: value) }
            }
            .onChange(of: activeSubPage) { value in
                if value != .news {
                    newsSearchText = ""
                    selectedNewsTypeFilter = nil
                    Task { await newsVM.setNewsFilter(search: "", type: nil) }
                }
            }
            .dsAlert(L10n.t("تنبيه الأخبار", "News Alert"), isPresented: $showNewNewsAlert) {
                Button(L10n.t("حسناً", "OK")) {}
            } message: { Text(L10n.t("تمت إضافة \(newNewsCount) خبر جديد.", "\(newNewsCount) new post(s) added.")) }

        }
        .onChange(of: selectedTab) { _ in
            if selectedTab != 0, activeSubPage != nil {
                activeSubPage = nil
            }
            // الرجوع للرئيسية — فحص الجديد (مرة كل دقيقة على الأكثر)
            if selectedTab == 0 { Task { await newDots.refresh(userId: authVM.currentUser?.id) } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReselectTab)) { notification in
            if let tab = notification.userInfo?["tab"] as? Int, tab == 0, activeSubPage != nil {
                activeSubPage = nil
            }
        }
        // Deep-link من push خارجي لطلب انضمام — يفتح مركز الإشعارات تلقائياً
        .onReceive(NotificationCenter.default.publisher(for: .openHomeNotificationsCenter)) { _ in
            if activeSubPage != nil { activeSubPage = nil }
            showingContactForm = false   // مربّع التواصل مفتوح؟ يُغلق حتى يظهر مركز الإشعارات
            showingNotifications = true
        }
        // Safety net — لو الـ event وصل قبل ما الـ view يكون mounted
        .onChange(of: notificationVM.pendingJoinDeepLinkRequestId) { newValue in
            guard newValue != nil else { return }
            if activeSubPage != nil { activeSubPage = nil }
            showingContactForm = false
            showingNotifications = true
        }
        // مركز الإشعارات (رابط push) — المربّع الطويل الموحّد من الأسفل بدل ورقة النظام
        .dsTallBox(isPresented: $showingNotifications) {
            NavigationStack {
                NotificationsCenterView()
            }
        }
        // التواصل مع الإدارة — مربّع بمنتصف الشاشة لا صفحة فرعية (طلب المالك)
        .dsCenterBox(isPresented: $showingContactForm) {
            MemberContactFormView()
        }
        .task {
            await newDots.refresh(userId: authVM.currentUser?.id)
        }
        .task {
            // جلب المشاريع لعرض البطاقة الفاخرة بأحدث مشروع (مع كاش داخلي)
            if (appSettingsVM.settings.projectsEnabled ?? true), projectsVM.projects.isEmpty {
                await projectsVM.fetchProjects()
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Sub-page Content
    @ViewBuilder
    private func subPageContent(for page: HomeSubPage) -> some View {
        VStack(spacing: 0) {
            subPageHeader(for: page)
            switch page {
            case .archive: FamilyArchiveView()
            case .projects: FamilyProjectsView()
            case .contact: MemberContactFormView()
            case .news: newsFullPage.dsSectionPage(.news)   // بلون قسم الأخبار مثل إضافة/تعديل الخبر والتعليقات
            }
        }
        // جلسات الاستخدام: الصفحة تُحسب باسمها ما دامت ظاهرة («التواصل» يُحسب للرئيسية)
        .appUsageScreen(usageScreen(for: page))
    }

    private func usageScreen(for page: HomeSubPage) -> AppUsageScreen? {
        switch page {
        case .archive: return .library
        case .projects: return .projects
        case .news: return .news
        case .contact: return nil
        }
    }

    // صفحة الأخبار الكاملة (تظهر عند الضغط على مربع الأخبار)
    private var newsFullPage: some View {
        ZStack {
            VStack(spacing: 0) {
                // شريط التصنيفات والبحث أُزيل (طلب المالك) — القائمة مباشرة
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        newsFeedSection
                            .padding(.top, DS.Spacing.sm)
                            .padding(.bottom, DS.Spacing.xxxxl)
                                .dsTabBarClearance()   // أفقياً فوق شريط التبويبات العائم
                            // بطاقات الأخبار تتوالى مع دخول الصفحة (نمط الأخبار والديوانيات)
                            .onAppear {
                                newsAppeared = true
                                scrollToFocusedNews(proxy)
                            }
                    }
                    .refreshable {
                            await refreshNews(notifyIfNew: true, force: true)
                            await newDots.refresh(userId: authVM.currentUser?.id, force: true)
                        }
                    .onChange(of: focusNewsId) { _ in scrollToFocusedNews(proxy) }
                }
            }

            if authVM.currentUser?.role != .pending {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        DSFloatingButton(icon: "plus", color: DS.Color.primary) {
                            showingAddNews = true
                        }
                        .accessibilityLabel(L10n.t("إضافة خبر", "Add Post"))
                        .padding(.trailing, DS.Spacing.xl)
                        .padding(.bottom, DS.Spacing.lg)
                    }
                }
            }
        }
        // الأوراق والتنبيهات مربوطة بصفحة الأخبار نفسها — كانت على الرئيسية خلف
        // الصفحة المدفوعة فلا تظهر إلا بعد الخروج من القسم
        // الإضافة مربّع بمنتصف الشاشة لا ورقة سفلية (طلب المالك)
        .fullScreenCover(isPresented: $showingAddNews) {
            DSCenterPanel(onBackgroundTap: nil, hugsContent: true) {
                AddNewsView()
            }
            .background(ClearPresentationBackground())
        }
        .transaction { t in
            if showingAddNews { t.disablesAnimations = true }
        }
        // التعليقات نصف الشاشة من الأسفل بزر إغلاق أعلاه (طلب المالك ٢٠٢٦-١٠-٠١)
        .dsHalfBox(item: $selectedNewsForComments) { news in
            NewsCommentsSheet(news: news)
        }
        .dsCenterBox(item: $postToEdit) { news in
            EditNewsView(news: news)
        }
        .dsAlert(L10n.t("حذف الخبر", "Delete Post"), isPresented: Binding(
            get: { postToDelete != nil },
            set: { if !$0 { postToDelete = nil } }
        )) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                if let post = postToDelete { Task { await newsVM.deleteNewsPost(postId: post.id) } }
                postToDelete = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { postToDelete = nil }
        } message: { Text(L10n.t("حذف هذا الخبر؟", "Delete this post?")) }
        .dsAlert(L10n.t("إبلاغ عن الخبر", "Report Post"), isPresented: Binding(
            get: { postToReport != nil },
            set: { if !$0 { postToReport = nil } }
        )) {
            TextField(L10n.t("سبب الإبلاغ (اختياري)", "Reason (optional)"), text: $newsReportReason)
                .dsAlertField()
            Button(L10n.t("إبلاغ", "Report"), role: .destructive) {
                let reason = newsReportReason.trimmingCharacters(in: .whitespacesAndNewlines)
                if let post = postToReport {
                    Task {
                        let ok = await newsVM.reportNewsPost(
                            postId: post.id,
                            reason: reason.isEmpty ? "بلاغ على محتوى خبر" : reason
                        )
                        if ok { await MainActor.run { newsReportSent = true } }
                    }
                }
                postToReport = nil
                newsReportReason = ""
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { postToReport = nil; newsReportReason = "" }
        } message: { Text(L10n.t("اكتب سبب الإبلاغ، وسيتم إرساله للإدارة لمراجعة هذا الخبر.",
                                "Enter a reason; it will be sent to the admins to review this post.")) }
        .dsAlert(L10n.t("تم الإبلاغ", "Reported"), isPresented: $newsReportSent) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(L10n.t("شكراً لك، وصل بلاغك للإدارة وستتم مراجعته خلال ٢٤ ساعة.",
                        "Thank you — your report reached the admins and will be reviewed within 24 hours."))
        }
        // حظر ناشر الخبر — نفس رسائل «إبلاغ» (بلاغ تلقائي للإدارة)
        .dsBlockMemberFlow(target: $blockTarget)
        .fullScreenCover(item: $selectedMemberForDetails) { member in
            MemberDetailsView(member: member, centered: true)
                .background(ClearPresentationBackground())
        }
        .transaction { t in
            // يظهر المربّع في مكانه بلا انزلاق — والإغلاق بلا انزلاق يتم داخل المربّع
            if selectedMemberForDetails != nil { t.disablesAnimations = true }
        }
    }

    // MARK: - Sub-page Header
    /// رأس الصفحة الفرعية = الرأس الموحّد `DSSubPageHeader` (مكان واحد لكل الأقسام — طلب المالك ٢٠٢٦-١٠-٠٧):
    /// بلون قسم الصفحة (طلب المالك ٢٠٢٦-١٠-٠٥ «خل الرأس بلون القسم»): المكتبة · المشاريع · التواصل · الأخبار
    private func subPageHeader(for page: HomeSubPage) -> some View {
        let title: String = {
            switch page {
            case .archive: return L10n.t("مكتبة العائلة", "Family Library")
            case .projects: return L10n.t("مشاريع العائلة", "Family Projects")
            case .contact: return L10n.t("التواصل", "Contact")
            case .news: return L10n.t("الأخبار والمناسبات", "News & Events")
            }
        }()

        // سطر توضيحي تحت اسم القسم
        let subtitle: String? = {
            switch page {
            case .archive:  return L10n.t("أرشيف ووثائق العائلة", "Family archive & documents")
            case .projects: return L10n.t("مبادرات ومشاريع الأعضاء", "Member initiatives & projects")
            case .contact:  return L10n.t("اكتب رسالتك ويصلك الرد بأقرب وقت",
                                          "Write your message — you'll get a reply soon")
            case .news:     return L10n.t("آخر أخبار العائلة ومناسباتها", "Latest family news & events")
            }
        }()

        let sec: AppSection = page == .archive ? .library : page == .projects ? .projects : page == .contact ? .admin : .news

        // الرجوع مكان أيقونة القسم (طلب المالك) — بلا علامة ×، بنفس زر الرجوع الموحّد
        return DSSubPageHeader(title: title, subtitle: subtitle, section: sec, onBack: { activeSubPage = nil }) {
            // التحديد المتعدّد انتقل للهيدر — للإدارة فقط (المكتبة والمشاريع)
            if authVM.isAdmin && (page == .archive || page == .projects) {
                DSHeaderButton(symbol: "checkmark.circle", label: L10n.t("تحديد متعدّد", "Multi-select"),
                               compact: isLandscape) {
                    NotificationCenter.default.post(name: .subPageStartSelection,
                                                    object: nil,
                                                    userInfo: ["page": page == .archive ? "archive" : "projects"])
                }
            }
        }
    }

    // MARK: - Bento Section — الترتيب الجديد
    //
    // 1) ترحيب     2) الشجرة + الديوانيات
    // 3) وصول سريع: المكتبة / المشاريع / التواصل     4) الأخبار والمناسبات
    //
    // كل بطاقة بنية View مستقلة في ملفها — يبقى نوع هذه الصفحة ضحلاً
    // (تضخّمه سابقاً أسقط التطبيق بطفح مكدس عند الإقلاع).
    private var bentoSection: some View {
        Group {
            if isLandscape {
                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    VStack(spacing: DS.Spacing.sm) {
                        greetingRow
                        primaryTilesRow(tileHeight: max(DS.Landscape.homeTileMinHeight, layout.tileHeight - DS.Landscape.homeTileTrim))
                        quickAccessGrid(tileHeight: max(DS.Landscape.homeTileMinHeight, layout.tileHeight - DS.Landscape.homeTileTrim))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    newsBentoCard
                        .frame(maxWidth: max(DS.Landscape.homeNewsMinWidth, UIScreen.main.bounds.width * DS.Landscape.homeNewsShare), alignment: .top)
                }
            } else {
                // فراغات أقل بين المربّعات (طلب المالك)
                VStack(spacing: DS.Spacing.sm) {
                    greetingRow
                    primaryTilesRow(tileHeight: layout.tileHeight + 12)
                    quickAccessGrid(tileHeight: layout.tileHeight + 6)
                    newsBentoCard
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        // حد أقصى للعرض على الأجهزة الواسعة (iPad) حتى لا تتمدد الكروت بشكل مبالغ
        .frame(maxWidth: hSizeClass == .regular ? 700 : .infinity)
        .frame(maxWidth: .infinity)
        .animation(DS.Anim.smooth, value: layout)
    }

    /// المسافة بين المربّعات — أضيق من شبكة التخطيط العامة
    private var tileSpacing: CGFloat { min(layout.gridSpacing, 6) }

    private var greetingRow: some View {
        HomeGreetingRow(onOpenProfile: { selectedTab = 3 }, onLongPress: debugLongPress)
            // أول البطاقات دخولاً
            .dsCardCascade(0, appeared: appeared)
    }

    // MARK: - Primary Tiles Row — الشجرة + الديوانيات
    /// صف علوي: مربّع الشجرة + مربّع الديوانيات بنفس ستايل التايل الموحّد،
    /// وأطول قليلاً ليكونا عنصري الوصول الأساسيين. الديوانيات تختفي إن عُطّلت.
    private func primaryTilesRow(tileHeight: CGFloat) -> some View {
        HStack(spacing: tileSpacing) {
            unifiedTile(
                title: L10n.t("شجرة المحمدعلي", "Al-Mohammad Ali family tree"),   // سطر واحد (طلب المالك ٢٠٢٦-١٠-٠٧)
                icon: "tree.fill",
                color: DS.Color.tileTree,
                deep: DS.Color.tileTreeDeep,
                imageURL: nil,
                count: nil,
                height: tileHeight,
                cascade: 1,
                action: { selectedTab = 1 }
            )
            if appSettingsVM.settings.diwaniyasEnabled ?? true {
                unifiedTile(
                    title: L10n.t("الديوانيات", "Diwaniyas"),
                    icon: AppSection.diwaniyas.symbol,   // «مجلس» الموحّد
                    color: DS.Color.tileDiwaniya,
                    deep: DS.Color.tileDiwaniyaDeep,
                    imageURL: nil,
                    count: nil,
                    height: tileHeight,
                    cascade: 2,
                    isNew: newDots.hasNew(.diwaniyas),
                    action: { selectedTab = 2 }
                )
            }
        }
    }

    // MARK: - Quick Access — الأقسام التي لا تبويب لها
    /// المكتبة / المشاريع / التواصل — المشاريع تختفي إن عُطّلت من الإعدادات.
    private func quickAccessGrid(tileHeight: CGFloat) -> some View {
        let projectsOn = appSettingsVM.settings.projectsEnabled ?? true
        let projectImageURL: String? = projectsVM.projects.first?.logoUrl

        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: tileSpacing),
                count: projectsOn ? 3 : 2
            ),
            spacing: tileSpacing
        ) {
            unifiedTile(
                title: L10n.t("مكتبة العائلة", "Family Library"),
                icon: "books.vertical.fill",
                color: AppSection.HomeTile.library.fill,
                deep: AppSection.HomeTile.library.deep,
                imageURL: nil,
                count: nil,
                height: tileHeight,
                cascade: 3,
                isNew: newDots.hasNew(.library),
                action: { activeSubPage = .archive }
            )
            if projectsOn {
                unifiedTile(
                    title: L10n.t("مشاريع العائلة", "Family Projects"),
                    icon: "storefront.fill",
                    color: AppSection.HomeTile.projects.fill,
                    deep: AppSection.HomeTile.projects.deep,
                    imageURL: projectImageURL,
                    count: projectsVM.projects.count,
                    height: tileHeight,
                    cascade: 4,
                    isNew: newDots.hasNew(.projects),
                    action: { activeSubPage = .projects }
                )
            }
            unifiedTile(
                title: L10n.t("التواصل", "Contact"),
                icon: "envelope.fill",
                color: DS.Color.tileContact,
                deep: DS.Color.tileContactDeep,
                imageURL: nil,
                count: nil,
                height: tileHeight,
                cascade: 5,
                action: { showingContactForm = true }
            )
        }
    }

    /// بطاقة وصول سريع بارتفاع موحد وصغير حتى تبقى الشبكة خفيفة.
    private func unifiedTile(
        title: String,
        icon: String,
        color: Color,
        deep: Color,
        imageURL: String?,
        count: Int?,
        height: CGFloat? = nil,
        /// ترتيب المربّع في دخول الرئيسية (بعد الترحيب ٠، وقبل الأخبار ٦)
        cascade: Int,
        /// فيه جديد لم يُفتح بعد — نقطة صفراء في زاوية المربّع
        isNew: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            ZStack(alignment: .bottomLeading) {
                tileBackground(color: color, deep: deep, imageURL: imageURL, icon: icon,
                               badge: (count ?? 0) > 0)

                // تعتيم أسفل المربّع للاسم الأبيض — «الهادئ الفاتح» بلا تعتيم (الاسم داكن فوق اللون الخفيف)
                if !DS.Theme.isCalm {
                LinearGradient(
                    stops: [
                        .init(color: DS.Color.overlayFillSubtle, location: 0),
                        .init(color: .clear, location: 0.32),
                        // الهوية (main): غلالة كحلية أسفل المربّع بدل الأسود
                        .init(color: DS.Color.navyDeep.opacity(0.46), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                }

                // «مجسّمات» — تكوين بالوسط (طلب المالك ٢٠٢٦-١٠-٠٥ «بالنص بشكل مرتب و ابداعي»):
                // المجسّم في وسط المربّع وتحته الاسم، ضوء ناعم خلفه ونسخة شفافة منه في الخلفية، بلا عدد
                if let place = FTArtPlace.place(for: icon),
                   let centerArt = FT5STrial.tileIcon(place, variant: FTArtVariants.value(for: place)) {
                    // ضلع المجسّم يتبع ارتفاع المربّع: أكبر في الصفّ الأول، ويترك سطرين للاسم
                    TrialCenteredTile(art: centerArt, title: title, count: count, scale: layout.scale,
                                      artSide: 46 * layout.scale,   // حجم واحد لكل المجسّمات في المربّعات الخمسة (طلب المالك ٢٠٢٦-١٠-٠٧)
                                      stagger: Double(cascade), entrance: !HomeTileEntrance.played)
                        .onAppear {
                            // الظهور الأول مرة لكل تشغيل — بعده المجسّمات تظهر مباشرة
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { HomeTileEntrance.played = true }
                        }
                        .id("tc-\(icon)")
                } else {
                    // أيقونة دائرية زجاجية + عدّاد (مربّعات بلا مكان مرسوم)
                    VStack {
                        HStack {
                            Image(dsSymbol: icon)
                                .dsGlyph(DS.Glyph.lgCompact)
                                .foregroundColor(DS.Color.textOnPrimary)
                                .frame(width: DS.Icon.rowLarge * layout.scale, height: DS.Icon.rowLarge * layout.scale)
                                .dsGlass(Circle())
                                .overlay(Circle().strokeBorder(DS.Color.overlayIconBorder, lineWidth: DS.Border.width))
                                .dsSubtleShadow()

                            Spacer()

                            if let count, count > 0 {
                                Text("\(count)")
                                    .dsFont(.badge)
                                    .foregroundColor(DS.Color.textOnPrimary)
                                    .padding(.horizontal, DS.Spacing.xsm)
                                    .padding(.vertical, DS.Spacing.xxs)
                                    .dsGlass(Capsule())
                                    .overlay(Capsule().strokeBorder(DS.Color.overlayIconBorder, lineWidth: DS.Border.width))
                            }
                        }
                        Spacer()
                    }
                    .padding(DS.Spacing.sm)

                    // العنوان أسفل — سطر واحد لضمان تساوي الأحجام
                    Text(title)
                        .dsFont(.rowTitleCompact)
                        .foregroundColor(DS.Color.tileTitle)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .shadow(color: DS.Theme.isCalm ? DS.Color.tileTitleShadow : DS.Color.hierarchicalSecondary, radius: 3, x: 0, y: 1)
                        .padding(DS.Spacing.sm)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height ?? layout.tileHeight)
            // منطقة اللمس = حدود المربّع المرئية بالضبط
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(DS.Color.tileStroke, lineWidth: DS.Border.width)
            )
            // الظلّ من شكل المربّع تحته — نفس الظلّ (المربّع مقصوص معتم)، يُرسم مرة بدل كل إطار (فحص «اللاق»)
            .dsCardShadow(in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            // جديد لم يُفتح — النقطة الصفراء في زاوية البداية
            .overlay(alignment: .topLeading) {
                if isNew {
                    DSNewDot()
                        .padding(DS.Spacing.sm + 2)
                }
            }
            .animation(DS.Anim.snappy, value: isNew)
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(isNew ? L10n.t("فيه جديد", "New") : "")
        // المربّعات تتوالى واحداً بعد الآخر مع بقية بطاقات الرئيسية
        .dsCardCascade(cascade, appeared: appeared)
    }

    /// خلفية المربّع — صورة من رابط أو gradient بلون الفئة مع زخارف.
    @ViewBuilder
    private func tileBackground(color: Color, deep: Color, imageURL: String?, icon: String,
                                badge: Bool = false) -> some View {
        if let urlStr = imageURL, let url = URL(string: urlStr) {
            CachedAsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                gradientBackground(color: color, deep: deep, icon: icon, badge: badge)
            }
        } else {
            gradientBackground(color: color, deep: deep, icon: icon, badge: badge)
        }
    }

    private func gradientBackground(color: Color, deep: Color, icon: String, badge: Bool = false) -> some View {
        ZStack {
            if DS.Theme.isCalm {
                // «الهادئ الفاتح»: لون القسم الخفيف بدل التدرّج الغامق — المجسّم والنسخة الشفافة كما هما
                color.dsCalmTint
            } else {
            LinearGradient(
                colors: [color.opacity(0.92), color, deep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            }
            // «مجسّمات»: نفس مجسّم المربّع كبير شفاف في خلفيته عند الطرف
            // (طلب المالك ٢٠٢٦-١٠-٠٥ «حط خلفيات ور الايقونات بنفس المجسمات بس شفافة بالرئيسية»)
            if let place = FTArtPlace.place(for: icon),
               let ghost = FT5STrial.tileIcon(place, variant: FTArtVariants.value(for: place)) {
                ghost
                    .frame(width: 86 * layout.scale, height: 86 * layout.scale)
                    .opacity(FT5STrial.ghostOpacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 16, y: 12)
                    .id("tw-\(icon)")
            }
        }
        .clipped()
    }

    // MARK: - الهيدر — نفس MainHeaderView المستخدم في بقية التبويبات
#if DEBUG
    /// معاينة شاشتي التسجيل والانتظار من داخل التطبيق (ضغطة مطوّلة على الترحيب).
    @State private var previewAuthScreens = false
    @State private var previewAuthStep = 0

    private var debugLongPress: (() -> Void)? {
        {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            previewAuthScreens = true
        }
    }

    private var debugAuthPreview: some View {
        ZStack(alignment: .top) {
            if previewAuthStep == 0 {
                RegistrationView(topInset: 46)
            } else {
                WaitingForApprovalView()
            }

            HStack(spacing: DS.Spacing.sm) {
                Button {
                    previewAuthScreens = false
                    previewAuthStep = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dsGlyph(DS.Glyph.xxl, weight: .regular)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(DS.Color.textOnPrimary, DS.Color.shadowHeavy)
                }
                Text(L10n.t("شاشة معاينة", "Preview"))
                    .dsFont(.badge)
                    .foregroundColor(DS.Color.textSecondary)

                // نفس مبدّل الأقسام الموحّد بدل مبدّل النظام
                DSSegmentedSwitch(options: [
                    DSSegmentOption(id: 0, title: L10n.t("البيانات", "Profile"), icon: "person.text.rectangle"),
                    DSSegmentOption(id: 1, title: L10n.t("الانتظار", "Waiting"), icon: "hourglass")
                ], selection: $previewAuthStep, size: .regular)
                .frame(maxWidth: 240)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .dsGlass(Capsule())
            .overlay(Capsule().strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke), lineWidth: DS.Border.width))
            .dsCardShadow()
            .padding(.top, DS.Spacing.xxxxl * 3)
        }
    }
#else
    private var debugLongPress: (() -> Void)? { nil }
#endif

    private var homeHeader: some View {
        // الجرس بشكله الأصلي (HomeBellButton) بدل جرس الهيدر الموحّد
        let header = MainHeaderView(
            selectedTab: $selectedTab,
            showingNotifications: $showingNotifications,
            title: L10n.t("عائلة المحمدعلي", "Al-Mohammad Ali"),
            subtitle: L10n.t("تطبيق العائلة", "Family App"),
            icon: "tree.fill",
            section: .home,
            hideNotificationBell: true
        ) {
            // الجرس ثم علامة «عن التطبيق» بعده (طلب المالك)
            HStack(spacing: 0) {
                HomeBellButton()
                HomeInfoButton()
            }
        }
#if DEBUG
        return header.fullScreenCover(isPresented: $previewAuthScreens) { debugAuthPreview }
#else
        return header
#endif
    }

    /// مربع الأخبار — بنية مستقلة (HomeNewsPreviewCard) وليست جسماً داخل هذه
    /// الصفحة، حتى يبقى عمق نوع الواجهة منخفضاً.
    private var newsBentoCard: some View {
        HomeNewsPreviewCard(
            onTap: { openNewsPage() },
            onOpenNews: { id in
                focusNewsId = id
                openNewsPage()
            }
        )
        // آخر بطاقات الرئيسية دخولاً
        .dsCardCascade(6, appeared: appeared)
    }

    private func openNewsPage() {
        // تصفير دخول بطاقات الصفحة قبل فتحها (الصفحة غير ظاهرة بعد) — فتتوالى مع كل فتح
        if activeSubPage != .news { newsAppeared = false }
        activeSubPage = .news
        newDots.markSeen(.news)
    }

    /// ينزل للخبر المختار من مربّع الرئيسية بعد دخول البطاقات، ويبرزه لحظة
    private func scrollToFocusedNews(_ proxy: ScrollViewProxy) {
        guard let id = focusNewsId else { return }
        focusNewsId = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(DS.Anim.smooth) { proxy.scrollTo(id, anchor: .top) }
            withAnimation(.easeOut(duration: 0.25)) { highlightedNewsId = id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeOut(duration: 0.6)) {
                    if highlightedNewsId == id { highlightedNewsId = nil }
                }
            }
        }
    }

    /// إطار يبرز الخبر المفتوح من الرئيسية
    private func focusOutline(for news: NewsPost) -> some View {
        RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
            .strokeBorder(DS.Color.primary, lineWidth: DS.Border.widthBold)
            .opacity(highlightedNewsId == news.id ? 1 : 0)
            .allowsHitTesting(false)
    }

    // MARK: - News Feed Section
    private var newsFeedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = newsVM.newsLoadError {
                // بطاقة الحالة الموحّدة (خطأ + إعادة المحاولة)
                DSStateCard(icon: "exclamationmark.triangle.fill", title: error, tint: DS.Color.error,
                            actionTitle: L10n.t("إعادة المحاولة", "Try again"),
                            action: { Task { await newsVM.fetchNews(force: true) } })
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
                .dsCardCascade(0, appeared: newsAppeared)
            }
            if newsVM.isLoadingNews && newsVM.allNews.isEmpty {
                // التحميل الموحّد: مجسّم الأخبار يتنفّس
                DSPageLoader(section: .news, fillsSpace: false)
                    .padding(.vertical, DS.Spacing.xxxxl)
                    .transition(.opacity)
            } else if filteredNews.isEmpty {
                if newsVM.newsLoadError == nil {
                    if !debouncedNewsSearch.isEmpty {
                        DSEmptyView(L10n.t("لا توجد نتائج لهذا البحث", "No results for this search"),
                                    section: .news, style: .inline)
                    } else if selectedNewsTypeFilter != nil {
                        DSEmptyView(L10n.t("لا منشورات من هذا النوع", "No posts of this type"),
                                    section: .news, style: .inline)
                    } else {
                        emptyNewsView
                    }
                }
            } else {
                newsListView
                    .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if newsVM.hasMoreNews && !newsVM.allNews.isEmpty {
                // الزرّ الموحّد (ثانوي رمادي) — الدوّارة الصغيرة داخله أثناء التحميل
                DSButton(L10n.t("تحميل أخبار أقدم", "Load older news"), role: .cancel,
                         isLoading: newsVM.isLoadingMoreNews) {
                    Task { await newsVM.loadMoreNews() }
                }
                .disabled(newsVM.isLoadingMoreNews || newsVM.isLoadingNews)
                .padding(.horizontal, DS.Spacing.lg)
                // يترك مكان زرّ الإضافة العائم في طرفه — كان الزرّ العائم فوق «تحميل أخبار أقدم» (فحص ٢٠٢٦-١٠-٠٨)
                .padding(.trailing, authVM.currentUser?.role != .pending
                         ? DS.Icon.floatingButton + DS.Spacing.xl - DS.Spacing.sm : 0)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.background)
            }
        }
        .animation(DS.Anim.medium, value: newsVM.isLoadingNews)
        .animation(DS.Anim.smooth, value: filteredNews.isEmpty)
    }

    /// الأخبار بلا منشورات من حظرهم المستخدم (منشور الإدارة بلا كاتب لا يُخفى)
    private var filteredNews: [NewsPost] {
        guard !blockedStore.entries.isEmpty else { return newsVM.allNews }
        return newsVM.allNews.filter { !isFromBlockedAuthor($0) }
    }

    private func isFromBlockedAuthor(_ news: NewsPost) -> Bool {
        guard let authorId = news.author_id else { return false }
        return blockedStore.isBlocked(id: authorId, name: news.author_name)
    }

    /// عدد التعليقات الظاهرة — عدد السيرفر ناقص تعليقات المحظورين المعروفة (إن حُمّلت)
    private func visibleCommentCount(for news: NewsPost) -> Int {
        let serverCount = newsVM.commentsCountByPost[news.id] ?? 0
        guard !blockedStore.entries.isEmpty, let loaded = newsVM.commentsByPost[news.id] else { return serverCount }
        let hidden = loaded.filter { blockedStore.isBlocked(id: $0.author_id, name: $0.author_name) }.count
        return max(0, serverCount - hidden)
    }

    /// حظر ناشر الخبر — لغير منشوراتي ولغير منشورات الإدارة بلا كاتب
    private func canBlockAuthor(of news: NewsPost) -> Bool {
        guard let authorId = news.author_id else { return false }
        return !AccountIdentity.isMine(authorId, currentUser: authVM.currentUser)
            && !AccountIdentity.isMine(news.ownerId, currentUser: authVM.currentUser)
    }


    private var newsListView: some View {
        Group {
            if isLandscape {
                // الوضع الأفقي: عمودان من بطاقات الأخبار لاستغلال العرض
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: DS.Landscape.columnMinWidth), spacing: DS.Spacing.lg, alignment: .top)],
                    alignment: .center,
                    spacing: DS.Spacing.lg
                ) {
                    ForEach(Array(filteredNews.enumerated()), id: \.element.id) { index, news in
                        newsCard(for: news)
                            .newsSwipeActions(
                                        id: news.id,
                                        canDelete: canDelete(news),
                                        // الإبلاغ لغير صاحب الخبر (سياسة Apple)
                                        canReport: authVM.currentUser?.id != news.ownerId,
                                        onDelete: { postToDelete = news },
                                        onReport: { postToReport = news }
                                    )
                            .overlay(focusOutline(for: news))
                            .dsCardCascade(index, appeared: newsAppeared)
                    }
                }
            } else {
                // قائمة واحدة بلا عناوين «اليوم / أمس / … / أقدم» ولا عدّاد (طلب المالك)
                LazyVStack(spacing: DS.Spacing.md) {
                    ForEach(Array(filteredNews.enumerated()), id: \.element.id) { index, news in
                        newsCard(for: news)
                            .newsSwipeActions(
                                id: news.id,
                                canDelete: canDelete(news),
                                // الإبلاغ لغير صاحب الخبر (سياسة Apple)
                                canReport: authVM.currentUser?.id != news.ownerId,
                                onDelete: { postToDelete = news },
                                onReport: { postToReport = news }
                            )
                            .overlay(focusOutline(for: news))
                            // أول ٧ بطاقات تتوالى مع دخول الصفحة، وما يُبنى بالتمرير يظهر مباشرة
                            .dsCardCascade(index, appeared: newsAppeared)
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.top, DS.Spacing.sm)
    }


    private func roleColorFor(_ roleColor: String?) -> Color {
        switch roleColor {
        case "purple": return DS.Color.adminRole
        case "orange": return DS.Color.supervisorRole
        case "blue":   return DS.Color.primary
        case "green":  return DS.Color.monitorRole
        default:       return DS.Color.primary
        }
    }

    /// الحذف للإدارة (مدير/مراقب) أو لصاحب الخبر فقط
    private func canDelete(_ news: NewsPost) -> Bool {
        authVM.canDeleteNews || (news.ownerId != nil && authVM.currentUser?.id == news.ownerId)
    }

    private func newsCard(for news: NewsPost) -> some View {
        HomeNewsCardView(
            postId: news.id,
            authorName: news.author_name,
            authorId: news.author_id,
            role: news.author_role,
            roleColor: roleColorFor(news.role_color),
            time: getRelativeTime(for: news.timestamp),
            type: news.type,
            content: news.content,
            imageUrl: news.image_url,
            imageUrls: news.mediaURLs,
            pollQuestion: news.poll_question,
            pollOptions: news.poll_options ?? [],
            pollVotes: newsVM.pollVotesByPost[news.id] ?? [:],
            selectedPollOption: newsVM.userVoteByPost[news.id],
            approvalStatus: news.approval_status,
            commentCount: visibleCommentCount(for: news),
            likeCount: newsVM.likesCountByPost[news.id] ?? 0,
            isLiked: newsVM.likedPosts.contains(news.id),
            onCommentTap: { selectedNewsForComments = news },
            onLikeTap: { toggleLike(for: news.id) },
            onVoteTap: { optionIndex in
                Task { await newsVM.submitNewsPollVote(postId: news.id, optionIndex: optionIndex) }
            },
            canDelete: canDelete(news),
            // الإبلاغ متاح للجميع (أعضاء وإدارة) لغير منشوراتهم — سياسة Apple
            canReport: authVM.currentUser?.id != news.author_id,
            canEdit: authVM.canDeleteNews || authVM.currentUser?.id == news.author_id,
            onDeleteTap: { postToDelete = news },
            onReportTap: { postToReport = news },
            onEditTap: { postToEdit = news },
            onMemberTap: { member in selectedMemberForDetails = member },
            postDate: news.timestamp,
            // حظر الناشر بجانب «إبلاغ» (Guideline 1.2)
            canBlock: canBlockAuthor(of: news),
            onBlockTap: {
                if let authorId = news.author_id {
                    blockTarget = BlockTarget(id: authorId, name: news.author_name)
                }
            }
        )
    }

    // MARK: - Empty State
    private var emptyNewsView: some View {
        // الحالة الفارغة الموحّدة: مجسّم الأخبار + عنوان (+ زرّ الإضافة لغير المعلّق)
        let canAdd = authVM.currentUser?.role != .pending
        return DSEmptyView(L10n.t("لا توجد أخبار حديثة", "No recent news"), section: .news,
                           actionTitle: canAdd ? L10n.t("أضف أول خبر", "Add First Post") : nil,
                           actionIcon: "plus.circle.fill",
                           action: canAdd ? { showingAddNews = true } : nil)
            .padding(.top, DS.Spacing.sm)
            // الحالة الفارغة تدخل مثل البطاقات
            .dsCardCascade(0, appeared: newsAppeared)
    }

    // MARK: - Helpers
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    func getRelativeTime(for date: Date) -> String {
        Self.relativeFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func toggleLike(for postId: UUID) {
        Task { await newsVM.toggleNewsLike(for: postId) }
    }

    @MainActor
    private func refreshNews(notifyIfNew: Bool, force: Bool = false) async {
        // تجنب التحديث المتكرر خلال 10 ثواني
        if !force, let last = lastRefreshDate, Date().timeIntervalSince(last) < 10 { return }
        lastRefreshDate = Date()
        
        let previousIDs = Set(newsVM.allNews.map(\.id))
        
        // تحميل الأخبار والأعضاء بالتوازي إذا لزم
        if memberVM.allMembers.isEmpty {
            async let news: () = newsVM.fetchNews(force: true)
            async let members: () = memberVM.fetchAllMembers(force: true)
            _ = await (news, members)
        } else {
            await newsVM.fetchNews(force: true)
        }
        
        guard notifyIfNew, !previousIDs.isEmpty else { return }
        let count = Set(newsVM.allNews.map(\.id)).subtracting(previousIDs).count
        if count > 0 { newNewsCount = count; showNewNewsAlert = true }
    }
}

extension HomeNewsView {
    init(selectedTab: Binding<Int>) { self._selectedTab = selectedTab }
}

// MARK: - مفتاح التقاط عرض الرئيسية (للتخطيط المتجاوب)
private struct HomeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - أيقونة الهيدر — Glass circle
private struct NoBounceIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.scrollBounceBehavior(.basedOnSize)
        } else {
            content
        }
    }
}

/// تفتّح مشاهد مربّعات الرئيسية مرة واحدة لكل تشغيل (لا يتكرر مع كل رجوع للرئيسية)
enum HomeTileEntrance {
    static var played = false
}
