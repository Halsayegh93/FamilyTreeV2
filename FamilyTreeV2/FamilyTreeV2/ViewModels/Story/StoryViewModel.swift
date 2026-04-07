import Foundation
import Combine
import Supabase
import SwiftUI

@MainActor
class StoryViewModel: ObservableObject {

    // MARK: - Supabase
    let supabase = SupabaseConfig.client

    // MARK: - Published
    @Published var activeStories: [FamilyStory] = []
    @Published var pendingStories: [FamilyStory] = []
    @Published var isLoading: Bool = false
    @Published var isUploading: Bool = false
    @Published var errorMessage: String?
    @Published var viewCounts: [UUID: Int] = [:]  // storyId → عدد المشاهدات

    // MARK: - Dependencies
    weak var authVM: AuthViewModel?
    weak var memberVM: MemberViewModel?
    weak var notificationVM: NotificationViewModel?

    func configure(authVM: AuthViewModel, memberVM: MemberViewModel, notificationVM: NotificationViewModel) {
        self.authVM = authVM
        self.memberVM = memberVM
        self.notificationVM = notificationVM
    }

    // MARK: - Helpers
    private var currentUser: FamilyMember? { authVM?.currentUser }
    private var canModerate: Bool { authVM?.canModerate ?? false }

    // Throttle
    private var lastFetchDate: Date?
    private var lastPendingFetchDate: Date?

    /// أعضاء عندهم قصص نشطة (مجمعة حسب العضو)
    /// القصص المعتمدة تظهر للكل + قصص المستخدم الحالي المعلقة تظهر له
    var membersWithStories: [(member: FamilyMember, stories: [FamilyStory])] {
        let userId = currentUser?.id
        let visible = activeStories.filter { story in
            let approved = story.isApproved && !story.isExpired
            let myPending = story.createdBy == userId && !story.isExpired
            let moderatorView = canModerate && !story.isExpired
            return approved || myPending || moderatorView
        }
        let grouped = Dictionary(grouping: visible, by: { $0.memberId })
        return grouped.compactMap { (memberId, stories) in
            guard let member = memberVM?.member(byId: memberId) else { return nil }
            let sorted = stories.sorted { $0.createdDate < $1.createdDate }
            return (member: member, stories: sorted)
        }
        .sorted { $0.stories.last?.createdDate ?? .distantPast > $1.stories.last?.createdDate ?? .distantPast }
    }

    // MARK: - Fetch Active Stories

    func fetchActiveStories(force: Bool = false) async {
        // تحميل من الكاش أولاً
        if activeStories.isEmpty,
           let cached = CacheManager.shared.load([FamilyStory].self, for: .stories) {
            self.activeStories = cached.filter { !$0.isExpired }
            Log.info("[Stories] تم تحميل \(self.activeStories.count) قصة من الكاش")
        }

        if !force, let last = lastFetchDate, Date().timeIntervalSince(last) < 15, !activeStories.isEmpty { return }

        guard NetworkMonitor.shared.isConnected else { return }

        lastFetchDate = Date()

        let now = ISO8601DateFormatter().string(from: Date())

        do {
            // القصص المعتمدة للكل
            let approved: [FamilyStory] = try await supabase
                .from("family_stories")
                .select()
                .eq("approval_status", value: ApprovalStatus.approved.rawValue)
                .gte("expires_at", value: now)
                .order("created_at", ascending: false)
                .execute()
                .value

            // القصص المعلقة — المشرف/المدير يشوف الكل، العضو يشوف حقه بس
            var pending: [FamilyStory] = []
            if canModerate {
                pending = try await supabase
                    .from("family_stories")
                    .select()
                    .eq("approval_status", value: ApprovalStatus.pending.rawValue)
                    .gte("expires_at", value: now)
                    .order("created_at", ascending: false)
                    .execute()
                    .value
            } else if let userId = currentUser?.id {
                pending = try await supabase
                    .from("family_stories")
                    .select()
                    .eq("approval_status", value: ApprovalStatus.pending.rawValue)
                    .eq("created_by", value: userId.uuidString)
                    .gte("expires_at", value: now)
                    .order("created_at", ascending: false)
                    .execute()
                    .value
            }

            // دمج بدون تكرار
            var all = approved
            let approvedIds = Set(approved.map { $0.id })
            for story in pending where !approvedIds.contains(story.id) {
                all.append(story)
            }

            self.activeStories = all

            // حفظ في الكاش
            CacheManager.shared.save(all, for: .stories)
        } catch {
            Log.error("فشل جلب القصص: \(error.localizedDescription)")
        }
    }

