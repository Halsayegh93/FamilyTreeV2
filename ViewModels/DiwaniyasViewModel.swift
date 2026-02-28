import Foundation
import Supabase
import SwiftUI
import Combine

@MainActor
class DiwaniyasViewModel: ObservableObject {
    @Published var diwaniyas: [Diwaniya] = []
    @Published var pendingDiwaniyas: [Diwaniya] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    let supabase = SupabaseConfig.client
    
    func fetchDiwaniyas() async {
        isLoading = true
        errorMessage = nil
        do {
            let response: [Diwaniya] = try await supabase
                .from("diwaniyas")
                .select()
                .eq("approval_status", value: "approved")
                .execute()
                .value
            
            self.diwaniyas = response
        } catch {
            self.errorMessage = error.localizedDescription
            Log.error("خطأ جلب الديوانيات: \(error.localizedDescription)")
        }
        isLoading = false
    }
    
    func fetchPendingDiwaniyas() async {
        isLoading = true
        errorMessage = nil
        do {
            let response: [Diwaniya] = try await supabase
                .from("diwaniyas")
                .select()
                .eq("approval_status", value: "pending")
                .execute()
                .value
            
            self.pendingDiwaniyas = response
        } catch {
            self.errorMessage = error.localizedDescription
            Log.error("خطأ جلب الديوانيات المعلقة: \(error.localizedDescription)")
        }
        isLoading = false
    }
    
    func addDiwaniya(ownerId: UUID, ownerName: String, title: String, scheduleText: String?, contactPhone: String?, mapsUrl: String?) async -> Bool {
        isLoading = true
        errorMessage = nil
        do {
            let newDiwaniya = Diwaniya(
                id: UUID(),
                ownerId: ownerId,
                ownerName: ownerName,
                title: title,
                scheduleText: scheduleText,
                contactPhone: contactPhone,
                mapsUrl: mapsUrl,
                imageUrl: nil,
                approvalStatus: "pending",
                approvedBy: nil
            )
            
            try await supabase
                .from("diwaniyas")
                .insert(newDiwaniya)
                .execute()
            
            isLoading = false
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            Log.error("خطأ إضافة ديوانية: \(error.localizedDescription)")
            isLoading = false
            return false
        }
    }
    
    func deleteDiwaniya(id: UUID) async {
        isLoading = true
        do {
            try await supabase
                .from("diwaniyas")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
            await fetchDiwaniyas()
        } catch {
            self.errorMessage = error.localizedDescription
            Log.error("خطأ حذف ديوانية: \(error.localizedDescription)")
            isLoading = false
        }
    }
    
    func approveDiwaniya(id: UUID, adminId: UUID) async {
        isLoading = true
        do {
            struct UpdateData: Codable {
                let approval_status: String
                let approved_by: UUID
            }
            try await supabase
                .from("diwaniyas")
                .update(UpdateData(approval_status: "approved", approved_by: adminId))
                .eq("id", value: id.uuidString)
                .execute()
            await fetchPendingDiwaniyas()
        } catch {
            self.errorMessage = error.localizedDescription
            Log.error("خطأ اعتماد ديوانية: \(error.localizedDescription)")
            isLoading = false
        }
    }
    
    func rejectDiwaniya(id: UUID) async {
        await deleteDiwaniya(id: id)
        await fetchPendingDiwaniyas()
    }
}
