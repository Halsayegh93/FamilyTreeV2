#!/usr/bin/env python3
"""Read-only production checks. JSON contains aggregates, never credentials/PII.
Exit 0: healthy, 1: incidents, 2: check unavailable. State supports deduplication.
"""
import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import subprocess

PROJECT = 'poxyxsgvzwmnmewytsiw'
QUERY = """
begin read only;
select jsonb_build_object(
 'cron', (select coalesce(jsonb_agg(jsonb_build_object(
   'name', j.jobname, 'status', r.status)), '[]')
   from cron.job j left join lateral (
     select status from cron.job_run_details where jobid=j.jobid
     and status in ('failed','succeeded')
     order by start_time desc,runid desc limit 1
   ) r on true where j.active),
 'dispatch_healthy', exists(select 1 from cron.job j join cron.job_run_details r using(jobid)
   where j.jobname='dispatch-scheduled-notifications' and j.active
   and r.status='succeeded' and r.end_time>now()-interval '5 minutes'),
 'http_failures', (select count(*) from net._http_response
   where created>now()-interval '1 hour'
   and (status_code>=400 or timed_out or error_msg is not null)),
 'pending_deletions', (select count(*) from public.account_deletion_jobs d
   where d.created_at<now()-interval '15 minutes'
   and exists(select 1 from auth.users u where u.id=d.auth_user_id)),
 'checked_at', now()) as health;
"""

def classify(health):
    issues = {}
    for job in health['cron']:
        if job['status'] == 'failed':
            issues['cron:' + job['name']] = 'Latest scheduled run failed'
    if not health['dispatch_healthy']:
        issues['dispatch_stale'] = 'No successful notification dispatcher run in 5 minutes'
    if health['http_failures'] >= 5:
        issues['http_failures'] = 'At least 5 outbound HTTP failures in the last hour'
    if health['pending_deletions'] > 0:
        issues['pending_deletions'] = 'Account deletion pending for more than 15 minutes'
    return issues

def transition(previous, issues, available):
    # A failed read must never announce recovery for unseen production incidents.
    current = dict(issues)
    if not available:
        current.update({k: v for k, v in previous.items() if k != 'monitor_unavailable'})
        current['monitor_unavailable'] = 'Production health could not be checked'
    return current, sorted(set(current) - set(previous)), sorted(set(previous) - set(current))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--workdir', required=True)
    parser.add_argument('--state', required=True, help='Private state file outside the repository')
    args = parser.parse_args()
    os.umask(0o077)
    state = Path(args.state).expanduser().resolve()
    repo = Path(__file__).resolve().parents[1]
    if state == repo or repo in state.parents:
        raise SystemExit('State must be outside the repository')
    state.parent.mkdir(parents=True, exist_ok=True)
    with open(str(state) + '.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        previous = json.loads(state.read_text()) if state.exists() else {}
        health, available, issues = None, False, {}
        try:
            linked = Path(args.workdir) / 'supabase/.temp/project-ref'
            if linked.read_text().strip() != PROJECT:
                raise ValueError('Wrong project')
            result = subprocess.run(['supabase','db','query','--linked','--workdir',args.workdir,
                QUERY,'--output','json'], capture_output=True, text=True, timeout=90, check=True)
            health = json.loads(result.stdout)['rows'][0]['health']
            issues = classify(health)
            available = True
        except (OSError, ValueError, KeyError, IndexError, TypeError, subprocess.SubprocessError):
            pass  # CLI errors may include private service details; do not emit them.
        current, opened, resolved = transition(previous.get('issues', {}), issues, available)
        now = dt.datetime.now(dt.timezone.utc).isoformat()
        output = {'checked_at': now, 'available': available, 'issues': current,
                  'opened': opened, 'resolved': resolved, 'notify': bool(opened or resolved),
                  'health': health}
        temporary = state.with_suffix('.tmp')
        temporary.write_text(json.dumps(output, indent=2))
        temporary.replace(state)
        print(json.dumps(output))
        return 2 if not available else (1 if current else 0)

if __name__ == '__main__':
    raise SystemExit(main())
