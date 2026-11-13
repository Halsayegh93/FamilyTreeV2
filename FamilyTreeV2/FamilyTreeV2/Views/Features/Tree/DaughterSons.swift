import SwiftUI
import Combine
import Supabase

// MARK: - «أبناء البنات من خارج العائلة» (موافقة المالك ٢٠٢٦-١١-٠٧، العيّنة samples/daughters-sons/v4.html)
//
// السيرفر (`20261107120000_daughter_sons_lineage`، بانتظار التطبيق):
//  • `approve_join_as_daughter_son(p_member_id)` — الإدارة تقبل طلب الانضمام كـ «ابن بنت من خارج العائلة»
//  • `my_lineage_status()` — {needs, pending, was_rejected, rejected_reason…} للعضو
//  • `submit_daughter_son_lineage(...)` — «أكمل حسابك» (كانت «نسبك»، طلب المالك ٢٠٢٦-١١-٠٧): الأم + الأب (المسجّل أو الاسم الرباعي) ← طلب `lineage_request`
//  • `decide_lineage_request(p_request_id, 'approve'|'reject', p_reason)` — قرار الإدارة في «الوارد»
//  • `add_outside_husband(p_woman_id, p_name, p_deceased)` — «زوج من خارج العائلة» في شجرة النساء
// الإعدادات والنصوص من `app_config()` (قاعدة المالك: بلا بناء تطبيق): `daughter_sons_enabled`، `daughter_sons_allow_later`،
// `daughter_sons_require_grandfather`، `daughter_sons_max_resubmits` (السيرفر يفرضه)، `daughter_sons_texts` {مفتاح: نص}.
// قبل الترحيل: الدوال غائبة ← كل الخيارات الجديدة مخفية والتطبيق كما كان.
//
// «الحساب المقيّد» (طلب المالك ٢٠٢٦-١١-٠٧ «نبي يكون مقيد الحساب … اسمه اكمل حسابك»): ما دام العضو مُعلَّماً ولم يكتمل
// (`flagged` و`!completed` — «يحتاج» أو «قيد المراجعة» حتى توافق الإدارة) يستعمل التطبيق بعد «لاحقاً» لكن الأقسام في
// `daughter_sons_locked_sections` (app_config، الافتراضي `LockedSection.defaults`) مقفولة بحالة هادئة
// (`lineageLocked(_:)` / `LineageLockedView`)، وبطاقة «أكمل حسابك» له وحده في الرئيسية (`LineageHomeCard`).
// السيرفر يفرض نفس القائمة (`20261108090000_daughter_sons_restricted`، بانتظار التطبيق): `lineage_locked(section)` +
// سياسات RESTRICTIVE للقراءة على الديوانيات والمشاريع والمكتبة وشجرة النساء، و`lineage_mother_candidates()` لصفحته.

enum DaughterSons {
    /// نوع طلب المراجعة (لا حالة في `RequestType` — تجنّباً لمطابقات شاملة في شاشات أخرى)
    static let requestType = "lineage_request"

    // MARK: الإعدادات والنصوص (السيرفر أولاً)

    @MainActor static var config: AppConfigValues { AppConfigValues.shared }

    @MainActor static func flag(_ key: String, default fallback: Bool) -> Bool {
        if let b = config.values[key] as? Bool { return b }
        if let n = config.values[key] as? NSNumber { return n.boolValue }
        return fallback
    }

    /// مفتاح الخيار (المالك يطفئه من الإعدادات)
    @MainActor static var isEnabled: Bool { flag("daughter_sons_enabled", default: true) }
    @MainActor static var allowsLater: Bool { flag("daughter_sons_allow_later", default: true) }
    @MainActor static var requiresGrandfather: Bool { flag("daughter_sons_require_grandfather", default: false) }
    /// أقل عدد كلمات في «اسم أبوك الكامل» — `daughter_sons_father_min_words` (٢–٦، الافتراضي ٣)؛
    /// «اسم الجد إلزامي» القديم = ٤ على الأقل (السيرفر يفرض نفس القاعدة)
    @MainActor static var fatherMinWords: Int {
        let n = min(6, max(2, config.int("daughter_sons_father_min_words", default: 3)))
        return requiresGrandfather ? max(n, 4) : n
    }

    /// الأقسام المقفولة على الحساب المقيّد — مفاتيحها كما في `daughter_sons_locked_sections` على السيرفر
    enum LockedSection: String, CaseIterable, Sendable {
        case diwaniyas, projects, library
        case womenTree = "women_tree"
        case memberDetails = "member_details"

        static let defaults: [LockedSection] = [.diwaniyas, .projects, .library, .womenTree, .memberDetails]
    }

    /// القائمة من السيرفر (مصفوفة نصوص)، وإلا الافتراضي — مصفوفة فارغة = لا قفل
    @MainActor static var lockedSections: Set<LockedSection> {
        guard let arr = config.values["daughter_sons_locked_sections"] as? [Any] else { return Set(LockedSection.defaults) }
        return Set(arr.compactMap { ($0 as? String).flatMap(LockedSection.init(rawValue:)) })
    }

    // MARK: «أكمل حسابك»: البحث عن الأم (طلب المالك ٢٠٢٦-١١-٠٧ للخصوصية — لا تصفّح لبنات العائلة)

    /// أقل عدد كلمات متتالية من اسم الأم قبل ظهور أي نتيجة — `daughter_sons_mother_min_parts` (٢–٥، الافتراضي ٣)
    @MainActor static var motherMinParts: Int {
        min(5, max(2, config.int("daughter_sons_mother_min_parts", default: 3)))
    }

    /// التلميح قبل اكتمال الاسم
    @MainActor static var motherHint: String {
        let n = motherMinParts
        return text("mother_hint",
                    n == 3 ? "اكتب اسم أمك الثلاثي" : "اكتب اسم أمك: \(n) أسماء متتالية على الأقل",
                    n == 3 ? "Type your mother's three-part name" : "Type at least \(n) consecutive parts of your mother's name")
    }

