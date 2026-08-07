import Foundation
import Combine
import Supabase

/// قائمة العوائل التي تضعها الإدارة، ويختار منها العضو عائلته.
/// الاسم يُخزَّن نصّاً في `profiles.family_name` — فلو حُذف من القائمة لاحقاً
/// يبقى اسم العضو كما هو ولا يضيع.
nonisolated struct FamilyNameOption: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var sortOrder: Int
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }
}

@MainActor
final class FamilyNamesViewModel: ObservableObject {
    @Published var options: [FamilyNameOption] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseConfig.client
    private let table = "family_names"
    private var didLoad = false

    /// أسماء العوائل الفعّالة فقط — للاختيار في التسجيل وتعديل الملف
    var activeNames: [String] {
        options.filter(\.isActive).map(\.name)
    }

    func fetch(force: Bool = false) async {
        guard force || !didLoad else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let rows: [FamilyNameOption] = try await supabase.from(table)
                .select()
                .order("sort_order", ascending: true)
                .order("name", ascending: true)
                .execute().value
            options = rows
            didLoad = true
        } catch {
            // الجدول قد لا يكون مُهاجَراً بعد — لا نُفشل الشاشة، لكن نُظهر السبب
            // بدل قائمة فارغة صامتة يستحيل تشخيصها من الجهاز.
            errorMessage = error.localizedDescription
            Log.warning("[FamilyNames] تعذّر الجلب: \(error.localizedDescription)")
        }
    }

    // MARK: - إدارة القائمة (للمالك والمدير — RLS تتكفّل بالتحقق)

    @discardableResult
    func add(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !options.contains(where: { $0.name == trimmed }) else {
            errorMessage = L10n.t("هذه العائلة موجودة مسبقاً.", "This family already exists.")
            return false
        }
        do {
            let payload: [String: AnyEncodable] = [
                "name": AnyEncodable(trimmed),
                "sort_order": AnyEncodable((options.map(\.sortOrder).max() ?? 0) + 1)
            ]
            try await supabase.from(table).insert(payload).execute()
            await fetch(force: true)
            return true
        } catch {
            errorMessage = L10n.t("تعذّرت الإضافة. \(error.localizedDescription)",
                                  "Add failed. \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func rename(id: UUID, to newName: String) async -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            try await supabase.from(table)
                .update(["name": AnyEncodable(trimmed)])
                .eq("id", value: id.uuidString)
                .execute()
            await fetch(force: true)
            return true
        } catch {
            errorMessage = L10n.t("تعذّر التعديل.", "Rename failed.")
            return false
        }
    }

    /// تعطيل بدل حذف — أعضاء اختاروها سابقاً يحتفظون باسمهم
    @discardableResult
    func setActive(id: UUID, _ active: Bool) async -> Bool {
        do {
            try await supabase.from(table)
                .update(["is_active": AnyEncodable(active)])
                .eq("id", value: id.uuidString)
                .execute()
            await fetch(force: true)
            return true
        } catch {
            errorMessage = L10n.t("تعذّر التحديث.", "Update failed.")
            return false
        }
    }

    @discardableResult
    func delete(id: UUID) async -> Bool {
        do {
            try await supabase.from(table).delete().eq("id", value: id.uuidString).execute()
            await fetch(force: true)
            return true
        } catch {
            errorMessage = L10n.t("تعذّر الحذف.", "Delete failed.")
            return false
        }
    }
}
