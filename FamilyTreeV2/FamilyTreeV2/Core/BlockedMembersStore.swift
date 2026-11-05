import Foundation
import Combine
import Supabase

// MARK: - حظر الأعضاء (Guideline 1.2 — «حظر المستخدمين المسيئين»)
//
// الحظر على السيرفر منذ ٢٠٢٦-١٠-٢٩ (`member_blocks`): `block_member(p_member)` (السيرفر نفسه يرفع بلاغاً للإدارة —
// التطبيق لا يرسل بلاغاً)، `unblock_member(p_member)`، و`my_blocked_ids()` عند الدخول. القائمة المحلية (UserDefaults)
// تبقى فهرساً للأسماء والمعرّفات الأخرى للمطابقة، والحظر المحلي القديم يُرحَّل للسيرفر مرة واحدة.
// يخفي عن الحاظر أخبار المحظور وتعليقاته (وإشعارات تعليقاته وإعجاباته)، ولا
// يغيّر شيئاً في شجرة العائلة ولا في شاشات الإدارة (الإدارة ترى كل شيء).
//
// ملاحظة: التعليقات تُحفظ بمعرّف الدخول (auth) والأخبار بمعرّف الملف، وقد يختلفان
// للعضو المربوط بسجل قديم في الشجرة — لذلك يحفظ الحظر كل معرّف معروف للعضو
// واسمه الكامل، ويطابق المحتوى بأيّهما.

@MainActor
final class BlockedMembersStore: ObservableObject {
    static let shared = BlockedMembersStore()

    struct Entry: Codable, Identifiable, Equatable {
        /// المعرّف الأساسي (معرّف الملف إن عُرف)
        let id: UUID
        /// كل المعرّفات المعروفة للعضو (الملف والدخول)
        var ids: [UUID]
        /// الاسم للعرض في قائمة المحظورين
        var name: String
        /// أشكال الاسم كما تظهر في الأخبار والتعليقات — للمطابقة
        var names: [String]
        var blockedAt: Date
        /// مؤكَّد على السيرفر — إن اختفى من `my_blocked_ids` (أُلغي من جهاز آخر) يُزال محلياً
        var onServer: Bool? = nil
        /// تاريخ الحظر معروف (المدخل الآتي من السيرفر وحده بلا تاريخ)
        var hasDate: Bool { blockedAt > Date(timeIntervalSince1970: 0) }
    }

    /// المحظورون للمستخدم الحالي — الأحدث أولاً
    @Published private(set) var entries: [Entry] = [] {
        didSet { rebuildIndex() }
    }

    /// صاحب القائمة الحالية (معرّف ملف المستخدم)
    private(set) var ownerId: UUID?
    private var idIndex: Set<UUID> = []
    private var nameIndex: Set<String> = []

    private init() {}

    private static func storageKey(_ owner: UUID) -> String {
        "blockedMembers.v1.\(owner.uuidString.lowercased())"
    }

    private static func migratedKey(_ owner: UUID) -> String {
        "blockedMembers.serverMigrated.v1.\(owner.uuidString.lowercased())"
    }

    private var syncTask: Task<Void, Never>?

    /// يربط القائمة بالمستخدم الحالي — عند دخول التطبيق وعند تغيّر الحساب
    func activate(for userId: UUID?) {
        guard userId != ownerId else { return }
        ownerId = userId
        syncTask?.cancel()
        guard let userId else {
            entries = []
            return
        }
        if let data = UserDefaults.standard.data(forKey: Self.storageKey(userId)),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
        syncTask = Task { [weak self] in await self?.syncWithServer(owner: userId) }
    }

    // MARK: - السيرفر

    enum ServerResult { case ok, notAllowed, selfBlock, notFound, failed }