    /// بنت من بنات العائلة كما يرجعها `search_daughters_for_lineage` (أقل ما تحتاجه الصفحة)
    nonisolated struct MotherCandidate: Decodable, Identifiable, Sendable, Equatable {
        let id: UUID
        let firstName: String
        let fullName: String
        let fatherName: String?
        let husbandId: UUID?
        let husbandName: String?
        let husbandInFamily: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case firstName = "first_name", fullName = "full_name", fatherName = "father_name"
            case husbandId = "husband_id", husbandName = "husband_name", husbandInFamily = "husband_in_family"
        }
    }

    /// nil = لم يُفحص · false = الدالة غائبة (قبل الترحيل) فيُبحث محلياً بالقاعدة نفسها
    @MainActor private static var searchRPCReady: Bool?

    /// السيرفر يفرض القاعدة (الحد الأدنى + سلسلة متتالية من الاسم الأول، ١٠ نتائج)؛ قبل الترحيل: شجرة النساء محلياً
    @MainActor static func searchMothers(_ query: String, isFamilyMember: (UUID) -> Bool) async -> [MotherCandidate] {
        let q = NameSearch.words(query)
        guard q.count >= motherMinParts else { return [] }
        if searchRPCReady != false {
            do {
                let rows: [MotherCandidate] = try await SupabaseConfig.client
                    .rpc("search_daughters_for_lineage", params: ["p_query": query]).execute().value
                searchRPCReady = true
                return rows
            } catch {
                if ErrorHelper.isCancellation(error) { return [] }
                guard (error as? PostgrestError)?.code == "PGRST202" else {
                    Log.warning("[DaughterSons] search_daughters_for_lineage: \(error.localizedDescription)")
                    return []
                }
                searchRPCReady = false
            }
        }
        // قبل الترحيل: نفس القاعدة على شجرة النساء المحمّلة
        if WomenStore.cache.isEmpty { _ = try? await WomenStore.fetch() }
        let women = WomenStore.cache
        let byId = Dictionary(women.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return women.compactMap { w -> (Int, MotherCandidate)? in
            guard w.isFemale, !w.isHiddenFromTree, w.hasName, let fid = w.fatherId, let f = byId[fid], !f.isFemale,
                  let rank = NameSearch.chainMatch(queryWords: q, candidateWords: NameSearch.words(w.fullName),
                                                   fromStart: true)?.rank else { return nil }
            let h = w.husbandId.flatMap { byId[$0] }
            let inFamily = h.map { isFamilyMember($0.id) || ($0.fatherId != nil && !WomenStore.outsideFamilyIds.contains($0.id)) } ?? false
            return (rank, MotherCandidate(id: w.id, firstName: w.firstName, fullName: w.fullName, fatherName: f.fullName,
                                          husbandId: w.husbandId, husbandName: h?.fullName, husbandInFamily: inFamily))
        }
        .sorted { $0.0 < $1.0 }
        .prefix(10)
        .map(\.1)
    }

    /// «ما لقيت أمي؟» متاح: دوال البحث على السيرفر (الترحيل مطبَّق)
    @MainActor static var newMotherAvailable: Bool { searchRPCReady == true }

    /// رجل من شجرة الرجال (أبو «الأم الجديدة») كما يرجعه `search_men_for_lineage`
    nonisolated struct ManCandidate: Decodable, Identifiable, Sendable, Equatable {
        let id: UUID
        let fullName: String
        let isDeceased: Bool
        enum CodingKeys: String, CodingKey { case id, fullName = "full_name", isDeceased = "is_deceased" }
    }

    /// نفس قاعدة الخصوصية (لا شيء قبل الحد الأدنى)، السيرفر وحده (لا بحث محلي — الخيار يظهر بعد الترحيل)
    @MainActor static func searchMen(_ query: String) async -> [ManCandidate] {
        guard NameSearch.words(query).count >= motherMinParts else { return [] }
        do {
            return try await SupabaseConfig.client
                .rpc("search_men_for_lineage", params: ["p_query": query]).execute().value
        } catch {
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[DaughterSons] search_men_for_lineage: \(error.localizedDescription)")
            }
            return []
        }
    }

    /// نص من `daughter_sons_texts` (عربي فقط — الإنجليزية من التطبيق)، وإلا نص التطبيق
    @MainActor static func text(_ key: String, _ ar: String, _ en: String) -> String {
        if L10n.isArabic, let dict = config.values["daughter_sons_texts"] as? [String: Any],
           let s = (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        return L10n.t(ar, en)
    }

    // MARK: السيرفر

    /// حالة «أكمل حسابك» للعضو الحالي
    nonisolated struct Status: Decodable, Sendable, Equatable {
        let flagged: Bool
        let needs: Bool
        let pending: Bool
        let completed: Bool
        let wasRejected: Bool
        let rejectedReason: String?

        enum CodingKeys: String, CodingKey {
            case flagged, needs, pending, completed
            case wasRejected = "was_rejected"
            case rejectedReason = "rejected_reason"
        }
    }

    /// الدوال موجودة على السيرفر (آخر فحص ناجح) — nil = لم يُفحص بعد
    @MainActor static var serverReady: Bool?

    /// nil = الدالة غائبة (قبل الترحيل) أو تعذّر الاتصال
    @MainActor static func fetchStatus() async -> Status? {
        do {
            let s: Status = try await SupabaseConfig.client.rpc("my_lineage_status").execute().value
            serverReady = true
            return s
        } catch {
            if ErrorHelper.isCancellation(error) { return nil }
            // PGRST202 = الدالة غير موجودة (الترحيل لم يُطبَّق)
            if (error as? PostgrestError)?.code == "PGRST202" { serverReady = false }
            Log.warning("[DaughterSons] my_lineage_status: \(error.localizedDescription)")
            return nil
        }
    }

    /// الخيار متاح للإدارة: المفتاح مفعّل والدوال على السيرفر
    @MainActor static func isAvailable() async -> Bool {
        await config.refresh()
        guard isEnabled else { return false }
        if let ready = serverReady { return ready }
        return await fetchStatus() != nil
    }

    static func approveJoin(memberId: UUID) async throws {
        _ = try await SupabaseConfig.client
            .rpc("approve_join_as_daughter_son", params: ["p_member_id": memberId.uuidString]).execute()
    }

    /// «ما لقيت أمي؟»: اسمها + أبوها من شجرة الرجال + حية/متوفاة (الإدارة تُنشئها تحت أبيها عند الموافقة)
    struct NewMother: Sendable {
        let name: String
        let fatherId: UUID
        let deceased: Bool
    }

    /// `motherId` = بنت من بنات العائلة (أو nil مع `newMother`) · `fatherId` = زوج الأم المسجّل، وإلا «اسم الأب الكامل»
    /// سطراً واحداً (`p_father_full_name`، ترحيل 20261108090000). قبل الترحيل (الدالة القديمة — PGRST202): الاسم يُقسَّم على
    /// الحقول الأربعة القديمة؛ و«أم جديدة» تحتاج الترحيل.
    static func submit(motherId: UUID?, newMother: NewMother?, fatherId: UUID?, fatherFullName: String, deceased: Bool) async throws {
        let line = fatherFullName.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let typed = fatherId == nil
        var params: [String: AnyEncodable] = [
            "p_mother_id": AnyEncodable(motherId?.uuidString),
            "p_father_id": AnyEncodable(fatherId?.uuidString),
            "p_father_deceased": AnyEncodable(typed && deceased)
        ]
        do {
            var p = params
            if typed { p["p_father_full_name"] = AnyEncodable(line) }
            if let nm = newMother {
                p["p_new_mother_name"] = AnyEncodable(nm.name.split(whereSeparator: \.isWhitespace).joined(separator: " "))
                p["p_new_mother_father_id"] = AnyEncodable(nm.fatherId.uuidString)
                p["p_new_mother_deceased"] = AnyEncodable(nm.deceased)
            }
            _ = try await SupabaseConfig.client.rpc("submit_daughter_son_lineage", params: p).execute()
        } catch {
            guard typed, newMother == nil, (error as? PostgrestError)?.code == "PGRST202" else { throw error }
            let w = line.split(separator: " ").map(String.init)
            params["p_first_name"] = AnyEncodable(w.first)
            params["p_father_name"] = AnyEncodable(w.count > 1 ? w[1] : nil)
            params["p_grandfather_name"] = AnyEncodable(w.count > 3 ? w[2..<(w.count - 1)].joined(separator: " ") : nil)
            params["p_family_name"] = AnyEncodable(w.count > 2 ? w.last : nil)
            _ = try await SupabaseConfig.client.rpc("submit_daughter_son_lineage", params: params).execute()
        }
    }

    static func decide(requestId: UUID, approve: Bool, reason: String?) async throws {
        let r = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let params: [String: AnyEncodable] = [
            "p_request_id": AnyEncodable(requestId.uuidString),
            "p_decision": AnyEncodable(approve ? "approve" : "reject"),
            "p_reason": AnyEncodable((r?.isEmpty == false) ? r : nil)
        ]
        _ = try await SupabaseConfig.client.rpc("decide_lineage_request", params: params).execute()
    }

    @discardableResult
    static func addOutsideHusband(womanId: UUID, name: String, deceased: Bool) async throws -> UUID {
        let params: [String: AnyEncodable] = [
            "p_woman_id": AnyEncodable(womanId.uuidString),
            "p_name": AnyEncodable(name.trimmingCharacters(in: .whitespacesAndNewlines)),
            "p_deceased": AnyEncodable(deceased)
        ]
        return try await SupabaseConfig.client.rpc("add_outside_husband", params: params).execute().value
    }

    /// رسائل الدوال بالـ hint
    static func message(_ error: Error) -> String {
        switch (error as? PostgrestError)?.hint ?? "" {
        case "not_allowed": return L10n.t("ليس لديك صلاحية لهذا الإجراء.", "You don't have permission for this.")
        case "feature_off": return L10n.t("هذا الخيار مطفأ من الإعدادات.", "This option is turned off in settings.")
        case "not_male": return L10n.t("صاحبة الطلب أنثى — تُربط من «ربط بشجرة النساء».", "The applicant is female — use «Link to women's tree».")
        case "has_father": return L10n.t("الحساب مربوط بشجرة الرجال — استعمل «ربط بالشجرة».", "The account is in the men's tree — use «Link to tree».")
        case "already_linked": return L10n.t("الحساب مربوط بشجرة النساء من قبل.", "The account is already in the women's tree.")
        case "already_handled", "request_not_found": return L10n.t("عولج هذا الطلب من قبل — لم يُطبَّق شيء.", "This request was already handled — nothing was applied.")
        case "already_pending": return L10n.t("طلبك عند الإدارة — انتظر ردّها.", "Your request is with the admins — please wait.")
        case "not_needed": return L10n.t("حسابك مكتمل.", "Your account is already complete.")
        case "resubmit_limit": return L10n.t("وصلت حد المحاولات — تواصل مع الإدارة.", "You've reached the limit — contact the admins.")
        case "bad_mother": return L10n.t("اختر أمّك من بنات العائلة.", "Choose your mother from the family's daughters.")
        case "bad_father", "mother_changed": return L10n.t("زوج الأم تغيّر — حدّث الصفحة واختر من جديد.", "The mother's husband changed — refresh and choose again.")
        case "father_in_family": return L10n.t("الأب من العائلة — يُربط من «ربط بالشجرة».", "The father is from the family — use «Link to tree».")
        case "mother_has_husband": return L10n.t("لها زوج مسجّل — اختره.", "She has a recorded husband — choose him.")
        case "has_husband": return L10n.t("لها زوج مسجّل.", "She already has a husband.")
        case "name_required": return L10n.t("اكتب الاسم كاملاً.", "Type the full name.")
        case "mother_father_not_found": return L10n.t("اختر أبوها من شجرة العائلة.", "Choose her father from the family tree.")
        case "name_too_long": return L10n.t("الاسم طويل.", "The name is too long.")
        case "requester_gone": return L10n.t("صاحب الطلب لم يعد له حساب.", "The requester no longer has an account.")
        default:
            return AuthViewModel.serverMessage(error, fallback: L10n.t("تعذّر الحفظ. حاول مرة أخرى.", "Couldn't save. Try again."))
        }
    }
}

// MARK: - من هم أبناء البنات (طلب المالك ٢٠٢٦-١١-٠٨ «ظهور ابناء البنات فقط في شجرة النساء»)

