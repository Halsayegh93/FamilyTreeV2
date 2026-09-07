import Foundation

/// Decode only the server payload: report fields cannot prevent jobs from loading.
struct ServerHealthDashboard: Decodable {
    let checked_at: String
    let dispatch_healthy: Bool
    let jobs: [ServerHealthJob]

    func jobs(matching filter: ServerHealthFilter) -> [ServerHealthJob] {
        jobs.filter { filter.includes($0) }.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.name < $1.name
        }
    }
}

struct ServerHealthJob: Decodable, Identifiable {
    let name: String
    let status: String
    let last_run: String?
    var id: String { name }
    var priority: Int {
        switch status {
        case "failed": return 0
        case "succeeded": return 2
        default: return 1
        }
    }
}

enum ServerHealthFilter: String, CaseIterable {
    case all, failed, succeeded, notRun
    func includes(_ job: ServerHealthJob) -> Bool {
        switch self {
        case .all: return true
        case .failed: return job.status == "failed"
        case .succeeded: return job.status == "succeeded"
        case .notRun: return job.status != "failed" && job.status != "succeeded"
        }
    }
}

/// Timestamps remain strings in decoded payloads; an unavailable display date
/// must never hide all server results or alter a diagnostic review cutoff.
enum HealthTimestamp {
    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
