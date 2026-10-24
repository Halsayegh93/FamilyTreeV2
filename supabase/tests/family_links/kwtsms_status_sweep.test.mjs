// تجربة 20261023110000 (فحص الوصول التلقائي) — قاعدة محلية معزولة.
import { makeDb, one, read, counter } from './app_config_env.mjs';
const ok = counter();
const M = read('migrations/20261023110000_kwtsms_status_sweep.sql');
const RB = read('rollback/20261023110000_kwtsms_status_sweep_rollback.sql');
const db = await makeDb();
await db.exec(`
  create table public.kwtsms_deliveries (event_hash text primary key, phone_hash text not null,
    created_at timestamptz not null default now(), test_mode boolean not null, outcome text not null default 'pending',
    provider_msgid text, delivery_status text, delivery_checked_at timestamptz);
  create table private.app_secrets (key text primary key, value text);
  create schema net; create table net.calls (id bigserial primary key, url text, body jsonb, headers jsonb);
  create function net.http_post(url text, body jsonb default '{}', params jsonb default '{}', headers jsonb default '{}',
    timeout_milliseconds int default 5000) returns bigint language sql as $f$
    insert into net.calls (url, body, headers) values (url, body, headers) returning id $f$;
  create schema if not exists cron;
  create table cron.job (jobid bigserial primary key, schedule text, command text, jobname text unique);
  create function cron.schedule(n text, s text, c text) returns bigint language sql as $c$
    insert into cron.job (jobname, schedule, command) values (n, s, c)
    on conflict (jobname) do update set schedule = excluded.schedule returning jobid $c$;
  create function cron.unschedule(n text) returns boolean language sql as $c$ delete from cron.job where jobname = n returning true $c$;
`);
await db.exec(M);
const ins = (id, mins, extra = {}) => db.query(`insert into public.kwtsms_deliveries (event_hash, phone_hash, created_at, test_mode, outcome,
  provider_msgid, delivery_status, delivery_checked_at) values ($1, 'p', now() - ($2::text || ' minutes')::interval, $3, $4, $5, $6, $7)`,
  [id, mins, extra.test ?? false, extra.outcome ?? 'accepted', extra.msgid === undefined ? id : extra.msgid,
   extra.status ?? null, extra.checked ?? null]);
const pending = async () => (await one(db, `select public.kwtsms_pending_status_checks(20) j`)).j;

ok.ok((await one(db, `select public.kwtsms_status_sweep_job() r`)).r === null, 'لا رسائل ← لا نداء');
await ins('fresh', 0.5);              // أقل من دقيقة
await ins('a', 2);                    // يحتاج فحص
await ins('old', 40);                 // أقدم من ٣٠ دقيقة
await ins('test', 3, { test: true }); // تجريبي
await ins('failed', 3, { outcome: 'failed' });
await ins('done', 3, { status: 'Delivered' });
await ins('recent', 3, { status: 'Sent', checked: new Date(Date.now() - 30000).toISOString() });
await ins('due', 4, { status: 'Sent', checked: new Date(Date.now() - 200000).toISOString() });
ok.ok(JSON.stringify(await pending()) === JSON.stringify(['due', 'a']), 'القائمة: المستحقة فقط بالترتيب', JSON.stringify(await pending()));
ok.ok((await one(db, `select public.kwtsms_status_sweep_job() r`)).r === null, 'بلا سرّ ← لا نداء');
await db.exec(`insert into private.app_secrets values ('push_webhook_secret', 'synthetic-secret-48-chars-xxxxxxxxxxxxxxxxxxxx')`);
ok.ok((await one(db, `select public.kwtsms_status_sweep_job() r`)).r !== null, 'بسرّ ← نداء واحد');
const c = await one(db, `select url, body, headers from net.calls order by id desc limit 1`);
ok.ok(c.url.endsWith('/kwtsms-cron') && c.body.action === 'status_sweep' && c.headers['x-webhook-secret'], 'النداء صحيح بالسرّ', JSON.stringify(c.body));
ok.ok((await one(db, `select schedule from cron.job where jobname = 'kwtsms-status-sweep'`)).schedule === '* * * * *', 'المهمة كل دقيقة');
for (const r of ['anon', 'authenticated']) ok.ok(!(await one(db, `select has_function_privilege('${r}', 'public.kwtsms_pending_status_checks(integer)', 'execute') x`)).x, `القائمة ممنوعة على ${r}`);
ok.ok(await (async () => (await one(db, `select has_function_privilege('service_role', 'public.kwtsms_pending_status_checks(integer)', 'execute') x`)).x)(), 'القائمة للخدمة');
ok.ok(!(await one(db, `select has_function_privilege('service_role', 'public.kwtsms_status_sweep_job()', 'execute') x`)).x, 'المهمة لا تُستدعى من الخدمة ولا التطبيقات');
await db.exec(RB);
ok.ok((await one(db, `select count(*)::int n from cron.job where jobname = 'kwtsms-status-sweep'`)).n === 0, 'التراجع يلغي المهمة');
await db.exec(M);
ok.ok((await one(db, `select count(*)::int n from cron.job where jobname = 'kwtsms-status-sweep'`)).n === 1, 'إعادة التطبيق تعمل');
ok.done();
