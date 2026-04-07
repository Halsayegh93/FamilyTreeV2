import Foundation
import Supabase
import SwiftUI
import Combine

@MainActor
class NewsViewModel: ObservableObject {

    // MARK: - Private Types

    private struct NewsPollVoteRecord: Decodable {
        let news_id: UUID
        let member_id: UUID
        let option_index: Int
    }

    // MARK: - Supabase Client

    let supabase = SupabaseConfig.client

    // MARK: - Published Properties

    @Published var allNews: [NewsPost] = []
    @Published var pendingNewsRequests: [NewsPost] = []
    @Published var pollVotesByPost: [UUID: [Int: Int]] = [:]
    @Published var userVoteByPost: [UUID: Int] = [:]
    @Published var likedPosts: Set<UUID> = []
    @Published var likesCountByPost: [UUID: Int] = [:]
    @Published var commentsCountByPost: [UUID: Int] = [:]
    @Published var commentsByPost: [UUID: [NewsCommentRecord]] = [:]
    @Published var newsApprovalFeatureAvailable: Bool = true
    @Published var newsPollFeatureAvailable: Bool = true
    @Published var newsPostErrorMessage: String?
    @Published var isLoading: Bool = false

    // MARK: - Fetch Throttle Timestamps

    private var lastNewsFetchDate: Date?
    private var lastPendingNewsFetchDate: Date?

    // MARK: - Dependencies

    weak var authVM: AuthViewModel?
    weak var memberVM: MemberViewModel?
    weak var notificationVM: NotificationViewModel?

    // MARK: - Configure

    func configure(authVM: AuthViewModel, memberVM: MemberViewModel, notificationVM: NotificationViewModel) {
        self.authVM = authVM
        self.memberVM = memberVM
        self.notificationVM = notificationVM
    }

    // MARK: - Local Removal Helper