/// حسابات أبناء البنات (`daughter_son_lineage` — يقرؤها المالك والمدير والمراقب، وكل عضو صفّه هو).
/// ابن البنت ليس من شجرة الرجال: لا يُعدّ في «الرجال» ولا يدخل «الكل» والفروع والمشكلات في «العائلة» —
/// بيته عقدته في شجرة النساء، وحسابه في «مسجّلون» وحده (مثل حساب المرأة). السيرفر يبقيه مخفياً من شجرة الرجال.
@MainActor
final class DaughterSonsIndex: ObservableObject {
    static let shared = DaughterSonsIndex()
    @Published private(set) var ids: Set<UUID> = []
    private var lastFetch: Date?

    private struct Row: Decodable { let profile_id: UUID }

    func contains(_ id: UUID) -> Bool { ids.contains(id) }

    /// `force` بعد قبول انضمام كابن بنت؛ غير ذلك مرة كل دقيقة على الأكثر
    func refresh(force: Bool = false) async {
        if !force, let last = lastFetch, Date().timeIntervalSince(last) < 60 { return }
        lastFetch = Date()
        do {
            // مهمة مستقلة: إلغاء مهمة الشاشة (أول فتح لـ«اليوم») كان يقطع الجلب فيُعدّ أبناء البنات في «الرجال»
            let rows: [Row] = try await Task { () -> [Row] in
                try await SupabaseConfig.client.from("daughter_son_lineage")
                    .select("profile_id").execute().value
            }.value
            let next = Set(rows.map(\.profile_id))
            if next != ids { ids = next }
        } catch {
            lastFetch = nil
            Log.warning("[DaughterSons] daughter_son_lineage: \(error.localizedDescription)")
        }
    }
}

// MARK: - بوابة «أكمل حسابك» (بعد قبول الانضمام كابن بنت)

@MainActor
final class LineageGateStore: ObservableObject {
    static let shared = LineageGateStore()
    @Published private(set) var status: DaughterSons.Status?
    /// «لاحقاً» — تختفي حتى الفتح القادم للتطبيق
    @Published var postponed = false
    /// فُتحت الصفحة من بطاقة الرئيسية أو من قسم مقفول
    @Published var pageRequested = false

    func refresh() async {
        status = await DaughterSons.fetchStatus()
    }
    func markSent() {
        if let s = status {
            status = .init(flagged: s.flagged, needs: false, pending: true, completed: false, wasRejected: false, rejectedReason: nil)
        }
        pageRequested = false
    }

    /// الحساب المقيّد: مُعلَّم كابن بنت ولم يكتمل (يحتاج أو قيد المراجعة) — حتى توافق الإدارة
    var isRestricted: Bool { status?.flagged == true && status?.completed == false }
    var isPending: Bool { isRestricted && status?.pending == true }

    /// القسم مقفول على هذا الحساب (القائمة من السيرفر)
    func isLocked(_ section: DaughterSons.LockedSection) -> Bool {
        isRestricted && DaughterSons.lockedSections.contains(section)
    }

    /// يفتح صفحة «أكمل حسابك» (أو حالة «قيد المراجعة»)
    func openPage() {
        guard isRestricted else { return }
        pageRequested = true
    }
}

private struct LineageGateModifier: ViewModifier {
    @ObservedObject private var store = LineageGateStore.shared
    @ObservedObject private var terms = TermsAcceptanceStore.shared

    /// عرض الصفحة على المحاكي بلا حساب بهذه الحالة (نسخة التطوير فقط): متغيّر البيئة LINEAGE_PAGE_TEST=1
    @State private var debugShow: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["LINEAGE_PAGE_TEST"] == "1"
        #else
        return false
        #endif
    }()

    private var showGate: Bool {
        if debugShow { return true }
        guard terms.statusChecked && !terms.needsAcceptance else { return false }
        return (store.status?.needs == true && !store.postponed) || (store.pageRequested && store.isRestricted)
    }

    func body(content: Content) -> some View {
        content
            .task {
                await AppConfigValues.shared.refresh()
                await store.refresh()
            }
            // يرجع للتطبيق أو يصله إشعار (قرار الإدارة) ← الحالة من جديد فينفكّ القفل بلا إعادة تشغيل
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                guard store.status?.flagged == true, store.status?.completed == false else { return }
                Task { await store.refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didReceivePushNotification)) { _ in
                guard store.status?.flagged == true, store.status?.completed == false else { return }
                Task { await store.refresh() }
            }
            .fullScreenCover(isPresented: Binding(get: { showGate }, set: { if !$0 { debugShow = false; store.postponed = true; store.pageRequested = false } })) {
                LineagePage(status: store.status, onSent: { store.markSent() },
                            onLater: (DaughterSons.allowsLater || store.status?.needs != true)
                                ? { debugShow = false; store.postponed = true; store.pageRequested = false } : nil)
                    .interactiveDismissDisabled()
            }
    }
}

extension View {
    /// «أكمل حسابك» لمن قُبل كابن بنت من خارج العائلة — قبل استخدام التطبيق (أو «لاحقاً» إن سمح الإعداد)
    func lineageGate() -> some View { modifier(LineageGateModifier()) }

    /// قسم مقفول على الحساب المقيّد («أكمل حسابك») — يحلّ محل المحتوى حالة هادئة بزرّ يفتح الصفحة.
    /// الرأس يبقى عند من يضعه تحت رأسه. القائمة من `daughter_sons_locked_sections` على السيرفر.
    func lineageLocked(_ section: DaughterSons.LockedSection, appSection: AppSection? = nil) -> some View {
        modifier(LineageLockedModifier(section: section, appSection: appSection))
    }
}

// MARK: - الحساب المقيّد: الأقسام المقفولة وبطاقة الرئيسية (طلب المالك ٢٠٢٦-١١-٠٧)

private struct LineageLockedModifier: ViewModifier {
    let section: DaughterSons.LockedSection
    let appSection: AppSection?
    @ObservedObject private var store = LineageGateStore.shared
    @ObservedObject private var config = AppConfigValues.shared

    func body(content: Content) -> some View {
        if store.isLocked(section) {
            LineageLockedView(section: appSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Color.background)
        } else {
            content
        }
    }
}

/// «أكمل حسابك عشان تشوف هذا القسم» + زرّ الصفحة · قيد المراجعة: «حسابك قيد المراجعة» بلا زرّ
struct LineageLockedView: View {
    var section: AppSection? = nil
    var style: DSEmptyStyle = .page
    /// nil = يفتح الصفحة مباشرة · مربّع تفاصيل العضو يُغلق نفسه أولاً
    var onOpen: (() -> Void)? = nil
    @ObservedObject private var store = LineageGateStore.shared

    var body: some View {
        let pending = store.isPending
        return DSEmptyView(
            pending ? DaughterSons.text("locked_pending_title", "حسابك قيد المراجعة", "Your account is under review")
                    : DaughterSons.text("locked_title", "يرجى إكمال الحساب لعرض هذا القسم", "Complete your account to see this section"),
            message: pending
                ? DaughterSons.text("locked_pending_body", "يُفتح هذا القسم فور موافقة الإدارة على البيانات.",
                                    "This section opens as soon as the admins approve your details.")
                : DaughterSons.text("locked_body", "اختر أمك واكتب اسم أبوك، وبعد موافقة الإدارة يفتح لك.",
                                    "Pick your mother and add your father's name; it opens once the admins approve."),
            section: section,
            icon: pending ? "hourglass" : "lock.fill",
            actionTitle: pending ? nil : DaughterSons.text("locked_button", "أكمل حسابك", "Complete your account"),
            actionIcon: pending ? nil : "person.crop.circle.badge.checkmark",
            style: style,
            action: pending ? nil : { if let onOpen { onOpen() } else { store.openPage() } }
        )
    }
}

/// رسالته وحده في الرئيسية: «أكمل حسابك» · «حسابك قيد المراجعة» · «راجع بياناتك وأرسلها من جديد» — الضغط يفتح الصفحة
struct LineageHomeCard: View {
    @ObservedObject private var store = LineageGateStore.shared

    var body: some View {
        if store.isRestricted, let s = store.status {
            Button { store.openPage() } label: {
                content(s).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L10n.t("يفتح «أكمل حسابك»", "Opens «Complete your account»"))
        }
    }

    @ViewBuilder
    private func content(_ s: DaughterSons.Status) -> some View {
        if s.pending {
            DSNoteCard(DaughterSons.text("home_pending_body", "يصلك إشعار فور موافقة الإدارة",
                                         "We'll let you know as soon as the admins approve"),
                       title: DaughterSons.text("home_pending_title", "حسابك قيد المراجعة", "Your account is under review"),
                       icon: "hourglass", tint: DS.Color.info)
        } else if s.wasRejected {
            DSNoteCard(s.rejectedReason.map { L10n.t("السبب: ", "Reason: ") + $0 }
                       ?? DaughterSons.text("home_rejected_body", "لم تُعتمد البيانات السابقة، يرجى تعديلها وإرسالها.",
                                            "Your previous details weren't confirmed — edit and send them."),
                       title: DaughterSons.text("home_rejected_title", "راجع بياناتك وأرسلها من جديد",
                                                "Review your details and send them again"),
                       icon: "arrow.uturn.backward.circle.fill", tint: DS.Color.warning)
        } else {
            DSNoteCard(DaughterSons.text("home_body", "يرجى اختيار الأم وكتابة اسم الأب لإكمال الحساب وفتح جميع الأقسام.",
                                         "Pick your mother and add your father's name to complete your account and unlock everything."),
                       title: DaughterSons.text("home_title", "أكمل حسابك", "Complete your account"),
                       icon: "person.crop.circle.badge.exclamationmark", tint: DS.Color.accent)
        }
    }
}