    /// `my_blocked_ids` + ترحيل الحظر المحلي القديم مرة واحدة (`block_member` لكل مدخل)
    func syncWithServer(owner: UUID) async {
        let serverIds: [UUID]
        do {
            serverIds = try await SupabaseConfig.client.rpc("my_blocked_ids").execute().value
        } catch {
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[Block] تعذّر جلب المحظورين: \(error.localizedDescription)")
            }
            return
        }
        guard ownerId == owner, !Task.isCancelled else { return }
        var known = Set(serverIds)
        var updated = entries

        // ترحيل مرة واحدة: كل مدخل محلي غير موجود على السيرفر
        if !UserDefaults.standard.bool(forKey: Self.migratedKey(owner)) {
            var allDone = true
            for i in updated.indices where !updated[i].ids.contains(where: known.contains) {
                switch await Self.serverBlock(updated[i].id) {
                case .ok:
                    known.insert(updated[i].id)
                    updated[i].onServer = true
                case .failed:
                    allDone = false
                case .notAllowed, .selfBlock, .notFound:
                    break   // يبقى محلياً كما كان
                }
            }
            guard ownerId == owner else { return }
            if allDone { UserDefaults.standard.set(true, forKey: Self.migratedKey(owner)) }
        }

        // المؤكَّد سابقاً واختفى من السيرفر = أُلغي من جهاز آخر
        updated.removeAll { $0.onServer == true && !$0.ids.contains(where: known.contains) }
        for i in updated.indices where updated[i].ids.contains(where: known.contains) {
            updated[i].onServer = true
        }
        // محظور على السيرفر بلا مدخل محلي (جهاز آخر، أو نسخة أخرى من التطبيق)
        for id in known where !updated.contains(where: { $0.ids.contains(id) }) {
            updated.append(Entry(id: id, ids: [id], name: "", names: [],
                                 blockedAt: Date(timeIntervalSince1970: 0), onServer: true))
        }
        if updated != entries {
            entries = updated
            persist()
        }
    }

    private static func serverBlock(_ member: UUID) async -> ServerResult {
        do {
            _ = try await SupabaseConfig.client
                .rpc("block_member", params: ["p_member": member.uuidString.lowercased()])
                .execute()
            return .ok
        } catch {
            switch (error as? PostgrestError)?.hint {
            case "not_allowed": return .notAllowed
            case "self_block": return .selfBlock
            case "member_not_found": return .notFound
            default:
                Log.warning("[Block] فشل الحظر على السيرفر: \(error.localizedDescription)")
                return .failed
            }
        }
    }

    /// يحظر على السيرفر بعد الحظر المحلي. `notAllowed`/`selfBlock` يلغيان الحظر المحلي.
    func blockOnServer(_ member: UUID) async -> ServerResult {
        let result = await Self.serverBlock(member)
        guard let index = entries.firstIndex(where: { $0.ids.contains(member) }) else { return result }
        switch result {
        case .ok:
            entries[index].onServer = true
            persist()
        case .notAllowed, .selfBlock:
            entries.remove(at: index)
            persist()
        case .notFound, .failed:
            break   // يبقى محلياً؛ الترحيل لا يعيد المحاولة بعد اكتماله — تكفي القائمة المحلية للإخفاء
        }
        return result
    }

    // MARK: - الاستعلام

    /// هل صاحب هذا المعرّف أو هذا الاسم محظور؟
    func isBlocked(id: UUID?, name: String? = nil) -> Bool {
        if let id, idIndex.contains(id) { return true }
        // لا تطبيع للاسم إن لم يوجد محظورون (الحالة الغالبة) — بلا كلفة على القوائم
        if let name, !nameIndex.isEmpty {
            let key = Self.normalize(name)
            if !key.isEmpty, nameIndex.contains(key) { return true }
        }
        return false
    }

    /// المدخل المطابق (لإلغاء الحظر من ملف العضو)
    func entry(id: UUID?, name: String? = nil) -> Entry? {
        let key = name.map(Self.normalize) ?? ""
        return entries.first { entry in
            if let id, entry.ids.contains(id) { return true }
            return !key.isEmpty && entry.names.contains { Self.normalize($0) == key }
        }
    }

    /// إشعار تعليق/إعجاب من عضو محظور — لا يظهر في الإشعارات ولا يُحسب في الجرس.
    /// إشعارات الإدارة والطلبات لا تتأثر أبداً.
    func hidesNotification(kind: String, createdBy: UUID?, body: String) -> Bool {
        guard !entries.isEmpty, Self.memberInteractionKinds.contains(kind) else { return false }
        return isBlocked(id: createdBy) || mentionsBlockedName(in: body)
    }

    private static let memberInteractionKinds: Set<String> = [
        NotificationKind.newsComment.rawValue,
        NotificationKind.newsLike.rawValue
    ]

    /// هل يحوي النص اسم عضو محظور؟ (نصوص الإشعارات: «فلان علّق على منشورك»)
    func mentionsBlockedName(in text: String) -> Bool {
        guard !nameIndex.isEmpty else { return false }
        let haystack = Self.normalize(text)
        // الاسم الكامل فقط (كلمتان فأكثر) — حتى لا يطابق اسم أول شائع نصاً آخر
        return nameIndex.contains { $0.contains(" ") && haystack.contains($0) }
    }

    // MARK: - التعديل

    /// يحظر عضواً. يرجع false إن لم يوجد مستخدم حالي أو كان المستهدف هو المستخدم نفسه.
    @discardableResult
    func block(ids: [UUID], names: [String], selfIds: [UUID], selfNames: [String], primary: UUID? = nil) -> Bool {
        guard let ownerId else { return false }
        let cleanIds = Array(Set(ids))
        let cleanNames = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleanIds.isEmpty || !cleanNames.isEmpty else { return false }

        // لا يحظر المستخدم نفسه أبداً
        let mine = Set(selfIds + [ownerId])
        if cleanIds.contains(where: mine.contains) { return false }
        let myNames = Set(selfNames.map(Self.normalize).filter { !$0.isEmpty })
        if cleanNames.contains(where: { myNames.contains(Self.normalize($0)) }) { return false }

        var updated = entries
        if let index = updated.firstIndex(where: { entry in
            entry.ids.contains(where: cleanIds.contains)
                || entry.names.contains { name in cleanNames.contains { Self.normalize($0) == Self.normalize(name) } }
        }) {
            // محظور مسبقاً — نضيف أي معرّف/اسم جديد عرفناه
            updated[index].ids = Array(Set(updated[index].ids + cleanIds))
            updated[index].names = Self.dedupe(updated[index].names + cleanNames)
        } else {
            let primary = primary.flatMap { cleanIds.contains($0) ? $0 : nil } ?? cleanIds.first ?? UUID()
            updated.insert(Entry(id: primary,
                                 ids: cleanIds,
                                 name: cleanNames.first ?? "",
                                 names: Self.dedupe(cleanNames),
                                 blockedAt: Date()), at: 0)
        }
        entries = updated
        persist()
        return true
    }

    func unblock(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        persist()
        // كل معرّفات العضو — السيرفر يحفظه بمعرّف ملفه
        let ids = entry.ids
        Task {
            for id in ids {
                do {
                    _ = try await SupabaseConfig.client
                        .rpc("unblock_member", params: ["p_member": id.uuidString.lowercased()])
                        .execute()
                } catch {
                    Log.warning("[Block] فشل إلغاء الحظر على السيرفر: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - داخلي

    private func persist() {
        guard let ownerId else { return }
        if entries.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.storageKey(ownerId))
        } else if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.storageKey(ownerId))
        }
    }

    private func rebuildIndex() {
        idIndex = Set(entries.flatMap(\.ids))
        nameIndex = Set(entries.flatMap(\.names).map(Self.normalize).filter { !$0.isEmpty })
    }

    private static func dedupe(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert(normalize($0)).inserted }
    }

    /// تطبيع الاسم للمطابقة: بلا تشكيل، همزات موحّدة، مسافات مفردة
    static func normalize(_ text: String) -> String {
        ArabicTextNormalizer.normalizeForSearch(text)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
