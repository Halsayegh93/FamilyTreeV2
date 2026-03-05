import SwiftUI
import PhotosUI

struct HomeNewsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Binding var selectedTab: Int
    @State private var showingAddNews = false
    @State private var showingNotifications = false
    @State private var selectedNewsForComments: NewsPost? = nil
    @State private var commentInput = ""
    @State private var postToDelete: NewsPost? = nil
    @State private var postToReport: NewsPost? = nil
    @State private var postToEdit: NewsPost? = nil
    @State private var showingContactCenter = false
    @State private var showNewNewsAlert = false
    @State private var newNewsCount = 0
    @State private var selectedMemberForDetails: FamilyMember? = nil
    @State private var lastRefreshDate: Date? = nil
    @State private var showingPhotoAlbums = false

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    MainHeaderView(selectedTab: $selectedTab, showingNotifications: $showingNotifications)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: DS.Spacing.xl) {
                            // الوصول السريع
                            quickActionsSection

                            // أخبار العائلة
                            newsFeedSection
                        }
                        .padding(.top, DS.Spacing.md)
                        .padding(.bottom, 120)
                    }
                    .refreshable { await refreshNews(notifyIfNew: true, force: true) }
                }


            }
            .navigationBarHidden(true)
            .task { await refreshNews(notifyIfNew: false) }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await refreshNews(notifyIfNew: true) }
            }
            .sheet(isPresented: $showingAddNews) {
                AddNewsView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingContactCenter) { ContactCenterView() }

            .sheet(isPresented: $showingPhotoAlbums) { FamilyPhotoAlbumsView() }
            .sheet(item: $selectedNewsForComments) { news in
                NewsCommentsSheet(news: news)
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
                    if let post = postToDelete { Task { await authVM.deleteNewsPost(postId: post.id) } }
                    postToDelete = nil
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { postToDelete = nil }
            } message: { Text(L10n.t("هل تريد حذف هذا الخبر نهائياً؟", "Are you sure you want to delete this post?")) }
            .alert(L10n.t("إبلاغ عن الخبر", "Report Post"), isPresented: Binding(
                get: { postToReport != nil },
                set: { if !$0 { postToReport = nil } }
            )) {
                Button(L10n.t("إبلاغ", "Report")) {
                    if let post = postToReport { Task { await authVM.reportNewsPost(postId: post.id) } }
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
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Comment Sheet Component
    @State private var isLoadingComments = false

    private func NewsCommentsSheet(news: NewsPost) -> some View {
        NavigationStack {
            VStack {
                if isLoadingComments {
                    VStack(spacing: DS.Spacing.md) {
                        ProgressView()
                        Text(L10n.t("جاري تحميل التعليقات...", "Loading comments..."))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let postComments = authVM.commentsByPost[news.id], !postComments.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: DS.Spacing.sm) {
                            ForEach(postComments) { comment in
                                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(comment.author_name).font(DS.Font.caption1).fontWeight(.bold)
                                        Text(comment.content).font(DS.Font.callout)
                                    }
                                    Spacer()
                                    Text(relativeTimeFromISO(comment.created_at))
                                    .font(DS.Font.caption2)
                                    .foregroundColor(DS.Color.textSecondary)
                                }
                                .padding(DS.Spacing.md)
                                .glassBackground(radius: DS.Radius.md)
                            }
                        }
                        .padding(DS.Spacing.lg)
                    }
                } else {
                    VStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(DS.Font.scaled(44))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا توجد تعليقات بعد", "No comments yet"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                            .padding(.top, DS.Spacing.sm)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // حقل الإدخال
                HStack(spacing: DS.Spacing.sm) {
                    TextField(L10n.t("اكتب تعليقك...", "Write a comment..."), text: $commentInput, axis: .vertical)
                        .lineLimit(1...3)
                        .font(DS.Font.callout)
                        .padding(DS.Spacing.md)
                        .glassBackground(radius: DS.Radius.md)

                    Button(action: {
                        Task {
                            let success = await authVM.addNewsComment(to: news.id, text: commentInput)
                            if success {
                                await MainActor.run { commentInput = "" }
                            }
                        }
                    }) {
                        Image(systemName: "paperplane.fill")
                            .font(DS.Font.scaled(15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(DS.Color.gradientPrimary)
                            .clipShape(Circle())
                    }
                    .disabled(commentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(DS.Spacing.lg)
            }
            .background(DS.Color.background)
            .navigationTitle(L10n.t("التعليقات", "Comments"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.t("إغلاق", "Close")) { selectedNewsForComments = nil }
                }
            }
            .task {
                isLoadingComments = true
                await authVM.fetchNewsComments(for: [news.id])
                isLoadingComments = false
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }



    // MARK: - Quick Actions Section
    private var quickActionsSection: some View {
        HStack(spacing: DS.Spacing.md) {
            quickActionItem(icon: "photo.on.rectangle.angled.fill", title: L10n.t("الصور", "Photos"), color: DS.Color.gridDiwaniya) { showingPhotoAlbums = true }
            quickActionItem(icon: "bubble.left.and.bubble.right.fill", title: L10n.t("تواصل", "Contact"), color: DS.Color.gridContact) { showingContactCenter = true }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func quickActionItem(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(20, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 52, height: 52)
                    .background(color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            .stroke(color.opacity(0.15), lineWidth: 1)
                    )

                Text(title)
                    .font(DS.Font.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(DSBoldButtonStyle())
        .frame(maxWidth: .infinity)
    }

    // MARK: - News Feed Section
    private var newsFeedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header — كرت زجاجي
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "newspaper.fill")
                    .font(DS.Font.scaled(16, weight: .semibold))
                    .foregroundColor(DS.Color.primary)

                Text(L10n.t("أخبار العائلة", "Family News"))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)

                Spacer()

                if !authVM.allNews.isEmpty {
                    Text("\(authVM.allNews.count)")
                        .font(DS.Font.caption1)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.primary)
                        .frame(minWidth: 26, minHeight: 26)
                        .background(DS.Color.primary.opacity(0.1))
                        .clipShape(Circle())
                }

                if authVM.currentUser?.role != .pending {
                    Button(action: { showingAddNews = true }) {
                        Image(systemName: "plus")
                            .font(DS.Font.scaled(14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(DS.Color.gradientPrimary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(DSBoldButtonStyle())
                    .accessibilityLabel(L10n.t("إضافة خبر جديد", "Add new post"))
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.75)
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
            .padding(.horizontal, DS.Spacing.md)

            if authVM.allNews.isEmpty {
                emptyNewsView
            } else {
                newsListView
            }
        }
    }

    private var newsListView: some View {
        LazyVStack(spacing: DS.Spacing.lg) {
            ForEach(authVM.allNews) { news in
                newsCard(for: news)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.top, DS.Spacing.sm)
    }

    private func newsCard(for news: NewsPost) -> some View {
        HomeNewsCardView(
            postId: news.id,
            authorName: news.author_name,
            authorId: news.author_id,
            role: news.author_role,
            roleColor: news.role_color == "purple" ? DS.Color.adminRole : (news.role_color == "orange" ? DS.Color.supervisorRole : DS.Color.primary),
            time: getRelativeTime(for: news.timestamp),
            type: news.type,
            content: news.content,
            imageUrl: news.image_url,
            imageUrls: news.mediaURLs,
            pollQuestion: news.poll_question,
            pollOptions: news.poll_options ?? [],
            pollVotes: authVM.pollVotesByPost[news.id] ?? [:],
            selectedPollOption: authVM.userVoteByPost[news.id],
            approvalStatus: news.approval_status,
            commentCount: authVM.commentsCountByPost[news.id] ?? 0,
            likeCount: authVM.likesCountByPost[news.id] ?? 0,
            isLiked: authVM.likedPosts.contains(news.id),
            onCommentTap: { selectedNewsForComments = news },
            onLikeTap: { toggleLike(for: news.id) },
            onVoteTap: { optionIndex in
                Task { await authVM.submitNewsPollVote(postId: news.id, optionIndex: optionIndex) }
            },
            canDelete: authVM.currentUser?.role == .admin || authVM.currentUser?.role == .supervisor,
            canReport: authVM.currentUser?.role == .member,
            canEdit: authVM.currentUser?.role != .pending,
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
                    .font(DS.Font.callout)
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
                        .padding(.vertical, DS.Spacing.sm)
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
        Task { await authVM.toggleNewsLike(for: postId) }
    }

    @MainActor
    private func refreshNews(notifyIfNew: Bool, force: Bool = false) async {
        // تجنب التحديث المتكرر خلال 10 ثواني
        if !force, let last = lastRefreshDate, Date().timeIntervalSince(last) < 10 { return }
        lastRefreshDate = Date()
        
        let previousIDs = Set(authVM.allNews.map(\.id))
        
        // تحميل الأخبار والأعضاء بالتوازي إذا لزم
        if authVM.allMembers.isEmpty {
            async let news: () = authVM.fetchNews(force: true)
            async let members: () = authVM.fetchAllMembers(force: true)
            _ = await (news, members)
        } else {
            await authVM.fetchNews(force: true)
        }
        
        guard notifyIfNew, !previousIDs.isEmpty else { return }
        let count = Set(authVM.allNews.map(\.id)).subtracting(previousIDs).count
        if count > 0 { newNewsCount = count; showNewNewsAlert = true }
    }
}

extension HomeNewsView {
    init(selectedTab: Binding<Int>) { self._selectedTab = selectedTab }
}

// MARK: - كرت الخبر — Glass card styling
struct HomeNewsCardView: View {
    @EnvironmentObject var authVM: AuthViewModel
    let postId: UUID
    let authorName: String
    let authorId: UUID?
    let role: String
    let roleColor: Color
    let time: String
    let type: String
    let content: String
    let imageUrl: String?
    let imageUrls: [String]
    let pollQuestion: String?
    let pollOptions: [String]
    let pollVotes: [Int: Int]
    let selectedPollOption: Int?
    let approvalStatus: String?
    let commentCount: Int
    let likeCount: Int
    let isLiked: Bool
    let onCommentTap: () -> Void
    let onLikeTap: () -> Void
    let onVoteTap: (Int) -> Void
    let canDelete: Bool
    let canReport: Bool
    let canEdit: Bool
    let onDeleteTap: () -> Void
    let onReportTap: () -> Void
    let onEditTap: () -> Void
    let onMemberTap: (FamilyMember) -> Void

    private func colorForType(_ type: String) -> Color {
        switch type {
        case "وفاة": return DS.Color.newsDeath
        case "زواج": return DS.Color.newsWedding
        case "مولود": return DS.Color.newsBirth
        case "تصويت": return DS.Color.newsVote
        case "إعلان": return DS.Color.newsAnnouncement
        case "تهنئة": return DS.Color.newsCongrats
        case "تذكير": return DS.Color.newsReminder
        case "دعوة": return DS.Color.newsInvitation
        default: return DS.Color.primary
        }
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "وفاة": return "heart.slash.fill"
        case "زواج": return "heart.fill"
        case "مولود": return "figure.child"
        case "تصويت": return "chart.bar.fill"
        case "إعلان": return "megaphone.fill"
        case "تهنئة": return "hands.clap.fill"
        case "تذكير": return "bell.badge.fill"
        case "دعوة": return "envelope.open.fill"
        default: return "newspaper.fill"
        }
    }

    private func displayNameForType(_ type: String) -> String {
        switch type {
        case "خبر": return L10n.t("خبر", "News")
        case "زواج": return L10n.t("زواج", "Wedding")
        case "مولود": return L10n.t("مولود", "Newborn")
        case "وفاة": return L10n.t("وفاة", "Obituary")
        case "تصويت": return L10n.t("تصويت", "Poll")
        case "إعلان": return L10n.t("إعلان", "Announcement")
        case "تهنئة": return L10n.t("تهنئة", "Congrats")
        case "تذكير": return L10n.t("تذكير", "Reminder")
        case "دعوة": return L10n.t("دعوة", "Invitation")
        default: return type
        }
    }

    private var authorMember: FamilyMember? {
        guard let authorId else { return nil }
        return authVM.member(byId: authorId)
    }

    private var shortDisplayName: String {
        let parts = authorName.split(separator: " ")
        guard parts.count > 4 else { return authorName }
        // الأول + الثاني + الثالث + الرابع + العائلة (الأخير)
        return "\(parts[0]) \(parts[1]) \(parts[2]) \(parts[3]) \(parts[parts.count - 1])"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // هيدر الكرت
            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                Button {
                    if let member = authorMember {
                        onMemberTap(member)
                    }
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        ZStack {
                            if let urlStr = authorMember?.avatarUrl, let url = URL(string: urlStr) {
                                CachedAsyncImage(url: url) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [colorForType(type), colorForType(type).opacity(0.7)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .overlay(
                                            Text(String(authorName.first ?? "A"))
                                                .font(DS.Font.scaled(15, weight: .bold))
                                                .foregroundColor(.white)
                                        )
                                }
                                .frame(width: 38, height: 38)
                                .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [colorForType(type), colorForType(type).opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 38, height: 38)
                                Text(String(authorName.first ?? "A"))
                                    .font(DS.Font.scaled(15, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(DS.Color.textTertiary.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: colorForType(type).opacity(0.3), radius: 6, x: 0, y: 3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortDisplayName)
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.textPrimary)
                                .lineLimit(1)
                            
                            HStack(spacing: 3) {
                                Image(systemName: iconForType(type))
                                    .font(DS.Font.scaled(9, weight: .bold))
                                Text(displayNameForType(type))
                                    .font(DS.Font.caption2)
                                    .fontWeight(.semibold)
                            }
                                .foregroundColor(colorForType(type))
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, 2)
                                .background(colorForType(type).opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if approvalStatus == "pending" {
                    Text(L10n.t("مراجعة", "Review"))
                        .font(DS.Font.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(DS.Color.warning)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(DS.Color.warning.opacity(0.3), lineWidth: 1))
                }

                if canDelete || canReport || canEdit {
                    Menu {
                        if canEdit {
                            Button(action: onEditTap) { Label(L10n.t("تعديل", "Edit"), systemImage: "pencil") }
                        }
                        if canDelete {
                            Button(role: .destructive, action: onDeleteTap) { Label(L10n.t("حذف", "Delete"), systemImage: "trash") }
                        }
                        if canReport {
                            Button(action: onReportTap) { Label(L10n.t("إبلاغ", "Report"), systemImage: "exclamationmark.bubble") }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(DS.Font.scaled(14, weight: .semibold))
                            .foregroundColor(DS.Color.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(DS.Color.textTertiary.opacity(0.3), lineWidth: 0.75))
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.md)

            // المحتوى
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(content)
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textPrimary.opacity(0.95))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.md)
            }

            // منطقة الميديا (صور) — Instagram-style
            if !imageUrls.isEmpty {
                TabView {
                    ForEach(Array(imageUrls.enumerated()), id: \.offset) { _, urlStr in
                        if let encodedStr = urlStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let url = URL(string: encodedStr) {
                            CachedAsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                            } placeholder: {
                                ZStack {
                                    Color.gray.opacity(0.05)
                                    ProgressView().tint(DS.Color.primary)
                                }
                            }
                        }
                    }
                }
                .aspectRatio(4/5, contentMode: .fit)
                .clipped()
                .tabViewStyle(.page(indexDisplayMode: imageUrls.count > 1 ? .automatic : .never))
            } else if let urlStr = imageUrl,
                      let encodedStr = urlStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: encodedStr) {
                CachedAsyncImage(url: url) { img in
                    img.resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .clipped()
                } placeholder: {
                    ZStack {
                        Color.gray.opacity(0.05)
                        ProgressView().tint(DS.Color.primary)
                    }
                }
                .aspectRatio(4/5, contentMode: .fit)
                .clipped()
            }

            // التصويت
            if !pollOptions.isEmpty {
                pollSection
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.md)
            }

            // فاصل زجاجي
            Rectangle()
                .fill(DS.Color.textTertiary.opacity(0.2))
                .frame(height: 0.5)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)

            // شريط الإجراءات
            actionBar
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
                    .fill(.thickMaterial)

                LinearGradient(
                    colors: [Color.white.opacity(0.15), Color.white.opacity(0.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        )
        .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 8)
        .shadow(color: colorForType(type).opacity(0.12), radius: 20, x: 0, y: 10)
    }

    private var pollSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if let q = pollQuestion, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(q).font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
            }
            ForEach(Array(pollOptions.enumerated()), id: \.offset) { index, option in
                let isSelected = selectedPollOption == index
                Button(action: { onVoteTap(index) }) {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? DS.Color.gradientPrimary : LinearGradient(colors: [DS.Color.textSecondary], startPoint: .top, endPoint: .bottom))
                            .font(DS.Font.scaled(20))
                        Text(option).font(DS.Font.callout)
                            .foregroundColor(DS.Color.textPrimary)
                        Spacer()
                        Text("\(pollVotes[index] ?? 0)")
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(isSelected ? .white : DS.Color.textSecondary)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 3)
                            .background(isSelected ? DS.Color.primary : Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.md)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .fill(.ultraThinMaterial)
                            if isSelected {
                                DS.Color.primary.opacity(0.12)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(isSelected ? DS.Color.primary.opacity(0.4) : Color.white.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            // Like
            Button(action: onLikeTap) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(DS.Font.scaled(15, weight: .medium))
                        .foregroundColor(isLiked ? DS.Color.error : DS.Color.textSecondary)
                        .symbolEffect(.bounce, value: isLiked)

                    if likeCount > 0 {
                        Text("\(likeCount)")
                            .font(DS.Font.caption1)
                            .fontWeight(.semibold)
                            .foregroundColor(isLiked ? DS.Color.error : DS.Color.textSecondary)
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, 7)
                .background(
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        if isLiked { DS.Color.error.opacity(0.10) }
                    }
                )
                .clipShape(Capsule())
                .overlay(Capsule().stroke(DS.Color.textTertiary.opacity(0.25), lineWidth: 0.75))
            }
            .buttonStyle(.plain)

            // Comment
            Button(action: onCommentTap) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "bubble.right")
                        .font(DS.Font.scaled(15, weight: .medium))
                        .foregroundColor(DS.Color.textSecondary)

                    if commentCount > 0 {
                        Text("\(commentCount)")
                            .font(DS.Font.caption1)
                            .fontWeight(.semibold)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(.ultraThinMaterial)
                )
                .clipShape(Capsule())
                .overlay(Capsule().stroke(DS.Color.textTertiary.opacity(0.25), lineWidth: 0.75))
            }
            .buttonStyle(.plain)

            Spacer()

            // Time
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "clock")
                    .font(DS.Font.scaled(11))
                Text(time)
                    .font(DS.Font.caption2)
            }
            .foregroundColor(DS.Color.textTertiary)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - Local Types Removed


// MARK: - إضافة خبر
struct AddNewsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var content = ""
    @State private var selectedType = "خبر"
    @State private var selectedImages: [UIImage] = []
    @State private var pollQuestion = ""
    @State private var pollOption1 = ""
    @State private var pollOption2 = ""
    @State private var pollOption3 = ""
    @State private var pollOption4 = ""
    @State private var showPostErrorAlert = false
    let types = ["خبر", "إعلان", "زواج", "مولود", "وفاة", "تهنئة", "دعوة", "تذكير", "تصويت"]

    private func colorForType(_ type: String) -> Color {
        switch type {
        case "وفاة": return DS.Color.newsDeath
        case "زواج": return DS.Color.newsWedding
        case "مولود": return DS.Color.newsBirth
        case "تصويت": return DS.Color.newsVote
        case "إعلان": return DS.Color.newsAnnouncement
        case "تهنئة": return DS.Color.newsCongrats
        case "تذكير": return DS.Color.newsReminder
        case "دعوة": return DS.Color.newsInvitation
        default: return DS.Color.primary
        }
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "وفاة": return "heart.slash.fill"
        case "زواج": return "heart.fill"
        case "مولود": return "figure.child"
        case "تصويت": return "chart.bar.fill"
        case "إعلان": return "megaphone.fill"
        case "تهنئة": return "hands.clap.fill"
        case "تذكير": return "bell.badge.fill"
        case "دعوة": return "envelope.open.fill"
        default: return "newspaper.fill"
        }
    }

    private func displayNameForType(_ type: String) -> String {
        switch type {
        case "خبر": return L10n.t("خبر", "News")
        case "زواج": return L10n.t("زواج", "Wedding")
        case "مولود": return L10n.t("مولود", "Newborn")
        case "وفاة": return L10n.t("وفاة", "Obituary")
        case "تصويت": return L10n.t("تصويت", "Poll")
        case "إعلان": return L10n.t("إعلان", "Announcement")
        case "تهنئة": return L10n.t("تهنئة", "Congrats")
        case "تذكير": return L10n.t("تذكير", "Reminder")
        case "دعوة": return L10n.t("دعوة", "Invitation")
        default: return type
        }
    }

    private var normalizedPollOptions: [String] {
        [pollOption1, pollOption2, pollOption3, pollOption4]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var isPollValid: Bool {
        selectedType != "تصويت" || normalizedPollOptions.count >= 2
    }

    private var canSubmit: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isPollValid && !authVM.isLoading
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.lg) {
                    addNewsTypeSelector
                    addNewsContentSection
                    addNewsPhotosSection

                    if selectedType == "تصويت" {
                        addNewsPollSection
                    }

                    addNewsSubmitSection
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.xxxl)
            }
            .background(.ultraThinMaterial)
            .navigationTitle(L10n.t("خبر جديد", "New Post"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
            .alert(L10n.t("تعذر النشر", "Post Failed"), isPresented: $showPostErrorAlert) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: { Text(authVM.newsPostErrorMessage ?? L10n.t("حدث خطأ أثناء نشر الخبر.", "An error occurred.")) }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }

    // MARK: - Type Selector
    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 3)

    private var addNewsTypeSelector: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("نوع الخبر", "Post Type"),
                icon: "tag.fill",
                iconColor: DS.Color.primary
            )

            LazyVGrid(columns: gridColumns, spacing: DS.Spacing.sm) {
                ForEach(types, id: \.self) { type in
                    let isSelected = selectedType == type
                    let typeColor = colorForType(type)

                    Button(action: {
                        withAnimation(DS.Anim.snappy) { selectedType = type }
                    }) {
                        VStack(spacing: DS.Spacing.xs) {
                            ZStack {
                                Circle()
                                    .fill(isSelected ? typeColor : typeColor.opacity(0.12))
                                    .frame(width: 42, height: 42)

                                Image(systemName: iconForType(type))
                                    .font(DS.Font.scaled(16, weight: .semibold))
                                    .foregroundColor(isSelected ? .white : typeColor)
                            }

                            Text(displayNameForType(type))
                                .font(DS.Font.caption1)
                                .fontWeight(.bold)
                                .foregroundColor(isSelected ? typeColor : DS.Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .fill(isSelected ? typeColor.opacity(0.1) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .stroke(isSelected ? typeColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(DSBoldButtonStyle())
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.md)
        }
    }

    // MARK: - Content Section
    private var addNewsContentSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("محتوى الخبر", "Post Content"),
                icon: "text.alignright",
                iconColor: DS.Color.accent
            )

            ZStack(alignment: .topTrailing) {
                TextEditor(text: $content)
                    .frame(minHeight: 60, maxHeight: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollContentBackground(.hidden)
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .padding(DS.Spacing.sm)

                if content.isEmpty {
                    Text(L10n.t("اكتب الخبر هنا...", "Write your post here..."))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textTertiary)
                        .padding(.top, DS.Spacing.md)
                        .padding(.trailing, DS.Spacing.md)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Photos Section
    private var addNewsPhotosSection: some View {
        DSMultiPhotoPicker(
            selectedImages: $selectedImages,
            maxCount: 5,
            enableCrop: false
        )
    }

    // MARK: - Poll Section
    private var addNewsPollSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("خيارات التصويت", "Poll Options"),
                icon: "chart.bar.fill",
                iconColor: DS.Color.newsVote
            )

            VStack(spacing: DS.Spacing.sm) {
                pollField(placeholder: L10n.t("سؤال التصويت (اختياري)", "Poll question (optional)"), text: $pollQuestion, icon: "questionmark.circle")
                pollField(placeholder: L10n.t("الخيار الأول", "Option 1"), text: $pollOption1, icon: "1.circle.fill")
                pollField(placeholder: L10n.t("الخيار الثاني", "Option 2"), text: $pollOption2, icon: "2.circle.fill")
                pollField(placeholder: L10n.t("الخيار الثالث (اختياري)", "Option 3 (optional)"), text: $pollOption3, icon: "3.circle.fill")
                pollField(placeholder: L10n.t("الخيار الرابع (اختياري)", "Option 4 (optional)"), text: $pollOption4, icon: "4.circle.fill")
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.md)
        }
    }

    // MARK: - Submit Section
    private var addNewsSubmitSection: some View {
        VStack(spacing: DS.Spacing.sm) {
            DSPrimaryButton(
                authVM.canAutoPublishNews ? L10n.t("نشر الخبر", "Publish Post") : L10n.t("إرسال للمراجعة", "Submit for Review"),
                icon: "paperplane.fill",
                isLoading: authVM.isLoading,
                useGradient: canSubmit,
                color: canSubmit ? DS.Color.primary : .gray
            ) {
                Task { await submitNews() }
            }
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1.0 : 0.6)

            if !authVM.canAutoPublishNews {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "info.circle.fill")
                        .font(DS.Font.scaled(12))
                    Text(L10n.t("سيتم مراجعة الخبر من الإدارة قبل النشر.", "Your post will be reviewed by admin before publishing."))
                        .font(DS.Font.caption2)
                }
                .foregroundColor(DS.Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func pollField(placeholder: String, text: Binding<String>, icon: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Font.scaled(14, weight: .medium))
                .foregroundColor(DS.Color.newsVote)
                .frame(width: 24)

            TextField(placeholder, text: text)
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textPrimary)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
        )
    }

    private func submitNews() async {
        guard canSubmit, let authorId = authVM.currentUser?.id else { return }
        var uploadedURLs: [String] = []
        for image in selectedImages {
            if let url = await authVM.uploadNewsImage(image: image, for: authorId) { uploadedURLs.append(url) }
        }

        let question = pollQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPosted = await authVM.postNews(
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            type: selectedType,
            imageURLs: uploadedURLs,
            pollQuestion: selectedType == "تصويت" && !question.isEmpty ? question : nil,
            pollOptions: selectedType == "تصويت" ? normalizedPollOptions : []
        )
        if isPosted { dismiss() } else { showPostErrorAlert = true }
    }
}

