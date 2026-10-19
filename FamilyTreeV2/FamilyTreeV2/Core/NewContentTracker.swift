import Foundation
import Combine
import Supabase

/// «النقاط الصفراء» (طلب المالك ٢٠٢٦-١٠-١٠): نقطة صغيرة على مربّع القسم في الرئيسية إذا نُشر فيه
/// شيء جديد معتمد من غيرك بعد آخر مرة فتحته — الأخبار، المشاريع، الديوانيات، المكتبة.
/// آخر فتح لكل قسم محفوظ على الجهاز لكل حساب، وأول تشغيل يبدأ من الآن (بلا نقاط على القديم).
@MainActor
final class NewContentTracker: ObservableObject {
    static let shared = NewContentTracker()

    enum Section: String, CaseIterable {
        case news, projects, diwaniyas, library

        fileprivate var table: String {
            switch self {
            case .news: return "news"
            case .projects: return "projects"
            case .diwaniyas: return "diwaniyas"
            case .library: return "family_archive"
            }
        }

        /// وقت النشر وصاحب المحتوى (باسم موحّد `owner`)، والإخفاء حيث يوجد
        fileprivate var columns: String {
            switch self {
            case .news: return "created_at, approved_at, owner:author_id"
            case .projects: return "created_at, owner:owner_id, is_hidden"
            case .diwaniyas: return "created_at, approved_at, owner:owner_id"
            case .library: return "created_at, approved_at, owner:uploaded_by, is_hidden"
            }
        }
    }

    @Published private(set) var newSections: Set<Section> = []

    private let supabase = SupabaseConfig.client
    private var userId: UUID?
    private var lastRefresh: Date?

#if DEBUG
    /// معاينة على المحاكي (`-tmpNewDots`): كل قسم فيه «جديد» وقت التشغيل ولم يُفتح من قبل —
    /// فتح القسم يخفي نقطته كما في الحقيقة
    private let debugPreview = ProcessInfo.processInfo.arguments.contains("-tmpNewDots")
    private let debugLaunch = Date()

    private init() {
        guard debugPreview else { return }
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("newDots.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
#else
    private init() {}
#endif

    func hasNew(_ section: Section) -> Bool { newSections.contains(section) }

    /// فُتح القسم — تختفي نقطته حتى يُنشر فيه جديد
    func markSeen(_ section: Section) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key(section))
        if newSections.contains(section) { newSections.remove(section) }
    }

    /// أحدث محتوى من غيري في كل قسم مقابل آخر فتح — مرة كل دقيقة على الأكثر إلا عند السحب للتحديث
    func refresh(userId: UUID?, force: Bool = false) async {
        if userId != self.userId { self.userId = userId; lastRefresh = nil }
        if !force, let last = lastRefresh, Date().timeIntervalSince(last) < 60 { return }
        lastRefresh = Date()

        var result = Set<Section>()
        for section in Section.allCases {
            if let newest = await newestFromOthers(section), newest > lastSeen(section) {
                result.insert(section)
            }
        }
        newSections = result
    }

    // MARK: - داخلي

    private struct Row: Decodable {
        let created_at: String?
        let approved_at: String?
        let owner: String?
        let is_hidden: Bool?
    }

    /// وقت ظهور أحدث محتوى معتمد من غيري (الاعتماد إن وُجد، وإلا الإنشاء)
    private func newestFromOthers(_ section: Section) async -> Date? {
#if DEBUG
        if debugPreview { return debugLaunch }
#endif
        do {
            let rows: [Row] = try await supabase
                .from(section.table)
                .select(section.columns)
                .eq("approval_status", value: "approved")
                .order("created_at", ascending: false)
                .limit(10)
                .execute()
                .value
            let me = userId?.uuidString.lowercased()
            return rows
                .filter { $0.is_hidden != true && ($0.owner?.lowercased() != me || me == nil) }
                .compactMap { Self.parse($0.approved_at) ?? Self.parse($0.created_at) }
                .max()
        } catch {
            Log.warning("[NEW-DOTS] تعذّر فحص \(section.rawValue): \(error.localizedDescription)")
            return nil
        }
    }

    /// آخر فتح للقسم — أول مرة تُحفظ «الآن» فلا يظهر القديم كجديد
    private func lastSeen(_ section: Section) -> Date {
        let stored = UserDefaults.standard.double(forKey: key(section))
        if stored > 0 { return Date(timeIntervalSince1970: stored) }
#if DEBUG
        if debugPreview { return .distantPast }
#endif
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: key(section))
        return now
    }

    private func key(_ section: Section) -> String {
        "newDots.lastSeen.\(userId?.uuidString ?? "anon").\(section.rawValue)"
    }

    /// وقت السيرفر (timestamptz) — كسور الثواني تُحذف لأن المحلّل لا يقبل أكثر من ثلاث خانات
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "T")
        return iso.date(from: trimmed)
    }
}
