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

    weak var notificationVM: NotificationViewModel?

    // MARK: - Local Removal Helper

    private func removeLocallyThenRefresh<T: Identifiable>(
        from array: inout [T],
        id: T.ID,
        refresh: @escaping () async -> Void
    ) {
        withAnimation(DS.Anim.snappy) {
            array.removeAll { $0.id as AnyHashable == id as AnyHashable }
        }
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refresh()
        }
    }

    func fetchDiwaniyas() async {
        isLoading = true
        errorMessage = nil
        do {
            let response: [Diwaniya] = try await supabase
                .from("diwaniyas")
                .select()
                .in("approval_status", values: ["approved", "pending"])
                .execute()
                .value

            self.diwaniyas = response
        } catch is CancellationError {
            Log.info("جلب الديوانيات تم إلغاؤه")
        } catch let urlError as URLError where urlError.code == .cancelled {
            Log.info("جلب الديوانيات تم إلغاؤه (URL)")
        } catch {
            self.errorMessage = L10n.t("تعذر تحميل الديوانيات. حاول مرة أخرى.", "Failed to load diwaniyas. Please try again.")
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
        } catch is CancellationError {
            Log.info("جلب الديوانيات المعلقة تم إلغاؤه")
        } catch let urlError as URLError where urlError.code == .cancelled {
            Log.info("جلب الديوانيات المعلقة تم إلغاؤه (URL)")
        } catch {
            self.errorMessage = L10n.t("تعذر تحميل الطلبات المعلقة. حاول مرة أخرى.", "Failed to load pending requests. Please try again.")
            Log.error("خطأ جلب الديوانيات المعلقة: \(error.localizedDescription)")
        }
        isLoading = false
    }
    
    func addDiwaniya(ownerId: UUID, ownerName: String, title: String, scheduleText: String?, contactPhone: String?, mapsUrl: String?, address: String? = nil, autoApprove: Bool = false) async -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOwner = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            self.errorMessage = L10n.t("يرجى إدخال اسم الديوانية.", "Please enter the diwaniya name.")
            return false
        }
        guard !trimmedOwner.isEmpty else {
            self.errorMessage = L10n.t("يرجى إدخال اسم صاحب الديوانية.", "Please enter the diwaniya owner name.")
            return false
        }
        isLoading = true
        errorMessage = nil
        do {
            struct InsertData: Codable {
                let id: UUID
                let owner_id: UUID
                let owner_name: String
                let title: String
                let schedule_text: String?
                let contact_phone: String?
                let maps_url: String?
                let approval_status: String
                let approved_by: UUID?
            }
            let newId = UUID()
            let status = autoApprove ? "approved" : "pending"
            try await supabase
                .from("diwaniyas")
                .insert(InsertData(
                    id: newId,
                    owner_id: ownerId,
                    owner_name: ownerName,
                    title: title,
                    schedule_text: scheduleText,
                    contact_phone: contactPhone,
                    maps_url: mapsUrl,
                    approval_status: status,
                    approved_by: autoApprove ? ownerId : nil
                ))
                .execute()

            // Update optional columns that may not exist yet
            if let address, !address.isEmpty {
                do {
                    struct AddrUpdate: Codable { let address: String }
                    try await supabase.from("diwaniyas").update(AddrUpdate(address: address)).eq("id", value: newId.uuidString).execute()
                } catch { Log.warning("address column not available: \(error.localizedDescription)") }
            }

            // Refresh the list so the new diwaniya appears
            if autoApprove {
                await fetchDiwaniyas()
            }

            isLoading = false
            return true
        } catch {
            self.errorMessage = L10n.t("فشل إضافة الديوانية. حاول مرة أخرى.", "Failed to add diwaniya. Please try again.")
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
            self.errorMessage = L10n.t("فشل حذف الديوانية. حاول مرة أخرى.", "Failed to delete diwaniya. Please try again.")
            Log.error("خطأ حذف ديوانية: \(error.localizedDescription)")
            isLoading = false
        }
    }
    
    func approveDiwaniya(id: UUID, adminId: UUID) async {
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

            // Find the owner to notify them
            if let diwaniya = pendingDiwaniyas.first(where: { $0.id == id }) {
                await notificationVM?.sendNotification(
                    title: L10n.t("تم تنفيذ طلبك", "Request Completed"),
                    body: L10n.t("تم اعتماد الديوانية", "Your diwaniya was approved"),
                    targetMemberIds: [diwaniya.ownerId]
                )
            }

            removeLocallyThenRefresh(from: &pendingDiwaniyas, id: id) { [weak self] in
                await self?.fetchPendingDiwaniyas()
            }

            // تحديث القائمة الرئيسية عشان الديوانية المعتمدة تظهر
            await fetchDiwaniyas()

            Log.info("تم اعتماد الديوانية بنجاح")
        } catch {
            self.errorMessage = L10n.t("فشل اعتماد الديوانية. حاول مرة أخرى.", "Failed to approve diwaniya. Please try again.")
            Log.error("خطأ اعتماد ديوانية: \(error.localizedDescription)")
        }
    }
    
    func updateDiwaniya(id: UUID, title: String, ownerName: String, scheduleText: String?, contactPhone: String?, mapsUrl: String?, address: String?, isClosed: Bool) async -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOwner = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            self.errorMessage = L10n.t("يرجى إدخال اسم الديوانية.", "Please enter the diwaniya name.")
            return false
        }
        guard !trimmedOwner.isEmpty else {
            self.errorMessage = L10n.t("يرجى إدخال اسم صاحب الديوانية.", "Please enter the diwaniya owner name.")
            return false
        }
        isLoading = true
        errorMessage = nil
        do {
            struct UpdateData: Codable {
                let title: String
                let owner_name: String
                let schedule_text: String?
                let contact_phone: String?
                let maps_url: String?
            }
            try await supabase
                .from("diwaniyas")
                .update(UpdateData(
                    title: title,
                    owner_name: ownerName,
                    schedule_text: scheduleText,
                    contact_phone: contactPhone,
                    maps_url: mapsUrl
                ))
                .eq("id", value: id.uuidString)
                .execute()
            
            // Update optional columns that may not exist yet
            do {
                struct ExtraUpdate: Codable { let address: String?; let is_closed: Bool }
                try await supabase.from("diwaniyas").update(ExtraUpdate(address: address, is_closed: isClosed)).eq("id", value: id.uuidString).execute()
            } catch {
                // Try each separately
                do {
                    struct AddrUpdate: Codable { let address: String? }
                    try await supabase.from("diwaniyas").update(AddrUpdate(address: address)).eq("id", value: id.uuidString).execute()
                } catch { Log.warning("address column not available: \(error.localizedDescription)") }
                do {
                    struct ClosedUpdate: Codable { let is_closed: Bool }
                    try await supabase.from("diwaniyas").update(ClosedUpdate(is_closed: isClosed)).eq("id", value: id.uuidString).execute()
                } catch { Log.warning("is_closed column not available: \(error.localizedDescription)") }
            }
            
            await fetchDiwaniyas()
            isLoading = false
            return true
        } catch {
            self.errorMessage = L10n.t("فشل تحديث الديوانية. حاول مرة أخرى.", "Failed to update diwaniya. Please try again.")
            Log.error("خطأ تحديث ديوانية: \(error.localizedDescription)")
            isLoading = false
            return false
        }
    }

    func rejectDiwaniya(id: UUID) async {
        do {
            try await supabase
                .from("diwaniyas")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()

            removeLocallyThenRefresh(from: &pendingDiwaniyas, id: id) { [weak self] in
                await self?.fetchPendingDiwaniyas()
            }

            Log.info("تم رفض الديوانية بنجاح")
        } catch {
            self.errorMessage = L10n.t("فشل رفض الديوانية. حاول مرة أخرى.", "Failed to reject diwaniya. Please try again.")
            Log.error("خطأ رفض ديوانية: \(error.localizedDescription)")
        }
    }
}
