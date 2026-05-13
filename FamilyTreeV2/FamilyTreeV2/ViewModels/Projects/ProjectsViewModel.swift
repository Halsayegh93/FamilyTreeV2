import Foundation
import Supabase
import SwiftUI
import Combine

@MainActor
class ProjectsViewModel: ObservableObject {

    let supabase = SupabaseConfig.client
    weak var authVM: AuthViewModel?
    weak var notificationVM: NotificationViewModel?

    @Published var projects: [Project] = []
    @Published var pendingProjects: [Project] = []
    @Published var myPendingProjects: [Project] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func configure(authVM: AuthViewModel, notificationVM: NotificationViewModel) {
        self.authVM = authVM
        self.notificationVM = notificationVM
    }
    
    // MARK: - Fetch
    
    func fetchProjects() async {
        // تحميل من الكاش أولاً
        if projects.isEmpty,
           let cached = CacheManager.shared.load([Project].self, for: .projects) {
            self.projects = cached
            Log.info("[Projects] تم تحميل \(cached.count) مشروع من الكاش")
        }

        guard NetworkMonitor.shared.isConnected else { return }

        isLoading = true
        errorMessage = nil
        do {
            let response: [Project] = try await supabase
                .from("projects")
                .select()
                .eq("approval_status", value: ApprovalStatus.approved.rawValue)
                .order("created_at", ascending: false)
                .execute()
                .value

            self.projects = response

            // حفظ في الكاش
            CacheManager.shared.save(response, for: .projects)
        } catch {
            self.errorMessage = L10n.t("تعذر تحميل المشاريع. حاول مرة أخرى.",
                                       "Failed to load projects. Please try again.")
            Log.error("خطأ جلب المشاريع: \(error.localizedDescription)")
        }
        isLoading = false
    }
    
    // MARK: - Add
    
