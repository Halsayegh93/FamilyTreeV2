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
    @State private var showComingSoonAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    MainHeaderView(selectedTab: $selectedTab, showingNotifications: $showingNotifications)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: DS.Spacing.xxxl) {
                            // الوصول السريع
                            quickActionsGrid

                            // أخبار العائلة
                            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                                sectionTitle(L10n.t("أخبار العائلة", "Family News"))

                                if authVM.allNews.isEmpty {
                                    emptyNewsView
                                } else {
                                    LazyVStack(spacing: DS.Spacing.lg) {
                                        ForEach(authVM.allNews) { news in
                                            HomeNewsCardView(
                                                postId: news.id,
                                                authorName: news.author_name,
                                                role: news.author_role,
                                                roleColor: news.role_color == "purple" ? .purple : (news.role_color == "orange" ? .orange : DS.Color.primary),
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
                                                onEditTap: { postToEdit = news }
                                            )
                                        }
                                    }
                                    .padding(.horizontal, DS.Spacing.lg)
                                }
                            }
                        }
                        .padding(.top, DS.Spacing.lg)
                        .padding(.bottom, 120)
                    }
                    .refreshable { await refreshNews(notifyIfNew: true) }
                }

                // FAB + AI Button
                floatingButtons
            }
            .navigationBarHidden(true)
            .onAppear { Task { await refreshNews(notifyIfNew: false) } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await refreshNews(notifyIfNew: true) }
            }
            .sheet(isPresented: $showingAddNews) {
                AddNewsView()
                    .presentationDetents([.fraction(0.45), .medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingNotifications) { NotificationsCenterView() }
            .sheet(isPresented: $showingContactCenter) { ContactCenterView() }
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
            .alert(L10n.t("قريباً", "Coming Soon"), isPresented: $showComingSoonAlert) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: { Text(L10n.t("هذه الواجهة ستكون متوفرة قريباً.", "This screen will be available soon.")) }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Comment Sheet Component
    private func NewsCommentsSheet(news: NewsPost) -> some View {
        NavigationStack {
            VStack {
                if let postComments = authVM.commentsByPost[news.id], !postComments.isEmpty {
                    ScrollView {
                        VStack(spacing: DS.Spacing.sm) {
                            ForEach(postComments) { comment in
                                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(comment.author_name).font(DS.Font.caption1).fontWeight(.bold)
                                        Text(comment.content).font(DS.Font.callout)
                                    }
                                    Spacer()
                                    Text({
                                        let formatter = ISO8601DateFormatter()
                                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                                        let date = formatter.date(from: comment.created_at) ?? Date()
                                        let f = RelativeDateTimeFormatter()
                                        f.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
                                        return f.localizedString(for: date, relativeTo: Date())
                                    }())
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
                            .font(.system(size: 44))
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
                            .font(.system(size: 15, weight: .bold))
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
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }



    // MARK: - Quick Actions — Glass cards
    private var quickActionsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: DS.Spacing.md
        ) {
            quickActionCard(icon: "calendar",                          title: L10n.t("المناسبات", "Events"),              color: DS.Color.gridTree)      { showComingSoonAlert = true }
            quickActionCard(icon: "briefcase.fill",                    title: L10n.t("المشاريع العائلية", "Family Projects"), color: DS.Color.success)       { showComingSoonAlert = true }
            quickActionCard(icon: "photo.on.rectangle.angled.fill",    title: L10n.t("معرض الصور", "Photo Gallery"),      color: DS.Color.gridDiwaniya)  { showComingSoonAlert = true }
            quickActionCard(icon: "bubble.left.and.bubble.right.fill", title: L10n.t("تواصل", "Contact"),        color: DS.Color.gridContact)   { showingContactCenter = true }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func quickActionCard(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 60, height: 60)
                    .background(color.opacity(0.12))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(color.opacity(0.2), lineWidth: 1))
                
                Text(title)
                    .font(DS.Font.caption1)
                    .fontWeight(.medium)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(DSBoldButtonStyle())
        .frame(maxWidth: .infinity)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.title2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Floating Buttons
    private var floatingButtons: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()

                // Add News FAB
                if authVM.currentUser?.role != .pending {
                    Button(action: {
                        showingAddNews = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(DS.Color.gradientPrimary)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.7))
                            .dsGlowShadow()
                    }
                    .buttonStyle(DSBoldButtonStyle())
                    .padding(.trailing, DS.Spacing.xl)
                }
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Empty State
    private var emptyNewsView: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "newspaper")
                .font(.system(size: 44))
                .foregroundColor(DS.Color.textTertiary)
            Text(L10n.t("لا توجد أخبار حديثة", "No recent news"))
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Helpers
    func getRelativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func toggleLike(for postId: UUID) {
        Task { await authVM.toggleNewsLike(for: postId) }
    }

    @MainActor
    private func refreshNews(notifyIfNew: Bool) async {
        let previousIDs = Set(authVM.allNews.map(\.id))
        await authVM.fetchNews()
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
    let postId: UUID
    let authorName: String
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

    private func colorForType(_ type: String) -> Color {
        switch type {
        case "وفاة": return .gray
        case "زواج": return .pink
        case "مولود": return .mint
        case "تصويت": return .orange
        default: return DS.Color.primary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // هيدر الكرت
            HStack(alignment: .center, spacing: DS.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(DS.Color.gradientPrimary)
                        .frame(width: 44, height: 44)
                    Text(String(authorName.first ?? "A"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(authorName)
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                    
                    Text(L10n.t("نُشر \(time)", "Posted \(time)"))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textSecondary)
                }

                Spacer()

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
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DS.Color.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Circle())
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
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.md)
            }

            // منطقة الميديا (صور/فيديو) - ممتدة للأطراف
            if !imageUrls.isEmpty {
                TabView {
                    ForEach(Array(imageUrls.enumerated()), id: \.offset) { _, urlStr in
                        if let encodedStr = urlStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let url = URL(string: encodedStr) {
                            AsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: { 
                                ZStack {
                                    Color.gray.opacity(0.05)
                                    ProgressView().tint(DS.Color.primary) 
                                }
                            }
                        }
                    }
                }
                .frame(height: 280)
                .tabViewStyle(.page(indexDisplayMode: imageUrls.count > 1 ? .automatic : .never))
                .clipped()
            } else if let urlStr = imageUrl,
                      let encodedStr = urlStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: encodedStr) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: { 
                    ZStack {
                        Color.gray.opacity(0.05)
                        ProgressView().tint(DS.Color.primary) 
                    }
                }
                .frame(height: 280)
                .frame(maxWidth: .infinity)
                .clipped()
            }

            // التصويت
            if !pollOptions.isEmpty {
                pollSection
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.md)
            }

            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(height: 1)
                .padding(.top, !imageUrls.isEmpty || imageUrl != nil ? DS.Spacing.md : 0)

            // شريط الإجراءات
            actionBar
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
        }
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(Color.gray.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    private var pollSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if let q = pollQuestion, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(q).font(DS.Font.calloutBold)
            }
            ForEach(Array(pollOptions.enumerated()), id: \.offset) { index, option in
                let isSelected = selectedPollOption == index
                Button(action: { onVoteTap(index) }) {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? DS.Color.primary : DS.Color.textSecondary)
                            .font(.system(size: 18))
                        Text(option).font(DS.Font.callout)
                            .foregroundColor(DS.Color.textPrimary)
                        Spacer()
                        Text("\(pollVotes[index] ?? 0)")
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(isSelected ? .white : DS.Color.textSecondary)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(isSelected ? DS.Color.primary : Color.clear)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.md)
                    .background(isSelected ? DS.Color.primary.opacity(0.10) : DS.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(isSelected ? DS.Color.primary.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionBar: some View {
        let pillHeight: CGFloat = 32

        return HStack(spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                if approvalStatus == "pending" {
                    Text(L10n.t("مراجعة", "Review"))
                        .font(DS.Font.caption1)
                        .fontWeight(.semibold)
                        .foregroundColor(DS.Color.warning)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 6)
                        .background(DS.Color.warning.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(DS.Color.warning.opacity(0.25), lineWidth: 1)
                        )
                        .frame(height: pillHeight)
                }

                Text(type)
                    .font(DS.Font.caption1)
                    .fontWeight(.semibold)
                    .foregroundColor(colorForType(type))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 6)
                    .background(colorForType(type).opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(colorForType(type).opacity(0.25), lineWidth: 1)
                    )
                    .frame(height: pillHeight)
            }

            Spacer(minLength: 0)

            HStack(spacing: DS.Spacing.sm) {
                // Like Button
                Button(action: onLikeTap) {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 14, weight: isLiked ? .bold : .medium))
                            .foregroundColor(isLiked ? DS.Color.error : DS.Color.textSecondary)
                            .symbolEffect(.bounce, value: isLiked)

                        Text("\(likeCount)")
                            .font(DS.Font.caption1)
                            .fontWeight(.semibold)
                            .foregroundColor(isLiked ? DS.Color.error : DS.Color.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background((isLiked ? DS.Color.error : DS.Color.textSecondary).opacity(0.14))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 6)
                    .background(isLiked ? DS.Color.error.opacity(0.12) : Color.white.opacity(0.3))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(isLiked ? DS.Color.error.opacity(0.3) : Color.gray.opacity(0.15), lineWidth: 1))
                    .frame(height: pillHeight)
                }
                .buttonStyle(.plain)

                // Comment Button
                Button(action: onCommentTap) {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(L10n.t("تعليق", "Comment"))
                            .font(DS.Font.caption1)
                            .fontWeight(.semibold)
                            .foregroundColor(DS.Color.primary)

                        if commentCount > 0 {
                            Text("\(commentCount)")
                                .font(DS.Font.caption1)
                                .fontWeight(.semibold)
                                .foregroundColor(DS.Color.primary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(DS.Color.primary.opacity(0.14))
                                .clipShape(Capsule())
                        }

                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DS.Color.primary)
                    }
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 6)
                    .background(DS.Color.primary.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(DS.Color.primary.opacity(0.22), lineWidth: 1))
                    .frame(height: pillHeight)
                }
                .buttonStyle(.plain)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .padding(.top, 2)
    }
}

