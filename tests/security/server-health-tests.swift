import Foundation

@main struct ServerHealthTests {
    static func main() throws {
        // PostgreSQL microseconds, null completed result, unknown status, and an
        // unrelated malformed reports field must not break the server screen.
        let payload = #"""
        {"checked_at":"2026-09-07T16:01:00.470921+00:00","dispatch_healthy":true,
         "errors":[{"first_seen":null,"last_seen":"unusable"}],
         "jobs":[
           {"name":"successful","status":"succeeded","last_run":"2026-09-07T16:01:00.470921+00:00"},
           {"name":"new-job","status":"not_run","last_run":null},
           {"name":"failed-job","status":"failed","last_run":"2026-09-02T03:00:00+00:00"},
           {"name":"unknown","status":"future-status","last_run":"unusable"}]}
        """#.data(using: .utf8)!
        let dashboard = try JSONDecoder().decode(ServerHealthDashboard.self, from: payload)
        precondition(dashboard.jobs.count == 4)
        precondition(dashboard.jobs(matching: .all).map(\.name) == ["failed-job", "new-job", "unknown", "successful"])
        precondition(dashboard.jobs(matching: .succeeded).map(\.name) == ["successful"])
        precondition(dashboard.jobs(matching: .failed).map(\.name) == ["failed-job"])
        precondition(dashboard.jobs(matching: .notRun).map(\.name) == ["new-job", "unknown"])
        precondition(HealthTimestamp.date(dashboard.checked_at) != nil)
        precondition(HealthTimestamp.date("2026-09-02T03:00:00+00:00") != nil)
        precondition(HealthTimestamp.date(nil) == nil)
        precondition(HealthTimestamp.date("unusable") == nil)
        let empty = try JSONDecoder().decode(ServerHealthDashboard.self, from: Data(#"{"checked_at":"bad-date","dispatch_healthy":false,"jobs":[]}"#.utf8))
        precondition(empty.jobs(matching: .all).isEmpty)
        precondition(HealthTimestamp.date(empty.checked_at) == nil)
        print("PASS: server payload isolation, status filters, attention order, nullable and PostgreSQL timestamps")
    }
}