// MARK: - صفحة «أكمل حسابك» (كانت «نسبك»)

struct LineagePage: View {
    let status: DaughterSons.Status?
    var onSent: () -> Void
    /// nil = لا «لاحقاً» (الإعداد مطفأ)
    var onLater: (() -> Void)?

    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel

    private enum Step { case intro, pick, sent }
    @State private var step: Step
    @State private var search = ""
    /// نتائج البحث — لا قائمة قبل الاسم الثلاثي (`DaughterSons.motherMinParts`، طلب المالك ٢٠٢٦-١١-٠٧ للخصوصية)
    @State private var results: [DaughterSons.MotherCandidate] = []
    @State private var searching = false
    @State private var mother: DaughterSons.MotherCandidate?
    /// nil = لم يختر · `.registered` زوجها المسجّل (وإلا «اسم الأب الكامل» سطراً واحداً)
    @State private var fatherChoice: FatherChoice?
    /// «اسم أبوك الكامل» سطراً واحداً (طلب المالك ٢٠٢٦-١١-٠٧ — كل شي في صفحة واحدة)
    @State private var fatherFull = ""
    /// «ما لقيت أمي؟» (موافقة المالك ٢٠٢٦-١١-٠٧): اسمها + أبوها من شجرة الرجال + حية/متوفاة
    @State private var newMotherMode = false
    @State private var newMotherName = ""
    @State private var newMotherFather: DaughterSons.ManCandidate?
    @State private var newMotherDeceased = false
    @State private var menSearch = ""
    @State private var menResults: [DaughterSons.ManCandidate] = []
    @State private var menSearching = false
    @State private var deceased = false
    @State private var busy = false
    @State private var errorText: String?

    private enum FatherChoice: Equatable { case registered(UUID) }

    init(status: DaughterSons.Status?, onSent: @escaping () -> Void, onLater: (() -> Void)?) {
        self.status = status
        self.onSent = onSent
        self.onLater = onLater
        // أُرسل وينتظر الإدارة ← «حسابك قيد المراجعة» مباشرة
        _step = State(initialValue: status?.pending == true ? .sent : .intro)
    }

    /// كتب الاسم الثلاثي (أو ما يطلبه السيرفر) — قبله لا قائمة
    private var queryLongEnough: Bool { NameSearch.words(search).count >= DaughterSons.motherMinParts }
    /// زوجها من العائلة (ملف في شجرة الرجال) — مكان ابنه «ربط بالشجرة»
    private var husbandInFamily: Bool { mother?.husbandInFamily ?? false }
    /// اسم الأب من اسمه المسجّل (بلا اسمه الأول) — يكمّل الناقص ويعدّله (طلب المالك ٢٠٢٦-١١-٠٨ «يكمل الى ناقص»)
    private func prefillFather() {
        guard fatherFull.isEmpty, let me = authVM.currentUser else { return }
        let full = me.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let units = PersonName.units(full.isEmpty ? me.firstName : full)
        guard units.count > 1 else { return }
        fatherFull = units.dropFirst().joined(separator: " ")
    }

