import Foundation
import Supabase

/// صفّ من جدول `women_members` كما يعود من Supabase.
private struct WomenRow: Decodable {
    let id: UUID
    let firstName: String?
    let fullName: String?
    let parentId: UUID?
    let motherId: UUID?
    let husbandId: UUID?
    let gender: String?
    let sortOrder: Int?
    let isDeceased: Bool?
    let birthDate: String?
    let deathDate: String?
    let isHiddenFromTree: Bool?
    let photoUrl: String?
    let avatarUrl: String?
    let linkedUserId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case fullName = "full_name"
        case parentId = "parent_id"
        case motherId = "mother_id"
        case husbandId = "husband_id"
        case gender
        case sortOrder = "sort_order"
        case isDeceased = "is_deceased"
        case birthDate = "birth_date"
        case deathDate = "death_date"
        case isHiddenFromTree = "is_hidden_from_tree"
        case photoUrl = "photo_url"
        case avatarUrl = "avatar_url"
        case linkedUserId = "linked_user_id"
    }
}

/// طبقة بيانات شجرة النساء — قراءة/إضافة/تعديل/حذف (الكتابة للإدارة عبر RLS).
enum WomenStore {
    /// كاش بالذاكرة — يخلي الانتقال لتبويب التفرّع فورياً (بلا إعادة جلب كل مرة).
    static var cache: [FamilyMember] = []
    /// ربط حساب التطبيق ↔ اسم في شجرة النساء (مرجع إداري + زر موقعي).
    static var womanByLinkedUser: [UUID: UUID] = [:]   // userId → womanId
    static var linkedUserByWoman: [UUID: UUID] = [:]   // womanId → userId

    static func fetch() async throws -> [FamilyMember] {
        let rows: [WomenRow] = try await SupabaseConfig.client
            .from("women_members")
            .select()
            .order("sort_order", ascending: true)
            .execute()
            .value
        var byUser: [UUID: UUID] = [:]
        var byWoman: [UUID: UUID] = [:]
        for r in rows where r.linkedUserId != nil {
            byUser[r.linkedUserId!] = r.id
            byWoman[r.id] = r.linkedUserId!
        }
        womanByLinkedUser = byUser
        linkedUserByWoman = byWoman
        let mapped = rows.map { r in
            FamilyMember(
                id: r.id,
                firstName: r.firstName ?? "",
                fullName: (r.fullName?.isEmpty == false ? r.fullName! : (r.firstName ?? "")),
                birthDate: r.birthDate,
                deathDate: r.deathDate,
                isDeceased: r.isDeceased,
                role: .member,
                fatherId: r.parentId,                 // parent → father لإعادة استخدام الشجرة
                motherId: r.motherId,
                husbandId: r.husbandId,
                photoURL: r.photoUrl,
                isHiddenFromTree: r.isHiddenFromTree ?? false,
                sortOrder: r.sortOrder ?? 0,
                status: .active,
                avatarUrl: r.avatarUrl,
                gender: (r.gender?.isEmpty == false ? r.gender! : "male")
            )
        }
        cache = mapped
        return mapped
    }

    static func addChild(parentId: UUID, name: String, sortOrder: Int,
                         gender: String = "male", parentFullName: String = "",
                         birthDate: String? = nil, isDeceased: Bool = false,
                         deathDate: String? = nil) async throws {
        // تسلسل الاسم: «الاسم + اسم الأب الكامل» (مثل الشجرة العامة).
        let chained = parentFullName.trimmingCharacters(in: .whitespaces).isEmpty
            ? name : "\(name) \(parentFullName)"
        let payload: [String: AnyEncodable] = [
            "first_name": AnyEncodable(name),
            "full_name": AnyEncodable(chained),
            "parent_id": AnyEncodable(parentId.uuidString),
            "sort_order": AnyEncodable(sortOrder),
            "gender": AnyEncodable(gender),
            "birth_date": AnyEncodable(birthDate),
            "is_deceased": AnyEncodable(isDeceased),
            "death_date": AnyEncodable(isDeceased ? deathDate : Optional<String>.none)
        ]
        try await SupabaseConfig.client.from("women_members").insert(payload).execute()
    }

    /// إضافة زوجة لعقدة (تظهر كشارة على الزوج) — أنثى husband_id = العقدة.
    static func addWife(husbandId: UUID, name: String, birthDate: String? = nil,
                        isDeceased: Bool = false, deathDate: String? = nil) async throws {
        let payload: [String: AnyEncodable] = [
            "first_name": AnyEncodable(name),
            "full_name": AnyEncodable(name),
            "husband_id": AnyEncodable(husbandId.uuidString),
            "gender": AnyEncodable("female"),
            "sort_order": AnyEncodable(0),
            "birth_date": AnyEncodable(birthDate),
            "is_deceased": AnyEncodable(isDeceased),
            "death_date": AnyEncodable(isDeceased ? deathDate : Optional<String>.none)
        ]
        try await SupabaseConfig.client.from("women_members").insert(payload).execute()
    }