    // MARK: - Fetch Pending Stories (Admin)

    func fetchPendingStories(force: Bool = false) async {
        guard canModerate else { return }
        if !force, let last = lastPendingFetchDate, Date().timeIntervalSince(last) < 15, !pendingStories.isEmpty { return }
        lastPendingFetchDate = Date()

        do {
            let stories: [FamilyStory] = try await supabase
                .from("family_stories")
                .select()
                .eq("approval_status", value: ApprovalStatus.pending.rawValue)
                .order("created_at", ascending: false)
                .execute()
                .value

            self.pendingStories = stories
        } catch {
            Log.error("فشل جلب الستوريات المعلقة: \(error.localizedDescription)")
        }
    }

    // MARK: - Upload Story

    func uploadStory(image: UIImage, caption: String?) async -> Bool {
        guard let userId = currentUser?.id else { return false }
        // إزالة الـ alpha channel لتقليل حجم الذاكرة
        guard let imageData = ImageProcessor.process(image, for: .story) else { return false }

        isUploading = true
        defer { isUploading = false }

        let storyId = UUID()
        let filePath = "story_\(userId.uuidString)/\(storyId.uuidString).jpg"

        do {
            // 1. رفع الصورة
            try await supabase.storage
                .from("stories")
                .upload(filePath, data: imageData, options: FileOptions(contentType: "image/jpeg", upsert: true))

            // 2. الحصول على الرابط العام
            let publicURL = try supabase.storage
                .from("stories")
                .getPublicURL(path: filePath)
            let timestamp = Int(Date().timeIntervalSince1970)
            let urlString = "\(publicURL.absoluteString)?v=\(timestamp)"

            // 3. تحديد حالة الموافقة
            let status = canModerate ? ApprovalStatus.approved.rawValue : ApprovalStatus.pending.rawValue

            // 4. إدراج بالقاعدة
            let payload: [String: AnyEncodable] = [
                "id": AnyEncodable(storyId.uuidString),
                "member_id": AnyEncodable(userId.uuidString),
                "image_url": AnyEncodable(urlString),
                "caption": AnyEncodable(caption),
                "approval_status": AnyEncodable(status),
                "created_by": AnyEncodable(userId.uuidString)
            ]

            try await supabase
                .from("family_stories")
                .insert(payload)
                .execute()

            // 5. إشعار المدراء إذا يحتاج موافقة
            if !canModerate {
                let memberName = currentUser?.firstName ?? ""
                await notificationVM?.notifyAdminsWithPush(
                    title: L10n.t("قصة جديدة تحتاج موافقة", "New Story Needs Approval"),
                    body: L10n.t(
                        "«\(memberName)» أضاف قصة جديدة تنتظر الموافقة",
                        "«\(memberName)» added a new story awaiting approval"
                    ),
                    kind: NotificationKind.storyPending.rawValue
                )
            }

            // 6. تحديث القوائم
            await fetchActiveStories(force: true)

            Log.info("تم رفع الستوري بنجاح — \(status)")
            return true

        } catch {
            Log.error("فشل رفع الستوري: \(error.localizedDescription)")
            errorMessage = L10n.t("فشل رفع القصة", "Failed to upload story")
            return false
        }
    }

    // MARK: - Approve Story