    private var fatherWords: Int { fatherFull.split(whereSeparator: \.isWhitespace).count }
    private var typedComplete: Bool { fatherWords >= DaughterSons.fatherMinWords }
    private var newMotherReady: Bool {
        !newMotherName.trimmingCharacters(in: .whitespaces).isEmpty && newMotherFather != nil
    }
    private var canSend: Bool {
        if newMotherMode { return newMotherReady && typedComplete }
        guard let m = mother else { return false }
        if m.husbandId != nil {
            if case .registered = fatherChoice { return !husbandInFamily }
            return false
        }
        return typedComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    switch step {
                    case .intro: introContent
                    case .pick: pickContent
                    case .sent: sentContent
                    }
                    if let errorText {
                        DSNoteCard(errorText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                    }
                }
                .padding(DS.Spacing.lg)
            }
            footer
        }
        .background(DS.Color.background.ignoresSafeArea())
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        // البحث بعد توقّف الكتابة لحظة — `task(id:)` يلغي السابق
        .onAppear(perform: prefillFather)
        .task(id: search) { await runSearch() }
        .task(id: menSearch) { await runMenSearch() }
    }

    // MARK: الرأس والشريط

    @ViewBuilder
    private var header: some View {
        switch step {
        case .intro, .sent:
            DSSubPageHeader(title: L10n.t("أهلاً \(authVM.currentUser?.firstName ?? "")", "Welcome \(authVM.currentUser?.firstName ?? "")"),
                            subtitle: DaughterSons.text("intro_subtitle", "تمت الموافقة على طلبك", "Your request was approved"),
                            section: .tree, nav: .none)
        case .pick:
            DSSubPageHeader(title: DaughterSons.text("page_title", "أكمل حسابك", "Complete your account"),
                            subtitle: DaughterSons.text("page_subtitle", "أمك وأبوك", "Your mother and father"),
                            section: .tree, nav: .back, onBack: { step = .intro })
        }
    }

    private var footer: some View {
        VStack(spacing: DS.Spacing.sm) {
            switch step {
            case .intro:
                DSButton(L10n.t("ابدأ", "Start"), icon: "arrow.backward", size: .large) { step = .pick }
                if let onLater {
                    DSButton(L10n.t("لاحقاً", "Later"), role: .cancel, size: .regular) { onLater() }
                }
            case .pick:
                DSButton(DaughterSons.text("send_button", "إرسال للإدارة", "Send to the admins"), icon: "paperplane.fill",
                         size: .large, isLoading: busy) { send() }
                    .disabled(!canSend || busy)
            case .sent:
                DSButton(L10n.t("تم", "Done"), icon: "checkmark", size: .large) { onSent() }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(DS.Color.background)
    }

    // MARK: ١) المقدّمة

    private var introContent: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            VStack(spacing: DS.Spacing.sm) {
                DSStateIcon("checkmark", tint: DS.Color.success, size: DS.Icon.state)
                Text(DaughterSons.text("intro_title", "أكمل حسابك", "Complete your account"))
                    .dsFont(.title)
                    .foregroundColor(DS.Color.textPrimary)
                Text(DaughterSons.text("intro_body",
                                       "يرجى اختيار الأم من بنات العائلة وكتابة اسم الأب، لإكمال الحساب والإضافة إلى الشجرة في الموضع الصحيح.",
                                       "Pick your mother from the family's daughters and add your father's name to complete your account and be placed correctly in the tree."))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            infoRow(icon: "heart", tint: DS.Color.female,
                    title: DaughterSons.text("mother_title", "اسم الأم", "Mother's name"),
                    subtitle: L10n.t("من بنات عائلة المحمدعلي", "A daughter of the Al-Mohammad Ali family"))
            Divider()
            infoRow(icon: "person.2", tint: DS.Color.male,
                    title: DaughterSons.text("father_title", "اسم الأب", "Father's name"),
                    subtitle: L10n.t("زوج أمك · من خارج العائلة", "Your mother's husband · from outside the family"))
            if status?.wasRejected == true {
                DSNoteCard(status?.rejectedReason.map { L10n.t("السبب: ", "Reason: ") + $0 }
                           ?? L10n.t("راجع اختيارك وأرسله من جديد.", "Review your choice and send it again."),
                           title: DaughterSons.text("rejected_title", "راجع بياناتك وأرسلها من جديد", "Review your details and send them again"),
                           icon: "arrow.uturn.backward.circle.fill", tint: DS.Color.warning)
            }
        }
        .dsCard(padding: DS.Spacing.md)
    }

    private func infoRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: tint)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title).dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
                Text(subtitle).dsFont(.caption).foregroundColor(DS.Color.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: ٢) الأم ثم الأب

    private var pickContent: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSBoxSectionTitle(title: DaughterSons.text("mother_title", "اسم الأم", "Mother's name"), icon: "person.fill", tint: DS.Color.female)
            if let m = mother {
                motherRow(m, selected: true) {
                    mother = nil; fatherChoice = nil
                }
                .dsRowBox()
            } else if newMotherMode {
                newMotherContent
            } else {
                DSSearchField(text: $search, placeholder: DaughterSons.text("mother_placeholder", "اكتب الاسم الثلاثي",
                                                                             "Type the three-part name"))
                // لا تصفّح لبنات العائلة قبل الاسم الثلاثي — بلا ملاحظة تحت الحقل (طلب المالك ٢٠٢٦-١١-٠٨)
                if !queryLongEnough {
                    EmptyView()
                } else if searching && results.isEmpty {
                    DSPageLoader(L10n.t("جارٍ البحث", "Searching"), fillsSpace: false)
                } else if results.isEmpty {
                    DSEmptyView(L10n.t("لم يُعثر على الاسم", "No match"),
                                message: L10n.t("تأكد من اسمها واسم أبيها وجدها، أو تواصل مع الإدارة.",
                                                "Check her, her father's and grandfather's names, or contact the admins."),
                                style: .compact)
                } else {
                    VStack(spacing: 0) {
                        ForEach(results) { d in
                            motherRow(d, selected: false) {
                                mother = d
                                fatherChoice = nil
                                search = ""
                            }
                            if d.id != results.last?.id { Divider() }
                        }
                    }
                    .dsCard(padding: DS.Spacing.sm)
                }
                // ما لقاها؟ يكتب اسمها ويختار أبوها (بعد البحث، والسيرفر جاهز)
                if queryLongEnough && !searching && DaughterSons.newMotherAvailable {
                    Button {
                        newMotherMode = true
                        newMotherName = search.trimmingCharacters(in: .whitespaces)
                        search = ""
                        fatherChoice = nil
                    } label: {
                        Label(DaughterSons.text("new_mother_title", "ما لقيت أمي؟", "Can't find my mother?"),
                              systemImage: "questionmark.circle")
                            .dsFont(.rowTitle)
                            .foregroundColor(DS.Color.primary)
                            .frame(minHeight: DS.Icon.tapTarget)
                    }
                    .buttonStyle(.plain)
                }
            }

            if newMotherMode && newMotherReady {
                DSBoxSectionTitle(title: DaughterSons.text("father_title", "اسم الأب", "Father's name"), icon: "person.2.fill", tint: DS.Color.male)
                fatherFields(motherName: newMotherName)
                DSNoteCard(DaughterSons.text("pending_note",
                                             "يُرسل الاختيار إلى الإدارة للتأكيد، ثم تتم الإضافة في شجرة النساء تحت الأم.",
                                             "Your choice goes to the admins to confirm; then you're added in the women's tree under your mother."),
                           icon: "checkmark.shield.fill", tint: DS.Color.info)
            }

            if let m = mother {
                DSBoxSectionTitle(title: DaughterSons.text("father_title", "اسم الأب", "Father's name"), icon: "person.2.fill", tint: DS.Color.male)
                if let hid = m.husbandId {
                    VStack(spacing: 0) {
                        choiceRow(icon: "person.2.fill", title: shortName(m.husbandName ?? ""),
                                  subtitle: husbandInFamily
                                    ? L10n.t("من العائلة — تواصل مع الإدارة لربطك بالشجرة", "From the family — ask the admins to link you")
                                    : L10n.t("زوج \(shortName(m.fullName)) · من خارج العائلة", "Husband of \(shortName(m.fullName)) · outside the family"),
                                  selected: fatherChoice == .registered(hid)) {
                            fatherChoice = .registered(hid)
                        }
                        .disabled(husbandInFamily)
                    }
                    .dsCard(padding: DS.Spacing.sm)
                } else {
                    fatherFields(motherName: m.fullName)
                }
                DSNoteCard(DaughterSons.text("pending_note",
                                             "يُرسل الاختيار إلى الإدارة للتأكيد، ثم تتم الإضافة في شجرة النساء تحت الأم.",
                                             "Your choice goes to the admins to confirm; then you're added in the women's tree under your mother."),
                           icon: "checkmark.shield.fill", tint: DS.Color.info)
            }
        }
    }

    private func motherRow(_ m: DaughterSons.MotherCandidate, selected: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                DSMemberAvatar(name: m.firstName, avatarUrl: nil, size: DS.Icon.row, roleColor: DS.Color.female)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(shortName(m.fullName)).dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary).lineLimit(1)
                    if let f = m.fatherName, !f.isEmpty {
                        Text(L10n.t("بنت \(shortName(f))", "Daughter of \(shortName(f))"))
                            .dsFont(.caption).foregroundColor(DS.Color.textTertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "xmark.circle.fill" : "chevron.backward")
                    .dsGlyph(DS.Glyph.md)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(selected ? L10n.t("إلغاء الاختيار", "Clear selection") : L10n.t("اختيار", "Choose"))
    }

    private func choiceRow(icon: String, title: String, subtitle: String, selected: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: icon, tint: DS.Color.male)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title).dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary).lineLimit(2)
                    Text(subtitle).dsFont(.caption).foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .dsGlyph(DS.Glyph.lg)
                    .foregroundColor(selected ? DS.Color.primary : DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: ٢ب) «ما لقيت أمي؟»

    private var newMotherContent: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSComposerField(icon: "person.fill",
                            label: DaughterSons.text("new_mother_name_title", "اسم الأم الكامل", "Mother's full name"),
                            placeholder: L10n.t("مثلاً: منيرة سعود", "e.g. Munira Saud"),
                            text: $newMotherName, limit: 120, required: true)
            DSBoxSectionTitle(title: DaughterSons.text("new_mother_father_title", "أبوها", "Her father") + " *",
                           icon: "person.fill", tint: DS.Color.male)
            if let f = newMotherFather {
                manRow(f, selected: true) { newMotherFather = nil }
                    .dsRowBox()
            } else {
                DSSearchField(text: $menSearch, placeholder: L10n.t("اسم أبوها الثلاثي", "Her father's name (three parts)"))
                if NameSearch.words(menSearch).count < DaughterSons.motherMinParts {
                    Text(L10n.t("اكتب اسم أبوها الثلاثي كما في شجرة العائلة", "Type her father's three-part name as in the family tree"))
                        .dsFont(.footnote).foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if menSearching && menResults.isEmpty {
                    DSPageLoader(L10n.t("جارٍ البحث", "Searching"), fillsSpace: false)
                } else if menResults.isEmpty {
                    DSEmptyView(L10n.t("لم يُعثر على الاسم", "No match"),
                                message: L10n.t("تأكد من الاسم، أو تواصل مع الإدارة.", "Check the name, or contact the admins."),
                                style: .compact)
                } else {
                    VStack(spacing: 0) {
                        ForEach(menResults) { f in
                            manRow(f, selected: false) { newMotherFather = f; menSearch = "" }
                            if f.id != menResults.last?.id { Divider() }
                        }
                    }
                    .dsCard(padding: DS.Spacing.sm)
                }
            }
            DSMenuTile(icon: "leaf.fill", label: L10n.t("الحالة", "Status"), options: [
                DSChoiceOption(id: false, title: L10n.t("على قيد الحياة", "Alive"), icon: "heart.fill"),
                DSChoiceOption(id: true, title: L10n.t("متوفاة", "Deceased"), icon: "leaf.fill")
            ], selection: $newMotherDeceased)
            DSNoteCard(L10n.t("تضيفها الإدارة بنتاً لأبيها عند الموافقة.", "The admins add her as her father's daughter on approval."),
                       title: L10n.t("أم جديدة", "New mother"), icon: "person.badge.plus", tint: DS.Color.info)
            Button {
                newMotherMode = false
                newMotherName = ""; newMotherFather = nil; menSearch = ""; newMotherDeceased = false
            } label: {
                Text(L10n.t("العودة إلى البحث عن الأم", "Back to searching for my mother"))
                    .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                    .frame(minHeight: DS.Icon.tapTarget)
            }
            .buttonStyle(.plain)
        }
    }

    private func manRow(_ f: DaughterSons.ManCandidate, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "person.fill", tint: DS.Color.male)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(shortName(f.fullName)).dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary).lineLimit(1)
                    if f.isDeceased {
                        Text(L10n.t("متوفى", "Deceased")).dsFont(.caption).foregroundColor(DS.Color.textTertiary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "xmark.circle.fill" : "chevron.backward")
                    .dsGlyph(DS.Glyph.md)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(selected ? L10n.t("إلغاء الاختيار", "Clear selection") : L10n.t("اختيار", "Choose"))
    }

    // MARK: ٣) اسم الأب — سطر واحد + حي/متوفى في الصفحة نفسها (طلب المالك ٢٠٢٦-١١-٠٧)

    private func fatherFields(motherName: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSComposerField(icon: "person.fill",
                            label: DaughterSons.text("father_name_title", "اسم الأب الكامل", "Father's full name"),
                            placeholder: DaughterSons.text("father_placeholder", "اكتب الاسم الثلاثي", "Type the three-part name"),
                            text: $fatherFull, limit: 120, required: true)
            if !fatherFull.trimmingCharacters(in: .whitespaces).isEmpty && !typedComplete {
                Text(L10n.t("اكتب \(DaughterSons.fatherMinWords) أسماء على الأقل", "Type at least \(DaughterSons.fatherMinWords) names"))
                    .dsFont(.footnote).foregroundColor(DS.Color.textTertiary)
            }
            DSMenuTile(icon: "leaf.fill", label: L10n.t("الحالة", "Status"), options: [
                DSChoiceOption(id: false, title: L10n.t("على قيد الحياة", "Alive"), icon: "heart.fill"),
                DSChoiceOption(id: true, title: L10n.t("متوفى", "Deceased"), icon: "leaf.fill")
            ], selection: $deceased)
            DSNoteCard(L10n.t("يظهر في شجرة النساء فقط: \(shortName(motherName)) ← زوجها ← أنت",
                              "Shown in the women's tree only: \(shortName(motherName)) → her husband → you"),
                       icon: "arrow.triangle.branch", tint: DS.Color.accent)
        }
    }

    // MARK: ٤) أُرسل

    private var sentContent: some View {
        VStack(spacing: DS.Spacing.sm) {
            DSStateIcon("paperplane.fill", tint: DS.Color.success, size: DS.Icon.state)
            Text(DaughterSons.text("pending_title", "حسابك قيد المراجعة", "Your account is under review"))
                .dsFont(.title).foregroundColor(DS.Color.textPrimary)
            Text(DaughterSons.text("sent_body", "يصلك إشعار فور موافقة الإدارة، وتتم الإضافة إلى الشجرة ويكتمل الحساب.",
                                   "We'll let you know as soon as the admins approve; then you're added to the tree and your account is complete."))
                .dsFont(.footnote).foregroundColor(DS.Color.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .dsCard(padding: DS.Spacing.lg)
    }

    // MARK: البيانات

    private func runSearch() async {
        guard queryLongEnough, mother == nil else { results = []; searching = false; return }
        try? await Task.sleep(nanoseconds: 300_000_000)
        if Task.isCancelled { return }
        searching = true
        let found = await DaughterSons.searchMothers(search, isFamilyMember: { memberVM.member(byId: $0) != nil })
        if Task.isCancelled { return }
        results = found
        searching = false
    }

    private func runMenSearch() async {
        guard NameSearch.words(menSearch).count >= DaughterSons.motherMinParts, newMotherFather == nil else {
            menResults = []; menSearching = false; return
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        if Task.isCancelled { return }
        menSearching = true
        let found = await DaughterSons.searchMen(menSearch)
        if Task.isCancelled { return }
        menResults = found
        menSearching = false
    }

    private func send() {
        guard canSend, !busy else { return }
        busy = true
        errorText = nil
        let fid: UUID? = { if !newMotherMode, case .registered(let id)? = fatherChoice { return id } else { return nil } }()
        let newMom = newMotherMode ? newMotherFather.map {
            DaughterSons.NewMother(name: newMotherName, fatherId: $0.id, deceased: newMotherDeceased)
        } : nil
        let motherId = newMotherMode ? nil : mother?.id
        Task {
            do {
                try await DaughterSons.submit(motherId: motherId, newMother: newMom, fatherId: fid,
                                              fatherFullName: fatherFull, deceased: deceased)
                step = .sent
            } catch {
                errorText = DaughterSons.message(error)
            }
            busy = false
        }
    }

    private func shortName(_ name: String) -> String {
        name.split(separator: " ").prefix(3).joined(separator: " ")
    }
}

// MARK: - «الوارد»: بطاقة طلب النسب

/// تفاصيل `lineage_request` (`details` نص JSON من السيرفر)
nonisolated struct LineageRequestDetails: Decodable, Sendable {
    struct Father: Decodable, Sendable {
        let isDeceased: Bool?
        enum CodingKeys: String, CodingKey { case isDeceased = "is_deceased" }
    }
    /// «أم جديدة» (ما لقيت أمي؟) — تُنشأ بنتاً لأبيها عند الموافقة
    struct NewMother: Decodable, Sendable {
        let name: String?
        let fatherName: String?
        let isDeceased: Bool?
        enum CodingKeys: String, CodingKey { case name, fatherName = "father_name", isDeceased = "is_deceased" }
    }
    let motherId: String?
    let motherName: String?
    let newMother: NewMother?
    let fatherId: String?
    let fatherName: String?
    /// v2: حي/متوفى للأب في الحالتين (المسجّل من الشجرة)
    let fatherIsDeceased: Bool?
    let father: Father?

    enum CodingKeys: String, CodingKey {
        case motherId = "mother_id", motherName = "mother_name", newMother = "new_mother", fatherId = "father_id"
        case fatherName = "father_name", fatherIsDeceased = "father_is_deceased", father
    }

    static func parse(_ details: String?) -> LineageRequestDetails? {
        guard let data = details?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LineageRequestDetails.self, from: data)
    }
}

/// «طلب نسب» كامل من `lineage_request_details(p_request_id)` (طلب المالك ٢٠٢٦-١١-٠٨: اسمه ورقمه، أمّه وجدها،
/// أبوه، منو سجّل، ومن أي جهاز) — للمالك والمدير والمراقب. nil = الدالة غائبة/تعذّر ← البطاقة كما كانت.
nonisolated struct LineageFullDetails: Decodable, Sendable {
    struct Person: Decodable, Sendable {
        let id: String?
        let name: String?
        let isSelf: Bool?
        let role: String?
        enum CodingKeys: String, CodingKey { case id, name, isSelf = "is_self", role }
    }
    struct Member: Decodable, Sendable {
        let fullName: String?
        let phone: String?
        let phoneHidden: Bool?
        let registeredAt: String?
        let registrationPlatform: String?
        enum CodingKeys: String, CodingKey {
            case fullName = "full_name", phone, phoneHidden = "phone_hidden", registeredAt = "registered_at"
            case registrationPlatform = "registration_platform"
        }
    }
    struct Mother: Decodable, Sendable {
        let isNew: Bool?
        let name: String?
        let isDeceased: Bool?
        let chain: [String]?
        let father: Person?
        let grandfather: Person?
        enum CodingKeys: String, CodingKey {
            case isNew = "is_new", name, isDeceased = "is_deceased", chain, father, grandfather
        }
    }
    struct Father: Decodable, Sendable {
        let registered: Bool?
        let name: String?
        let isDeceased: Bool?
        enum CodingKeys: String, CodingKey { case registered, name, isDeceased = "is_deceased" }
    }
    struct Join: Decodable, Sendable {
        let createdAt: String?
        let requester: Person?
        let repliedBy: Person?
        enum CodingKeys: String, CodingKey { case createdAt = "created_at", requester, repliedBy = "replied_by" }
    }
    struct Lineage: Decodable, Sendable {
        let approvedAt: String?
        let approvedBy: Person?
        enum CodingKeys: String, CodingKey { case approvedAt = "approved_at", approvedBy = "approved_by" }
    }
    struct Device: Decodable, Sendable {
        let platform: String?
        let deviceName: String?
        let appVersion: String?
        let appBuild: Int?
        let createdAt: String?
        enum CodingKeys: String, CodingKey {
            case platform, deviceName = "device_name", appVersion = "app_version", appBuild = "app_build"
            case createdAt = "created_at"
        }
    }
    let member: Member?
    let mother: Mother?
    let father: Father?
    let requester: Person?
    let join: Join?
    let lineage: Lineage?
    let devices: [Device]?
    let deviceCount: Int?
    enum CodingKeys: String, CodingKey {
        case member, mother, father, requester, join, lineage, devices, deviceCount = "device_count"
    }

    /// تاريخ السيرفر (ISO بأجزاء الثانية أو بدونها) ← «13/03/2026» (الصيغة الموحّدة)
    static func date(_ raw: String?) -> String? {
        guard var s = raw, !s.isEmpty else { return nil }
        if let dot = s.firstIndex(of: "."), let tz = s[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            s.removeSubrange(dot..<tz)
        }
        guard let d = isoParser.date(from: s) else { return nil }
        return DateHelper.displayDate(d)
    }
    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// ios → iPhone · ipados → iPad · android → Android
    static func platform(_ raw: String?) -> String {
        switch (raw ?? "").lowercased() {
        case "ios", "iphone": return "iPhone"
        case "ipados", "ipad": return "iPad"
        case "android": return "Android"
        case "web": return L10n.t("الموقع", "Website")
        case "": return "—"
        default: return raw ?? "—"
        }
    }
}

extension DaughterSons {
    /// nil = الدالة غائبة (قبل الترحيل) أو تعذّر — البطاقة ترجع لما في الطلب
    @MainActor static func fetchRequestDetails(_ requestId: UUID) async -> LineageFullDetails? {
        do {
            let params: [String: AnyEncodable] = ["p_request_id": AnyEncodable(requestId.uuidString)]
            return try await SupabaseConfig.client.rpc("lineage_request_details", params: params).execute().value
        } catch {
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[DaughterSons] lineage_request_details: \(error.localizedDescription)")
            }
            return nil
        }
    }
}

