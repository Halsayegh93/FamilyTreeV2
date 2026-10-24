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
    let isMarried: Bool?

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
        case isMarried = "is_married"
    }
}

/// فشل كتابة برسالة جاهزة للمستخدم (نداء رجع بلا نتيجة، أو رسالة من الـ ViewModel) — يعرضها `failureMessage`
struct WomenWriteFailure: Error {
    let message: String
}

/// طبقة بيانات شجرة النساء — قراءة/إضافة/تعديل/حذف (الكتابة للإدارة عبر RLS).
enum WomenStore {
    /// كاش بالذاكرة — يخلي الانتقال لتبويب التفرّع فورياً (بلا إعادة جلب كل مرة).
    static var cache: [FamilyMember] = []
    /// ربط حساب التطبيق ↔ اسم في شجرة النساء (مرجع إداري + زر موقعي).
    static var womanByLinkedUser: [UUID: UUID] = [:]   // userId → womanId
    static var linkedUserByWoman: [UUID: UUID] = [:]   // womanId → userId

    static func fetch() async throws -> [FamilyMember] {
        // سجلّات «الموقع فقط» لا وجود لها في التطبيق — تُستبعد على السيرفر
        // فلا تُنقل أصلاً، بدل تصفيتها بعد الوصول.
        let rows: [WomenRow] = try await SupabaseConfig.client
            .from("women_members")
            .select()
            .eq("is_web_only", value: false)
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
                isMarried: r.isMarried ?? false,
                gender: (r.gender?.isEmpty == false ? r.gender! : "male")
            )
        }
        cache = mapped
        return mapped
    }

    static func addChild(parentId: UUID, name: String, sortOrder: Int,
                         gender: String = "male", parentFullName: String = "",
                         birthDate: String? = nil, isDeceased: Bool = false,
                         deathDate: String? = nil, isMarried: Bool = false,
                         motherId: UUID? = nil) async throws {
        // تسلسل الاسم: «الاسم + اسم الأب الكامل» (مثل الشجرة العامة).
        let chained = parentFullName.trimmingCharacters(in: .whitespaces).isEmpty
            ? name : "\(name) \(parentFullName)"
        var payload: [String: AnyEncodable] = [
            "first_name": AnyEncodable(name),
            "full_name": AnyEncodable(chained),
            "parent_id": AnyEncodable(parentId.uuidString),
            "sort_order": AnyEncodable(sortOrder),
            "gender": AnyEncodable(gender),
            "birth_date": AnyEncodable(birthDate),
            "is_deceased": AnyEncodable(isDeceased),
            "death_date": AnyEncodable(isDeceased ? deathDate : Optional<String>.none),
            "is_married": AnyEncodable(gender == "female" && isMarried)
        ]
        // ابن/ابنة امرأة متزوجة من العائلة: الأب زوجها والأم هي (كان الأب = المرأة فيتكرّر الفرع تحتها)
        if let motherId { payload["mother_id"] = AnyEncodable(motherId.uuidString) }
        try await SupabaseConfig.client.from("women_members").insert(payload).execute()
    }

    /// إضافة ابن/ابنة عبر السيرفر (`add_family_child`): الذكر يُكتب في الشجرة العامة (profiles) وينعكس
    /// لشجرة النساء بنفس المعرّف، والأنثى في شجرة النساء وحدها. كان «إضافة ابن» من شجرة النساء يكتب
    /// الذكر في women_members مباشرة فلا يظهر في شجرة العائلة أبداً (المزامنة باتجاه واحد).
    /// السيرفر: المالك/المدير/المراقب لأي أب، والعضو لعقدته هو فقط. يرجّع معرّف الفرد الجديد.
    @discardableResult
    static func addFamilyChild(parentId: UUID, name: String, gender: String,
                               birthDate: String?, sortOrder: Int,
                               parentFullName: String) async throws -> UUID {
        // مفاتيح فارغة تُرسل null صريحة — وإلا نقص توقيع الدالة على السيرفر
        let params: [String: AnyEncodable] = [
            "p_parent_id": AnyEncodable(parentId.uuidString),
            "p_name": AnyEncodable(name),
            "p_gender": AnyEncodable(gender),
            "p_birth": AnyEncodable(birthDate),
            "p_deceased": AnyEncodable(false),
            "p_death": AnyEncodable(Optional<String>.none),
            "p_sort": AnyEncodable(sortOrder),
            "p_parent_full_name": AnyEncodable(parentFullName)
        ]
        let newId: UUID = try await SupabaseConfig.client
            .rpc("add_family_child", params: params).execute().value
        return newId
    }

    /// إضافة زوجة لعقدة (تظهر كشارة على الزوج) — أنثى husband_id = العقدة.
    static func addWife(husbandId: UUID, name: String, birthDate: String? = nil,
                        isDeceased: Bool = false, deathDate: String? = nil,
                        isMarried: Bool = false) async throws {
        let payload: [String: AnyEncodable] = [
            "first_name": AnyEncodable(name),
            "full_name": AnyEncodable(name),
            "husband_id": AnyEncodable(husbandId.uuidString),
            "gender": AnyEncodable("female"),
            "sort_order": AnyEncodable(0),
            "birth_date": AnyEncodable(birthDate),
            "is_deceased": AnyEncodable(isDeceased),
            "death_date": AnyEncodable(isDeceased ? deathDate : Optional<String>.none),
            "is_married": AnyEncodable(isMarried)
        ]
        try await SupabaseConfig.client.from("women_members").insert(payload).execute()
    }

    /// إضافة أمّ لعقدة — تُنشئ أنثى (زوجةً للأب `husbandId` إن عُرف) ثم تربطها mother_id بالعقدة.
    /// بلا زوج كانت الأم تظهر جذراً مستقلاً في أعلى الشجرة (ليست بنتاً لأحد ولا زوجة لأحد).
    static func addMother(childId: UUID, name: String, husbandId: UUID? = nil,
                          birthDate: String? = nil,
                          isDeceased: Bool = false, deathDate: String? = nil,
                          isMarried: Bool = false) async throws {
        struct InsertedRow: Decodable { let id: UUID }
        var payload: [String: AnyEncodable] = [
            "first_name": AnyEncodable(name),
            "full_name": AnyEncodable(name),
            "gender": AnyEncodable("female"),
            "sort_order": AnyEncodable(0),
            "birth_date": AnyEncodable(birthDate),
            "is_deceased": AnyEncodable(isDeceased),
            "death_date": AnyEncodable(isDeceased ? deathDate : Optional<String>.none),
            "is_married": AnyEncodable(isMarried)
        ]
        if let husbandId {
            payload["husband_id"] = AnyEncodable(husbandId.uuidString)
            payload["is_married"] = AnyEncodable(true)
        }
        let rows: [InsertedRow] = try await SupabaseConfig.client.from("women_members")
            .insert(payload).select("id").execute().value
        // بلا معرّف راجع = لم تُنشأ — خطأ لا نجاح صامت
        guard let newId = rows.first?.id else {
            throw WomenWriteFailure(message: L10n.t("لم تُحفظ الأم. حاول مرة أخرى.", "The mother wasn't saved. Try again."))
        }
        do {
            try await SupabaseConfig.client.from("women_members")
                .update(["mother_id": AnyEncodable(newId.uuidString)])
                .eq("id", value: childId.uuidString).execute()
        } catch {
            // فشل الربط → لا نترك أمّاً يتيمة بلا ابن (أفضل جهد، والخطأ الأصلي يُعرض)
            try? await SupabaseConfig.client.from("women_members").delete().eq("id", value: newId.uuidString).execute()
            throw error
        }
    }

    static func update(id: UUID, fullName: String, isDeceased: Bool, deathDate: String?,
                       birthDate: String?, gender: String? = nil, isHidden: Bool) async throws {
        // أول وحدة لا أول كلمة (PersonName القاعدة ١-ج) — «زين العابدين»/«فاطمة الزهراء» وحدة واحدة
        let first = PersonName.firstUnit(fullName)
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

    /// ذكر من الشجرة العامة معروض هنا بنفس المعرّف: الوفاة والتواريخ تُكتب في `profiles` أيضاً — المزامنة
    /// باتجاه واحد (profiles → women_members)، فالكتابة هنا وحدها لا تظهر في شجرة العائلة وتمحوها المزامنة لاحقاً
    static func updateMirroredProfileLife(id: UUID, isDeceased: Bool, deathDate: String?,
                                          birthDate: String?) async throws {
        let payload: [String: AnyEncodable] = [
            "is_deceased": AnyEncodable(isDeceased),
            "death_date": AnyEncodable(isDeceased ? deathDate : Optional<String>.none),
            "birth_date": AnyEncodable(birthDate)
        ]
        try await SupabaseConfig.client.from("profiles").update(payload).eq("id", value: id.uuidString).execute()
    }

    /// تعليم/إلغاء «متزوجة» — تُستبعد من مرشّحات الزوجة عند التعليم.
    static func setMarried(id: UUID, _ married: Bool) async throws {
        try await SupabaseConfig.client.from("women_members")
            .update(["is_married": AnyEncodable(married)])
            .eq("id", value: id.uuidString).execute()
    }

    /// تعديل تاريخ الميلاد وحده — يُستخدم في تفاصيل العضو بشجرة النساء.
    static func setBirthDate(id: UUID, _ date: String?) async throws {
        try await SupabaseConfig.client.from("women_members")
            .update(["birth_date": AnyEncodable(date)])
            .eq("id", value: id.uuidString).execute()
    }

    static func setMotherId(childId: UUID, motherId: UUID?) async throws {
        try await SupabaseConfig.client.from("women_members")
            .update(["mother_id": AnyEncodable(motherId?.uuidString)])
            .eq("id", value: childId.uuidString).execute()
    }

    /// ربط أنثى موجودة في الشجرة كزوجة لعقدة (اختيار زوجة من العائلة).
    /// ربط/فكّ زوج — الربط يعلّم «متزوجة» تلقائياً (المرتبطة بزوج متزوجة فعلاً).
    static func setHusbandId(womanId: UUID, husbandId: UUID?) async throws {
        var payload: [String: AnyEncodable] = ["husband_id": AnyEncodable(husbandId?.uuidString)]
        if husbandId != nil { payload["is_married"] = AnyEncodable(true) }
        try await SupabaseConfig.client.from("women_members")
            .update(payload)
            .eq("id", value: womanId.uuidString).execute()
    }

    // ── إدارة العضو لعائلته الخاصة (الأم/الزوجة) عبر دوال السيرفر ──────────
    static func addSelfWife(name: String, hidden: Bool = false) async throws {
        try await SupabaseConfig.client
            .rpc("add_self_wife", params: ["p_name": AnyEncodable(name),
                                           "p_hidden": AnyEncodable(hidden)]).execute()
    }

    /// إخفاء/إظهار زوجة العضو في الشجرة — مقيَّد بزوجاته هو (RPC ذاتي).
    static func setSelfWifeHidden(wifeId: UUID, _ hidden: Bool) async throws {
        try await SupabaseConfig.client
            .rpc("set_self_wife_hidden", params: ["p_wife_id": AnyEncodable(wifeId.uuidString),
                                                  "p_hidden": AnyEncodable(hidden)]).execute()
    }
    static func addSelfMother(name: String) async throws {
        try await SupabaseConfig.client
            .rpc("add_self_mother", params: ["p_name": AnyEncodable(name)]).execute()
    }
    /// ربط أنثى موجودة زوجةً للعضو نفسه (RPC set_self_wife — مقيّدة على عقدته).
    static func setSelfWife(wifeId: UUID) async throws {
        try await SupabaseConfig.client
            .rpc("set_self_wife", params: ["p_wife_id": AnyEncodable(wifeId.uuidString)]).execute()
    }
    /// «إضافة أخت» — بنت جديدة تحت أبي العضو نفسه (RPC add_or_link_self_relative، طلب المالك ٢٠٢٦-١٠-٢٤:
    /// الأخت تُضاف من الشجرة فقط لا من الملف الشخصي). المفاتيح الأربعة كلها تُرسل (null صريحة).
    @discardableResult
    static func addSelfSister(fatherId: UUID, name: String) async throws -> UUID {
        let params: [String: AnyEncodable] = [
            "p_kind": AnyEncodable("sister"),
            "p_father_id": AnyEncodable(fatherId.uuidString),
            "p_woman_id": AnyEncodable(Optional<String>.none),
            "p_name": AnyEncodable(name)
        ]
        let newId: UUID = try await SupabaseConfig.client
            .rpc("add_or_link_self_relative", params: params).execute().value
        return newId
    }
    static func setSelfMother(motherId: UUID?) async throws {
        try await SupabaseConfig.client
            .rpc("set_self_mother", params: ["p_mother_id": AnyEncodable(motherId?.uuidString)]).execute()
    }

    /// نص خطأ الكتابة للمستخدم (م-٢ فحص ٢٠٢٦-١٠-٠٧): رسالة السيرفر العربية حين يرفض حارس روابط العائلة
    /// الحذف (`hint = family_links_protected`، كما في شجرة العائلة) — وإلا رسالة عامة
    static func failureMessage(_ error: Error) -> String {
        if let failure = error as? WomenWriteFailure { return failure.message }
        if let pg = error as? PostgrestError {
            switch pg.hint ?? "" {
            case "family_links_protected": return pg.message
            // أخطاء «إضافة أخت» (add_or_link_self_relative)
            case "no_own_father", "no_father":
                return L10n.t("أبوك غير مسجّل في الشجرة — اطلب ربطك من الإدارة.",
                              "Your father isn't in the tree — ask the administration to link you.")
            case "not_daughter":
                return L10n.t("الأخت تُضاف تحت أبيك أنت فقط.", "A sister can only be added under your own father.")
            case "name_required":
                return L10n.t("اكتب الاسم.", "Enter the name.")
            case "not_allowed":
                return L10n.t("حسابك غير مفعّل بعد.", "Your account isn't active yet.")
            case "no_node":
                return L10n.t("لا توجد لك عقدة في الشجرة بعد.", "You don't have a node in the tree yet.")
            default: break
            }
        }
        return L10n.t("لم يتم الحفظ. تحقّق من الاتصال وحاول مرة أخرى.",
                      "Not saved. Check your connection and try again.")
    }

    static func delete(id: UUID) async throws {
        try await SupabaseConfig.client.from("women_members").delete().eq("id", value: id.uuidString).execute()
    }

    /// إعادة ترتيب الأبناء — يحدّث sort_order حسب الترتيب الجديد. (إدارة فقط).
    /// التحديثات تُرسَل معاً لا بالتسلسل — الطلب المتسلسل يجعل الترتيب بطيئاً
    /// بمقدار عدد الأبناء (طلب شبكة لكل صف).
    static func reorder(orderedIds: [UUID]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (i, id) in orderedIds.enumerated() {
                group.addTask {
                    try await SupabaseConfig.client.from("women_members")
                        .update(["sort_order": AnyEncodable(i)])
                        .eq("id", value: id.uuidString).execute()
                }
            }
            try await group.waitForAll()
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
