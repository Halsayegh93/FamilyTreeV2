import Foundation
import Supabase
import SwiftUI
import Combine

@MainActor
class ProjectsViewModel: ObservableObject {
    
    let supabase = SupabaseConfig.client
    weak var authVM: AuthViewModel?

    @Published var projects: [Project] = []
    @Published var pendingProjects: [Project] = []
    @Published var myPendingProjects: [Project] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
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
                .eq("approval_status", value: "approved")
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
                    twitterUrl: String?, tiktokUrl: String?,
                    snapchatUrl: String?, whatsappNumber: String?,
                    phoneNumber: String?) async -> Bool {
        isLoading = true
        errorMessage = nil
        do {
            // نرسل فقط الحقول المطلوبة — DB يولد id و created_at تلقائياً
            // owner_id لازم يساوي auth.uid() عشان RLS يسمح بالإدراج
            var payload: [String: AnyEncodable] = [
                "owner_id": AnyEncodable(ownerId.uuidString),
                "owner_name": AnyEncodable(ownerName),
                "title": AnyEncodable(title),
                "approval_status": AnyEncodable("pending")
            ]
            if let description, !description.isEmpty { payload["description"] = AnyEncodable(description) }
            if let logoUrl, !logoUrl.isEmpty { payload["logo_url"] = AnyEncodable(logoUrl) }
            if let websiteUrl, !websiteUrl.isEmpty { payload["website_url"] = AnyEncodable(websiteUrl) }
            if let instagramUrl, !instagramUrl.isEmpty { payload["instagram_url"] = AnyEncodable(instagramUrl) }
            if let twitterUrl, !twitterUrl.isEmpty { payload["twitter_url"] = AnyEncodable(twitterUrl) }
            if let tiktokUrl, !tiktokUrl.isEmpty { payload["tiktok_url"] = AnyEncodable(tiktokUrl) }
            if let snapchatUrl, !snapchatUrl.isEmpty { payload["snapchat_url"] = AnyEncodable(snapchatUrl) }
            if let whatsappNumber, !whatsappNumber.isEmpty { payload["whatsapp_number"] = AnyEncodable(whatsappNumber) }
            if let phoneNumber, !phoneNumber.isEmpty { payload["phone_number"] = AnyEncodable(phoneNumber) }

            try await supabase
                .from("projects")
                .insert(payload)
                .execute()

            await fetchProjects()
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
                .eq("approval_status", value: "pending")
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
                .eq("approval_status", value: "pending")
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
        // حذف فوري محلياً
        withAnimation(.snappy(duration: 0.25)) {
            pendingProjects.removeAll { $0.id == id }
        }
        Task { [weak self] in
            do {
                try await self?.supabase
                    .from("projects")
                    .update([
                        "approval_status": "approved",
                        "approved_by": approvedBy.uuidString
                    ])
                    .eq("id", value: id.uuidString)
                    .execute()
                await self?.fetchProjects()
            } catch {
                await MainActor.run { self?.errorMessage = L10n.t("تعذر اعتماد المشروع.", "Failed to approve project.") }
                Log.error("خطأ اعتماد المشروع: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Reject

    func rejectProject(id: UUID) async {
        guard authVM?.isAdmin == true else { Log.warning("رفض المشروع مرفوض: الصلاحية للمدير فقط"); return }
        // حذف فوري محلياً
        withAnimation(.snappy(duration: 0.25)) {
            pendingProjects.removeAll { $0.id == id }
        }
        Task { [weak self] in
            do {
                try await self?.supabase
                    .from("projects")
                    .update(["approval_status": "rejected"])
                    .eq("id", value: id.uuidString)
                    .execute()
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
                       tiktokUrl: String?, snapchatUrl: String?,
                       whatsappNumber: String?, phoneNumber: String?) async -> Bool {
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
                    "tiktok_url": tiktokUrl ?? "",
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
