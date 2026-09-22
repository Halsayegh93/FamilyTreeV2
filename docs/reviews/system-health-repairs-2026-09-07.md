# Actual repairs from System Health

Owners and active admins can now open **Server jobs → Repair and run**, review the affected-record count, and execute a fixed repair on the server. The errors page links to these tools. A report acknowledgment remains separate from a completed repair.

Supported recipes:

| Job | Repair and retention policy |
| --- | --- |
| cleanup-old-join-requests | Restore weekly schedule/command and active state; add missing created_at if necessary. Delete only approved/rejected requests older than 60 days. Missing legacy dates start at repair time. |
| cleanup-old-web-sessions | Restore daily schedule and last_seen_at command; delete sessions inactive over 30 days. |
| cleanup-delivery-attempts | Restore daily schedule; delete delivery attempts older than 8 days. |
| cleanup-app-diagnostics | Restore daily schedule; delete reports and reviews older than 30 days. |

The server owns the recipes. Clients cannot submit SQL, select arbitrary tables, change retention periods, send notifications, or change account permissions through this endpoint. Other failure types still require their respective tools or a code/database update.

Execution safeguards:
- Active owner/admin authorization is checked server-side; audit tables and recipe helpers have no direct authenticated/anonymous access.
- The preview reports the exact current count. The executor locks the relevant tables, rechecks the count, rejects changed previews and operations above 5,000 rows, and refuses a currently running job.
- Request UUIDs bind to the actor and target job. A retry of a committed request returns its existing result. Per-job serialization and a 30-second cooldown prevent overlapping manual repairs.
- All definition/schema/cleanup changes occur in one subtransaction. A failed step rolls them back and stores a failed audit result with a SQLSTATE code, without exposing raw database messages.
- pg_cron schedule updates do not necessarily reactivate an existing inactive job. The repair explicitly activates it and verifies its command, schedule and active state before recording success.
- The UI requests confirmation before an operation that deletes records; zero-record repairs execute directly from the labeled action.

Actual manual executions are stored in `system_health_repairs`. No rows are fabricated in `cron.job_run_details`. The dashboard compares the most recent completed scheduled run with the most recent actual repair attempt and labels its source. Previous scheduled status remains visible in job details; a later scheduled failure takes precedence. The last 10 repairs show outcome, count and completion time without exposing actor identifiers.

Validation:
- PGlite executes the migrations and real repair functions against fixtures. Coverage includes authorization/RLS, unsupported actions, schema repair, legacy/pending retention, actual cleanup counts (including multi-statement totals), scheduler reactivation, rollback on a forced database error, stale counts, idempotency/actor binding, cooldown, running jobs, operation limits and scheduled/manual ordering.
- Production integration test inside a rolled-back transaction temporarily disabled the existing join-request job, called the actual repair RPC with zero eligible records, verified reactivation and a successful zero-row execution, then rolled back everything. It exposed the pg_cron reactivation detail above, which is fixed and covered in tests.
- After deployment, authenticated read-only verification confirmed all four previews work, all four definitions are healthy, and there are zero persisted repair records from testing.
- Simulator uses a separate temporary bundle and a loopback HTTP fixture. Production SwiftUI preview/execute methods sent the expected RPC payloads; canceling confirmation sent no execution request; confirmed positive-count and zero-count flows displayed success and refreshed history. The temporary app was uninstalled and its fixture server stopped after testing.
- Signed iOS build succeeds. No production records were deleted while developing or validating this feature.