/// مجموعات «طلب النسب» الكاملة: صاحب الطلب · الأم · الأب · منو سجّل · الجهاز.
/// `compact` في البطاقة (أول جهاز)، والكامل في «كل التفاصيل» (كل الأجهزة، أبو الأم وجدها، والاتصال).
struct LineageDetailsGroups: View {
    let details: LineageFullDetails
    var fallbackName: String = ""
    var compact: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            group(L10n.t("صاحب الطلب", "Applicant")) { applicant }
            group(L10n.t("الأم", "Mother")) { mother }
            group(L10n.t("الأب", "Father")) { father }
            group(L10n.t("من سجّل", "Who registered")) { registeredBy }
            group(L10n.t("الجهاز", "Device")) { devices }
        }
    }

    // MARK: المجموعات

    @ViewBuilder private var applicant: some View {
        let m = details.member
        LineageInfoRow(icon: "person.fill", tint: DS.Color.male, label: L10n.t("الاسم", "Name"),
                       value: nonEmpty(m?.fullName) ?? nonEmpty(fallbackName) ?? "—",
                       note: LineageFullDetails.date(m?.registeredAt).map { L10n.t("سجّل ", "Registered ") + $0 } ?? "")
        Divider()
        LineageInfoRow(icon: "phone.fill", tint: DS.Color.sea, label: L10n.t("الهاتف", "Phone"),
                       value: KuwaitPhone.display(m?.phone),
                       note: m?.phoneHidden == true ? L10n.t("مخفي عن الأعضاء", "Hidden from members") : "",
                       link: compact ? nil : KuwaitPhone.telURL(m?.phone))
    }

    @ViewBuilder private var mother: some View {
        let mo = details.mother
        let chain = (mo?.chain ?? []).filter { !$0.isEmpty }
        let isNew = mo?.isNew == true
        let life = mo?.isDeceased == true ? L10n.t("متوفاة", "deceased") : L10n.t("حية", "living")
        LineageInfoRow(icon: "heart.fill", tint: DS.Color.female,
                       label: isNew ? L10n.t("أم جديدة · كما كتبها", "New mother · as typed") : L10n.t("من بنات العائلة", "Family daughter"),
                       value: chain.isEmpty ? (nonEmpty(mo?.name) ?? "—") : chain.joined(separator: " · "),
                       note: (isNew ? L10n.t("الاسم: ", "Name: ") + (nonEmpty(mo?.name) ?? "—") : (nonEmpty(mo?.name) ?? ""))
                             + " · " + life,
                       badge: isNew ? L10n.t("أم جديدة", "New mother") : nil)
        if !compact {
            if let f = nonEmpty(mo?.father?.name) {
                Divider()
                LineageInfoRow(icon: "person.fill", tint: DS.Color.male, label: L10n.t("أبوها", "Her father"), value: f, note: "")
            }
            if let g = nonEmpty(mo?.grandfather?.name) {
                Divider()
                LineageInfoRow(icon: "person.fill", tint: DS.Color.male, label: L10n.t("جدها", "Her grandfather"), value: g, note: "")
            }
        }
    }

    @ViewBuilder private var father: some View {
        let fa = details.father
        let life = fa?.isDeceased == true ? L10n.t("متوفى", "Deceased") : L10n.t("حي", "Living")
        LineageInfoRow(icon: "person.2.fill", tint: DS.Color.male,
                       label: fa?.registered == true ? L10n.t("زوجها المسجّل", "Her recorded husband")
                                                     : L10n.t("جديد · من خارج العائلة", "New · outside the family"),
                       value: nonEmpty(fa?.name) ?? "—", note: life)
    }

    @ViewBuilder private var registeredBy: some View {
        let j = details.join
        let who: String = {
            if let r = j?.requester { return r.isSelf == true ? L10n.t("هو بنفسه", "Himself") : (nonEmpty(r.name) ?? "—") }
            if let r = details.requester { return r.isSelf == true ? L10n.t("هو بنفسه", "Himself") : (nonEmpty(r.name) ?? "—") }
            return "—"
        }()
        let joinNote: String = {
            var n = LineageFullDetails.date(j?.createdAt) ?? ""
            if !compact, let by = nonEmpty(j?.repliedBy?.name) {
                n += (n.isEmpty ? "" : " · ") + L10n.t("ردّ عليه ", "Answered by ") + by
            }
            return n
        }()
        LineageInfoRow(icon: "person.crop.circle.badge.plus", tint: DS.Color.primary,
                       label: L10n.t("سجّل الحساب وأرسل الانضمام", "Created the account"), value: who, note: joinNote)
        if let l = details.lineage {
            Divider()
            LineageInfoRow(icon: "checkmark.seal.fill", tint: DS.Color.success,
                           label: L10n.t("وافق على انضمامه «ابن بنت»", "Approved him as a daughter's son"),
                           value: nonEmpty(l.approvedBy?.name) ?? "—",
                           note: LineageFullDetails.date(l.approvedAt) ?? "")
        }
    }

    @ViewBuilder private var devices: some View {
        let list = details.devices ?? []
        if list.isEmpty {
            LineageInfoRow(icon: "iphone.slash", tint: DS.Color.textTertiary, label: L10n.t("لا يوجد جهاز مسجّل", "No registered device"),
                           value: LineageFullDetails.platform(details.member?.registrationPlatform),
                           note: L10n.t("منصة التسجيل", "Registration platform"))
        } else {
            let shown = compact ? Array(list.prefix(1)) : list
            ForEach(Array(shown.enumerated()), id: \.offset) { i, d in
                if i > 0 { Divider() }
                LineageInfoRow(icon: (d.platform ?? "").lowercased() == "android" ? "candybarphone" : "iphone",
                               tint: DS.Color.primary,
                               label: i == 0 ? L10n.t("أول جهاز سجّل منه", "First device") : L10n.t("جهاز آخر", "Another device"),
                               value: [LineageFullDetails.platform(d.platform), nonEmpty(d.deviceName)].compactMap { $0 }.joined(separator: " · "),
                               note: deviceNote(d, count: i == 0 && compact ? (details.deviceCount ?? list.count) : 1))
            }
        }
    }

    // MARK: أدوات

    private func deviceNote(_ d: LineageFullDetails.Device, count: Int) -> String {
        var parts: [String] = []
        if let v = nonEmpty(d.appVersion) {
            parts.append(L10n.t("النسخة ", "Version ") + v + (d.appBuild.map { " (\($0))" } ?? ""))
        } else if let b = d.appBuild {
            parts.append(L10n.t("البناء ", "Build ") + "\(b)")
        }
        if let date = LineageFullDetails.date(d.createdAt) { parts.append(date) }
        if count > 1 { parts.append(L10n.t("\(count) أجهزة", "\(count) devices")) }
        return parts.joined(separator: " · ")
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title).dsFont(.sectionTitle).foregroundColor(DS.Color.textSecondary)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, DS.Spacing.sm)
                .dsCard(padding: nil, radius: DS.Radius.md, fill: DS.Color.background)
        }
    }
}

