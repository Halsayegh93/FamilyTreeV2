# System Health navigation and server jobs — 2026-09-07

The overview previously used locally registered value destinations below the administration screen's mixed navigation stack. Both report tiles selected the review queue, and the successful-jobs tile opened an unfiltered server page. Server content also depended on decoding unrelated diagnostic records.

Changes:
- Direct destination links throughout the overview, with the full visible row/card as a tap target. The five section entries come before summary metrics; errors and server jobs appear first.
- Separate entry routes for all reports, reports needing review, successful jobs, failed jobs, and operational indicators. Report summary cards also select their matching filter. Existing activity, device-management, and push-health screens remain their respective destinations.
- Dedicated server page with all/failed/succeeded/no-result filters, counts, failure-first ordering, expandable job details, last completed run dates, and a separate operational summary. Operational alerts open with that summary first.
- Server JSON decoding only requires server fields. Display dates tolerate PostgreSQL microseconds, absent dates, and invalid display dates without discarding the job list. Reports no longer decode unused server fields or first-seen dates; review requests still send the original last-seen timestamp unchanged.
- The page describes the limits of each status: a past failed result remains until a new completed run; no recorded completion does not mean the scheduler is broken; dispatcher success is not proof of delivery to every device.

Validation:
- Signed iOS device build; native Swift regression tests for decoding isolation, filtering, sorting, empty results, and timestamps.
- Existing diagnostic security/RLS, recurrence, and stale-review tests.
- Navigation and rendering verified separately using an isolated simulator copy. Only data loaders and the app entry are replaced with synthetic fixtures; destination mapping and destination views are the production implementation. The copy points to an unreachable loopback backend, so test taps cannot mutate production data. The actual app entry and device build retain the production configuration.

Read-only production check: six jobs, including the dispatcher, had successful latest completed runs; cleanup-old-join-requests still showed its September 2 failed completion, and cleanup-app-diagnostics had no completed result yet. No cron jobs were manually executed and no scheduler configuration changed in this patch.

Follow-up after the cleanup was run on demand:
- The real cleanup job completed successfully at 2026-09-07 16:34 UTC (`DELETE 0`), and its original weekly schedule was restored. A read-only transaction invoking the actual dashboard RPC returned that successful result and zero failed jobs.
- The isolated simulator preview was still showing its fixed failed-job fixture. It was replaced with a normal simulator build so this test data could not be mistaken for current server state.
- The server page now refreshes every 30 seconds while visible and active, with cancellation when the page disappears or the scene becomes inactive. The last successful refresh timestamp appears above the results. The overview also refreshes when returning to the foreground. Failed refreshes continue to show the stale-data warning; no successful result is synthesized locally.