    func addProject(ownerId: UUID, ownerName: String, title: String,
                    description: String?, logoUrl: String?,
                    websiteUrl: String?, instagramUrl: String?,
                    twitterUrl: String?,
                    snapchatUrl: String?, whatsappNumber: String?,
                    phoneNumber: String?) async -> Bool {
        guard NetworkMonitor.shared.requireOnline() else { return false }
        isLoading = true
        errorMessage = nil
        do {
            // نرسل فقط الحقول المطلوبة — DB يولد id و created_at تلقائياً
            // owner_id لازم يساوي auth.uid() عشان RLS يسمح بالإدراج
            var payload: [String: AnyEncodable] = [
                "owner_id": AnyEncodable(ownerId.uuidString),
                "owner_name": AnyEncodable(ownerName),
                "title": AnyEncodable(title),
                "approval_status": AnyEncodable(ApprovalStatus.pending.rawValue)
            ]
            if let description, !description.isEmpty { payload["description"] = AnyEncodable(description) }
            if let logoUrl, !logoUrl.isEmpty { payload["logo_url"] = AnyEncodable(logoUrl) }
            if let websiteUrl, !websiteUrl.isEmpty { payload["website_url"] = AnyEncodable(websiteUrl) }
            if let instagramUrl, !instagramUrl.isEmpty { payload["instagram_url"] = AnyEncodable(instagramUrl) }
            if let twitterUrl, !twitterUrl.isEmpty { payload["twitter_url"] = AnyEncodable(twitterUrl) }
            if let snapchatUrl, !snapchatUrl.isEmpty { payload["snapchat_url"] = AnyEncodable(snapchatUrl) }
            if let whatsappNumber, !whatsappNumber.isEmpty { payload["whatsapp_number"] = AnyEncodable(whatsappNumber) }
            if let phoneNumber, !phoneNumber.isEmpty { payload["phone_number"] = AnyEncodable(phoneNumber) }

            try await supabase
                .from("projects")
                .insert(payload)
                .execute()

            await fetchProjects()

            // إشعار للأدمن بطلب جديد
            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("مشروع جديد يحتاج موافقة", "New Project Needs Approval"),
                body: L10n.t(
                    "«\(ownerName)» قدّم مشروع: «\(title)»",
                    "«\(ownerName)» submitted a project: «\(title)»"
                ),
                kind: NotificationKind.projectPending.rawValue,
                requestType: "project_pending"
            )

            isLoading = false
            Log.info("[Projects] ✅ تم إضافة المشروع: \(title)")
            return true
        } catch {
            self.errorMessage = L10n.t("تعذر إضافة المشروع.",
                                       "Failed to add project.")
            Log.error("[Projects] ❌ خطأ إضافة المشروع: \(error.localizedDescription)")
            isLoading = false
            return false
        }
    }
    
    // MARK: - Fetch Pending (Admin)
    
    func fetchPendingProjects() async {
        do {
            let response: [Project] = try await supabase
                .from("projects")
                .select()
                .eq("approval_status", value: ApprovalStatus.pending.rawValue)
                .order("created_at", ascending: false)
                .execute()
                .value

            self.pendingProjects = response
        } catch {
            Log.error("خطأ جلب المشاريع المعلقة: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Fetch My Pending
    
    func fetchMyPendingProjects(ownerId: UUID) async {
        do {
            let response: [Project] = try await supabase
                .from("projects")
                .select()
                .eq("owner_id", value: ownerId.uuidString)
                .eq("approval_status", value: ApprovalStatus.pending.rawValue)
                .order("created_at", ascending: false)
                .execute()
                .value

            self.myPendingProjects = response
        } catch {
            Log.error("خطأ جلب مشاريعي المعلقة: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Approve
    
    func approveProject(id: UUID, approvedBy: UUID) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        // حفظ معلومات المشروع قبل الحذف المحلي للإشعار
        let projectInfo = pendingProjects.first(where: { $0.id == id })

        // حذف فوري محلياً
        withAnimation(.snappy(duration: 0.25)) {
            pendingProjects.removeAll { $0.id == id }
        }
        Task { [weak self] in
            do {
                try await self?.supabase
                    .from("projects")
                    .update([
                        "approval_status": ApprovalStatus.approved.rawValue,
                        "approved_by": approvedBy.uuidString
                    ])
                    .eq("id", value: id.uuidString)
                    .execute()
                await self?.fetchProjects()

                // إشعار للمالك
                if let info = projectInfo {
                    await self?.notificationVM?.sendNotification(
                        title: L10n.t("تم اعتماد مشروعك", "Your Project Was Approved"),
                        body: L10n.t(
                            "مشروع «\(info.title)» أصبح مرئياً للجميع",
                            "Project «\(info.title)» is now visible to everyone"
                        ),
                        targetMemberIds: [info.ownerId],
                        kind: NotificationKind.projectApproved.rawValue
                    )

                    // إشعار للإدارة في "المستجدات"
                    await self?.notificationVM?.notifyAdminsWithPush(
                        title: L10n.t("تم اعتماد مشروع", "Project Approved"),
                        body: L10n.t(
                            "تم اعتماد مشروع «\(info.title)» لـ «\(info.ownerName)»",
                            "Project «\(info.title)» for «\(info.ownerName)» was approved"
                        ),
                        kind: NotificationKind.projectApproved.rawValue
                    )
                }
            } catch {
                await MainActor.run { self?.errorMessage = L10n.t("تعذر اعتماد المشروع.", "Failed to approve project.") }
                Log.error("خطأ اعتماد المشروع: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Reject

    func rejectProject(id: UUID) async {
        guard authVM?.isAdmin == true else { Log.warning("رفض المشروع مرفوض: الصلاحية للمدير فقط"); return }
        // حفظ معلومات المشروع قبل الحذف المحلي للإشعار
        let projectInfo = pendingProjects.first(where: { $0.id == id })

        // حذف فوري محلياً
        withAnimation(.snappy(duration: 0.25)) {
            pendingProjects.removeAll { $0.id == id }
        }
        Task { [weak self] in
            do {
                try await self?.supabase
                    .from("projects")
                    .update(["approval_status": ApprovalStatus.rejected.rawValue])
                    .eq("id", value: id.uuidString)
                    .execute()

                // إشعار للمالك
                if let info = projectInfo {
                    await self?.notificationVM?.sendNotification(
                        title: L10n.t("لم يتم اعتماد مشروعك", "Your Project Was Not Approved"),
                        body: L10n.t(
                            "مشروع «\(info.title)» لم يتم اعتماده. تواصل مع الإدارة لمعرفة السبب.",
                            "Project «\(info.title)» was not approved. Contact admin for details."
                        ),
                        targetMemberIds: [info.ownerId],
                        kind: NotificationKind.projectRejected.rawValue
                    )

                    // إشعار للإدارة في "المستجدات"
                    await self?.notificationVM?.notifyAdminsWithPush(
                        title: L10n.t("تم رفض مشروع", "Project Rejected"),
                        body: L10n.t(
                            "تم رفض مشروع «\(info.title)» لـ «\(info.ownerName)»",
                            "Project «\(info.title)» for «\(info.ownerName)» was rejected"
                        ),
                        kind: NotificationKind.projectRejected.rawValue
                    )
                }
            } catch {
                await MainActor.run { self?.errorMessage = L10n.t("تعذر رفض المشروع.", "Failed to reject project.") }
                Log.error("خطأ رفض المشروع: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Update
    
    func updateProject(id: UUID, title: String, description: String?,
                       logoUrl: String?, websiteUrl: String?,
                       instagramUrl: String?, twitterUrl: String?,
                       snapchatUrl: String?,
                       whatsappNumber: String?, phoneNumber: String?) async -> Bool {
        guard NetworkMonitor.shared.requireOnline() else { return false }
        isLoading = true
        errorMessage = nil
        do {
            try await supabase
                .from("projects")
                .update([
                    "title": title,
                    "description": description ?? "",
                    "logo_url": logoUrl ?? "",
                    "website_url": websiteUrl ?? "",
                    "instagram_url": instagramUrl ?? "",
                    "twitter_url": twitterUrl ?? "",
                    "snapchat_url": snapchatUrl ?? "",
                    "whatsapp_number": whatsappNumber ?? "",
                    "phone_number": phoneNumber ?? ""
                ])
                .eq("id", value: id.uuidString)
                .execute()
            
            await fetchProjects()
            isLoading = false
            return true
        } catch {
            self.errorMessage = L10n.t("تعذر تحديث المشروع.",
                                       "Failed to update project.")
            Log.error("خطأ تحديث المشروع: \(error.localizedDescription)")
            isLoading = false
            return false
        }
    }
    
    // MARK: - Delete
    
    func deleteProject(id: UUID) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard authVM?.isAdmin == true else { Log.warning("حذف المشروع مرفوض: الصلاحية للمدير فقط"); return }
        do {
            try await supabase
                .from("projects")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
            
            projects.removeAll { $0.id == id }
        } catch {
            self.errorMessage = L10n.t("تعذر حذف المشروع.",
                                       "Failed to delete project.")
            Log.error("خطأ حذف المشروع: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Logo Upload
    
    func uploadLogo(imageData: Data, projectId: UUID) async -> String? {
        let path = "project-logos/\(projectId.uuidString).jpg"
        do {
            try await supabase.storage
                .from("avatars")
                .upload(path, data: imageData, options: .init(
                    contentType: "image/jpeg",
                    upsert: true
                ))
            
            let publicURL = try supabase.storage
                .from("avatars")
                .getPublicURL(path: path)
            
            return publicURL.absoluteString
        } catch {
            Log.error("خطأ رفع لوقو المشروع: \(error.localizedDescription)")
            return nil
        }
    }
}
