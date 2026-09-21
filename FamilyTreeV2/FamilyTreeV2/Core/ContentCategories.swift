import SwiftUI
import Combine
import Supabase

// MARK: - تصنيفات الأقسام من السيرفر (طلب المالك)
//
// جدول content_categories يحدد اسم كل تصنيف وأيقونته ولونه وظهوره.
// المفتاح (key) هو القيمة المخزّنة في المحتوى ولا يتغيّر — الاسم هو اللي يتعدّل.
// إذا ما وصلت البيانات (بلا إنترنت أول مرة)، تُستخدم التصنيفات المدمجة كما كانت.

enum CategorySection: String, CaseIterable, Identifiable {
    case news, archive
    var id: String { rawValue }
    var title: String {
        switch self {
        case .news:    return L10n.t("الأخبار", "News")
        case .archive: return L10n.t("مكتبة العائلة", "Family Library")
        }
    }
    /// إضافة تصنيف جديد — متاحة للقسمين. في المكتبة يُحفظ المحتوى بـ category_key
    /// و category = other، فتراه النسخة القديمة تحت «أخرى» بدل أن تتعطّل
    var allowsAdding: Bool { true }
}

struct ContentCategory: Codable, Identifiable, Equatable {
    let id: UUID
    let section: String
    let key: String
    var nameAr: String
    var nameEn: String
    var iconKey: String
    var colorKey: String
    var sortOrder: Int
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, section, key
        case nameAr = "name_ar"
        case nameEn = "name_en"
        case iconKey = "icon_key"
        case colorKey = "color_key"
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }

    var displayName: String { L10n.isArabic ? nameAr : nameEn }
    var color: Color { CategoryPalette.color(colorKey) }
}

/// الأيقونات والألوان المسموحة — نفس المجموعة يعرفها الأندرويد
enum CategoryPalette {
    static let icons: [String] = [
        "newspaper.fill", "megaphone.fill", "heart.fill", "figure.child", "heart.slash.fill",
        "hands.clap.fill", "envelope.open.fill", "bell.badge.fill", "chart.bar.fill", "star.fill",
        "calendar", "gift.fill", "graduationcap.fill", "house.fill", "trophy.fill",
        "doc.text.fill", "book.closed.fill", "photo.stack.fill", "folder.fill", "sparkles"
    ]

    static let colorKeys: [String] = [
        "navy", "green", "gold", "wedding", "birth", "death", "vote",
        "announcement", "congrats", "reminder", "invitation", "info", "rose", "gray"
    ]

    /// ١٤ لوناً مختلفاً فعلاً — كانت بعض المفاتيح تشير لنفس لون التطبيق فتظهر
    /// مكرّرة (طلب المالك). نسخة الوضع الداكن = نفس اللون مفتّحاً ٢٥٪ فقط، حتى يبقى
    /// متقارباً بين الوضعين ومقروءاً على الخلفية الداكنة. نفس القيم في الأندرويد.
    static let hex: [String: (light: String, dark: String)] = [
        "navy":         ("#1F4E79", "#577A9A"),
        "green":        ("#2E6B4F", "#62907B"),
        "gold":         ("#9A7432", "#B39765"),
        "wedding":      ("#B24C63", "#C5798A"),
        "birth":        ("#2E9E6A", "#62B68F"),
        "death":        ("#55555C", "#808085"),
        "vote":         ("#6A4C93", "#8F79AE"),
        "announcement": ("#D9731A", "#E29653"),
        "congrats":     ("#E0A416", "#E8BB50"),
        "reminder":     ("#C62828", "#D45E5E"),
        "invitation":   ("#00838F", "#40A2AB"),
        "info":         ("#1E88E5", "#56A6EC"),
        "rose":         ("#8C2F45", "#A96374"),
        "gray":         ("#8E8E93", "#AAAAAE")
    ]