/// صفّ «طلب النسب»: أيقونة · عنوان صغير (+ شارة) · القيمة · سطر — اختيارياً رابط (اتصال)
struct LineageInfoRow: View {
    let icon: String
    let tint: Color
    let label: String
    let value: String
    let note: String
    var badge: String? = nil
    var link: URL? = nil

    var body: some View {
        if let link {
            Link(destination: link) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: tint)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(label).dsFont(.caption).foregroundColor(DS.Color.textTertiary)
                    if let badge { DSStatusChip(text: badge, tint: DS.Color.warning, size: .mini) }
                }
                Text(value).dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary).fixedSize(horizontal: false, vertical: true)
                if !note.isEmpty {
                    Text(note).dsFont(.caption).foregroundColor(DS.Color.textTertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if link != nil {
                Image(systemName: "phone.arrow.up.right").dsGlyph(DS.Glyph.md).foregroundColor(DS.Color.sea)
            }
        }
        .frame(minHeight: DS.Icon.tapTarget + DS.Spacing.sm)
        .accessibilityElement(children: .combine)
    }
}

/// «كل التفاصيل» — مربّع طويل بالمجموعات كاملة
struct LineageFullDetailsBox: View {
    let details: LineageFullDetails
    let name: String
    let onClose: () -> Void

    var body: some View {
        DSComposer(
            title: DaughterSons.text("inbox_title", "طلب نسب · ابن بنت", "Lineage request · daughter's son"),
            subtitle: name,
            icon: "arrow.triangle.branch",
            tint: DS.Color.female,
            actionTitle: "",
            showsAction: false,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: onClose
        ) {
            LineageDetailsGroups(details: details, fallbackName: name, compact: false)
        }
    }
}

extension AdminRequestViewModel {
    /// قبول/رفض طلب النسب — true = نجح وأُزيل الصف
    func decideLineage(_ request: AdminRequest, approve: Bool, reason: String?) async -> Bool {
        guard canHandleRelativeAdd, NetworkMonitor.shared.requireOnline() else { return false }
        isLoading = true
        defer { isLoading = false }
        do {
            try await DaughterSons.decide(requestId: request.id, approve: approve, reason: reason)
            lineageRequests.removeAll { $0.id == request.id }
            if approve {
                _ = try? await WomenStore.fetch()
                NotificationCenter.default.post(name: .womenMembersChanged, object: nil)
            }
            return true
        } catch {
            Log.error("[DaughterSons] فشل القرار: \(error.localizedDescription)")
            errorMessage = DaughterSons.message(error)
            return false
        }
    }
}

struct AdminLineageRequestCard: View {
    let request: AdminRequest
    @ObservedObject var adminRequestVM: AdminRequestViewModel

    @State private var busy = false
    @State private var showReject = false
    @State private var reason = ""
    /// `lineage_request_details` — nil قبل الترحيل/عند التعذّر ← صفّا الأم والأب من الطلب كما كانا
    @State private var full: LineageFullDetails?
    @State private var showFull = false

