import Foundation
import Combine
import Supabase

/// Owner-only SMS audit. Codes are fetched through the separate audited RPC;
/// this payload contains request metadata, never an OTP.
struct SmsAttemptDetails {
    struct Attempt: Identifiable {
        let id: Int
        var recordedAt: Date?
        var requestedAt: Date?
        var outcome: String
        var sender: String?
        var msgid: String?
        var errorCode: String?
        var points: Double?
        var balanceAfter: Double?
        var httpStatus: Int?
        var retryAfter: Int?
        var testMode: Bool?
        var queueStatus: String?
        var queueCheckedAt: Date?
        var alerted: Bool
    }

    struct CodeView: Identifiable {
        let id: Int
        let at: Date?
        let result: String
        let by: String?
    }

    var summary: SmsLoginAttempts.Item
    var days: Int
    var retentionDays: Int
    var generatedAt: Date?
    var activeCodeSentAt: Date?
    var activeCodeExpiresAt: Date?
    var total: Int
    var attempts: [Attempt]
    var nextBefore: Int?
    var codeViews: [CodeView]
    var codeViewCount: Int

    static func decode(_ data: Data, fallback: SmsLoginAttempts.Item) throws -> SmsAttemptDetails {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        var summary = fallback
        if let s = root["summary"] as? [String: Any] {
            summary.name = s["name"] as? String ?? fallback.name
            summary.memberStatus = s["member_status"] as? String
            summary.isMember = s["is_member"] as? Bool ?? fallback.isMember
            summary.attemptsToday = SmsJSON.int(s["attempts_today"]) ?? 0
            summary.attemptsInWindow = SmsJSON.int(s["attempts_in_window"]) ?? 0
            summary.sent = SmsJSON.int(s["sent"]) ?? 0
            summary.blocked = SmsJSON.int(s["blocked"]) ?? 0
            summary.failed = SmsJSON.int(s["failed"]) ?? 0
            summary.unknown = SmsJSON.int(s["unknown"]) ?? 0
            summary.test = SmsJSON.int(s["test"]) ?? 0
            summary.firstAt = ApprovalWorkflow.date(s["first_at"] as? String)
            summary.lastAt = ApprovalWorkflow.date(s["last_at"] as? String)
            summary.lastOutcome = s["last_outcome"] as? String ?? "unknown"
            summary.loggedIn = s["logged_in"] as? Bool ?? false
            summary.maxInHour = SmsJSON.int(s["max_in_hour"]) ?? fallback.maxInHour
            summary.suspicious = s["suspicious"] as? Bool ?? fallback.suspicious
            summary.lastSignInAt = ApprovalWorkflow.date(s["last_sign_in_at"] as? String)
        }
        let active = root["active_code"] as? [String: Any] ?? [:]
        let attempts = (root["items"] as? [[String: Any]] ?? []).compactMap { x -> Attempt? in
            guard let id = SmsJSON.int(x["id"]) else { return nil }
            let d = x["details"] as? [String: Any] ?? [:]
            return Attempt(id: id, recordedAt: ApprovalWorkflow.date(x["recorded_at"] as? String),
                requestedAt: ApprovalWorkflow.date(d["requested_at"] as? String),
                outcome: x["outcome"] as? String ?? "unknown", sender: d["sender"] as? String,
                msgid: d["msgid"] as? String, errorCode: d["error_code"] as? String,
                points: SmsJSON.double(d["points"]), balanceAfter: SmsJSON.double(d["balance_after"]),
                httpStatus: SmsJSON.int(d["http_status"]), retryAfter: SmsJSON.int(d["retry_after_seconds"]),
                testMode: d["test_mode"] as? Bool, queueStatus: d["queue_status"] as? String,
                queueCheckedAt: ApprovalWorkflow.date(d["queue_checked_at"] as? String),
                alerted: x["alerted"] as? Bool ?? false)
        }
        let views = (root["code_views"] as? [[String: Any]] ?? []).compactMap { x -> CodeView? in
            guard let id = SmsJSON.int(x["id"]) else { return nil }
            return CodeView(id: id, at: ApprovalWorkflow.date(x["at"] as? String),
                            result: x["result"] as? String ?? "none", by: x["by"] as? String)
        }
        return SmsAttemptDetails(summary: summary, days: SmsJSON.int(root["days"]) ?? 7,
            retentionDays: SmsJSON.int(root["retention_days"]) ?? 30,
            generatedAt: ApprovalWorkflow.date(root["generated_at"] as? String),
            activeCodeSentAt: ApprovalWorkflow.date(active["sent_at"] as? String),
            activeCodeExpiresAt: ApprovalWorkflow.date(active["expires_at"] as? String),
            total: SmsJSON.int(root["total"]) ?? attempts.count, attempts: attempts,
            nextBefore: SmsJSON.int(root["next_before"]), codeViews: views,
            codeViewCount: SmsJSON.int(root["code_view_count"]) ?? views.count)
    }
}

@MainActor
final class SmsAttemptDetailsStore: ObservableObject {
    let item: SmsLoginAttempts.Item
    let days: Int
    @Published private(set) var detail: SmsAttemptDetails?
    @Published private(set) var code: OwnerCodeReveal?
    @Published private(set) var loading = false
    @Published private(set) var loadingMore = false
    @Published private(set) var revealing = false
    @Published private(set) var failed = false
    @Published private(set) var denied = false
    @Published private(set) var codeFailed = false
    @Published private(set) var checking: Set<String> = []
    @Published private(set) var checkFailed: Set<String> = []
    private var generation = UUID()