    static func color(_ key: String) -> Color {
        guard let pair = hex[key] else { return DS.Color.primary }
        return SwiftUI.Color.adaptive(light: pair.light, dark: pair.dark)
    }
}

/// مخزن التصنيفات — يُحمَّل عند فتح التطبيق، ويقرؤه كل من يعرض تصنيفاً
@MainActor
final class CategoryStore: ObservableObject {
    static let shared = CategoryStore()

    @Published private(set) var categories: [ContentCategory] = []
    /// عدد العناصر في كل تصنيف — المفتاح "section|key"
    @Published private(set) var counts: [String: Int] = [:]
    @Published var errorMessage: String?

    func itemCount(_ category: ContentCategory) -> Int {
        counts["\(category.section)|\(category.key)"] ?? 0
    }

    /// تصنيفات أساسية لا تُحذف: النوع الافتراضي للأخبار، الاستطلاعات، و«أخرى» في المكتبة
    func isProtected(_ category: ContentCategory) -> Bool {
        (category.section == "news" && ["خبر", "تصويت"].contains(category.key))
            || (category.section == "archive" && category.key == "other")
    }

    /// قراءة سريعة من خارج الواجهات — تُحدَّث مع كل تحميل
    nonisolated(unsafe) private static var snapshot: [String: ContentCategory] = [:]

    nonisolated private static func snapshotKey(_ section: CategorySection, _ key: String) -> String {
        "\(section.rawValue)|\(key)"
    }

    /// التصنيف بمفتاحه — nil إذا لم يُحمَّل بعد (يُستخدم الافتراضي المدمج)
    nonisolated static func lookup(_ section: CategorySection, _ key: String) -> ContentCategory? {
        snapshot[snapshotKey(section, key)]
    }

