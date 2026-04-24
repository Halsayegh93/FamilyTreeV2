import SwiftUI

struct HomeNewsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var storyVM: StoryViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTab: Int
    @State private var showingAddNews = false
    @State private var showingNotifications = false
    @State private var selectedNewsForComments: NewsPost? = nil
    @State private var postToDelete: NewsPost? = nil
    @State private var postToReport: NewsPost? = nil
    @State private var postToEdit: NewsPost? = nil
    @State private var showNewNewsAlert = false
    @State private var newNewsCount = 0
    @State private var selectedMemberForDetails: FamilyMember? = nil
    @State private var lastRefreshDate: Date? = nil
    @State private var activeSubPage: HomeSubPage? = nil
    @State private var appeared = false
    @State private var showAddStory = false
    @State private var storyViewerGroup: Int? = nil
    @State private var showStoryViewer = false
    @State private var showNewsSearch = false
    @State private var newsSearchText = ""
    @State private var debouncedNewsSearch = ""
    @State private var newsSearchTask: Task<Void, Never>?

    private enum HomeSubPage {
        case photos, projects, contact
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                if let subPage = activeSubPage {
                    subPageContent(for: subPage)
                        .transition(.move(edge: L10n.isArabic ? .leading : .trailing))
                } else {
                    // Main home content
                    VStack(spacing: 0) {
                        MainHeaderView(selectedTab: $selectedTab, showingNotifications: $showingNotifications)

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: DS.Spacing.lg) {
                                // الوصول السريع
                                quickActionsSection
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : 15)

                                // ستوري العائلة
                                realStoriesSection
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : 18)

                                // أخبار العائلة
                                newsFeedSection
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : 20)
                            }
                            .padding(.top, DS.Spacing.md)
                            .padding(.bottom, DS.Spacing.xxxxl)
                            .onAppear {
                                guard !appeared else { return }
                                withAnimation(DS.Anim.smooth.delay(0.1)) { appeared = true }
                            }
                        }
                        .refreshable { await refreshNews(notifyIfNew: true, force: true) }
                    }
                    .transition(.move(edge: L10n.isArabic ? .trailing : .leading))

                    // زر إضافة خبر عائم — فوق البار السفلي
                    if authVM.currentUser?.role != .pending && activeSubPage == nil {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                DSFloatingButton(icon: "plus") {
                                    showingAddNews = true
                                }
                                .padding(.trailing, DS.Spacing.xl)
                                .padding(.bottom, DS.Spacing.lg)
                            }
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .animation(DS.Anim.snappy, value: activeSubPage == nil)
            .task {
                await memberVM.fetchApprovedGalleryPhotos()
                rebuildGalleryMembers()
                rebuildStoryGroups()
            }
            .onChange(of: storyVM.membersWithStories.count) { _ in rebuildStoryGroups() }
            .onChange(of: memberVM.approvedGalleryPhotos.count) { _ in rebuildGalleryMembers() }
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
                Button(L10n.t("إبلاغ", "Report")) {
                    if let post = postToReport { Task { await newsVM.reportNewsPost(postId: post.id) } }
                    postToReport = nil
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { postToReport = nil }
            } message: { Text(L10n.t("تم استلام البلاغ.", "Report received.")) }
            .alert(L10n.t("تنبيه الأخبار", "News Alert"), isPresented: $showNewNewsAlert) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: { Text(L10n.t("تمت إضافة \(newNewsCount) خبر جديد.", "\(newNewsCount) new post(s) added.")) }

            .sheet(item: $selectedMemberForDetails) { member in
                NavigationStack {
                    MemberDetailsView(member: member)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAddStory) {
                AddStorySheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .overlay {
                if showStoryViewer {
                    StoryViewerView(
                        isPresented: $showStoryViewer,
                        allGroups: sortedStoryGroups,
                        initialGroupIndex: storyViewerGroup ?? 0
                    )
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
        }
        .onChange(of: selectedTab) { _ in
            if selectedTab != 0, activeSubPage != nil {
                activeSubPage = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReselectTab)) { notification in
            if let tab = notification.userInfo?["tab"] as? Int, tab == 0, activeSubPage != nil {
                withAnimation(DS.Anim.snappy) { activeSubPage = nil }
            }
        }
        .toolbar(showStoryViewer ? .hidden : .visible, for: .tabBar)
        .animation(.easeInOut(duration: 0.3), value: showStoryViewer)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Sub-page Content
    @ViewBuilder
    private func subPageContent(for page: HomeSubPage) -> some View {
        VStack(spacing: 0) {
            subPageHeader(for: page)
            switch page {
            case .photos: FamilyPhotoAlbumsView()
            case .projects: FamilyProjectsView()
            case .contact: ContactCenterView()
            }
        }
    }

    // MARK: - Sub-page Header
    private func subPageHeader(for page: HomeSubPage) -> some View {
        let title: String = {
            switch page {
            case .photos: return L10n.t("صور العائلة", "Family Photos")
            case .projects: return L10n.t("مشاريع العائلة", "Family Projects")
            case .contact: return L10n.t("التواصل", "Contact")
            }
        }()

        return HStack(spacing: DS.Spacing.md) {
            DSIconButton(
                icon: L10n.isArabic ? "chevron.right" : "chevron.left",
                iconColor: DS.Color.textPrimary,
                fillColor: DS.Color.surface,
                borderColor: DS.Color.primary.opacity(0.08),
                borderWidth: 1
            ) {
                withAnimation(DS.Anim.snappy) { activeSubPage = nil }
            }

            Text(title)
                .font(DS.Font.title3)
                .fontWeight(.black)
                .foregroundColor(DS.Color.textPrimary)

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.background)
    }

    // MARK: - Gallery Stories Section

    /// أعضاء عندهم صور معتمدة — cached
    @State private var cachedGalleryMembers: [(member: FamilyMember, count: Int)] = []

    private var galleryMembersWithPhotos: [(member: FamilyMember, count: Int)] {
        cachedGalleryMembers
    }

    private func rebuildGalleryMembers() {
        let grouped = Dictionary(grouping: memberVM.approvedGalleryPhotos, by: { $0.memberId })
        cachedGalleryMembers = grouped.compactMap { (memberId, photos) in
            guard let member = memberVM.member(byId: memberId) else { return nil }
            return (member: member, count: photos.count)
        }
        .sorted { $0.count > $1.count }
    }

    // MARK: - Real Stories Section

    /// ستوريات مرتبة: المستخدم الحالي أولاً — cached
    @State private var cachedStoryGroups: [(member: FamilyMember, stories: [FamilyStory])] = []

    private var sortedStoryGroups: [(member: FamilyMember, stories: [FamilyStory])] {
        cachedStoryGroups
    }

    private func rebuildStoryGroups() {
        var groups = storyVM.membersWithStories
        if let userId = authVM.currentUser?.id,
           let myIndex = groups.firstIndex(where: { $0.member.id == userId }) {
            let myGroup = groups.remove(at: myIndex)
            groups.insert(myGroup, at: 0)
        }
        cachedStoryGroups = groups
    }

    private var realStoriesSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(L10n.t("القصص", "Stories"))
                .font(DS.Font.caption1)
                .fontWeight(.bold)
                .foregroundColor(DS.Color.textSecondary)
                .padding(.horizontal, DS.Spacing.xl)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.lg) {
                    addStoryButton

                    ForEach(Array(sortedStoryGroups.enumerated()), id: \.element.member.id) { index, item in
                        storyMemberCircle(item: item, index: index)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.surface.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .padding(.horizontal, DS.Spacing.lg)
    }

    private var addStoryButton: some View {
        Button { showAddStory = true } label: {
            VStack(spacing: DS.Spacing.xs) {
                ZStack {
                    Circle()
                        .fill(DS.Color.primary.opacity(0.12))
                        .frame(width: 64, height: 64)

                    Image(systemName: "plus")
                        .font(DS.Font.scaled(24, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                }

                Text(L10n.t("إضافة", "Add"))
                    .font(DS.Font.scaled(11, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
                    .frame(width: 64)
            }
        }
        .buttonStyle(.plain)
    }

    private func storyMemberCircle(item: (member: FamilyMember, stories: [FamilyStory]), index: Int) -> some View {
        Button {
            storyViewerGroup = index
            withAnimation(.easeOut(duration: 0.3)) {
                showStoryViewer = true
            }
        } label: {
            VStack(spacing: DS.Spacing.xs) {
                ZStack {
                    Circle()
                        .stroke(DS.Color.gradientSecondary, lineWidth: 2.5)
                        .frame(width: 64, height: 64)

                    galleryMemberAvatar(item.member, size: 56)
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())

                    if item.stories.count > 1 {
                        Text("\(item.stories.count)")
                            .font(DS.Font.scaled(9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(DS.Color.primary)
                            .clipShape(Capsule())
                            .offset(x: 18, y: 20)
                    }
                }

                Text(item.member.firstName)
                    .font(DS.Font.scaled(11, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
                    .frame(width: 64)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Gallery Stories Section (Legacy)

    private var galleryStoriesSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.lg) {
                galleryStoryCircle(
                    name: L10n.t("الصور", "Photos"),
                    avatarView: AnyView(
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(DS.Font.scaled(20, weight: .semibold))
                            .foregroundColor(DS.Color.primary)
                    ),
                    count: memberVM.approvedGalleryPhotos.count,
                    memberId: nil
                )

                ForEach(galleryMembersWithPhotos, id: \.member.id) { item in
                    galleryStoryCircle(
                        name: item.member.firstName,
                        avatarView: AnyView(galleryMemberAvatar(item.member, size: 56)),
                        count: item.count,
                        memberId: item.member.id
                    )
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
        }
    }

    private func galleryStoryCircle(name: String, avatarView: AnyView, count: Int, memberId: UUID?) -> some View {
        Button {
            withAnimation(DS.Anim.snappy) { activeSubPage = .photos }
        } label: {
            VStack(spacing: DS.Spacing.xs) {
                ZStack {
                    Circle()
                        .stroke(DS.Color.gradientSecondary, lineWidth: 2.5)
                        .frame(width: 64, height: 64)

                    if memberId == nil {
                        Circle()
                            .fill(DS.Color.surface)
                            .frame(width: 56, height: 56)
                            .overlay(avatarView)
                    } else {
                        avatarView
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                    }

                    if count > 0 {
                        Text("\(count)")
                            .font(DS.Font.scaled(9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(DS.Color.primary)
                            .clipShape(Capsule())
                            .offset(x: 18, y: 20)
                    }
                }

                Text(name)
                    .font(DS.Font.scaled(11, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
                    .frame(width: 64)
            }
        }
        .buttonStyle(.plain)
    }

    private func galleryMemberAvatar(_ member: FamilyMember, size: CGFloat) -> some View {
        DSMemberAvatar(name: member.firstName, avatarUrl: member.avatarUrl, size: size, roleColor: DS.Color.primary)
    }

    // MARK: - Quick Actions Section
    private var quickActionsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.md) {
                quickActionItem(icon: "photo.on.rectangle.angled.fill", title: L10n.t("الصور", "Photos"), color: DS.Color.primary) { withAnimation(DS.Anim.snappy) { activeSubPage = .photos } }
                quickActionItem(icon: "briefcase.fill", title: L10n.t("مشاريع", "Projects"), color: DS.Color.accent) { withAnimation(DS.Anim.snappy) { activeSubPage = .projects } }
                quickActionItem(icon: "bubble.left.and.bubble.right.fill", title: L10n.t("تواصل", "Contact"), color: DS.Color.primary) { withAnimation(DS.Anim.snappy) { activeSubPage = .contact } }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    private func quickActionItem(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(16, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.1))
                    .clipShape(Circle())

                Text(title)
                    .font(DS.Font.caption1)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Color.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
        .frame(maxWidth: .infinity)
    }

    // MARK: - News Feed Section
    private var newsFeedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header + بحث
            VStack(spacing: DS.Spacing.xs) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "newspaper.fill")
                        .font(DS.Font.scaled(14, weight: .semibold))
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(width: 30, height: 30)
                        .background(DS.Color.gradientPrimary)
                        .clipShape(Circle())

                    Text(L10n.t("أخبار العائلة", "Family News"))
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textPrimary)

                    Spacer()

                    Button {
                        withAnimation(DS.Anim.snappy) { showNewsSearch.toggle() }
                    } label: {
                        Image(systemName: showNewsSearch ? "xmark.circle.fill" : "magnifyingglass")
                            .font(DS.Font.scaled(16, weight: .semibold))
                            .foregroundColor(DS.Color.textSecondary)
                    }
                }

                if showNewsSearch {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(DS.Color.textTertiary)
                        TextField(L10n.t("بحث بالأخبار...", "Search news..."), text: $newsSearchText)
                            .font(DS.Font.body)
                        if !newsSearchText.isEmpty {
                            Button { newsSearchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                        }
                    }
                    .padding(DS.Spacing.sm)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.md)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)

            if newsVM.isLoading && newsVM.allNews.isEmpty {
                VStack(spacing: DS.Spacing.md) {
                    Spacer().frame(height: DS.Spacing.xxxl)
                    ProgressView()
                        .tint(DS.Color.primary)
                        .scaleEffect(1.3)
                    Text(L10n.t("جاري تحميل الأخبار...", "Loading news..."))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
            } else if newsVM.allNews.isEmpty {
                emptyNewsView
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
            } else {
                newsListView
            }
        }
    }

    private var filteredNews: [NewsPost] {
        if debouncedNewsSearch.isEmpty { return newsVM.allNews }
        let query = debouncedNewsSearch.lowercased()
        return newsVM.allNews.filter {
            $0.content.lowercased().contains(query) ||
            $0.author_name.lowercased().contains(query)
        }
    }

    private var newsListView: some View {
        LazyVStack(spacing: DS.Spacing.lg) {
            ForEach(filteredNews) { news in
                newsCard(for: news)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
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
            canReport: authVM.currentUser?.role == .member,
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