    /// إضافة أمّ لعقدة — تُنشئ أنثى ثم تربطها mother_id بالعقدة.
    static func addMother(childId: UUID, name: String, birthDate: String? = nil,
                          isDeceased: Bool = false, deathDate: String? = nil) async throws {
        struct InsertedRow: Decodable { let id: UUID }
        let payload: [String: AnyEncodable] = [
            "first_name": AnyEncodable(name),
            "full_name": AnyEncodable(name),
            "gender": AnyEncodable("female"),
            "sort_order": AnyEncodable(0),
            "birth_date": AnyEncodable(birthDate),
            "is_deceased": AnyEncodable(isDeceased),
            "death_date": AnyEncodable(isDeceased ? deathDate : Optional<String>.none)
        ]
        let rows: [InsertedRow] = try await SupabaseConfig.client.from("women_members")
            .insert(payload).select("id").execute().value
        guard let newId = rows.first?.id else { return }
        try await SupabaseConfig.client.from("women_members")
            .update(["mother_id": AnyEncodable(newId.uuidString)])
            .eq("id", value: childId.uuidString).execute()
    }

    static func update(id: UUID, fullName: String, isDeceased: Bool, deathDate: String?,
                       birthDate: String?, gender: String? = nil, isHidden: Bool) async throws {
        let first = fullName.components(separatedBy: " ").first ?? fullName
        var payload: [String: AnyEncodable] = [
            "full_name": AnyEncodable(fullName),
            "first_name": AnyEncodable(first),
            "is_deceased": AnyEncodable(isDeceased),
            "death_date": AnyEncodable(isDeceased ? deathDate : Optional<String>.none),
            "birth_date": AnyEncodable(birthDate),
            "is_hidden_from_tree": AnyEncodable(isHidden)
        ]
        if let gender { payload["gender"] = AnyEncodable(gender) }
        try await SupabaseConfig.client.from("women_members").update(payload).eq("id", value: id.uuidString).execute()
    }

    static func setMotherId(childId: UUID, motherId: UUID?) async throws {
        try await SupabaseConfig.client.from("women_members")
            .update(["mother_id": AnyEncodable(motherId?.uuidString)])
            .eq("id", value: childId.uuidString).execute()
    }

    /// ربط أنثى موجودة في الشجرة كزوجة لعقدة (اختيار زوجة من العائلة).
    static func setHusbandId(womanId: UUID, husbandId: UUID?) async throws {
        try await SupabaseConfig.client.from("women_members")
            .update(["husband_id": AnyEncodable(husbandId?.uuidString)])
            .eq("id", value: womanId.uuidString).execute()
    }

    // ── إدارة العضو لعائلته الخاصة (الأم/الزوجة) عبر دوال السيرفر ──────────
    static func addSelfWife(name: String) async throws {
        try await SupabaseConfig.client
            .rpc("add_self_wife", params: ["p_name": AnyEncodable(name)]).execute()
    }
    static func addSelfMother(name: String) async throws {
        try await SupabaseConfig.client
            .rpc("add_self_mother", params: ["p_name": AnyEncodable(name)]).execute()
    }
    static func setSelfMother(motherId: UUID?) async throws {
        try await SupabaseConfig.client
            .rpc("set_self_mother", params: ["p_mother_id": AnyEncodable(motherId?.uuidString)]).execute()
    }

    static func delete(id: UUID) async throws {
        try await SupabaseConfig.client.from("women_members").delete().eq("id", value: id.uuidString).execute()
    }

    /// إعادة ترتيب الأبناء — يحدّث sort_order حسب الترتيب الجديد. (إدارة فقط).
    static func reorder(orderedIds: [UUID]) async throws {
        for (i, id) in orderedIds.enumerated() {
            try await SupabaseConfig.client.from("women_members")
                .update(["sort_order": AnyEncodable(i)])
                .eq("id", value: id.uuidString).execute()
        }
    }

    /// ربط/فكّ ربط اسم في شجرة النساء بحساب مستخدم (للإدارة فقط عبر RLS).
    static func linkAccount(womanId: UUID, userId: UUID?) async throws {
        try await SupabaseConfig.client.from("women_members")
            .update(["linked_user_id": AnyEncodable(userId?.uuidString)])
            .eq("id", value: womanId.uuidString).execute()
        if let old = linkedUserByWoman[womanId] { womanByLinkedUser[old] = nil }
        if let userId {
            linkedUserByWoman[womanId] = userId
            womanByLinkedUser[userId] = womanId
        } else {
            linkedUserByWoman[womanId] = nil
        }
    }

    /// دمج سجل مكرر [removeId] في السجل المُبقى [keepId].
    static func merge(keepId: UUID, removeId: UUID) async throws {
        let c = SupabaseConfig.client
        try await c.from("women_members")
            .update(["parent_id": AnyEncodable(keepId.uuidString)])
            .eq("parent_id", value: removeId.uuidString).execute()
        try await c.from("women_members")
            .update(["mother_id": AnyEncodable(keepId.uuidString)])
            .eq("mother_id", value: removeId.uuidString).execute()
        try await c.from("women_members")
            .update(["husband_id": AnyEncodable(keepId.uuidString)])
            .eq("husband_id", value: removeId.uuidString).execute()
        try await c.from("women_members").delete().eq("id", value: removeId.uuidString).execute()
    }
}
