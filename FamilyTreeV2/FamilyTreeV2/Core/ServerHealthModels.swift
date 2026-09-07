import Foundation

/// Decode only the server payload: report fields cannot prevent jobs from loading.
struct ServerHealthDashboard: Decodable {
    let checked_at: String
    let dispatch_healthy: Bool
    let jobs: [ServerHealthJob]
    var repairs: [SystemHealthRepairResult]? = nil

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
    var active: Bool? = nil
    var repair_available: Bool? = nil
    var configuration_needs_repair: Bool? = nil
    var last_run_source: String? = nil
    var scheduled_status: String? = nil
    var scheduled_last_run: String? = nil
    var id: String { name }
    var priority: Int {
        if active == false || configuration_needs_repair == true { return -1 }
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

struct SystemHealthRepairPreview: Decodable {
    let job_name: String
    let eligible_rows: Int
    let can_run: Bool
    let schema_repair_needed: Bool
    let configuration_needs_repair: Bool
    let checked_at: String
}

struct SystemHealthRepairResult: Decodable, Identifiable {
    let request_id: String
    let job_name: String
    let status: String
    let affected_rows: Int
    let error_code: String?
    let completed_at: String
    var id: String { request_id }
}