    /// تصنيفات قسم مرتّبة (الظاهرة فقط أو الكل)
    func list(_ section: CategorySection, activeOnly: Bool) -> [ContentCategory] {
        categories
            .filter { $0.section == section.rawValue && (!activeOnly || $0.isActive) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// مفاتيح التصنيفات الظاهرة — nil قبل التحميل (يستخدم المستدعي القائمة المدمجة)
    nonisolated static func activeKeys(_ section: CategorySection) -> [String]? {
        let rows = snapshot.values.filter { $0.section == section.rawValue }
        guard !rows.isEmpty else { return nil }
        return rows.filter(\.isActive).sorted { $0.sortOrder < $1.sortOrder }.map(\.key)
    }

    func fetch() async {
        do {
            let rows: [ContentCategory] = try await SupabaseConfig.client
                .from("content_categories")
                .select()
                .order("sort_order")
                .execute()
                .value
            apply(rows)
        } catch {
            Log.fetchError("تعذر جلب التصنيفات", error)
        }
    }

    /// أعداد العناصر — لشاشة «التصنيفات»
    func fetchCounts() async {
        struct Row: Decodable { let section: String; let key: String?; let items: Int }
        do {
            let rows: [Row] = try await SupabaseConfig.client
                .rpc("content_category_counts")
                .execute()
                .value
            var map: [String: Int] = [:]
            for row in rows { if let key = row.key { map["\(row.section)|\(key)"] = row.items } }
            counts = map
        } catch {
            Log.fetchError("تعذر جلب أعداد التصنيفات", error)
        }
    }

    /// حذف نهائي — السيرفر يرفضه إذا كان التصنيف أساسياً أو فيه عناصر
    func delete(_ category: ContentCategory) async -> Bool {
        do {
            try await SupabaseConfig.client
                .rpc("delete_content_category", params: ["p_id": category.id.uuidString])
                .execute()
            await fetch()
            await fetchCounts()
            return true
        } catch {
            let text = "\(error)"
            if text.contains("category_not_empty") {
                errorMessage = L10n.t("لا يمكن حذفه — فيه عناصر. انقلها لتصنيف آخر أو أخفِ التصنيف.",
                                      "Can't delete — it has items. Move them or hide the category.")
            } else if text.contains("protected_category") {
                errorMessage = L10n.t("هذا تصنيف أساسي ولا يُحذف.", "This is a core category and can't be deleted.")
            } else {
                errorMessage = L10n.t("تعذّر حذف التصنيف", "Couldn't delete the category")
            }
            Log.error("[Categories] حذف: \(error.localizedDescription)")
            return false
        }
    }

    private func apply(_ rows: [ContentCategory]) {
        categories = rows
        var map: [String: ContentCategory] = [:]
        for row in rows {
            if let section = CategorySection(rawValue: row.section) {
                map[Self.snapshotKey(section, row.key)] = row
            }
        }
        Self.snapshot = map
    }

    // MARK: التعديل — للمالك فقط (سياسة الجدول)

    func save(_ category: ContentCategory, refetch: Bool = true) async -> Bool {
        struct Payload: Encodable {
            let name_ar: String, name_en: String, icon_key: String, color_key: String
            let sort_order: Int, is_active: Bool, updated_at: String
        }
        do {
            try await SupabaseConfig.client
                .from("content_categories")
                .update(Payload(name_ar: category.nameAr.trimmingCharacters(in: .whitespacesAndNewlines),
                                name_en: category.nameEn.trimmingCharacters(in: .whitespacesAndNewlines),
                                icon_key: category.iconKey, color_key: category.colorKey,
                                sort_order: category.sortOrder, is_active: category.isActive,
                                updated_at: ISO8601DateFormatter().string(from: Date())))
                .eq("id", value: category.id.uuidString)
                .execute()
            if refetch { await fetch() }
            return true
        } catch {
            errorMessage = L10n.t("تعذّر حفظ التصنيف", "Couldn't save the category")
            Log.error("[Categories] حفظ: \(error.localizedDescription)")
            return false
        }
    }

    /// تصنيف أخبار جديد — المفتاح هو الاسم العربي (كما تُخزَّن أنواع الأخبار دائماً)
    func add(section: CategorySection, nameAr: String, nameEn: String,
             iconKey: String, colorKey: String) async -> Bool {
        struct Payload: Encodable {
            let section: String, key: String, name_ar: String, name_en: String
            let icon_key: String, color_key: String, sort_order: Int
        }
        let ar = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        let en = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard section.allowsAdding, !ar.isEmpty else { return false }
        if categories.contains(where: { $0.section == section.rawValue && ($0.key == ar || $0.nameAr == ar) }) {
            errorMessage = L10n.t("يوجد تصنيف بنفس الاسم", "A category with this name exists")
            return false
        }
        let nextOrder = (list(section, activeOnly: false).map(\.sortOrder).max() ?? -1) + 1
        do {
            // الأخبار تخزّن الاسم العربي نفسه نوعاً؛ المكتبة رمزاً ثابتاً مستقلاً عن الاسم
            let key = section == .news
                ? ar
                : "custom_" + UUID().uuidString.prefix(8).lowercased()
            try await SupabaseConfig.client
                .from("content_categories")
                .insert(Payload(section: section.rawValue, key: key, name_ar: ar,
                                name_en: en.isEmpty ? ar : en,
                                icon_key: iconKey, color_key: colorKey, sort_order: nextOrder))
                .execute()
            await fetch()
            return true
        } catch {
            errorMessage = L10n.t("تعذّرت إضافة التصنيف", "Couldn't add the category")
            Log.error("[Categories] إضافة: \(error.localizedDescription)")
            return false
        }
    }

    /// حفظ ترتيب جديد لقسم
    func reorder(_ section: CategorySection, ids: [UUID]) async {
        for (index, id) in ids.enumerated() {
            if var row = categories.first(where: { $0.id == id }), row.sortOrder != index {
                row.sortOrder = index
                _ = await save(row, refetch: false)
            }
        }
        await fetch()
    }
}