    init(item: SmsLoginAttempts.Item, days: Int) { self.item = item; self.days = days }

    private struct Params: Encodable {
        let p_phone: String
        let p_days: Int
        var p_before: Int? = nil
    }

    private func fetch(before: Int? = nil) async throws -> SmsAttemptDetails {
        guard let phone = item.phoneE164 else { throw CocoaError(.coderReadCorrupt) }
        let data = try await SupabaseConfig.client.rpc("owner_sms_login_details",
            params: Params(p_phone: phone, p_days: days, p_before: before)).execute().data
        return try SmsAttemptDetails.decode(data, fallback: item)
    }

    func refresh(isOwner: Bool, revealAvailableCode: Bool = false) async {
        guard isOwner else { clearSensitive(); return }
        guard !loading, !loadingMore, !revealing else { return }
        let token = generation
        loading = true; failed = false
        defer { if generation == token { loading = false } }
        do {
            let reply = try await fetch()
            guard token == generation else { return }
            detail = reply; denied = false
            if code?.sentAt != reply.activeCodeSentAt { clearCode() }
            if revealAvailableCode, code == nil, let expiry = reply.activeCodeExpiresAt, expiry > Date() {
                await reveal(isOwner: isOwner)
            }
        } catch {
            guard token == generation, !ErrorHelper.isCancellation(error) else { return }
            if rejectIfDenied(error) { return }
            failed = true
        }
    }

    func more(isOwner: Bool) async {
        guard isOwner, let cursor = detail?.nextBefore, !loading, !loadingMore else { return }
        let token = generation
        loadingMore = true; failed = false
        defer { if token == generation { loadingMore = false } }
        do {
            let reply = try await fetch(before: cursor)
            guard token == generation, var current = detail else { return }
            let existing = Set(current.attempts.map(\.id))
            current.attempts += reply.attempts.filter { !existing.contains($0.id) }
            current.nextBefore = reply.nextBefore
            current.total = reply.total
            detail = current
        } catch {
            guard token == generation, !ErrorHelper.isCancellation(error) else { return }
            if rejectIfDenied(error) { return }
            failed = true
        }
    }

    func reveal(isOwner: Bool) async {
        guard isOwner, !revealing, let phone = item.phoneE164 else { return }
        let token = generation
        revealing = true; codeFailed = false
        defer { if token == generation { revealing = false } }
        do {
            let reply = try await SmsLoginAttemptsStore.shared.reveal(phone)
            guard token == generation else { return }
            code = reply
            // Read the audit after the reveal has committed, not concurrently.
            if let fresh = try? await fetch(), token == generation { detail = fresh }
        } catch {
            guard token == generation, !ErrorHelper.isCancellation(error) else { return }
            if rejectIfDenied(error) { return }
            clearCode(); codeFailed = true
        }
    }

    func check(_ msgid: String, isOwner: Bool) async {
        guard isOwner, !checking.contains(msgid) else { return }
        let token = generation
        checking.insert(msgid); checkFailed.remove(msgid)
        defer { if token == generation { checking.remove(msgid) } }
        do {
            let reply = try await SmsBalanceStore.shared.call("status", msgid: msgid,
                                                            as: SmsBalanceStore.StatusReply.self)
            guard token == generation, var current = detail else { return }
            for index in current.attempts.indices where current.attempts[index].msgid == msgid {
                current.attempts[index].queueStatus = reply.status
                current.attempts[index].queueCheckedAt = Date()
            }
            detail = current
        } catch {
            guard token == generation, !ErrorHelper.isCancellation(error) else { return }
            if rejectIfDenied(error) { return }
            checkFailed.insert(msgid)
        }
    }

    func clearCode() { code = nil; codeFailed = false }

    /// A newer code or a subsequent sign-in invalidates the displayed value.
    /// Recheck metadata only; this never reveals another code or creates a view audit.
    func validateDisplayedCode(isOwner: Bool) async {
        guard isOwner, let shown = code, shown.status == "shown", !revealing else { return }
        let token = generation
        do {
            let fresh = try await fetch()
            guard token == generation, code?.sentAt == shown.sentAt else { return }
            if fresh.activeCodeSentAt != shown.sentAt || fresh.activeCodeExpiresAt != shown.expiresAt {
                clearCode()
                detail?.activeCodeSentAt = fresh.activeCodeSentAt
                detail?.activeCodeExpiresAt = fresh.activeCodeExpiresAt
                detail?.summary.lastSignInAt = fresh.summary.lastSignInAt
                detail?.summary.loggedIn = fresh.summary.loggedIn
            }
        } catch {
            guard token == generation, !ErrorHelper.isCancellation(error) else { return }
            if rejectIfDenied(error) { return }
            clearCode(); codeFailed = true
        }
    }

    private func rejectIfDenied(_ error: Error) -> Bool {
        guard (error as? PostgrestError)?.code == "42501" else { return false }
        clearSensitive(); denied = true; failed = true
        return true
    }

    func clearSensitive() {
        generation = UUID(); detail = nil; clearCode()
        loading = false; loadingMore = false; revealing = false; checking = []; checkFailed = []
    }

    func expireCode() async {
        guard let expiry = code?.expiresAt else { return }
        let delay = max(0, min(300, expiry.timeIntervalSinceNow))
        do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        catch { return }
        guard code?.expiresAt == expiry else { return }
        code?.code = nil; code?.status = "expired"
    }
}