    private func removeLocallyThenRefresh<T: Identifiable>(
        from array: inout [T],
        id: T.ID,
        refresh: @escaping () async -> Void
    ) {
        withAnimation(.snappy(duration: 0.25)) {
            array.removeAll { $0.id as AnyHashable == id as AnyHashable }
        }
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refresh()
        }
    }

    /// حذف فوري ثم تنفيذ API + تحديث بالخلفية (optimistic)
    private func optimisticRemove<T: Identifiable>(
        from array: inout [T],
        id: T.ID,
        apiWork: @escaping () async -> Void,
        refresh: @escaping () async -> Void
    ) {
        withAnimation(.snappy(duration: 0.25)) {
            array.removeAll { $0.id as AnyHashable == id as AnyHashable }
        }
        Task {
            await apiWork()
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refresh()
        }
    }

    // MARK: - Computed Properties

    var canAutoPublishNews: Bool { authVM?.canModerate ?? false }

    private var currentUser: FamilyMember? { authVM?.currentUser }

    private var canModerate: Bool { authVM?.canModerate ?? false }

    // MARK: - Auth Helper

    private func authenticatedUserId() async -> UUID? {
        if let sessionUser = try? await supabase.auth.session.user {
            return sessionUser.id
        }
        return currentUser?.id
    }

    // MARK: - Schema Error Helpers (delegated to ErrorHelper)

    // MARK: - Fetch News

    func fetchNews(force: Bool = false) async {
        // تحميل من الكاش أولاً
        if allNews.isEmpty,
           let cached = CacheManager.shared.load([NewsPost].self, for: .news) {
            self.allNews = cached
            Log.info("[News] تم تحميل \(cached.count) خبر من الكاش")
        }

        if !force, let last = lastNewsFetchDate, Date().timeIntervalSince(last) < 10, !allNews.isEmpty { return }

        guard NetworkMonitor.shared.isConnected else { return }

        lastNewsFetchDate = Date()
        do {
            let response: [NewsPost] = try await supabase.from("news")
                .select()
                .order("created_at", ascending: false)
                .limit(10000)
                .execute()
                .value

            let userId = currentUser?.id
            if canModerate {
                self.allNews = response
            } else {
                self.allNews = response.filter { post in
                    post.isApproved || post.author_id == userId
                }
            }

            // حفظ في الكاش
            CacheManager.shared.save(self.allNews, for: .news)

            // تجنب إطلاق طلبات فرعية إذا تم إلغاء المهمة
            guard !Task.isCancelled else { return }

            let pollPostIds = allNews.filter { $0.hasPoll }.map(\.id)
            let allPostIds = allNews.map(\.id)
            await fetchNewsPollVotes(for: pollPostIds)
            await fetchNewsLikes(for: allPostIds)
            await fetchNewsComments(for: allPostIds)
        } catch {
            Log.error("خطأ جلب الأخبار: \(error)")
        }
    }

    // MARK: - Fetch Poll Votes

    func fetchNewsPollVotes(for postIds: [UUID]) async {
        guard newsPollFeatureAvailable else {
            pollVotesByPost = [:]
            userVoteByPost = [:]
            return
        }
        guard !postIds.isEmpty else {
            pollVotesByPost = [:]
            userVoteByPost = [:]
            return
        }

        do {
            let postIdSet = Set(postIds)
            let votes: [NewsPollVoteRecord] = try await supabase
                .from("news_poll_votes")
                .select("news_id,member_id,option_index")
                .limit(10000)
                .execute()
                .value

            var aggregated: [UUID: [Int: Int]] = [:]
            var userSelection: [UUID: Int] = [:]
            let currentUserId = currentUser?.id

            for vote in votes where postIdSet.contains(vote.news_id) {
                aggregated[vote.news_id, default: [:]][vote.option_index, default: 0] += 1
                if let currentUserId, vote.member_id == currentUserId {
                    userSelection[vote.news_id] = vote.option_index
                }
            }

            pollVotesByPost = aggregated
            userVoteByPost = userSelection
            newsPollFeatureAvailable = true
        } catch {
            if ErrorHelper.isMissingTable(error, table: "news_poll_votes") {
                newsPollFeatureAvailable = false
                pollVotesByPost = [:]
                userVoteByPost = [:]
            } else {
                Log.error("خطأ جلب أصوات التصويت: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Fetch Likes

    func fetchNewsLikes(for postIds: [UUID]) async {
        guard !postIds.isEmpty else {
            likesCountByPost = [:]
            likedPosts = []
            return
        }

        do {
            let postIdSet = Set(postIds)
            let likes: [NewsLikeRecord] = try await supabase
                .from("news_likes")
                .select("id,news_id,member_id")
                .order("news_id")
                .limit(10000)
                .execute()
                .value

            var counts: [UUID: Int] = [:]
            var userLikes: Set<UUID> = []
            let currentUserId = await authenticatedUserId()

            for like in likes where postIdSet.contains(like.news_id) {
                counts[like.news_id, default: 0] += 1
                if let currentUserId, like.member_id == currentUserId {
                    userLikes.insert(like.news_id)
                }
            }

            self.likesCountByPost = counts
            self.likedPosts = userLikes
        } catch {
            if ErrorHelper.isCancellation(error) { return }
            Log.error("خطأ جلب الاعجابات: \(error.localizedDescription)")
        }
    }

    // MARK: - Fetch Comments

    func fetchNewsComments(for postIds: [UUID]) async {
        guard !postIds.isEmpty else {
            commentsByPost = [:]
            commentsCountByPost = [:]
            return
        }

        do {
            let postIdSet = Set(postIds)
            let commentsData: [NewsCommentRecord] = try await supabase
                .from("news_comments")
                .select()
                .order("created_at", ascending: true)
                .limit(10000)
                .execute()
                .value

            var aggregated: [UUID: [NewsCommentRecord]] = [:]
            var counts: [UUID: Int] = [:]

            for comment in commentsData where postIdSet.contains(comment.news_id) {
                aggregated[comment.news_id, default: []].append(comment)
                counts[comment.news_id, default: 0] += 1
            }

            self.commentsByPost = aggregated
            self.commentsCountByPost = counts
        } catch {
            if ErrorHelper.isCancellation(error) { return }
            Log.error("خطأ جلب التعليقات: \(error.localizedDescription)")
        }
    }

    // MARK: - Toggle Like

    func toggleNewsLike(for postId: UUID) async {
        guard let memberId = await authenticatedUserId() else { return }

        let isCurrentlyLiked = likedPosts.contains(postId)

        // Optimistic update
        if isCurrentlyLiked {
            likedPosts.remove(postId)
            likesCountByPost[postId, default: 1] -= 1
        } else {
            likedPosts.insert(postId)
            likesCountByPost[postId, default: 0] += 1
        }

        do {
            if isCurrentlyLiked {
                try await supabase
                    .from("news_likes")
                    .delete()
                    .eq("news_id", value: postId.uuidString)
                    .eq("member_id", value: memberId.uuidString)
                    .execute()
            } else {
                let likeRecord: [String: AnyEncodable] = [
                    "news_id": AnyEncodable(postId.uuidString),
                    "member_id": AnyEncodable(memberId.uuidString)
                ]
                try await supabase
                    .from("news_likes")
                    .insert(likeRecord)
                    .execute()

                // إشعار صاحب الخبر بالإعجاب (إذا مو هو نفسه)
                if let postAuthorId = allNews.first(where: { $0.id == postId })?.author_id,
                   postAuthorId != memberId {
                    let likerName = currentUser?.fullName ?? ""
                    await notificationVM?.sendPushToMembers(
                        title: L10n.t("إعجاب جديد", "New Like"),
                        body: L10n.t(
                            "\(likerName) أعجب بمنشورك",
                            "\(likerName) liked your post"
                        ),
                        kind: NotificationKind.newsLike.rawValue,
                        targetMemberIds: [postAuthorId]
                    )
                    // حفظ داخلي
                    let payload: [String: AnyEncodable] = [
                        "target_member_id": AnyEncodable(postAuthorId.uuidString),
                        "title": AnyEncodable(L10n.t("إعجاب جديد ❤️", "New Like ❤️")),
                        "body": AnyEncodable(L10n.t("\(likerName) أعجب بخبرك", "\(likerName) liked your post")),
                        "kind": AnyEncodable(NotificationKind.newsLike.rawValue),
                        "created_by": AnyEncodable(memberId.uuidString)
                    ]
                    _ = try? await supabase.from("notifications").insert(payload).execute()
                }
            }
        } catch {
            Log.error("خطأ تحديث الاعجاب: \(error.localizedDescription)")
            // Revert on error
            if isCurrentlyLiked {
                likedPosts.insert(postId)
                likesCountByPost[postId, default: 0] += 1
            } else {
                likedPosts.remove(postId)
                likesCountByPost[postId, default: 1] -= 1
            }
        }
    }

    // MARK: - Add Comment

    func addNewsComment(to postId: UUID, text: String) async -> Bool {
        guard let memberId = await authenticatedUserId(),
              let authorName = currentUser?.fullName else { return false }

        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return false }

        do {
            let commentRecord: [String: AnyEncodable] = [
                "news_id": AnyEncodable(postId.uuidString),
                "author_id": AnyEncodable(memberId.uuidString),
                "author_name": AnyEncodable(authorName),
                "content": AnyEncodable(normalizedText)
            ]

            try await supabase
                .from("news_comments")
                .insert(commentRecord)
                .execute()

            // Refresh comments to get new data
            await fetchNewsComments(for: allNews.map(\.id))

            // إشعار صاحب الخبر بالتعليق الجديد (إذا مو هو نفسه)
            if let postAuthorId = allNews.first(where: { $0.id == postId })?.author_id,
               postAuthorId != memberId {
                await notificationVM?.sendPushToMembers(
                    title: L10n.t("تعليق جديد", "New Comment"),
                    body: L10n.t(
                        "\(authorName) علّق على منشورك",
                        "\(authorName) commented on your post"
                    ),
                    kind: NotificationKind.newsComment.rawValue,
                    targetMemberIds: [postAuthorId]
                )
                // حفظ داخلي
                if let creator = currentUser?.id {
                    let payload: [String: AnyEncodable] = [
                        "target_member_id": AnyEncodable(postAuthorId.uuidString),
                        "title": AnyEncodable(L10n.t("تعليق جديد 💬", "New Comment 💬")),
                        "body": AnyEncodable(L10n.t("\(authorName) علّق على خبرك", "\(authorName) commented on your post")),
                        "kind": AnyEncodable(NotificationKind.newsComment.rawValue),
                        "created_by": AnyEncodable(creator.uuidString)
                    ]
                    _ = try? await supabase.from("notifications").insert(payload).execute()
                }
            }

            return true
        } catch {
            Log.error("خطأ إضافة تعليق: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Delete Comment (Admin/Moderator)

    func deleteComment(commentId: UUID, postId: UUID) async -> Bool {
        do {
            try await supabase
                .from("news_comments")
                .delete()
                .eq("id", value: commentId.uuidString)
                .execute()

            // تحديث محلي
            commentsByPost[postId]?.removeAll { $0.id == commentId }
            commentsCountByPost[postId] = commentsByPost[postId]?.count ?? 0

            Log.info("[News] تم حذف التعليق: \(commentId)")
            return true
        } catch {
            Log.error("[News] خطأ حذف التعليق: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Fetch Pending News Requests

    func fetchPendingNewsRequests(force: Bool = false) async {
        if !force, let last = lastPendingNewsFetchDate, Date().timeIntervalSince(last) < 20, !pendingNewsRequests.isEmpty { return }
        lastPendingNewsFetchDate = Date()
        guard canModerate else {
            pendingNewsRequests = []
            return
        }
        guard newsApprovalFeatureAvailable else {
            pendingNewsRequests = []
            return
        }

        do {
            let response: [NewsPost] = try await supabase.from("news")
                .select()
                .eq("approval_status", value: ApprovalStatus.pending.rawValue)
                .order("created_at", ascending: false)
                .execute()
                .value
            newsApprovalFeatureAvailable = true
            self.pendingNewsRequests = response
        } catch {
            if ErrorHelper.isMissingColumn(error, column: "approval_status") {
                newsApprovalFeatureAvailable = false
                pendingNewsRequests = []
            } else {
                Log.error("خطأ جلب طلبات الأخبار: \(error)")
            }
        }
    }

    // MARK: - Upload News Image

    func uploadNewsImage(image: UIImage, for authorId: UUID) async -> String? {
        guard let imageData = ImageProcessor.process(image, for: .news) else { return nil }

        let imageId = UUID()
        let safeAuthorName = memberVM?.getSafeMemberName(for: authorId) ?? authorId.uuidString
        let filePath = "news/\(safeAuthorName)/\(imageId.uuidString).jpg"

        do {
            try await supabase.storage
                .from("news")
                .upload(
                    filePath,
                    data: imageData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )

            let publicURL = try supabase.storage
                .from("news")
                .getPublicURL(path: filePath)
                .absoluteString

            return publicURL
        } catch {
            Log.error("خطأ رفع صورة الخبر: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Submit Poll Vote

    func submitNewsPollVote(postId: UUID, optionIndex: Int) async {
        guard let memberId = currentUser?.id else { return }
        guard newsPollFeatureAvailable else { return }

        do {
            let payload: [String: AnyEncodable] = [
                "news_id": AnyEncodable(postId.uuidString),
                "member_id": AnyEncodable(memberId.uuidString),
                "option_index": AnyEncodable(optionIndex)
            ]

            try await supabase
                .from("news_poll_votes")
                .upsert(payload, onConflict: "news_id,member_id")
                .execute()

            var counts = pollVotesByPost[postId] ?? [:]
            if let old = userVoteByPost[postId] {
                if old != optionIndex {
                    counts[old] = max(0, (counts[old] ?? 1) - 1)
                    counts[optionIndex] = (counts[optionIndex] ?? 0) + 1
                    userVoteByPost[postId] = optionIndex
                }
            } else {
                counts[optionIndex] = (counts[optionIndex] ?? 0) + 1
                userVoteByPost[postId] = optionIndex
            }
            pollVotesByPost[postId] = counts
        } catch {
            if ErrorHelper.isMissingTable(error, table: "news_poll_votes") {
                newsPollFeatureAvailable = false
            } else {
                Log.error("خطأ إرسال التصويت: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Post News

    func postNews(
        content: String,
        type: String,
        imageURLs: [String] = [],
        pollQuestion: String? = nil,
        pollOptions: [String] = []
    ) async -> Bool {
        guard let user = currentUser else {
            Log.error("لا يوجد مستخدم مسجل دخول")
            newsPostErrorMessage = "لا يوجد مستخدم مسجل دخول."
            return false
        }

        self.isLoading = true
        newsPostErrorMessage = nil

        let shouldAutoApprove = canAutoPublishNews

        let newPost: [String: AnyEncodable] = [
            "author_id": AnyEncodable(user.id.uuidString),
            "author_name": AnyEncodable(user.fullName),
            "author_role": AnyEncodable(user.roleName),
            "role_color": AnyEncodable(user.role.colorString),
            "content": AnyEncodable(content),
            "type": AnyEncodable(type),
            "image_url": AnyEncodable(imageURLs.first),
            "image_urls": AnyEncodable(imageURLs),
            "poll_question": AnyEncodable(pollQuestion),
            "poll_options": AnyEncodable(pollOptions),
            "approval_status": AnyEncodable(shouldAutoApprove ? ApprovalStatus.approved.rawValue : ApprovalStatus.pending.rawValue),
            "approved_by": AnyEncodable(shouldAutoApprove ? user.id.uuidString : Optional<String>.none)
        ]

        do {
            try await supabase.from("news").insert(newPost).execute()
            let posterName = currentUser?.fullName ?? ""
            if !shouldAutoApprove, currentUser?.role == .member {
                await notificationVM?.notifyAdminsWithPush(
                    title: L10n.t("منشور بانتظار الموافقة", "Post Pending Approval"),
                    body: L10n.t(
                        "\(posterName) أرسل منشوراً جديداً يحتاج موافقتكم",
                        "\(posterName) submitted a new post for review"
                    ),
                    kind: NotificationKind.newsAdd.rawValue
                )
            }
            if shouldAutoApprove {
                await notificationVM?.notifyAdminsWithPush(
                    title: L10n.t("منشور جديد", "New Post"),
                    body: L10n.t(
                        "\(posterName) نشر منشوراً جديداً",
                        "\(posterName) published a new post"
                    ),
                    kind: NotificationKind.newsPublished.rawValue
                )
            }
            Log.info(shouldAutoApprove ? "تم نشر الخبر بنجاح" : "تم إرسال الخبر للمراجعة")
            await fetchNews(force: true)
            if canModerate {
                await fetchPendingNewsRequests(force: true)
            }
            self.isLoading = false
            return true
        } catch {
            if ErrorHelper.isMissingColumn(error, column: "approval_status") ||
                ErrorHelper.isMissingColumn(error, column: "image_urls") ||
                ErrorHelper.isMissingColumn(error, column: "poll_question") ||
                ErrorHelper.isMissingColumn(error, column: "approved_by") {
                newsApprovalFeatureAvailable = false
                let legacyPost: [String: AnyEncodable] = [
                    "author_id": AnyEncodable(user.id.uuidString),
                    "author_name": AnyEncodable(user.fullName),
                    "author_role": AnyEncodable(user.roleName),
                    "role_color": AnyEncodable(user.role.colorString),
                    "content": AnyEncodable(content),
                    "type": AnyEncodable(type),
                    "image_url": AnyEncodable(imageURLs.first),
                    "image_urls": AnyEncodable(imageURLs)
                ]

                do {
                    try await supabase.from("news").insert(legacyPost).execute()
                    Log.info("تم نشر الخبر (وضع التوافق)")
                    await fetchNews(force: true)
                    self.isLoading = false
                    return true
                } catch {
                    Log.error("خطأ في نشر الخبر (وضع التوافق): \(error.localizedDescription)")
                    newsPostErrorMessage = "تعذر نشر الخبر: \(error.localizedDescription)"
                }
            } else {
                Log.error("خطأ في نشر الخبر: \(error.localizedDescription)")
                newsPostErrorMessage = "تعذر نشر الخبر: \(error.localizedDescription)"
            }
        }

        self.isLoading = false
        return false
    }

    // MARK: - Update News Post

    func updateNewsPost(
        postId: UUID,
        content: String,
        type: String,
        imageURLs: [String] = [],
        pollQuestion: String? = nil,
        pollOptions: [String] = []
    ) async -> Bool {
        guard let userId = currentUser?.id, currentUser?.role != .pending else {
            newsPostErrorMessage = "غير مصرح لك بتعديل الخبر."
            return false
        }

        // التحقق: العضو يعدل خبره فقط، المدير/المشرف يعدل أي خبر
        let isAuthor = allNews.first(where: { $0.id == postId })?.author_id == userId
        guard isAuthor || canModerate else {
            newsPostErrorMessage = L10n.t("لا يمكنك تعديل خبر غيرك.", "You can only edit your own posts.")
            return false
        }

        self.isLoading = true
        newsPostErrorMessage = nil

        let payload: [String: AnyEncodable] = [
            "content": AnyEncodable(content),
            "type": AnyEncodable(type),
            "image_url": AnyEncodable(imageURLs.first),
            "image_urls": AnyEncodable(imageURLs),
            "poll_question": AnyEncodable(pollQuestion),
            "poll_options": AnyEncodable(pollOptions)
        ]

        do {
            try await supabase
                .from("news")
                .update(payload)
                .eq("id", value: postId.uuidString)
                .execute()

            await fetchNews(force: true)
            if canModerate {
                await fetchPendingNewsRequests(force: true)
            }

            self.isLoading = false
            return true
        } catch {
            if ErrorHelper.isMissingColumn(error, column: "image_urls") ||
                ErrorHelper.isMissingColumn(error, column: "poll_question") ||
                ErrorHelper.isMissingColumn(error, column: "approved_by") {
                let legacyPayload: [String: AnyEncodable] = [
                    "content": AnyEncodable(content),
                    "type": AnyEncodable(type),
                    "image_url": AnyEncodable(imageURLs.first)
                ]

                do {
                    try await supabase
                        .from("news")
                        .update(legacyPayload)
                        .eq("id", value: postId.uuidString)
                        .execute()

                    await fetchNews(force: true)
                    if canModerate {
                        await fetchPendingNewsRequests(force: true)
                    }

                    self.isLoading = false
                    return true
                } catch {
                    Log.error("خطأ تعديل الخبر (وضع التوافق): \(error.localizedDescription)")
                    newsPostErrorMessage = "تعذر تعديل الخبر: \(error.localizedDescription)"
                }
            } else {
                Log.error("خطأ تعديل الخبر: \(error.localizedDescription)")
                newsPostErrorMessage = "تعذر تعديل الخبر: \(error.localizedDescription)"
            }
        }

        self.isLoading = false
        return false
    }

    // MARK: - Approve News Post

    func approveNewsPost(postId: UUID) async {
        guard canModerate, let approverId = currentUser?.id else { return }
        guard newsApprovalFeatureAvailable else { return }

        // حفظ authorId قبل الحذف المحلي
        let authorId = pendingNewsRequests.first(where: { $0.id == postId })?.author_id ?? allNews.first(where: { $0.id == postId })?.author_id

        optimisticRemove(from: &pendingNewsRequests, id: postId, apiWork: { [weak self] in
            do {
                let payload: [String: AnyEncodable] = [
                    "approval_status": AnyEncodable(ApprovalStatus.approved.rawValue),
                    "approved_by": AnyEncodable(approverId.uuidString),
                    "approved_at": AnyEncodable(ISO8601DateFormatter().string(from: Date()))
                ]

                try await self?.supabase
                    .from("news")
                    .update(payload)
                    .eq("id", value: postId.uuidString)
                    .execute()

                if let authorId {
                    await self?.notificationVM?.sendNotification(
                        title: L10n.t("تم نشر منشورك", "Your Post is Published"),
                        body: L10n.t("منشورك تمت الموافقة عليه وأصبح مرئياً للجميع", "Your post was approved and is now visible to everyone"),
                        targetMemberIds: [authorId]
                    )
                }
                Log.info("تم اعتماد الخبر بنجاح")
            } catch {
                if let self, ErrorHelper.isMissingColumn(error, column: "approval_status") {
                    await MainActor.run { self.newsApprovalFeatureAvailable = false }
                } else {
                    Log.error("خطأ اعتماد الخبر: \(error.localizedDescription)")
                }
            }
        }, refresh: { [weak self] in
            await self?.fetchPendingNewsRequests(force: true)
            await self?.fetchNews(force: true)
        })
    }

    // MARK: - Reject News Post

    func rejectNewsPost(postId: UUID) async {
        guard authVM?.isAdmin == true else { Log.warning("رفض الخبر مرفوض: الصلاحية للمدير فقط"); return }

        optimisticRemove(from: &pendingNewsRequests, id: postId, apiWork: { [weak self] in
            do {
                try await self?.supabase
                    .from("news")
                    .delete()
                    .eq("id", value: postId.uuidString)
                    .execute()
                Log.info("تم رفض الخبر بنجاح")
            } catch {
                Log.error("خطأ رفض الخبر: \(error.localizedDescription)")
            }
        }, refresh: { [weak self] in
            await self?.fetchPendingNewsRequests(force: true)
            await self?.fetchNews(force: true)
        })
    }

    // MARK: - Delete News Post

    func deleteNewsPost(postId: UUID) async {
        guard authVM?.canDeleteNews == true else { return }
        self.isLoading = true

        do {
            try await supabase
                .from("news")
                .delete()
                .eq("id", value: postId.uuidString)
                .execute()

            await fetchNews(force: true)
            if canModerate {
                await fetchPendingNewsRequests(force: true)
            }

            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("حذف منشور", "Post Deleted"),
                body: L10n.t("تم حذف منشور من الأخبار", "A news post has been deleted"),
                kind: NotificationKind.newsAdd.rawValue
            )
        } catch {
            Log.error("خطأ حذف الخبر: \(error.localizedDescription)")
        }

        self.isLoading = false
    }

    // MARK: - Report News Post

    func reportNewsPost(postId: UUID, reason: String = "بلاغ على محتوى خبر") async {
        guard let userId = currentUser?.id else { return }
        guard currentUser?.role == .member else { return }
        self.isLoading = true

        do {
            let payload: [String: AnyEncodable] = [
                "member_id": AnyEncodable(userId.uuidString),
                "requester_id": AnyEncodable(userId.uuidString),
                "request_type": AnyEncodable(RequestType.newsReport.rawValue),
                "new_value": AnyEncodable(postId.uuidString),
                "status": AnyEncodable(ApprovalStatus.pending.rawValue),
                "details": AnyEncodable(reason)
            ]

            try await supabase
                .from("admin_requests")
                .insert(payload)
                .execute()

            let reporterName = currentUser?.fullName ?? ""
            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("بلاغ على منشور", "Post Report"),
                body: L10n.t(
                    "\(reporterName) أبلغ عن منشور يحتاج مراجعتكم",
                    "\(reporterName) reported a post that needs your review"
                ),
                kind: NotificationKind.newsReport.rawValue
            )

            await notificationVM?.sendNotification(
                title: L10n.t("تم استلام بلاغك", "Report Received"),
                body: L10n.t("بلاغك وصلنا وسيتم مراجعته من الإدارة", "Your report was received and will be reviewed"),
                targetMemberIds: [userId]
            )
        } catch {
            Log.error("خطأ إرسال البلاغ: \(error.localizedDescription)")
        }

        self.isLoading = false
    }
}
