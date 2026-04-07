import Foundation

/// تحليلات بسيطة — يسجل الأحداث محلياً
enum AppAnalytics {
    private static let key = "app_analytics_events"
    private static let maxEvents = 200

    struct Event: Codable {
        let name: String
        let date: String
        let params: [String: String]?
    }

    /// تسجيل حدث
    static func track(_ name: String, params: [String: String]? = nil) {
        let formatter = ISO8601DateFormatter()
        let event = Event(
            name: name,
            date: formatter.string(from: Date()),
            params: params
        )

        var events = loadEvents()
        events.insert(event, at: 0)
        if events.count > maxEvents { events = Array(events.prefix(maxEvents)) }

        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// أحداث مهمة مسبقة التعريف
    static func trackLogin() { track("login") }
    static func trackRegister() { track("register") }
    static func trackViewTree() { track("view_tree") }
    static func trackSearch(query: String) { track("search", params: ["query": query]) }
    static func trackPostNews() { track("post_news") }
    static func trackKinship() { track("kinship") }
    static func trackViewMember(id: String) { track("view_member", params: ["id": id]) }
    static func trackTabSwitch(tab: String) { track("tab_switch", params: ["tab": tab]) }

    /// تحميل الأحداث
    static func loadEvents() -> [Event] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Event].self, from: data)) ?? []
    }

    /// مسح الأحداث
    static func clearEvents() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// عدد الأحداث
    static var count: Int { loadEvents().count }
}
