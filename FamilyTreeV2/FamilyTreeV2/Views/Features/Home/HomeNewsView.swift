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
    /// إزاحة السحب التفاعلي للرجوع — الصفحة تتبع الإصبع
    @State private var backDragOffset: CGFloat = 0

    @Binding var selectedTab: Int
    @State private var showingAddNews = false
    @State private var showingNotifications = false
    @State private var selectedNewsForComments: NewsPost? = nil
    @State private var postToDelete: NewsPost? = nil
    @State private var postToReport: NewsPost? = nil
    @State private var newsReportReason = ""
    @State private var postToEdit: NewsPost? = nil
    @State private var showNewNewsAlert = false
    @State private var newNewsCount = 0
    @State private var selectedMemberForDetails: FamilyMember? = nil
    @State private var lastRefreshDate: Date? = nil
    /// فلتر نوع الخبر في صفحة الأخبار — nil يعني الكل
    @State private var selectedNewsTypeFilter: String? = nil
    @State private var showNewsSearch = false
    @State private var newsSearchText = ""
    @State private var debouncedNewsSearch = ""
    @State private var newsSearchTask: Task<Void, Never>?

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
                                // بلا أنيميشن ظهور — المحتوى يثبت مكانه بلا انزلاق
                                .padding(.top, DS.Spacing.md)
                                .padding(.bottom, isLandscape ? DS.Spacing.xxxxl + 44 : DS.Spacing.xxxxl)
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
                        .refreshable { await refreshNews(notifyIfNew: true, force: true) }
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
                    subPageContent(for: page)
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
            .sheet(isPresented: $showingAddNews) {
                AddNewsView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedNewsForComments) { news in
                NewsCommentsSheet(news: news)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $postToEdit) { news in
                EditNewsView(news: news)
                    .presentationDetents([.fraction(0.5), .medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert(L10n.t("حذف الخبر", "Delete Post"), isPresented: Binding(
                get: { postToDelete != nil },
                set: { if !$0 { postToDelete = nil } }
            )) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    if let post = postToDelete { Task { await newsVM.deleteNewsPost(postId: post.id) } }
                    postToDelete = nil
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { postToDelete = nil }
            } message: { Text(L10n.t("حذف هذا الخبر؟", "Delete this post?")) }
            .alert(L10n.t("إبلاغ عن الخبر", "Report Post"), isPresented: Binding(
                get: { postToReport != nil },
                set: { if !$0 { postToReport = nil } }
            )) {
                TextField(L10n.t("سبب الإبلاغ (اختياري)", "Reason (optional)"), text: $newsReportReason)
                Button(L10n.t("إبلاغ", "Report"), role: .destructive) {
                    let reason = newsReportReason.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let post = postToReport {
                        Task {
                            await newsVM.reportNewsPost(
                                postId: post.id,
                                reason: reason.isEmpty ? "بلاغ على محتوى خبر" : reason
                            )
                        }
                    }
                    postToReport = nil
                    newsReportReason = ""
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { postToReport = nil; newsReportReason = "" }
            } message: { Text(L10n.t("اكتب سبب الإبلاغ، وسيتم إرساله للإدارة لمراجعة هذا الخبر.",
                                    "Enter a reason; it will be sent to the admins to review this post.")) }
            .alert(L10n.t("تنبيه الأخبار", "News Alert"), isPresented: $showNewNewsAlert) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: { Text(L10n.t("تمت إضافة \(newNewsCount) خبر جديد.", "\(newNewsCount) new post(s) added.")) }

            .sheet(item: $selectedMemberForDetails) { member in
                NavigationStack {
                    MemberDetailsView(member: member)
                }
                .presentationDetents([.fraction(0.42), .large])
                .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: selectedTab) { _ in
            if selectedTab != 0, activeSubPage != nil {
                activeSubPage = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReselectTab)) { notification in
            if let tab = notification.userInfo?["tab"] as? Int, tab == 0, activeSubPage != nil {
                activeSubPage = nil
            }
        }
        // Deep-link من push خارجي لطلب انضمام — يفتح مركز الإشعارات تلقائياً
        .onReceive(NotificationCenter.default.publisher(for: .openHomeNotificationsCenter)) { _ in
            if activeSubPage != nil { activeSubPage = nil }
            showingNotifications = true
        }
        // Safety net — لو الـ event وصل قبل ما الـ view يكون mounted
        .onChange(of: notificationVM.pendingJoinDeepLinkRequestId) { newValue in
            guard newValue != nil else { return }
            if activeSubPage != nil { activeSubPage = nil }
            showingNotifications = true
        }
        .sheet(isPresented: $showingNotifications) {
            NavigationStack {
                NotificationsCenterView()
            }
            .presentationDragIndicator(.visible)
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
            case .news: newsFullPage
            }
        }
    }

    // صفحة الأخبار الكاملة (تظهر عند الضغط على مربع الأخبار)
    private var newsFullPage: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                newsTypeFilterBar
                    // مسافة أوضح بين الهيدر وشريط الفلاتر
                    .padding(.top, DS.Spacing.md)
                newsFeedSection
                    // أول منشور أقرب للفلاتر
                    .padding(.top, 0)
                    .padding(.bottom, isLandscape ? DS.Spacing.xxxxl + 44 : DS.Spacing.xxxxl)
            }
            .refreshable { await refreshNews(notifyIfNew: true, force: true) }

            if authVM.currentUser?.role != .pending {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        DSFloatingButton(label: L10n.t("إضافة خبر", "Add Post"), color: DS.Color.primary) {
                            showingAddNews = true
                        }
                        .padding(.trailing, DS.Spacing.xl)
                        .padding(.bottom, DS.Spacing.lg)
                    }
                }
            }
        }
    }

    // MARK: - Sub-page Header
    private func subPageHeader(for page: HomeSubPage) -> some View {
        let title: String = {
            switch page {
            case .archive: return L10n.t("مكتبة العائلة", "Family Library")
            case .projects: return L10n.t("مشاريع العائلة", "Family Projects")
            case .contact: return L10n.t("التواصل", "Contact")
            case .news: return L10n.t("الأخبار والمناسبات", "News & Events")
            }
        }()

        let icon: String = {
            switch page {
            case .archive:  return "books.vertical.fill"
            case .projects: return "briefcase.fill"
            case .contact:  return "envelope.fill"
            case .news:     return "newspaper.fill"
            }
        }()

        return VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.md) {
                // أيقونة القسم — بنفس مقاس أيقونة الرئيسية والشجرة تماماً (هوية فقط)
                ZStack {
                    Circle()
                        .fill(DS.Color.overlayIcon)
                        .overlay(Circle().strokeBorder(DS.Color.overlayIconBorder, lineWidth: 1.5))
                    Image(systemName: icon)
                        .font(DS.Font.scaled(isLandscape ? 16 : 20, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                }
                .frame(width: isLandscape ? 38 : 52, height: isLandscape ? 38 : 52)

                Text(title)
                    .font(DS.Font.plex(19, weight: .bold))
                    .foregroundColor(DS.Color.textOnPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: DS.Spacing.xs)

                // الرجوع في الطرف المقابل — نفس موضع الجرس في الرئيسية
                Button {
                    activeSubPage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(DS.Font.scaled(isLandscape ? 15 : 17, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(width: isLandscape ? 36 : 44, height: isLandscape ? 36 : 44)
                        .background(Circle().fill(DS.Color.overlayIcon))
                        .overlay(Circle().strokeBorder(DS.Color.overlayIconBorder, lineWidth: 1.5))
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityLabel(L10n.t("رجوع", "Back"))
            }
            .padding(.horizontal, isLandscape ? DS.Spacing.xxl : DS.Spacing.lg)
            .padding(.bottom, isLandscape ? DS.Spacing.xs : DS.Spacing.sm)
            .padding(.top, isLandscape ? DS.Spacing.xs : 0)
            .frame(minHeight: isLandscape ? 46 : 70, alignment: .bottom)

            // شريط سدو زخرفي — يحلّ محل الخط الفاصل بلا زيادة ارتفاع تُذكر
            saduStrip
        }
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                DS.Color.gradientPrimary
                // نفس طبقة MainHeaderView — بدونها يطلع الهيدر أفتح
                DS.Color.headerVeil
            }
            .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Bento Grid Section — توزيع عائلي احترافي
    private var bentoSection: some View {
        Group {
            if isLandscape {
                // الوضع الأفقي: عمودان — يسار (ترحيب + كل المربعات) ويمين (الأخبار)
                // الوضع الأفقي: عمود الوصول السريع (ترحيب مضغوط + بلاطات) وعمود الأخبار
                // عمودان متساويان بارتفاع طبيعي — بلا ارتفاع مفروض حتى لا يُقتطع
                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    VStack(spacing: DS.Spacing.sm) {
                        greetingCard
                            .frame(height: 92)      // لا تتمدد لتطابق طول البلاطات
                        landscapeTilesGrid
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    // عمود الأخبار أضيق — البلاطات تأخذ المساحة الأوسع (طلب المالك)
                    newsBentoCard
                        .frame(maxWidth: max(230, UIScreen.main.bounds.width * 0.29), alignment: .top)
                }
            } else {
                VStack(spacing: DS.Spacing.sm) {
                    // 1) Hero ترحيب (يفتح حسابي عند الضغط)
                    greetingCard

                    // 2) الشجرة + الديوانيات — مربعين بنفس ستايل التايل
                    primaryTilesRow

                    // 3) شبكة الوصول السريع — أرشيف / مشاريع / تواصل (تحت الشجرة والديوانيات، فوق الأخبار)
                    quickAccessGrid

                    // 4) آخر الأخبار
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

    // MARK: - Primary Tiles Row — الشجرة + الديوانيات

    /// صف علوي: مربّع الشجرة + مربّع الديوانيات — بنفس ستايل التايل الموحّد،
    /// وبارتفاع أكبر قليلاً ليكونا عنصري الوصول الأساسيين.
    private var primaryTilesRow: some View {
        HStack(spacing: layout.gridSpacing) {
            unifiedTile(
                title: L10n.t("شجرة\nالمحمدعلي", "Al-Mohammad Ali\nFamily Tree"),
                icon: "tree.fill",
                color: DS.Color.tileTree,
                imageURL: nil,
                count: nil,
                height: primaryTileHeight,
                action: { selectedTab = 1 }
            )
            unifiedTile(
                title: L10n.t("الديوانيات", "Diwaniyas"),
                icon: "map.fill",
                color: DS.Color.tileDiwaniya,
                imageURL: nil,
                count: nil,
                height: primaryTileHeight,
                action: { selectedTab = 2 }
            )
        }
    }

    /// ارتفاع المربّعين العلويين — أطول قليلاً من تايلات الوصول السريع.
    private var primaryTileHeight: CGFloat { layout.tileHeight + 6 }

    // MARK: - Quick Access Grid — أرشيف / مشاريع / تواصل

    /// صف من 3 مربعات موحّدة: أرشيف العائلة / مشاريع العائلة / التواصل
    /// — كلها بنفس التصميم وأحجام متطابقة.
    private var quickAccessGrid: some View {
        let projectImageURL: String? = projectsVM.projects.first?.logoUrl

        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: layout.gridSpacing),
                count: 3
            ),
            spacing: layout.gridSpacing
        ) {
            unifiedTile(
                title: L10n.t("مكتبة العائلة", "Family Library"),
                icon: "books.vertical.fill",
                color: DS.Color.tileLibrary,
                imageURL: nil,
                count: nil,
                action: { activeSubPage = .archive }
            )
            unifiedTile(
                title: L10n.t("مشاريع العائلة", "Family Projects"),
                icon: "briefcase.fill",
                color: DS.Color.tileProjects,
                imageURL: projectImageURL,
                count: projectsVM.projects.count,
                action: { activeSubPage = .projects }
            )
            unifiedTile(
                title: L10n.t("التواصل", "Contact"),
                icon: "envelope.fill",
                color: DS.Color.tileContact,
                imageURL: nil,
                count: nil,
                action: { activeSubPage = .contact }
            )
        }
    }

    // MARK: - شبكة المربعات في الوضع الأفقي
    /// الوضع الأفقي: كل المربعات الخمسة في شبكة تكيّفية واحدة بارتفاع أقصر
    /// حتى لا يضيع الارتفاع القصير للشاشة.
    /// ارتفاع قسم الأفقي: ترحيب (92) + صفّا بلاطات + الفواصل.
    private var landscapeBentoHeight: CGFloat {
        let tileH = max(66, layout.tileHeight - 18)
        return 92 + DS.Spacing.sm + tileH * 2 + layout.gridSpacing + DS.Spacing.sm
    }

    private var landscapeTilesGrid: some View {
        let projectImageURL: String? = projectsVM.projects.first?.logoUrl
        let tileHeight = max(66, layout.tileHeight - 18)

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: layout.gridSpacing), count: 3),
            spacing: layout.gridSpacing
        ) {
            unifiedTile(
                title: L10n.t("شجرة\nالمحمدعلي", "Al-Mohammad Ali\nFamily Tree"),
                icon: "tree.fill",
                color: DS.Color.tileTree,
                imageURL: nil,
                count: nil,
                height: tileHeight,
                action: { selectedTab = 1 }
            )
            unifiedTile(
                title: L10n.t("الديوانيات", "Diwaniyas"),
                icon: "map.fill",
                color: DS.Color.tileDiwaniya,
                imageURL: nil,
                count: nil,
                height: tileHeight,
                action: { selectedTab = 2 }
            )
            unifiedTile(
                title: L10n.t("مكتبة العائلة", "Family Library"),
                icon: "books.vertical.fill",
                color: DS.Color.tileLibrary,
                imageURL: nil,
                count: nil,
                height: tileHeight,
                action: { activeSubPage = .archive }
            )
            unifiedTile(
                title: L10n.t("مشاريع العائلة", "Family Projects"),
                icon: "briefcase.fill",
                color: DS.Color.tileProjects,
                imageURL: projectImageURL,
                count: projectsVM.projects.count,
                height: tileHeight,
                action: { activeSubPage = .projects }
            )
            unifiedTile(
                title: L10n.t("التواصل", "Contact"),
                icon: "envelope.fill",
                color: DS.Color.tileContact,
                imageURL: nil,
                count: nil,
                height: tileHeight,
                action: { activeSubPage = .contact }
            )
        }
    }

    /// بطاقة وصول سريع بارتفاع موحد وصغير حتى تبقى الشبكة خفيفة.
    private func unifiedTile(
        title: String,
        icon: String,
        color: Color,
        imageURL: String?,
        count: Int?,
        height: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            ZStack(alignment: .bottomLeading) {
                tileBackground(color: color, imageURL: imageURL, icon: icon)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.06), .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // أيقونة دائرية أكبر + عدّاد
                VStack {
                    HStack {
                        Image(systemName: icon)
                            .font(DS.Font.scaled(15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36 * layout.scale, height: 36 * layout.scale)
                            .background(Circle().fill(.ultraThinMaterial))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.30), lineWidth: 1))
                            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)

                        Spacer()

                        if let count, count > 0 {
                            Text("\(count)")
                                .font(DS.Font.scaled(11, weight: .black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.ultraThinMaterial))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.30), lineWidth: 1))
                        }
                    }
                    Spacer()
                }
                .padding(9)

                // العنوان أسفل — سطر واحد لضمان تساوي الأحجام
                Text(title)
                    .font(DS.Font.scaled(13, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                    .padding(8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height ?? layout.tileHeight)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.07), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(title)
    }

    /// خلفية المربّع — صورة من رابط أو gradient بلون الفئة مع زخارف.
    @ViewBuilder
    private func tileBackground(color: Color, imageURL: String?, icon: String) -> some View {
        if let urlStr = imageURL, let url = URL(string: urlStr) {
            CachedAsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                gradientBackground(color: color, icon: icon)
            }
        } else {
            gradientBackground(color: color, icon: icon)
        }
    }

    private func gradientBackground(color: Color, icon: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [color, color.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // زخرفة خفيفة — مقيّدة في صندوق ثابت ومثبّتة أسفل-يمين حتى
            // تبقى في نفس المكان لكل الأيقونات مهما اختلف ارتفاع الرمز
            // (مثلاً tree.fill الطويلة كانت تطلع فوق مقارنةً بـ map.fill)
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 78, height: 78)
                .foregroundColor(.white.opacity(0.13))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 16, y: 12)
        }
        .clipped()
    }

    // MARK: - Legacy (لم يعد مستخدماً بعد توحيد الشبكة)
    @available(*, deprecated, message: "Replaced by quickAccessGrid")
    private var familyProjectsCard: some View {
        let approvedProjects = projectsVM.projects
        let featured = approvedProjects.first
        let total = approvedProjects.count

        return Button {
            activeSubPage = .projects
        } label: {
            ZStack(alignment: .bottomLeading) {
                // ── خلفية: صورة المشروع المميَّز أو gradient ──
                projectsBackground(featured: featured)

                // ── تدرّج داكن للقراءة ──
                LinearGradient(
                    colors: [.clear, .black.opacity(0.10), .black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // ── شارة القسم أعلى ──
                VStack {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "briefcase.fill")
                                .font(DS.Font.scaled(11, weight: .bold))
                            Text(L10n.t("مشاريع العائلة", "Family Projects"))
                                .font(DS.Font.scaled(11, weight: .black))
                                .tracking(0.5)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.30), lineWidth: 1))

                        Spacer()

                        // عدّاد إجمالي
                        if total > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "square.stack.fill")
                                    .font(DS.Font.scaled(11, weight: .bold))
                                Text("\(total)")
                                    .font(DS.Font.scaled(11, weight: .black))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.ultraThinMaterial))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.30), lineWidth: 1))
                        }
                    }
                    Spacer()
                }
                .padding(DS.Spacing.md)

                // ── معلومات أسفل ──
                VStack(alignment: .leading, spacing: 6) {
                    if let p = featured {
                        Text(p.title)
                            .font(DS.Font.scaled(22, weight: .black))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 1)

                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                                .font(DS.Font.scaled(11, weight: .bold))
                            Text(L10n.t("صاحب المشروع: ", "Owner: ") + p.ownerName)
                                .font(DS.Font.scaled(11, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white.opacity(0.95))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.30)))
                    } else {
                        Text(L10n.t("ابدأ مشاريع العائلة",
                                   "Start Family Projects"))
                            .font(DS.Font.scaled(20, weight: .black))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 1)

                        Text(L10n.t("اعرض ما يقدّمه أبناء العائلة",
                                   "Showcase what family members offer"))
                            .font(DS.Font.scaled(12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.90))
                    }
                }
                .padding(DS.Spacing.md)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 5)
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(L10n.t("افتح مشاريع العائلة", "Open Family Projects"))
    }

    /// خلفية البطاقة — صورة شعار المشروع المميَّز أو gradient عند عدم وجود مشاريع.
    @ViewBuilder
    private func projectsBackground(featured: Project?) -> some View {
        if let urlStr = featured?.logoUrl, let url = URL(string: urlStr) {
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                projectsPlaceholderGradient
            }
        } else {
            projectsPlaceholderGradient
        }
    }

    private var projectsPlaceholderGradient: some View {
        ZStack {
            LinearGradient(
                colors: [DS.Color.warning, DS.Color.warning.opacity(0.7), DS.Color.accent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // زخرفة باهتة
            Image(systemName: "briefcase.fill")
                .font(.system(size: 110, weight: .light))
                .foregroundColor(.white.opacity(0.15))
                .offset(x: 90, y: -20)
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(.white.opacity(0.10))
                .offset(x: -90, y: 30)
        }
    }

    // MARK: - Contact Card

    /// بطاقة التواصل المستقلة — full-width أصغر من بطاقة المشاريع، بنمط الـ tile الموحّد.
    private var contactCard: some View {
        Button {
            activeSubPage = .contact
        } label: {
            HStack(spacing: DS.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [DS.Color.info, DS.Color.info.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(DS.Font.scaled(17, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("التواصل مع الإدارة", "Contact Admin"))
                        .font(DS.Font.scaled(15, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                    Text(L10n.t("أرسل سؤالاً أو ملاحظة",
                               "Send a question or remark"))
                        .font(DS.Font.scaled(11, weight: .semibold))
                        .foregroundColor(DS.Color.textSecondary)
                }
                Spacer()
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .font(DS.Font.scaled(12, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(DS.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(DS.Color.info.opacity(0.12), lineWidth: 1)
            )
            .dsSubtleShadow()
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - بطاقة الترحيب «سماء الوقت» — مشهد خفيف يتبدّل مع الساعة، تفتح "حسابي"
    /// شريط سدو زخرفي — معينات صغيرة بين خطين متلاشيين
    private var saduStrip: some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(DS.Color.textOnPrimary.opacity(0.16))
                .frame(height: 1)
            ForEach(0..<5, id: \.self) { i in
                Rectangle()
                    .fill(DS.Color.textOnPrimary.opacity(i == 2 ? 0.55 : 0.30))
                    .frame(width: i == 2 ? 6 : 4, height: i == 2 ? 6 : 4)
                    .rotationEffect(.degrees(45))
            }
            Rectangle()
                .fill(DS.Color.textOnPrimary.opacity(0.16))
                .frame(height: 1)
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.bottom, DS.Spacing.xs)
    }

    // MARK: - هيدر الرئيسية — شعار العائلة + شريط سدو زخرفي (خاص بالرئيسية فقط)
    private var homeHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.md) {
                // ═══ شعار العائلة — مربّع زجاجي بشجرة ═══
                Image("AppIconImage")
                    .resizable()
                    .scaledToFill()
                    .frame(width: isLandscape ? 38 : 52, height: isLandscape ? 38 : 52)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(DS.Color.overlayIconBorder, lineWidth: 1.5))

                // ═══ اسم العائلة ═══
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("عائلة المحمدعلي", "Al-Mohammad Ali"))
                        .font(DS.Font.plex(21, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(L10n.t("تطبيق العائلة", "Family App"))
                        .font(DS.Font.plex(13, weight: .medium))
                        .foregroundColor(DS.Color.overlayText)
                }

                Spacer(minLength: DS.Spacing.sm)

                // ═══ الجرس ═══
                NavigationLink(destination: NotificationsCenterView()) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: notificationVM.unreadNotificationsCount > 0
                              ? "bell.badge.fill" : "bell.fill")
                            .font(DS.Font.scaled(isLandscape ? 15 : 18, weight: .bold))
                            .foregroundColor(DS.Color.textOnPrimary)
                            .frame(width: isLandscape ? 36 : 44, height: isLandscape ? 36 : 44)

                        if notificationVM.unreadNotificationsCount > 0 {
                            Text(notificationVM.unreadNotificationsCount > 99
                                 ? "99+" : "\(notificationVM.unreadNotificationsCount)")
                                .font(DS.Font.scaled(11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(DS.Color.error)
                                .clipShape(Capsule())
                                .offset(x: 6, y: -4)
                        }
                    }
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityLabel(L10n.t("الإشعارات", "Notifications"))
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, isLandscape ? DS.Spacing.xs : DS.Spacing.sm)
            .padding(.top, isLandscape ? DS.Spacing.xs : 0)
            .frame(minHeight: isLandscape ? 46 : 70, alignment: .bottom)

            // الخط الفاصل السفلي — مطابق لبقية الواجهات
            // شريط سدو زخرفي — يحلّ محل الخط الفاصل بلا زيادة ارتفاع تُذكر
            saduStrip
        }
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                DS.Color.gradientPrimary
                // نفس طبقة MainHeaderView — بدونها يطلع الهيدر أفتح
                DS.Color.headerVeil
            }
            .ignoresSafeArea(edges: .top)
        )
    }

    private var greetingCard: some View {
        Button {
            selectedTab = 3
        } label: {
            HStack(alignment: .center, spacing: DS.Spacing.md) {
                // ═══ الصورة في البداية — قوس تقدّم اليوم حولها ═══
                if let user = authVM.currentUser {
                    ZStack {
                        Group {
                            if let urlStr = user.avatarUrl, let url = URL(string: urlStr) {
                                CachedAsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Text(String(user.firstName.prefix(1)))
                                        .font(DS.Font.plex(18, weight: .bold))
                                        .foregroundColor(user.roleColor)
                                }
                            } else {
                                Text(String(user.firstName.prefix(1)))
                                    .font(DS.Font.plex(18, weight: .bold))
                                    .foregroundColor(user.roleColor)
                            }
                        }
                        .frame(width: 50 * layout.scale, height: 50 * layout.scale)
                        .clipShape(Circle())
                        // فسحة بين الصورة والإطار ثم الإطار نفسه
                        .padding(4)
                        .overlay(
                            Circle().strokeBorder(timeAccent.opacity(0.45), lineWidth: 2)
                        )
                    }
                    .frame(width: 58 * layout.scale, height: 58 * layout.scale)
                }

                // ═══ التحية والاسم ═══
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: greetingSymbol)
                            .font(.system(size: 10, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(timeAccent)
                        Text(timeBasedGreeting)
                            .font(DS.Font.plex(12, weight: .medium))
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .fixedSize()
                    Text(greetingName)
                        .font(DS.Font.plex(20, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: DS.Spacing.sm)

                // سهم خفيف — ينعكس تلقائياً مع RTL
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(timeAccent.opacity(0.4))
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            // إطار خفيف جداً يحدّد المربّع بلا ما يثقله
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .strokeBorder(DS.Color.textTertiary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
    }




    /// أيقونة الوقت المرافقة للتحية
    private var greetingSymbol: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "sun.and.horizon.fill" }
        else if hour < 17 { return "sun.max.fill" }
        else { return "moon.stars.fill" }
    }

    /// لون الوقت — فجر أخضر، نهار أزرق، ليل نيلي
    private var timeAccent: Color {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return DS.Color.secondary }
        else if hour < 17 { return DS.Color.primary }
        else { return DS.Color.accent }
    }

    /// الاسم الأول + اسم العائلة (الأخير) — بلا سلسلة النسب الكاملة
    private var greetingName: String {
        guard let user = authVM.currentUser else { return L10n.t("أهلاً بك", "Welcome") }
        let parts = user.fullName
            .trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard let first = parts.first, let last = parts.last, first != last else {
            return user.firstName
        }
        return "\(first) \(last)"
    }

    private var timeBasedGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 {
            return L10n.t("صباح الخير", "GOOD MORNING")
        } else if hour < 17 {
            return L10n.t("مساء الخير", "GOOD AFTERNOON")
        } else {
            return L10n.t("مساء الخير", "GOOD EVENING")
        }
    }

    // MARK: - شريط الإحصائيات السريعة
    private var statsStrip: some View {
        HStack(spacing: DS.Spacing.sm) {
            statChip(
                icon: "person.2.fill",
                value: memberVM.allMembers.count,
                label: L10n.t("فرد", "Members"),
                color: DS.Color.secondary
            )
            statChip(
                icon: "newspaper.fill",
                value: newsVM.allNews.count,
                label: L10n.t("خبر", "News"),
                color: DS.Color.primary
            )
        }
    }

    private func statChip(icon: String, value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(color)
                Text("\(value)")
                    .font(DS.Font.scaled(17, weight: .heavy))
                    .foregroundColor(DS.Color.textPrimary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            Text(label)
                .font(DS.Font.scaled(11, weight: .medium))
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
        }
        .padding(.vertical, DS.Spacing.sm)
        .padding(.horizontal, DS.Spacing.xs)
        .frame(maxWidth: .infinity)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .shadow(color: .black.opacity(0.035), radius: 8, x: 0, y: 2)
    }

    // pill أفقي مدمج للأكشن الثانوي (التواصل / مشاريع العائلة)
    private func actionPill(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.14))
                    .clipShape(Circle())
                Text(title)
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 3)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // مربع الأخبار: هيدر بأيقونة بتدرّج + معاينات بـ avatars + "عرض الكل"
    private var newsBentoCard: some View {
        Button {
            activeSubPage = .news
        } label: {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(alignment: .center, spacing: DS.Spacing.sm) {
                    premiumIcon("newspaper.fill", color: DS.Color.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("الأخبار والمناسبات", "News & Events"))
                            .font(DS.Font.scaled(18, weight: .bold))
                            .foregroundColor(DS.Color.textPrimary)
                        if !newsVM.allNews.isEmpty {
                            Text("\(newsVM.allNews.count) " + L10n.t("منشور", "POSTS"))
                                .font(DS.Font.scaled(11, weight: .heavy))
                                .foregroundColor(DS.Color.textSecondary)
                                .tracking(0.6)
                        }
                    }

                    Spacer()
                }

                if newsVM.isLoading && newsVM.allNews.isEmpty {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(0..<2, id: \.self) { _ in
                            DSSkeletonRow(avatarSize: 40)
                        }
                    }
                    .padding(.vertical, DS.Spacing.sm)
                } else if newsVM.allNews.isEmpty {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "newspaper")
                            .font(DS.Font.scaled(18))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا توجد أخبار بعد", "No news yet"))
                            .font(DS.Font.scaled(13, weight: .medium))
                            .foregroundColor(DS.Color.textSecondary)
                        Spacer()
                    }
                    .padding(.vertical, DS.Spacing.md)
                } else {
                    // عرض مبسّط — نقطة + نص الخبر + الوقت، بلا صور ولا عدّادات
                    VStack(spacing: DS.Spacing.sm + 2) {
                        ForEach(Array(newsVM.allNews.prefix(4))) { news in
                            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                                Circle()
                                    .fill(roleColorFor(news.role_color))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 5)

                                Text(news.content)
                                    .font(DS.Font.plex(13, weight: .medium))
                                    .foregroundColor(DS.Color.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(getRelativeTime(for: news.timestamp))
                                    .font(DS.Font.plex(10))
                                    .foregroundColor(DS.Color.textTertiary)
                                    .lineLimit(1)
                                    .layoutPriority(1)
                            }
                        }
                    }
                }

                if newsVM.allNews.count > 3 {
                    HStack {
                        Spacer()
                        Text(L10n.t("عرض المزيد", "Show more"))
                            .font(DS.Font.scaled(13, weight: .bold))
                            .foregroundColor(DS.Color.primary)
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .background(DS.Color.primary.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(DS.Color.primary.opacity(0.20), lineWidth: 1)
                            )
                        Spacer()
                    }
                    .padding(.top, DS.Spacing.sm)
                }
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    DS.Color.surface
                    Circle()
                        .fill(DS.Color.primary.opacity(0.09))
                        .frame(width: 220, height: 220)
                        .blur(radius: 60)
                        .offset(x: 130, y: -90)
                    Circle()
                        .fill(DS.Color.secondary.opacity(0.07))
                        .frame(width: 160, height: 160)
                        .blur(radius: 50)
                        .offset(x: -70, y: 130)
                    Circle()
                        .fill(DS.Color.primary.opacity(0.13))
                        .frame(width: 130, height: 130)
                        .blur(radius: 38)
                        .offset(x: -100, y: -70)
                    Circle()
                        .fill(DS.Color.secondary.opacity(0.09))
                        .frame(width: 90, height: 90)
                        .blur(radius: 30)
                        .offset(x: -30, y: -60)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            .shadow(color: .black.opacity(0.045), radius: 14, x: 0, y: 4)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // صف معاينة خبر — avatar للمؤلف + نص الخبر + اسم/وقت + تفاعلات + صورة مصغّرة
    private func newsPreviewRow(for news: NewsPost) -> some View {
        let member = news.author_id.flatMap { memberVM.member(byId: $0) }
        // منشور بهوية الإدارة: الاسم المحفوظ هو الصحيح — لا يُستبدل باسم العضو
        let isAdminIdentity = news.author_name == L10n.t("إدارة العائلة", "Family Admin")
            || news.author_name == "إدارة العائلة"
        let displayName = isAdminIdentity ? news.author_name
                                          : (member?.fourPartName ?? news.author_name)
        let roleC = roleColorFor(news.role_color)
        let likes = newsVM.likesCountByPost[news.id] ?? 0
        let comments = newsVM.commentsCountByPost[news.id] ?? 0
        let thumbURL = news.mediaURLs.first.flatMap { URL(string: $0) }
        return HStack(alignment: .top, spacing: DS.Spacing.sm) {
            if isAdminIdentity {
                ZStack {
                    Circle().fill(DS.Color.gradientPrimary)
                    Image(systemName: "megaphone.fill")
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(DS.Color.headerBorder, lineWidth: 1))
            } else {
                DSMemberAvatar(
                    name: news.author_name,
                    avatarUrl: member?.avatarUrl,
                    size: 32,
                    roleColor: roleC
                )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(news.content)
                    .font(DS.Font.scaled(13, weight: .medium))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    Text(displayName)
                        .font(DS.Font.scaled(11, weight: isAdminIdentity ? .bold : .medium))
                        .foregroundColor(isAdminIdentity ? DS.Color.primary : DS.Color.textSecondary)
                        .lineLimit(1)
                    Text("•")
                        .font(DS.Font.scaled(11))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(getRelativeTime(for: news.timestamp))
                        .font(DS.Font.scaled(11))
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)

                    if news.hasPoll {
                        previewMetaChip(icon: "chart.bar.fill", value: nil)
                    }
                    if likes > 0 {
                        previewMetaChip(icon: "heart.fill", value: likes)
                    }
                    if comments > 0 {
                        previewMetaChip(icon: "bubble.left.fill", value: comments)
                    }
                }
            }

            Spacer(minLength: 0)

            if let thumbURL {
                CachedAsyncImage(url: thumbURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    DS.Color.mutedBackground
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            }
        }
    }

    /// شريحة بيانات صغيرة في معاينة الخبر (تفاعل/تصويت)
    private func previewMetaChip(icon: String, value: Int?) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(DS.Font.scaled(11, weight: .bold))
            if let value {
                Text("\(value)")
                    .font(DS.Font.scaled(11, weight: .bold))
            }
        }
        .foregroundColor(DS.Color.textTertiary)
    }

    // MARK: - بطاقة الإدارة (Bento) — للمراقبين فقط
    private struct AdminActivityItem: Identifiable {
        let id: UUID
        let icon: String
        let color: Color
        let title: String
        let subtitle: String
        let date: Date
    }

    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func parseISO(_ str: String?) -> Date? {
        guard let s = str, !s.isEmpty else { return nil }
        return Self.isoFormatter.date(from: s) ?? Self.isoFormatterNoFrac.date(from: s)
    }

    private var adminPendingTotalCount: Int {
        adminRequestVM.deceasedRequests.count
            + adminRequestVM.childAddRequests.count
            + adminRequestVM.phoneChangeRequests.count
            + adminRequestVM.newsReportRequests.count
            + adminRequestVM.treeEditRequests.count
            + adminRequestVM.nameChangeRequests.count
            + adminRequestVM.photoSuggestionRequests.count
            + newsVM.pendingNewsRequests.count
            + memberVM.allMembers.filter { $0.role == .pending }.count
    }

    private var newMembersTodayCount: Int {
        let cal = Calendar.current
        let today = Date()
        return memberVM.allMembers.filter { m in
            guard let d = parseISO(m.createdAt) else { return false }
            return cal.isDate(d, inSameDayAs: today)
        }.count
    }

    private var recentAdminActivity: [AdminActivityItem] {
        var items: [AdminActivityItem] = []
        for m in memberVM.allMembers where m.role == .pending {
            if let d = parseISO(m.createdAt) {
                items.append(.init(id: m.id, icon: "person.badge.plus", color: DS.Color.success,
                    title: L10n.t("تسجيل جديد", "New registration"),
                    subtitle: m.fullName, date: d))
            }
        }
        for r in adminRequestVM.deceasedRequests {
            if let d = parseISO(r.createdAt) {
                items.append(.init(id: r.id, icon: "heart.slash.fill", color: DS.Color.error,
                    title: L10n.t("طلب وفاة", "Death request"),
                    subtitle: r.member?.fullName ?? "", date: d))
            }
        }
        for r in adminRequestVM.childAddRequests {
            if let d = parseISO(r.createdAt) {
                items.append(.init(id: r.id, icon: "person.2.fill", color: DS.Color.accent,
                    title: L10n.t("طلب إضافة ابن", "Add child request"),
                    subtitle: r.member?.fullName ?? "", date: d))
            }
        }
        for n in newsVM.pendingNewsRequests {
            items.append(.init(id: n.id, icon: "newspaper.fill", color: DS.Color.primary,
                title: L10n.t("خبر بانتظار الموافقة", "News pending"),
                subtitle: n.author_name, date: n.timestamp))
        }
        return Array(items.sorted { $0.date > $1.date }.prefix(3))
    }

    /// بطاقة Bento كبيرة للوحة الإدارة — تتبع نفس نمط familyTreeCard/newsBentoCard
    private var adminBentoCard: some View {
        Button {
            selectedTab = 4
        } label: {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                // الهيدر
                HStack(alignment: .center, spacing: DS.Spacing.sm) {
                    premiumIcon("shield.lefthalf.filled", color: DS.Color.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("لوحة الإدارة", "Admin Panel"))
                            .font(DS.Font.scaled(18, weight: .bold))
                            .foregroundColor(DS.Color.textPrimary)
                        Text(L10n.t("نظرة سريعة على الطلبات والنشاط", "Quick overview"))
                            .font(DS.Font.scaled(11, weight: .heavy))
                            .foregroundColor(DS.Color.textSecondary)
                            .tracking(0.6)
                    }

                    Spacer()
                }

                // 3 شارات إحصائية
                HStack(spacing: DS.Spacing.sm) {
                    adminMiniStat(
                        icon: "tray.full.fill",
                        value: adminPendingTotalCount,
                        label: L10n.t("طلب", "Pending"),
                        color: DS.Color.warning
                    )
                    adminMiniStat(
                        icon: "person.badge.plus",
                        value: newMembersTodayCount,
                        label: L10n.t("جديد اليوم", "New Today"),
                        color: DS.Color.success
                    )
                    adminMiniStat(
                        icon: "newspaper.fill",
                        value: newsVM.pendingNewsRequests.count,
                        label: L10n.t("خبر", "News"),
                        color: DS.Color.primary
                    )
                }

                // بانر تحذيري — فقط لو فيه طلبات معلّقة
                if adminPendingTotalCount > 0 {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(DS.Font.scaled(13, weight: .bold))
                            .foregroundColor(DS.Color.warning)
                        Text(L10n.t(
                            "عندك \(adminPendingTotalCount) طلب ينتظر مراجعتك",
                            "\(adminPendingTotalCount) requests awaiting review"
                        ))
                        .font(DS.Font.scaled(12, weight: .semibold))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.warning.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .strokeBorder(DS.Color.warning.opacity(0.20), lineWidth: 1)
                    )
                }

                // آخر النشاط الإداري
                if !recentAdminActivity.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(recentAdminActivity.enumerated()), id: \.element.id) { index, item in
                            adminActivityRow(item)
                                .padding(.vertical, DS.Spacing.sm)
                            if index < recentAdminActivity.count - 1 {
                                Rectangle()
                                    .fill(DS.Color.textTertiary.opacity(0.10))
                                    .frame(height: 0.5)
                            }
                        }
                    }
                }

                // CTA pill
                HStack {
                    Spacer()
                    Text(L10n.t("الانتقال للوحة الإدارة", "Open Admin Dashboard"))
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(DS.Color.accent)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(DS.Color.accent.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(DS.Color.accent.opacity(0.20), lineWidth: 1)
                        )
                    Spacer()
                }
                .padding(.top, DS.Spacing.xs)
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    DS.Color.surface
                    Circle()
                        .fill(DS.Color.accent.opacity(0.10))
                        .frame(width: 220, height: 220)
                        .blur(radius: 60)
                        .offset(x: 130, y: -90)
                    Circle()
                        .fill(DS.Color.warning.opacity(0.06))
                        .frame(width: 150, height: 150)
                        .blur(radius: 48)
                        .offset(x: -80, y: 120)
                    Circle()
                        .fill(DS.Color.accent.opacity(0.13))
                        .frame(width: 120, height: 120)
                        .blur(radius: 36)
                        .offset(x: -100, y: -60)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl))
            .shadow(color: .black.opacity(0.045), radius: 14, x: 0, y: 4)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    private func adminMiniStat(icon: String, value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(color)
                Text("\(value)")
                    .font(DS.Font.scaled(17, weight: .heavy))
                    .foregroundColor(DS.Color.textPrimary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            Text(label)
                .font(DS.Font.scaled(11, weight: .medium))
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
        }
        .padding(.vertical, DS.Spacing.sm)
        .padding(.horizontal, DS.Spacing.xs)
        .frame(maxWidth: .infinity)
        .background(DS.Color.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private func adminActivityRow(_ item: AdminActivityItem) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            ZStack {
                Circle().fill(item.color.opacity(0.15)).frame(width: 32, height: 32)
                Image(systemName: item.icon)
                    .font(DS.Font.scaled(12, weight: .semibold))
                    .foregroundColor(item.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(DS.Font.scaled(12, weight: .semibold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(DS.Font.scaled(11, weight: .medium))
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DS.Spacing.sm)

            Text(getRelativeTime(for: item.date))
                .font(DS.Font.scaled(11))
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1)
        }
    }

    // مربع Bento مدمج أفقي — أيقونة جنب النص + إطار ودائرة زخرفية
    private func bentoTile(icon: String, title: String, subtitle: String?, color: Color, height: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(14, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.14))
                    .clipShape(Circle())

                Text(title)
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .background(
                ZStack {
                    DS.Color.surface
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 110, height: 110)
                        .blur(radius: 40)
                        .offset(x: 60, y: -15)
                    Circle()
                        .fill(color.opacity(0.13))
                        .frame(width: 70, height: 70)
                        .blur(radius: 26)
                        .offset(x: -50, y: -15)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .shadow(color: .black.opacity(0.035), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // أيقونة دائرية بتدرّج خفيف + لمسة highlight
    private func premiumIcon(_ icon: String, color: Color, size: CGFloat = 48) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.22), color.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(color.opacity(0.15), lineWidth: 0.5)
                )

            Image(systemName: icon)
                .font(DS.Font.scaled(size * 0.42, weight: .bold))
                .foregroundColor(color)
        }
    }

    // MARK: - News Feed Section
    private var newsFeedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // البحث صار داخل كبسولة الفلتر أعلى الصفحة — بلا حقل مكرّر هنا
            if newsVM.isLoading && newsVM.allNews.isEmpty {
                newsLoadingSkeleton(count: 3)
                    .padding(.horizontal, DS.Spacing.lg)
                    .transition(.opacity)
            } else if newsVM.allNews.isEmpty {
                emptyNewsView
            } else if filteredNews.isEmpty && debouncedNewsSearch.isEmpty {
                // فلتر نوع بلا نتائج (نادر — النوع اختفى بعد حذف)
                VStack(spacing: DS.Spacing.md) {
                    Spacer().frame(height: DS.Spacing.xxxl)
                    Image(systemName: "tray")
                        .font(DS.Font.scaled(36))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(L10n.t("لا منشورات من هذا النوع", "No posts of this type"))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textSecondary)
                }
                .transition(.opacity)
            } else if !debouncedNewsSearch.isEmpty && filteredNews.isEmpty {
                VStack(spacing: DS.Spacing.md) {
                    Spacer().frame(height: DS.Spacing.xxxl)
                    Image(systemName: "magnifyingglass")
                        .font(DS.Font.scaled(36))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(L10n.t("لا توجد نتائج لـ \"\(debouncedNewsSearch)\"", "No results for \"\(debouncedNewsSearch)\""))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .transition(.opacity)
            } else {
                newsListView
                    .transition(.opacity)
            }
        }
        .animation(DS.Anim.medium, value: newsVM.isLoading)
        .animation(DS.Anim.smooth, value: filteredNews.isEmpty)
    }

    /// بطاقة خبر هيكلية (skeleton) — تظهر أثناء التحميل الأول
    private var newsCardSkeleton: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(spacing: DS.Spacing.sm) {
                    DSSkeletonCircle(size: 40)
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        DSSkeleton(width: 120, height: 13)
                        DSSkeleton(width: 70, height: 10)
                    }
                    Spacer()
                }
                DSSkeleton(height: 12)
                DSSkeleton(width: 220, height: 12)
                DSSkeleton(height: 150, cornerRadius: DS.Radius.md)
            }
        }
    }

    private func newsLoadingSkeleton(count: Int) -> some View {
        VStack(spacing: DS.Spacing.md) {
            ForEach(0..<count, id: \.self) { _ in
                newsCardSkeleton
            }
        }
    }

    private var filteredNews: [NewsPost] {
        var list = newsVM.allNews
        if let t = selectedNewsTypeFilter {
            list = list.filter { $0.type == t }
        }
        guard !debouncedNewsSearch.isEmpty else { return list }
        let query = debouncedNewsSearch.lowercased()
        return list.filter {
            $0.content.lowercased().contains(query) ||
            $0.author_name.lowercased().contains(query)
        }
    }

    // MARK: - شريط فلترة الأنواع — «الكل» + الأنواع الموجودة فعلاً في السيل
    private var newsTypeFilterBar: some View {
        let presentTypes = NewsTypeHelper.mainTypes.filter { t in
            newsVM.allNews.contains { $0.type == t }
        }
        return Group {
            if presentTypes.count > 1 || showNewsSearch {
                HStack {
                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        if showNewsSearch {
                            // البحث يفتح داخل نفس كبسولة الفلتر — مثل شريط الشجرة
                            Image(systemName: "magnifyingglass")
                                .font(DS.Font.scaled(13, weight: .bold))
                                .foregroundColor(DS.Color.primary)

                            TextField(L10n.t("ابحث في الأخبار", "Search news"), text: $newsSearchText)
                                .font(DS.Font.subheadline)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .frame(minWidth: 140)

                            Button {
                                withAnimation(.spring(response: 0.40, dampingFraction: 0.78)) {
                                    newsSearchText = ""
                                    showNewsSearch = false
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(DS.Font.scaled(12, weight: .bold))
                                    .foregroundColor(DS.Color.textSecondary)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(DS.Color.textTertiary.opacity(0.12)))
                            }
                            .buttonStyle(DSScaleButtonStyle())
                            .accessibilityLabel(L10n.t("إغلاق البحث", "Close search"))
                        } else {
                            newsTypeChip(nil, label: L10n.t("الكل", "All"),
                                         icon: "square.grid.2x2", color: DS.Color.primary)
                            ForEach(presentTypes, id: \.self) { t in
                                newsTypeChip(t,
                                             label: NewsTypeHelper.displayName(for: t),
                                             icon: NewsTypeHelper.icon(for: t),
                                             color: NewsTypeHelper.color(for: t))
                            }

                            // فاصل ثم زر البحث — داخل نفس الكبسولة
                            Capsule()
                                .fill(DS.Color.textTertiary.opacity(0.25))
                                .frame(width: 1, height: 22)
                                .padding(.horizontal, 2)

                            Button {
                                withAnimation(.spring(response: 0.40, dampingFraction: 0.78)) {
                                    showNewsSearch = true
                                }
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(DS.Font.scaled(13, weight: .bold))
                                    .foregroundColor(DS.Color.primary)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(DS.Color.primary.opacity(0.12)))
                                    .overlay(Circle().strokeBorder(DS.Color.primary.opacity(0.20), lineWidth: 1))
                            }
                            .buttonStyle(DSScaleButtonStyle())
                            .accessibilityLabel(L10n.t("بحث", "Search"))
                        }
                    }
                    .padding(6)
                    .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(DS.Color.primary.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                    .animation(.spring(response: 0.40, dampingFraction: 0.78), value: selectedNewsTypeFilter)
                    .animation(.spring(response: 0.40, dampingFraction: 0.78), value: showNewsSearch)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, 2)
            }
        }
    }

    private func newsTypeChip(_ type: String?, label: String, icon: String, color: Color) -> some View {
        let selected = selectedNewsTypeFilter == type
        return Button {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.78)) { selectedNewsTypeFilter = type }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            // نفس نمط مكتبة العائلة: المختار كبسولة بنص، وغيره أيقونة دائرية
            if selected {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(DS.Font.scaled(12, weight: .bold))
                    Text(label)
                        .font(DS.Font.scaled(13, weight: .bold))
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.85)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                )
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            } else {
                Image(systemName: icon)
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(color.opacity(0.12)))
                    .overlay(Circle().strokeBorder(color.opacity(0.20), lineWidth: 1))
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    private var newsListView: some View {
        Group {
            if isLandscape {
                // الوضع الأفقي: عمودان من بطاقات الأخبار لاستغلال العرض
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 340), spacing: DS.Spacing.lg, alignment: .top)],
                    alignment: .center,
                    spacing: DS.Spacing.lg
                ) {
                    ForEach(filteredNews) { news in
                        newsCard(for: news)
                    }
                }
            } else {
                LazyVStack(spacing: DS.Spacing.lg) {
                    ForEach(filteredNews) { news in
                        newsCard(for: news)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if authVM.canDeleteNews {
                                    Button(role: .destructive) {
                                        postToDelete = news
                                    } label: {
                                        Label(L10n.t("حذف", "Delete"), systemImage: "trash.fill")
                                    }
                                }
                            }
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
        case "green":  return DS.Color.success
        default:       return DS.Color.primary
        }
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
            commentCount: newsVM.commentsCountByPost[news.id] ?? 0,
            likeCount: newsVM.likesCountByPost[news.id] ?? 0,
            isLiked: newsVM.likedPosts.contains(news.id),
            onCommentTap: { selectedNewsForComments = news },
            onLikeTap: { toggleLike(for: news.id) },
            onVoteTap: { optionIndex in
                Task { await newsVM.submitNewsPollVote(postId: news.id, optionIndex: optionIndex) }
            },
            canDelete: authVM.canDeleteNews,
            // الإبلاغ متاح للجميع (أعضاء وإدارة) لغير منشوراتهم — سياسة Apple
            canReport: authVM.currentUser?.id != news.author_id,
            canEdit: authVM.canModerate || authVM.currentUser?.id == news.author_id,
            onDeleteTap: { postToDelete = news },
            onReportTap: { postToReport = news },
            onEditTap: { postToEdit = news },
            onMemberTap: { member in selectedMemberForDetails = member }
        )
    }

    // MARK: - Empty State
    private var emptyNewsView: some View {
        DSCard(padding: 0) {
            VStack(spacing: DS.Spacing.md) {
                Image(systemName: "newspaper")
                    .font(DS.Font.scaled(40))
                    .foregroundColor(DS.Color.textTertiary)

                Text(L10n.t("لا توجد أخبار حديثة", "No recent news"))
                    .font(DS.Font.title3)
                    .foregroundColor(DS.Color.textSecondary)

                if authVM.currentUser?.role != .pending {
                    Button(action: { showingAddNews = true }) {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "plus.circle.fill")
                                .font(DS.Font.scaled(14, weight: .bold))
                            Text(L10n.t("أضف أول خبر", "Add First Post"))
                                .font(DS.Font.caption1)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(DS.Color.primary)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(DS.Color.primary.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(DS.Color.primary.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(DSBoldButtonStyle())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xxxl)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.sm)
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

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func relativeTimeFromISO(_ dateString: String) -> String {
        let date = Self.isoFormatter.date(from: dateString) ?? Date()
        return getRelativeTime(for: date)
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
struct HeaderIconView: View {
    let icon: String
    let color: Color
    var body: some View {
        Image(systemName: icon)
            .font(DS.Font.scaled(16, weight: .bold))
            .foregroundColor(color)
            .frame(width: 44, height: 44)
            .background(color.opacity(0.12))
            .clipShape(Circle())
            .overlay(Circle().stroke(color.opacity(0.15), lineWidth: 1))
    }
}

/// يمنع الارتداد المطّاطي على الأجهزة التي تدعمه، ويتجاهله على iOS 16.0–16.3
private struct NoBounceIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.scrollBounceBehavior(.basedOnSize)
        } else {
            content
        }
    }
}
