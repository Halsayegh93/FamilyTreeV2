import Foundation
import Combine

// MARK: - حظر الأعضاء (Guideline 1.2 — «حظر المستخدمين المسيئين»)
//
// الحظر على الجهاز فقط ولكل مستخدم (UserDefaults) — بلا أي تغيير في السيرفر:
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

    /// يربط القائمة بالمستخدم الحالي — عند دخول التطبيق وعند تغيّر الحساب
    func activate(for userId: UUID?) {
        guard userId != ownerId else { return }
        ownerId = userId
        guard let userId,
              let data = UserDefaults.standard.data(forKey: Self.storageKey(userId)),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
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
    func block(ids: [UUID], names: [String], selfIds: [UUID], selfNames: [String]) -> Bool {
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
            let primary = cleanIds.first ?? UUID()
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