    func approveStory(_ story: FamilyStory) async {
        guard canModerate, let approverId = currentUser?.id else { return }

        // Optimistic remove from pending
        pendingStories.removeAll { $0.id == story.id }

        do {
            let payload: [String: AnyEncodable] = [
                "approval_status": AnyEncodable(ApprovalStatus.approved.rawValue),
                "approved_by": AnyEncodable(approverId.uuidString),
                "approved_at": AnyEncodable(ISO8601DateFormatter().string(from: Date()))
            ]

            try await supabase
                .from("family_stories")
                .update(payload)
                .eq("id", value: story.id.uuidString)
                .execute()

            // إشعار صاحب الستوري
            _ = memberVM?.member(byId: story.createdBy)?.firstName ?? ""
            await notificationVM?.sendNotification(
                title: L10n.t("تم نشر قصتك", "Your Story is Published"),
                body: L10n.t(
                    "تمت الموافقة على قصتك وأصبحت مرئية للجميع",
                    "Your story was approved and is now visible"
                ),
                targetMemberIds: [story.createdBy]
            )

            await fetchActiveStories(force: true)
            Log.info("تم اعتماد الستوري: \(story.id)")

        } catch {
            Log.error("فشل اعتماد الستوري: \(error.localizedDescription)")
            await fetchPendingStories(force: true)
        }
    }

    // MARK: - Reject Story

    func rejectStory(_ story: FamilyStory) async {
        guard canModerate else { return }

        pendingStories.removeAll { $0.id == story.id }

        do {
            // حذف الصورة من التخزين
            let urlComponents = story.imageUrl.components(separatedBy: "/stories/")
            if let path = urlComponents.last?.components(separatedBy: "?").first {
                _ = try? await supabase.storage.from("stories").remove(paths: [path])
            }

            // حذف السجل
            try await supabase
                .from("family_stories")
                .delete()
                .eq("id", value: story.id.uuidString)
                .execute()

            // إشعار صاحب الستوري
            await notificationVM?.sendNotification(
                title: L10n.t("تم رفض القصة", "Story Rejected"),
                body: L10n.t(
                    "تم رفض قصتك من قبل الإدارة",
                    "Your story was rejected by admin"
                ),
                targetMemberIds: [story.createdBy]
            )

            Log.info("تم رفض الستوري: \(story.id)")

        } catch {
            Log.error("فشل رفض الستوري: \(error.localizedDescription)")
            await fetchPendingStories(force: true)
        }
    }

    // MARK: - Delete Story

    func deleteStory(_ story: FamilyStory) async {
        do {
            let urlComponents = story.imageUrl.components(separatedBy: "/stories/")
            if let path = urlComponents.last?.components(separatedBy: "?").first {
                _ = try? await supabase.storage.from("stories").remove(paths: [path])
            }

            try await supabase
                .from("family_stories")
                .delete()
                .eq("id", value: story.id.uuidString)
                .execute()

            activeStories.removeAll { $0.id == story.id }
            pendingStories.removeAll { $0.id == story.id }

            Log.info("تم حذف الستوري: \(story.id)")
        } catch {
            Log.error("فشل حذف الستوري: \(error.localizedDescription)")
        }
    }

    // MARK: - Story Views (المشاهدات)

    /// تسجيل مشاهدة — مرة وحدة لكل مستخدم لكل قصة
    func recordView(storyId: UUID) async {
        guard let viewerId = currentUser?.id else { return }

        do {
            let payload: [String: AnyEncodable] = [
                "story_id": AnyEncodable(storyId.uuidString),
                "viewer_id": AnyEncodable(viewerId.uuidString)
            ]

            try await supabase
                .from("family_story_views")
                .upsert(payload, onConflict: "story_id,viewer_id")
                .execute()
        } catch {
            // تجاهل — مشاهدة مكررة أو خطأ بسيط
        }
    }

    /// جلب عدد المشاهدات لمجموعة قصص
    func fetchViewCounts(storyIds: [UUID]) async {
        guard !storyIds.isEmpty else { return }

        do {
            struct ViewCount: Decodable {
                let storyId: UUID
                let count: Int

                enum CodingKeys: String, CodingKey {
                    case storyId = "story_id"
                    case count
                }
            }

            // جلب عدد المشاهدات لكل قصة
            for storyId in storyIds {
                let count: Int = try await supabase
                    .from("family_story_views")
                    .select("*", head: true, count: .exact)
                    .eq("story_id", value: storyId.uuidString)
                    .execute()
                    .count ?? 0

                viewCounts[storyId] = count
            }
        } catch {
            Log.error("فشل جلب المشاهدات: \(error.localizedDescription)")
        }
    }
}

// MARK: - UIImage Alpha Extension

extension UIImage {
    func withoutAlpha() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