    var body: some View {
        let d = LineageRequestDetails.parse(request.details)
        let isNewFather = (d?.fatherId ?? "").isEmpty
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "arrow.triangle.branch", tint: DS.Color.female)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(DaughterSons.text("inbox_title", "طلب نسب · ابن بنت", "Lineage request · daughter's son"))
                        .dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
                    Text(request.member?.fullName ?? L10n.t("العضو", "the member"))
                        .dsFont(.footnote).foregroundColor(DS.Color.textSecondary).dsNameLines()
                }
                Spacer(minLength: 0)
                if let created = request.createdAt {
                    Text(DateHelper.relativeTime(from: created)).dsFont(.caption).foregroundColor(DS.Color.textTertiary)
                }
            }
            if let full {
                AnyView(LineageDetailsGroups(details: full, fallbackName: request.member?.fullName ?? ""))
                DSChipButton(L10n.t("كل التفاصيل", "All details"), icon: "list.bullet.rectangle", size: .small) {
                    showFull = true
                }
            } else {
                legacyRows(d, isNewFather: isNewFather)
            }
            Text(d?.newMother != nil
                 ? L10n.t("عند الموافقة تُضاف أمّه بنتاً لأبيها، وأبوه زوجاً لها، ثم هو تحتهما في شجرة النساء.",
                          "On approval his mother is added as her father's daughter, his father as her husband, then he under them in the women's tree.")
                 : L10n.t("عند الموافقة يُضاف تحت أمّه في شجرة النساء" + (isNewFather ? "، ويُضاف أبوه زوجاً لها." : "."),
                          "On approval he's added under his mother in the women's tree" + (isNewFather ? ", and his father as her husband." : ".")))
                .dsFont(.footnote).foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            // «مكانه في الشجرة» (طلب المالك ٢٠٢٦-١١-١٣): أمّه في شجرة النساء — زرّ المعاينة الرئيسي = «موافقة»
            let men = adminRequestVM.memberVM?.allMembers ?? []
            if let place = TreePlace.lineage(request, kindLabel: DaughterSons.text("inbox_title", "طلب نسب · ابن بنت", "Lineage request · daughter's son"),
                                             data: TreePlaceData(men: men, women: WomenStore.cache)) {
                AnyView(TreePlaceSection(place: place, men: men,
                                         primary: TreePlacePrimary(title: L10n.t("موافقة", "Approve")) {
                                             decide(approve: true, reason: nil)
                                         })
                    .environment(\.dsFlatComposerSections, true))
            }
            HStack(spacing: DS.Spacing.sm) {
                DSButton(L10n.t("موافقة", "Approve"), icon: "checkmark", tint: DS.Color.success, isLoading: busy) {
                    decide(approve: true, reason: nil)
                }
                DSButton(L10n.t("رفض", "Reject"), icon: "xmark", role: .cancel) {
                    reason = ""; showReject = true
                }
            }
            .disabled(busy)
        }
        .padding(DS.Spacing.md)
        .dsCard(padding: nil, radius: DS.Hub.tileRadius)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: DS.Spacing.xsm, leading: DS.Spacing.lg, bottom: DS.Spacing.xsm, trailing: DS.Spacing.lg))
        .task(id: request.id) { full = await DaughterSons.fetchRequestDetails(request.id) }
        .dsTallBox(isPresented: $showFull) {
            if let full {
                LineageFullDetailsBox(details: full, name: request.member?.fullName ?? "") { showFull = false }
            }
        }
        .dsAlert(L10n.t("سبب الرفض", "Rejection Reason"), isPresented: $showReject) {
            TextField(L10n.t("اكتب السبب (اختياري)", "Reason (optional)"), text: $reason)
                .dsAlertField()
            Button(L10n.t("إرسال الرفض", "Send Rejection"), role: .destructive) { decide(approve: false, reason: reason) }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("تعود له خانة «أكمل حسابك» ليختار من جديد، ويصله السبب.", "He gets «Complete your account» again with the reason."))
        }
    }

    /// قبل `lineage_request_details`: الأم والأب من حمولة الطلب (البطاقة كما كانت)
    private func legacyRows(_ d: LineageRequestDetails?, isNewFather: Bool) -> some View {
        VStack(spacing: 0) {
            if let nm = d?.newMother {
                // «أم جديدة» واضحة: اسمها كما كتبه + أبوها من الشجرة + حية/متوفاة
                row(icon: "heart.fill", tint: DS.Color.female, label: L10n.t("الأم · أم جديدة", "Mother · new mother"),
                    value: nm.name ?? d?.motherName ?? "—",
                    note: L10n.t("بنت ", "Daughter of ") + (nm.fatherName ?? "—")
                          + (nm.isDeceased == true ? L10n.t(" · متوفاة", " · deceased") : L10n.t(" · حية", " · living")),
                    badge: L10n.t("أم جديدة", "New mother"))
            } else {
                row(icon: "heart.fill", tint: DS.Color.female, label: L10n.t("الأم", "Mother"),
                    value: d?.motherName ?? "—", note: L10n.t("من بنات العائلة", "Family daughter"))
            }
            Divider()
            row(icon: "person.2.fill", tint: DS.Color.male, label: L10n.t("الأب", "Father"),
                value: d?.fatherName ?? "—",
                note: (isNewFather
                    ? L10n.t("جديد · من خارج العائلة", "New · outside the family")
                    : L10n.t("زوجها المسجّل", "Her recorded husband"))
                    + fatherLifeNote(d))
        }
        .padding(.horizontal, DS.Spacing.sm)
        .dsCard(padding: nil, radius: DS.Radius.md, fill: DS.Color.background)
    }

    /// « · حي» / « · متوفى» — v2 يحملها للأب في الحالتين، والقديم للأب الجديد فقط
    private func fatherLifeNote(_ d: LineageRequestDetails?) -> String {
        guard let dead = d?.fatherIsDeceased ?? d?.father?.isDeceased else { return "" }
        return dead ? L10n.t(" · متوفى", " · deceased") : L10n.t(" · حي", " · living")
    }

    private func row(icon: String, tint: Color, label: String, value: String, note: String, badge: String? = nil) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: tint)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(label).dsFont(.caption).foregroundColor(DS.Color.textTertiary)
                    if let badge { DSStatusChip(text: badge, tint: DS.Color.warning, size: .mini) }
                }
                Text(value).dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(note).dsFont(.caption).foregroundColor(DS.Color.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: DS.Icon.tapTarget + DS.Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    private func decide(approve: Bool, reason: String?) {
        guard !busy else { return }
        busy = true
        Task {
            let ok = await adminRequestVM.decideLineage(request, approve: approve, reason: reason)
            busy = false
            if ok && approve { DSMomentToast.show(L10n.t("تمت الموافقة", "Approved")) }
        }
    }
}

// MARK: - شجرة النساء: «زوج من خارج العائلة»

struct OutsideHusbandBox: View {
    let woman: FamilyMember
    var onDone: () async -> Void
    var onCancel: () -> Void

    @State private var name = ""
    @State private var deceased = false
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        DSComposer(
            title: DaughterSons.text("outside_husband_title", "زوج من خارج العائلة", "Husband from outside the family"),
            subtitle: woman.fullName,
            icon: "person.badge.plus",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("إضافة", "Add"),
            actionIcon: "plus",
            canSubmit: !name.trimmingCharacters(in: .whitespaces).isEmpty,
            isBusy: busy,
            note: L10n.t("يظهر تحتها في شجرة النساء فقط، وتضيف عياله من «الأبناء».",
                         "Shown under her in the women's tree only; add their children from «Children»."),
            hasUnsavedChanges: !name.isEmpty,
            onSubmit: save,
            onCancel: onCancel
        ) {
            DSComposerSection(title: L10n.t("الزوج", "Husband"), icon: "person.fill", tint: DS.Color.male, index: 0) {
                DSComposerField(icon: "person.fill", label: L10n.t("الاسم الكامل", "Full name"),
                                placeholder: L10n.t("مثلاً: فهد ناصر العتيبي", "e.g. Fahad Nasser Al-Otaibi"),
                                text: $name, limit: 120, required: true)
                DSMenuTile(icon: "leaf.fill", label: L10n.t("الحالة", "Status"), options: [
                    DSChoiceOption(id: false, title: L10n.t("على قيد الحياة", "Alive"), icon: "heart.fill"),
                    DSChoiceOption(id: true, title: L10n.t("متوفى", "Deceased"), icon: "leaf.fill")
                ], selection: $deceased)
                if let errorText {
                    DSNoteCard(errorText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                }
            }
        }
    }

    private func save() {
        guard !busy else { return }
        busy = true
        errorText = nil
        Task {
            do {
                try await DaughterSons.addOutsideHusband(womanId: woman.id, name: name, deceased: deceased)
                await onDone()
            } catch {
                errorText = DaughterSons.message(error)
            }
            busy = false
        }
    }
}

// MARK: - طلب الانضمام: «كيف ننضمه؟»

/// خياران فوق «ربط بالشجرة»: من أبناء العائلة / ابن بنت من خارج العائلة (يظهر فقط والسيرفر جاهز والمفتاح مفعّل)
struct JoinKindPicker: View {
    @Binding var asDaughterSon: Bool

    var body: some View {
        // خياران = الاختيار الموحّد (طلب المالك ٢٠٢٦-١١-١١)، وشرح المختار تحته
        DSComposerSection(title: L10n.t("طريقة الانضمام", "How does he join?"), icon: "questionmark.circle", index: 0) {
            DSChoiceTiles(options: [
                DSChoiceOption(id: false, title: L10n.t("ربط بالشجرة", "Link to tree"), icon: "link"),
                DSChoiceOption(id: true, title: DaughterSons.text("option_short", "ابن بنت", "A daughter's son"),
                               icon: "arrow.triangle.branch")
            ], selection: $asDaughterSon,
               note: asDaughterSon
                ? DaughterSons.text("option_title", "ابن بنت من خارج العائلة", "A daughter's son from outside the family")
                  + " — " + DaughterSons.text("option_subtitle", "بعد الموافقة يختار أمه واسم أبيه",
                                              "After approval he picks his mother and his father's name")
                : L10n.t("من أبناء العائلة، ويُحدَّد مكانه في الشجرة", "A son of the family — pick his place"))
        }
    }
}
