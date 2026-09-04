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

    /// الديوانيات تُجلب مرة واحدة هنا وتُمرَّر لبطاقة المستجدات وبطاقة «الليلة»
    @StateObject private var diwaniyasVM = DiwaniyasViewModel()

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
            // الديوانيات لبطاقة المستجدات وبطاقة «الليلة» (بكاش داخلي)
            if (appSettingsVM.settings.diwaniyasEnabled ?? true), diwaniyasVM.diwaniyas.isEmpty {
                await diwaniyasVM.fetchDiwaniyas()
            }
            // تحديث صامت للأخبار عند فتح الرئيسية — بخانق الـ ١٠ ثوانٍ نفسه
            await refreshNews(notifyIfNew: false)
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
            VStack(spacing: 0) {
                // شريط الفلاتر والبحث مثبّت فوق القائمة — يبقى ظاهراً أثناء التمرير
                newsTypeFilterBar
                    .padding(.top, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.xs)

                ScrollView(showsIndicators: false) {
                    newsFeedSection
                        .padding(.top, 0)
                        .padding(.bottom, isLandscape ? DS.Spacing.xxxxl + 44 : DS.Spacing.xxxxl)
                }
                .refreshable { await refreshNews(notifyIfNew: true, force: true) }
            }

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

        // سطر توضيحي تحت اسم القسم
        let subtitle: String? = {
            switch page {
            case .archive:  return L10n.t("وثائق وصور العائلة", "Family documents & photos")
            case .projects: return L10n.t("مبادرات ومشاريع الأعضاء", "Member initiatives & projects")
            case .contact:  return L10n.t("اكتب رسالتك ويصلك الرد بأقرب وقت",
                                          "Write your message — you'll get a reply soon")
            case .news:     return L10n.t("آخر أخبار العائلة ومناسباتها", "Latest family news & events")
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

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.Font.plex(19, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let subtitle {
                        Text(subtitle)
                            .font(DS.Font.plex(12, weight: .medium))
                            .foregroundColor(DS.Color.overlayText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

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

    // MARK: - Bento Section — الترتيب الجديد
    //
    // 1) ترحيب مدمج     2) شريط المستجدات (الرابط مع بقية الأقسام)
    // 3) وصول سريع: المكتبة / المشاريع / التواصل     4) آخر الأخبار (مع آخر مناسبة)
    //
    // كل بطاقة بنية View مستقلة في ملفها — يبقى نوع هذه الصفحة ضحلاً
    // (تضخّمه سابقاً أسقط التطبيق بطفح مكدس عند الإقلاع).
    private var bentoSection: some View {
        Group {
            if isLandscape {
                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    VStack(spacing: DS.Spacing.sm) {
                        greetingRow
                        updatesStrip
                        diwaniyaTonightCard
                        quickAccessGrid(tileHeight: max(66, layout.tileHeight - 18))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    newsBentoCard
                        .frame(maxWidth: max(260, UIScreen.main.bounds.width * 0.36), alignment: .top)
                }
            } else {
                VStack(spacing: DS.Spacing.md) {
                    greetingRow
                    updatesStrip
                    diwaniyaTonightCard
                    quickAccessGrid(tileHeight: layout.tileHeight + 6)
                    newsBentoCard
                    emptyInvite
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        // حد أقصى للعرض على الأجهزة الواسعة (iPad) حتى لا تتمدد الكروت بشكل مبالغ
        .frame(maxWidth: hSizeClass == .regular ? 700 : .infinity)
        .frame(maxWidth: .infinity)
        .animation(DS.Anim.smooth, value: layout)
    }

    private var greetingRow: some View {
        HomeGreetingRow(onOpenProfile: { selectedTab = 3 }, onLongPress: debugLongPress)
    }

    /// ديوانيات اليوم (المعتمدة والمفتوحة) — لبطاقة «الليلة»
    private var todaysDiwaniyas: [Diwaniya] {
        guard appSettingsVM.settings.diwaniyasEnabled ?? true else { return [] }
        return diwaniyasVM.diwaniyas.filter {
            $0.approvalStatus == "approved" && $0.isClosed != true
                && ($0.scheduleDays ?? []).contains(HomeDates.todayIndex)
        }
    }

    private var diwaniyaTonightCard: some View {
        HomeDiwaniyaTonightCard(diwaniyas: todaysDiwaniyas) { selectedTab = 2 }
    }

    /// دعوة واحدة واضحة حين لا توجد أخبار ولا مستجدات
    @ViewBuilder
    private var emptyInvite: some View {
        if newsVM.allNews.isEmpty && !newsVM.isLoading && authVM.currentUser?.role != .pending {
            Button { showingAddNews = true } label: {
                HStack(spacing: DS.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(DS.Color.gradientPrimary)
                            .frame(width: 44, height: 44)
                        Image(systemName: "square.and.pencil")
                            .font(DS.Font.scaled(18, weight: .bold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("شارك أول خبر", "Share the first post"))
                            .font(DS.Font.scaled(15, weight: .bold))
                            .foregroundColor(DS.Color.textPrimary)
                        Text(L10n.t("مناسبة، إعلان، أو صورة تجمع العائلة", "An occasion, an announcement, or a photo"))
                            .font(DS.Font.scaled(12, weight: .medium))
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    Spacer()
                    Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.textTertiary)
                }
                .padding(DS.Spacing.md)
                .background(DS.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .strokeBorder(DS.Color.primary.opacity(0.14), lineWidth: 1)
                )
            }
            .buttonStyle(DSScaleButtonStyle())
        }
    }

    /// بطاقة المستجدات — كل عمود يفتح قسمه
    private var updatesStrip: some View {
        HomeUpdatesStrip(
            diwaniyas: diwaniyasVM.diwaniyas,
            onNews: { activeSubPage = .news },
            onTree: { selectedTab = 1 },
            onNotifications: { showingNotifications = true },
            onAdmin: { selectedTab = 4 },
            onDiwaniyas: { selectedTab = 2 }
        )
    }

    // MARK: - Quick Access — الأقسام التي لا تبويب لها
    /// المكتبة / المشاريع / التواصل — المشاريع تختفي إن عُطّلت من الإعدادات.
    private func quickAccessGrid(tileHeight: CGFloat) -> some View {
        let projectsOn = appSettingsVM.settings.projectsEnabled ?? true
        let projectImageURL: String? = projectsVM.projects.first?.logoUrl

        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: layout.gridSpacing),
                count: projectsOn ? 3 : 2
            ),
            spacing: layout.gridSpacing
        ) {
            unifiedTile(
                title: L10n.t("مكتبة العائلة", "Family Library"),
                icon: "books.vertical.fill",
                color: DS.Color.tileLibrary,
                deep: DS.Color.tileLibraryDeep,
                imageURL: nil,
                count: nil,
                height: tileHeight,
                action: { activeSubPage = .archive }
            )
            if projectsOn {
                unifiedTile(
                    title: L10n.t("مشاريع العائلة", "Family Projects"),
                    icon: "briefcase.fill",
                    color: DS.Color.tileProjects,
                    deep: DS.Color.tileProjectsDeep,
                    imageURL: projectImageURL,
                    count: projectsVM.projects.count,
                    height: tileHeight,
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
                action: { activeSubPage = .contact }
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
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            ZStack(alignment: .bottomLeading) {
                tileBackground(color: color, deep: deep, imageURL: imageURL, icon: icon)

                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.10), location: 0),
                        .init(color: .clear, location: 0.32),
                        .init(color: .black.opacity(0.36), location: 1)
                    ],
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
            // منطقة اللمس = حدود المربّع المرئية بالضبط
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
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
    private func tileBackground(color: Color, deep: Color, imageURL: String?, icon: String) -> some View {
        if let urlStr = imageURL, let url = URL(string: urlStr) {
            CachedAsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                gradientBackground(color: color, deep: deep, icon: icon)
            }
        } else {
            gradientBackground(color: color, deep: deep, icon: icon)
        }
    }

    private func gradientBackground(color: Color, deep: Color, icon: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [color.opacity(0.92), color, deep],
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
                .foregroundColor(.white.opacity(0.17))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 16, y: 12)
        }
        .clipped()
    }

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
                        .font(.system(size: 26))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
                }
                Text(L10n.t("شاشة معاينة", "Preview"))
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(DS.Color.textSecondary)

                Picker("", selection: $previewAuthStep) {
                    Text(L10n.t("البيانات", "Profile")).tag(0)
                    Text(L10n.t("الانتظار", "Waiting")).tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .environment(\.layoutDirection, .rightToLeft)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(DS.Color.textTertiary.opacity(0.20), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .padding(.top, 118)
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
            backgroundGradient: DS.Color.gradientPrimary,
            hideNotificationBell: true
        ) {
            HomeBellButton()
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
        HomeNewsPreviewCard { activeSubPage = .news }
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
                // مجمّعة زمنياً: اليوم / أمس / هذا الأسبوع / هذا الشهر / أقدم
                // العناوين تثبت أعلى الشاشة أثناء التمرير
                LazyVStack(spacing: DS.Spacing.lg, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedNews) { group in
                        Section {
                            ForEach(group.posts) { news in
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
                        } header: {
                            newsGroupHeader(group)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.top, DS.Spacing.sm)
    }

    // MARK: - تجميع الأخبار زمنياً

    private struct NewsGroup: Identifiable {
        let id: String
        let title: String
        let icon: String
        let posts: [NewsPost]
    }

    private var groupedNews: [NewsGroup] {
        let cal = Calendar.current
        var today: [NewsPost] = [], yesterday: [NewsPost] = [], week: [NewsPost] = []
        var month: [NewsPost] = [], older: [NewsPost] = []
        for n in filteredNews {
            let d = n.timestamp
            if cal.isDateInToday(d) { today.append(n) }
            else if cal.isDateInYesterday(d) { yesterday.append(n) }
            else if HomeDates.isWithinLastDays(d, days: 7) { week.append(n) }
            else if HomeDates.isWithinLastDays(d, days: 30) { month.append(n) }
            else { older.append(n) }
        }
        var out: [NewsGroup] = []
        if !today.isEmpty     { out.append(.init(id: "today",     title: L10n.t("اليوم", "Today"),               icon: "sun.max.fill",   posts: today)) }
        if !yesterday.isEmpty { out.append(.init(id: "yesterday", title: L10n.t("أمس", "Yesterday"),             icon: "moon.fill",      posts: yesterday)) }
        if !week.isEmpty      { out.append(.init(id: "week",      title: L10n.t("هذا الأسبوع", "This week"),     icon: "calendar",       posts: week)) }
        if !month.isEmpty     { out.append(.init(id: "month",     title: L10n.t("هذا الشهر", "This month"),      icon: "calendar.badge.clock", posts: month)) }
        if !older.isEmpty     { out.append(.init(id: "older",     title: L10n.t("أقدم", "Earlier"),              icon: "clock.arrow.circlepath", posts: older)) }
        return out
    }

    private func newsGroupHeader(_ group: NewsGroup) -> some View {
        DSSectionHeader(
            title: group.title,
            icon: group.icon,
            trailing: "\(group.posts.count)"
        )
        .padding(.vertical, DS.Spacing.xs)
        // خلفية مصمتة حتى لا يظهر المحتوى من خلف العنوان المثبّت
        .background(DS.Color.background)
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
