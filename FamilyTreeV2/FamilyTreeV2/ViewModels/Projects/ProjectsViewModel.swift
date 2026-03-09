import Foundation
import Supabase
import SwiftUI
import Combine

@MainActor
class ProjectsViewModel: ObservableObject {
    
    let supabase = SupabaseConfig.client
    
    @Published var projects: [Project] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Fetch
    
    func fetchProjects() async {
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
            let newProject = Project(
                ownerId: ownerId,
                ownerName: ownerName,
                title: title,
                description: description,
                logoUrl: logoUrl,
                websiteUrl: websiteUrl,
                instagramUrl: instagramUrl,
                twitterUrl: twitterUrl,
                tiktokUrl: tiktokUrl,
                snapchatUrl: snapchatUrl,
                whatsappNumber: whatsappNumber,
                phoneNumber: phoneNumber
            )
            
            try await supabase
                .from("projects")
                .insert(newProject)
                .execute()
            
            await fetchProjects()
            isLoading = false
            return true
        } catch {
            self.errorMessage = L10n.t("تعذر إضافة المشروع.",
                                       "Failed to add project.")
            Log.error("خطأ إضافة المشروع: \(error.localizedDescription)")
            isLoading = false
            return false
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