struct EditNewsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    let news: NewsPost
    @State private var content: String
    @State private var selectedType: String
    @State private var existingImageURLs: [String]
    @State private var selectedImages: [UIImage] = []
    @State private var editPickerItems: [PhotosPickerItem] = []
    @State private var isLoadingEditImages = false
    @State private var pollQuestion: String
    @State private var pollOption1: String
    @State private var pollOption2: String
    @State private var pollOption3: String
    @State private var pollOption4: String
    @State private var showEditErrorAlert = false
    let types = ["خبر", "إعلان", "زواج", "مولود", "وفاة", "تهنئة", "دعوة", "تذكير", "تصويت"]

    init(news: NewsPost) {
        self.news = news
        _content = State(initialValue: news.content)
        _selectedType = State(initialValue: news.type)
        _existingImageURLs = State(initialValue: news.mediaURLs)
        _pollQuestion = State(initialValue: news.poll_question ?? "")

        let options = news.poll_options ?? []
        _pollOption1 = State(initialValue: options.indices.contains(0) ? options[0] : "")
        _pollOption2 = State(initialValue: options.indices.contains(1) ? options[1] : "")
        _pollOption3 = State(initialValue: options.indices.contains(2) ? options[2] : "")
        _pollOption4 = State(initialValue: options.indices.contains(3) ? options[3] : "")
    }

    private func colorForType(_ type: String) -> Color {
        switch type {
        case "وفاة": return DS.Color.newsDeath
        case "زواج": return DS.Color.newsWedding
        case "مولود": return DS.Color.newsBirth
        case "تصويت": return DS.Color.newsVote
        case "إعلان": return DS.Color.newsAnnouncement
        case "تهنئة": return DS.Color.newsCongrats
        case "تذكير": return DS.Color.newsReminder
        case "دعوة": return DS.Color.newsInvitation
        default: return DS.Color.primary
        }
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "وفاة": return "heart.slash.fill"
        case "زواج": return "heart.fill"
        case "مولود": return "figure.child"
        case "تصويت": return "chart.bar.fill"
        case "إعلان": return "megaphone.fill"
        case "تهنئة": return "hands.clap.fill"
        case "تذكير": return "bell.badge.fill"
        case "دعوة": return "envelope.open.fill"
        default: return "newspaper.fill"
        }
    }

    private func displayNameForType(_ type: String) -> String {
        switch type {
        case "خبر": return L10n.t("خبر", "News")
        case "زواج": return L10n.t("زواج", "Wedding")
        case "مولود": return L10n.t("مولود", "Newborn")
        case "وفاة": return L10n.t("وفاة", "Obituary")
        case "تصويت": return L10n.t("تصويت", "Poll")
        case "إعلان": return L10n.t("إعلان", "Announcement")
        case "تهنئة": return L10n.t("تهنئة", "Congrats")
        case "تذكير": return L10n.t("تذكير", "Reminder")
        case "دعوة": return L10n.t("دعوة", "Invitation")
        default: return type
        }
    }

    private var normalizedPollOptions: [String] {
        [pollOption1, pollOption2, pollOption3, pollOption4]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var isPollValid: Bool {
        selectedType != "تصويت" || normalizedPollOptions.count >= 2
    }

    private var canSubmit: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isPollValid && !authVM.isLoading
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) {
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: L10n.t("نوع الخبر", "Post Type"),
                            icon: "tag.fill",
                            iconColor: DS.Color.primary
                        )

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 3), spacing: DS.Spacing.sm) {
                            ForEach(types, id: \.self) { type in
                                let isSelected = selectedType == type
                                let typeColor = colorForType(type)

                                Button(action: {
                                    withAnimation(DS.Anim.snappy) { selectedType = type }
                                }) {
                                    VStack(spacing: DS.Spacing.xs) {
                                        ZStack {
                                            Circle()
                                                .fill(isSelected ? typeColor : typeColor.opacity(0.12))
                                                .frame(width: 42, height: 42)

                                            Image(systemName: iconForType(type))
                                                .font(DS.Font.scaled(16, weight: .semibold))
                                                .foregroundColor(isSelected ? .white : typeColor)
                                        }

                                        Text(displayNameForType(type))
                                            .font(DS.Font.caption1)
                                            .fontWeight(.bold)
                                            .foregroundColor(isSelected ? typeColor : DS.Color.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, DS.Spacing.sm)
                                    .background(
                                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                            .fill(isSelected ? typeColor.opacity(0.1) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                            .stroke(isSelected ? typeColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(DSBoldButtonStyle())
                            }
                        }
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.bottom, DS.Spacing.md)
                    }

                    TextEditor(text: $content)
                        .frame(minHeight: 120, maxHeight: 150)
                        .padding(DS.Spacing.sm)
                        .background(DS.Color.surface.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .stroke(DS.Color.primary.opacity(0.10), lineWidth: 1)
                        )

                    PhotosPicker(selection: $editPickerItems, maxSelectionCount: 5, matching: .images) {
                        HStack(spacing: DS.Spacing.sm) {
                            if isLoadingEditImages {
                                ProgressView().tint(DS.Color.primary)
                            } else {
                                Image(systemName: "photo.on.rectangle.angled")
                            }
                            Text(L10n.t("إضافة صور جديدة", "Add new photos"))
                        }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(DS.Color.primary.opacity(0.08))
                        .cornerRadius(DS.Radius.md)
                    }
                    .disabled(isLoadingEditImages)

                    if !existingImageURLs.isEmpty || !selectedImages.isEmpty {
                        let allImages: [(isExisting: Bool, index: Int, urlOrNil: String?)] =
                            existingImageURLs.enumerated().map { (true, $0.offset, $0.element) } +
                            selectedImages.enumerated().map { (false, $0.offset, nil) }

                        TabView {
                            ForEach(Array(allImages.enumerated()), id: \.offset) { _, item in
                                ZStack(alignment: .topTrailing) {
                                    if item.isExisting, let url = item.urlOrNil {
                                        CachedAsyncImage(url: URL(string: url)) { image in
                                            image.resizable().scaledToFill()
                                                .frame(maxWidth: .infinity)
                                                .clipped()
                                        } placeholder: {
                                            ZStack {
                                                Color.gray.opacity(0.05)
                                                ProgressView().tint(DS.Color.primary)
                                            }
                                        }
                                    } else if !item.isExisting, selectedImages.indices.contains(item.index) {
                                        Image(uiImage: selectedImages[item.index])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(maxWidth: .infinity)
                                            .clipped()
                                    }

                                    Button {
                                        withAnimation {
                                            if item.isExisting {
                                                existingImageURLs.remove(at: item.index)
                                            } else {
                                                selectedImages.remove(at: item.index)
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(DS.Font.scaled(22, weight: .bold))
                                            .foregroundColor(.white)
                                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                                    }
                                    .padding(DS.Spacing.sm)
                                }
                            }
                        }
                        .aspectRatio(4/5, contentMode: .fit)
                        .clipped()
                        .tabViewStyle(.page(indexDisplayMode: allImages.count > 1 ? .automatic : .never))
                    }

                    if selectedType == "تصويت" {
                        VStack(spacing: DS.Spacing.sm) {
                            TextField(L10n.t("سؤال التصويت (اختياري)", "Poll question (optional)"), text: $pollQuestion)
                                .textFieldStyle(.roundedBorder)
                            TextField(L10n.t("الخيار الأول", "Option 1"), text: $pollOption1)
                                .textFieldStyle(.roundedBorder)
                            TextField(L10n.t("الخيار الثاني", "Option 2"), text: $pollOption2)
                                .textFieldStyle(.roundedBorder)
                            TextField(L10n.t("الخيار الثالث (اختياري)", "Option 3 (optional)"), text: $pollOption3)
                                .textFieldStyle(.roundedBorder)
                            TextField(L10n.t("الخيار الرابع (اختياري)", "Option 4 (optional)"), text: $pollOption4)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    DSPrimaryButton(
                        L10n.t("حفظ التعديلات", "Save Changes"),
                        icon: "checkmark.circle.fill",
                        isLoading: authVM.isLoading,
                        useGradient: canSubmit,
                        color: canSubmit ? DS.Color.primary : .gray
                    ) {
                        Task { await submitEdits() }
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1.0 : 0.6)
                }
                .padding(DS.Spacing.lg)
            }
            .navigationTitle(L10n.t("تعديل الخبر", "Edit Post"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.error)
                }
            }
            .alert(L10n.t("تعذر التعديل", "Edit Failed"), isPresented: $showEditErrorAlert) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: { Text(authVM.newsPostErrorMessage ?? L10n.t("حدث خطأ أثناء تعديل الخبر.", "An error occurred while updating.")) }
            .onChange(of: editPickerItems) { _, items in
                Task {
                    await MainActor.run { isLoadingEditImages = true }
                    var loaded: [UIImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) { loaded.append(image) }
                    }
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    await MainActor.run {
                        selectedImages = loaded
                        isLoadingEditImages = false
                    }
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }

    private func submitEdits() async {
        guard canSubmit else { return }

        var imageURLs = existingImageURLs
        if let authorId = authVM.currentUser?.id {
            for image in selectedImages {
                if let url = await authVM.uploadNewsImage(image: image, for: authorId) {
                    imageURLs.append(url)
                }
            }
        }

        let question = pollQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let isUpdated = await authVM.updateNewsPost(
            postId: news.id,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            type: selectedType,
            imageURLs: imageURLs,
            pollQuestion: selectedType == "تصويت" && !question.isEmpty ? question : nil,
            pollOptions: selectedType == "تصويت" ? normalizedPollOptions : []
        )

        if isUpdated {
            dismiss()
        } else {
            showEditErrorAlert = true
        }
    }
}

// MARK: - أيقونة الهيدر — Glass circle
struct headerIconView: View {
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