// MARK: - Local Types Removed


// MARK: - إضافة خبر
struct AddNewsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var content = ""
    @State private var selectedType = "تنبيه"
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var pollQuestion = ""
    @State private var pollOption1 = ""
    @State private var pollOption2 = ""
    @State private var pollOption3 = ""
    @State private var pollOption4 = ""
    @State private var showPostErrorAlert = false
    let types = ["زواج", "مولود", "تنبيه", "وفاة", "تصويت"]

    private func colorForType(_ type: String) -> Color {
        switch type {
        case "وفاة": return .gray
        case "زواج": return .pink
        case "مولود": return .mint
        case "تصويت": return .orange
        default: return DS.Color.primary
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
                    HStack(spacing: DS.Spacing.xs) {
                        ForEach(types, id: \.self) { type in
                            let isSelected = selectedType == type
                            let typeColor = colorForType(type)

                            Button(action: { selectedType = type }) {
                                Text(type)
                                    .font(DS.Font.caption1)
                                    .fontWeight(.bold)
                                    .foregroundColor(isSelected ? .white : typeColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? typeColor : typeColor.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                            .stroke(typeColor.opacity(0.25), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Text box (updated)
                    TextEditor(text: $content)
                        .frame(minHeight: 120, maxHeight: 150)
                        .padding(DS.Spacing.sm)
                        .background(DS.Color.surface.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .stroke(DS.Color.primary.opacity(0.10), lineWidth: 1)
                        )
                        .overlay(alignment: .topTrailing) {
                            if content.isEmpty {
                                Text(L10n.t("اكتب الخبر هنا...", "Write your post here..."))
                                    .font(DS.Font.body)
                                    .foregroundColor(DS.Color.textTertiary)
                                    .padding(.top, DS.Spacing.md)
                                    .padding(.trailing, DS.Spacing.md)
                            }
                        }

                    // Photos
                    PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 5, matching: .images) {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text(L10n.t("إضافة صور (اختياري)", "Add Photos (optional)"))
                        }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(DS.Color.primary.opacity(0.08))
                        .cornerRadius(DS.Radius.md)
                    }

                    if !selectedImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DS.Spacing.sm) {
                                ForEach(Array(selectedImages.enumerated()), id: \.offset) { _, image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 76, height: 76)
                                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                                }
                            }
                        }
                    }

                    // Poll
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
                        authVM.canAutoPublishNews ? L10n.t("نشر", "Publish") : L10n.t("إرسال", "Submit"),
                        icon: "paperplane.fill",
                        isLoading: authVM.isLoading,
                        useGradient: canSubmit,
                        color: canSubmit ? DS.Color.primary : .gray
                    ) {
                        Task { await submitNews() }
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1.0 : 0.6)
                }
                .padding(DS.Spacing.lg)
            }
            .navigationTitle(L10n.t("إضافة خبر", "Add News"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.error)
                }
            }
            .alert(L10n.t("تعذر النشر", "Post Failed"), isPresented: $showPostErrorAlert) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: { Text(authVM.newsPostErrorMessage ?? L10n.t("حدث خطأ أثناء نشر الخبر.", "An error occurred.")) }
            .onChange(of: selectedPhotoItems) { _, newItems in
                handleSelectedImages(newItems)
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }

    private func handleSelectedImages(_ items: [PhotosPickerItem]) {
        Task {
            var loaded: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) { loaded.append(image) }
            }
            await MainActor.run { selectedImages = loaded }
        }
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
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var pollQuestion: String
    @State private var pollOption1: String
    @State private var pollOption2: String
    @State private var pollOption3: String
    @State private var pollOption4: String
    @State private var showEditErrorAlert = false
    let types = ["زواج", "مولود", "تنبيه", "وفاة", "تصويت"]

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
        case "وفاة": return .gray
        case "زواج": return .pink
        case "مولود": return .mint
        case "تصويت": return .orange
        default: return DS.Color.primary
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
                    HStack(spacing: DS.Spacing.xs) {
                        ForEach(types, id: \.self) { type in
                            let isSelected = selectedType == type
                            let typeColor = colorForType(type)

                            Button(action: { selectedType = type }) {
                                Text(type)
                                    .font(DS.Font.caption1)
                                    .fontWeight(.bold)
                                    .foregroundColor(isSelected ? .white : typeColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? typeColor : typeColor.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                            .stroke(typeColor.opacity(0.25), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
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

                    PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 5, matching: .images) {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text(L10n.t("إضافة صور جديدة", "Add new photos"))
                        }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(DS.Color.primary.opacity(0.08))
                        .cornerRadius(DS.Radius.md)
                    }

                    if !existingImageURLs.isEmpty || !selectedImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DS.Spacing.sm) {
                                ForEach(Array(existingImageURLs.enumerated()), id: \.offset) { index, url in
                                    ZStack(alignment: .topTrailing) {
                                        AsyncImage(url: URL(string: url)) { image in
                                            image.resizable().scaledToFill()
                                        } placeholder: {
                                            RoundedRectangle(cornerRadius: DS.Radius.sm)
                                                .fill(DS.Color.surface)
                                        }
                                        .frame(width: 76, height: 76)
                                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

                                        Button {
                                            existingImageURLs.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white)
                                                .background(Color.black.opacity(0.45))
                                                .clipShape(Circle())
                                        }
                                        .padding(4)
                                    }
                                }

                                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 76, height: 76)
                                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

                                        Button {
                                            selectedImages.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white)
                                                .background(Color.black.opacity(0.45))
                                                .clipShape(Circle())
                                        }
                                        .padding(4)
                                    }
                                }
                            }
                        }
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
            .onChange(of: selectedPhotoItems) { _, newItems in
                handleSelectedImages(newItems)
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }

    private func handleSelectedImages(_ items: [PhotosPickerItem]) {
        Task {
            var loaded: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) { loaded.append(image) }
            }
            await MainActor.run { selectedImages = loaded }
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
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(color)
            .frame(width: 44, height: 44)
            .background(color.opacity(0.12))
            .clipShape(Circle())
            .overlay(Circle().stroke(color.opacity(0.15), lineWidth: 1))
    }
}
