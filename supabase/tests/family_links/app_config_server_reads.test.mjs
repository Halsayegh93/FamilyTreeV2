// تجربة 20261021120000_app_config_server_reads على قاعدة محلية معزولة — لا تلمس السيرفر.
// «قبل» = آخر تعريف لكل دالة من ملفات الترحيل (announce_death 20261007130000، approvals_sla_tick/approvals_report
// 20261016120000، sms_login_attempts 20261020170000، log_login_attempt 20261020190000، reserve_kwtsms_send 20261020170000).
// ١) النص: كل دالة جديدة = القديمة مع استبدال الثابت فقط (عكس الاستبدال يعطي القديمة حرفياً)، والصلاحيات كما هي.
// ٢) السلوك عند الافتراضي = القديم حرفياً على نفس البيانات (كل تشغيل داخل begin … rollback).
// ٣) تغيير المفتاح يغيّر السلوك (المدة، القالب، المهلة، «مريب»، نص الرسالة)، وغياب المفتاح ← الثابت القديم.
// ٤) الصلاحيات بعد الترحيل: anon/العضو/المجمّد/المدير/المالك كما كانت.
// ٥) التراجع يعيد الدوال الست حرفياً (md5 والصلاحيات)، ثم إعادة التطبيق تعمل.
// التشغيل: cd supabase/tests/family_links && node app_config_server_reads.test.mjs
import { makeDb, as, tx as txOn, mig, rb, read, P, id, counter, one, val, md5fn, acl, canExec } from './app_config_env.mjs';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? ''); process.exit(2); });
const t = counter(); const ok = t.ok;
const db = await makeDb();

// ── البيئة: KWT (كما على الحي) + الأخبار والوفيات + مسار الموافقات (دوال مساعدة مبسّطة لا تتغيّر هنا) ──
await db.exec(`
  alter table public.app_settings drop column sms_wait_seconds;   -- يضيفه 20261020170000 نفسه
  alter table auth.users add column last_sign_in_at timestamptz;
  alter table public.notifications add column details jsonb, add column subject_member_id uuid;
  create schema net;
  create table net.calls (id bigserial primary key, url text, body jsonb);
  create function net.http_post(url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
    headers jsonb default '{}'::jsonb, timeout_milliseconds integer default 5000) returns bigint language plpgsql as $f$
  declare v bigint; begin insert into net.calls (url, body) values (url, body) returning id into v; return v; end $f$;
  create schema cron;
  create table cron.job (jobid bigserial primary key, schedule text, command text, jobname text unique);
  create function cron.schedule(job_name text, schedule text, command text) returns bigint language plpgsql as $c$
  declare j bigint; begin insert into cron.job (jobname, schedule, command) values (job_name, schedule, command)
    on conflict (jobname) do update set schedule = excluded.schedule returning jobid into j; return j; end $c$;
  create table private.app_secrets (key text primary key, value text);
  create table public.news (id uuid primary key default gen_random_uuid(), author_id uuid, posted_by uuid, author_name text,
    author_role text, role_color text, content text, type text, image_urls jsonb, poll_options jsonb,
    approval_status text default 'pending', approved_by uuid, approved_at timestamptz);
  -- مسار الموافقات: الأعمدة التي تقرؤها الدالتان + دوال مساعدة مبسّطة (لم تتغيّر في هذا الترحيل)
  alter table public.admin_requests add column created_at timestamptz default now(), add column stage text,
    add column stage_since timestamptz, add column reminded_at timestamptz, add column escalated_at timestamptz,
    add column priority text default 'normal', add column assigned_to uuid, add column assigned_at timestamptz,
    add column fast_track boolean default false;
  create table public.admin_request_steps (id bigserial primary key, request_id uuid, actor_id uuid, actor_role text,
    action text, note text, subject_id uuid, created_at timestamptz default now());
  create table public.test_notes (id bigserial primary key, targets uuid[], title text, body text, kind text);
  create function public.approvals_workflow_on() returns boolean language sql as $f$ select true $f$;
  create function public.workflow_specialist_role(p text) returns text language sql as $f$ select 'monitor'::text $f$;
  create function public.admin_request_label(p text) returns text language sql as $f$ select 'طلب'::text $f$;
  create function public.workflow_specialist_ids(p text) returns setof uuid language sql as $f$ select '${P.MON}'::uuid $f$;
  create function public.approvals_manager_ids() returns setof uuid language sql as $f$ select '${P.A}'::uuid $f$;
  create function public.approvals_notify(p_targets uuid[], p_title text, p_body text, p_actor uuid, p_request uuid,
    p_type text, p_stage text, p_kind text) returns void language sql as $f$
    insert into public.test_notes (targets, title, body, kind) values (p_targets, p_title, p_body, p_kind) $f$;
  alter table public.app_settings add column approvals_sla_hours integer not null default 24,
    add column approvals_escalate_hours integer not null default 48, add column approvals_urgent_sla_hours integer not null default 6,
    add column approvals_urgent_escalate_hours integer not null default 12;
  insert into auth.users (id, phone) values ('${P.M}', '96590000005');`);
for (const f of ['20261019200000_kwtsms_delivery_guard', '20261019210000_kwtsms_low_balance_alert', '20261019220000_kwtsms_cooldown_one_minute',
  '20261019230000_kwtsms_urgent_alert_12h', '20261020150000_kwtsms_daily_stats', '20261020151000_kwtsms_admin_overview',
  '20261020160000_login_attempts', '20261020170000_kwtsms_editable_limits', '20261020180000_kwtsms_wait_min_30',
  '20261020190000_kwtsms_daily_check_and_suspicious', '20261021080000_owner_login_code',
  '20260927233000_death_announcements', '20261007130000_announce_death_admin_recent']) await db.exec(read(`migrations/${f}.sql`));
// approvals_sla_tick وapprovals_report: آخر تعريف (20261016120000) + صلاحياتهما من الملف نفسه
const v2 = read('migrations/20261016120000_approvals_v2.sql');
const grab = (src, start) => { const i = src.indexOf(start); return src.slice(i, src.indexOf('$function$;', i) + 11); };
await db.exec(grab(v2, 'create or replace function public.approvals_sla_tick()'));
await db.exec(grab(v2, 'create or replace function public.approvals_report('));
await db.exec(`revoke all on function public.approvals_report(timestamptz, timestamptz) from public, anon;
  grant execute on function public.approvals_report(timestamptz, timestamptz) to authenticated;
  revoke all on function public.approvals_sla_tick() from public, anon, authenticated;`);
await db.exec(mig('config'));   // 20261021110000 مطبّق قبله

const FNS = ['public.announce_death(uuid,text,text,boolean)', 'public.approvals_sla_tick()', 'public.approvals_report(timestamp with time zone,timestamp with time zone)',
  'public.sms_login_attempts(integer)', 'public.log_login_attempt(text,text)', 'public.reserve_kwtsms_send(text,text,boolean,integer)'];
const BEFORE = {}; for (const f of FNS) BEFORE[f] = { m: await md5fn(db, f), a: await acl(db, f), src: await val(db, `select prosrc from pg_proc where oid = '${f}'::regprocedure`) };

// ── تشغيل داخل معاملة تُلغى: نفس البيانات لكل مقارنة ──
const tx = fn => txOn(db, fn);
const today = (await val(db, `select ((now() at time zone 'Asia/Kuwait')::date)::text`));
const day = n => (n === 0 ? today : (val(db, `select ((now() at time zone 'Asia/Kuwait')::date - ${n})::text`)));
const D = { male5: id(41), fem10: id(42), male31: id(43), male32: id(44), nodate10: id(45), nodate40: id(46), male40: id(47), live: id(48) };
await db.exec(`insert into public.profiles (id, first_name, full_name, role, status, gender, is_deceased, death_date) values
  ('${D.male5}', 'زيد', 'زيد المحمدعلي', 'member', 'active', 'male', true, '${await day(5)}'),
  ('${D.male31}', 'عمر', 'عمر المحمدعلي', 'member', 'active', 'male', true, '${await day(31)}'),
  ('${D.male32}', 'سالم', 'سالم المحمدعلي', 'member', 'active', 'male', true, '${await day(32)}'),
  ('${D.male40}', 'ماجد', 'ماجد المحمدعلي', 'member', 'active', 'male', true, '${await day(40)}'),
  ('${D.nodate10}', 'فهد', 'فهد المحمدعلي', 'member', 'active', 'male', true, null),
  ('${D.nodate40}', 'نايف', 'نايف المحمدعلي', 'member', 'active', 'male', true, null),
  ('${D.live}', 'حي', 'حي المحمدعلي', 'member', 'active', 'male', false, null);
  insert into public.women_members (id, first_name, full_name, gender, is_deceased, death_date) values
  ('${D.fem10}', 'مريم', 'مريم المحمدعلي', 'female', true, '${await day(10)}');
  insert into public.death_marks (member_id, marked_at) values ('${D.nodate10}', now() - interval '10 days'), ('${D.nodate40}', now() - interval '40 days');`);
const announce = async (who, member, content = null) => {
  const x = await as(db, who, `select public.announce_death($1, $2, 'مقبرة الصليبيخات', true) n`, [member, content]);
  if (!x.ok) return { err: x.hint || x.code };
  const news = await one(db, `select content, author_name, type, approval_status from public.news where id = $1`, [x.rows[0].n]);
  const note = await one(db, `select title, body, kind from public.notifications where details->>'news_id' = $1`, [x.rows[0].n]);
  return { news, note };
};
const deathRun = async () => {
  const out = {};
  for (const [k, m] of Object.entries(D)) out[k] = await tx(() => announce('A', m));
  out.custom = await tx(() => announce('O', D.male5, 'نص مخصص'));
  for (const k of ['M', 'MON', 'FA', 'S']) out['role_' + k] = await tx(() => announce(k, D.male5));
  return JSON.stringify(out);
};

// المهلة: طلبات في «طلب معلومات» عمرها ٢٠ و٣٠ و٤٧ و٤٩ و٨٠ ساعة، وطلب مراجعة ٣٠ ساعة
const R = [id(61), id(62), id(63), id(64), id(65), id(66)];
await db.exec(`insert into public.admin_requests (id, member_id, requester_id, request_type, status, stage, stage_since, created_at) values
  ('${R[0]}', '${P.M}', '${P.M}', 'tree_edit', 'pending', 'info', now() - interval '20 hours', now() - interval '3 days'),
  ('${R[1]}', '${P.M}', '${P.M}', 'tree_edit', 'pending', 'info', now() - interval '30 hours', now() - interval '3 days'),
  ('${R[2]}', '${P.M}', '${P.M}', 'tree_edit', 'pending', 'info', now() - interval '47 hours', now() - interval '3 days'),
  ('${R[3]}', '${P.M2}', '${P.M2}', 'tree_edit', 'pending', 'info', now() - interval '49 hours', now() - interval '3 days'),
  ('${R[4]}', '${P.M2}', '${P.M2}', 'tree_edit', 'pending', 'info', now() - interval '80 hours', now() - interval '4 days'),
  ('${R[5]}', '${P.M2}', '${P.M2}', 'tree_edit', 'pending', 'review', now() - interval '30 hours', now() - interval '2 days');`);
const slaRun = async () => tx(async () => {
  const res = await val(db, `select public.approvals_sla_tick()`);
  const rem = (await db.query(`select id from public.admin_requests where reminded_at is not null order by id`)).rows.map(x => x.id);
  const notes = (await db.query(`select title, kind from public.test_notes order by id`)).rows;
  return JSON.stringify({ res, rem, notes });
});
const report = async (who = 'O') => { const x = await as(db, who, `select public.approvals_report(now() - interval '30 days', now() + interval '1 hour') j`);
  return x.ok ? x.rows[0].j : { err: x.code }; };
const overdue = async () => (await report()).totals.overdue_now;

// «مريب»: رقم بـ ٦ محاولات في ساعة، ورقم بـ ٤، ورقم بـ ٢
const PH = ['96550001111', '96550002222', '96550003333'];
await db.exec(`insert into public.login_attempts (phone, outcome, created_at)
  select '${PH[0]}', 'sent', date_trunc('hour', now()) - interval '2 hours' + (i || ' minutes')::interval from generate_series(1, 6) i
  union all select '${PH[1]}', 'blocked', date_trunc('hour', now()) - interval '2 hours' + (i || ' minutes')::interval from generate_series(1, 4) i
  union all select '${PH[2]}', 'failed', date_trunc('hour', now()) - interval '5 hours' + (i || ' minutes')::interval from generate_series(1, 2) i`);
const attempts = async (who = 'O') => { const x = await as(db, who, `select public.sms_login_attempts(7) j`); if (!x.ok) return { err: x.code };
  const o = x.rows[0].j; delete o.generated_at; return o; };
const suspicious = async () => { const o = await attempts(); return { total: o.totals.suspicious, items: o.items.filter(i => i.suspicious).map(i => i.phone).sort() }; };
// تنبيه التسجيل: كم محاولة حتى يصل التنبيه لرقم جديد
const alertAt = async phone => tx(async () => {
  for (let i = 1; i <= 8; i++) {
    const x = await as(db, 'service', `select public.log_login_attempt($1, 'sent')`, [phone]);
    if (!x.ok) return 'err:' + x.err;
    if (await val(db, `select count(*)::int from public.notifications where kind = 'sms_suspicious'`) > 0) return i;
  }
  return null;
});

// الحجز: نفس السلسلة لكل صيغة (رقمان، إعادة نفس الحدث، الانتظار)
const h = c => c.repeat(64).slice(0, 64);
const reserve = async (ev, ph, fmt) => { const x = await as(db, 'service', fmt === undefined
  ? `select public.reserve_kwtsms_send($1, $2, false) r` : `select public.reserve_kwtsms_send($1, $2, false, $3) r`,
  fmt === undefined ? [h(ev), h(ph)] : [h(ev), h(ph), fmt]); return x.ok ? x.rows[0].r : 'ERR ' + x.err; };
const reserveRun = async fmt => tx(async () => [await reserve('a', '1', fmt), await reserve('a', '1', fmt), await reserve('b', '1', fmt),
  await reserve('c', '2', fmt), await db.query(`update public.app_settings set sms_sender = 'MYAPP'`).then(() => reserve('d', '3', fmt))]
  .map(x => x.replace(/^blocked:\d+$/, 'blocked:N')));

// ── «قبل» ──
const DEATH_BEFORE = await deathRun();
const SLA_BEFORE = await slaRun();
const OVERDUE_BEFORE = await overdue();
const REPORT_BEFORE = JSON.stringify((await report()).totals);
const ATT_BEFORE = JSON.stringify({ o: await attempts('O'), a: await attempts('A') });
const ALERT_BEFORE = await alertAt('96551234567');
const RES_BEFORE = { 1: await reserveRun(undefined), 2: await reserveRun(2) };
ok(JSON.parse(DEATH_BEFORE).male5.news.content.startsWith('انتقل إلى رحمة الله تعالى زيد المحمدعلي'), 'قبل: إعلان الوفاة يعمل في البيئة');
ok(JSON.parse(SLA_BEFORE).rem.length === 3 && OVERDUE_BEFORE === 3, 'قبل: تذكير «طلب معلومات» بعد ٤٨ ساعة (٤٩ و٨٠) + المراجعة ٣٠', SLA_BEFORE);
ok(ALERT_BEFORE === 5, 'قبل: التنبيه عند المحاولة الخامسة', ALERT_BEFORE);
ok(JSON.stringify(RES_BEFORE[2]) === JSON.stringify(['send', 'blocked', 'blocked:N', 'send', 'send:MYAPP']), 'قبل: ردود الحجز بالصيغة ٢ (حدث مكرر، انتظار، رقم آخر، مرسل محفوظ)', JSON.stringify(RES_BEFORE[2]));

// ══════════ الترحيل ══════════
await db.exec(mig('reads'));
// ١) النص: عكس الاستبدال = القديم حرفياً
const src = async f => val(db, `select prosrc from pg_proc where oid = '${f}'::regprocedure`);
const undo = (s, pairs) => pairs.reduce((x, [a, b]) => x.split(a).join(b), s);
ok(undo(await src(FNS[1]), [["public.config_int('approvals_info_hours', 48)", '48']]) === BEFORE[FNS[1]].src, 'approvals_sla_tick: الفرق الوحيد هو الثابت ٤٨');
ok(undo(await src(FNS[2]), [["public.config_int('approvals_info_hours', 48)", '48']]) === BEFORE[FNS[2]].src, 'approvals_report: الفرق الوحيد هو الثابت ٤٨');
ok(undo(await src(FNS[3]), [["public.config_int('sms_suspicious_per_hour', 5)", '5']]) === BEFORE[FNS[3]].src, 'sms_login_attempts: الفرق الوحيد هو الثابت ٥ (مرتين)');
ok(undo(await src(FNS[4]), [["public.config_int('sms_suspicious_per_hour', 5)", '5']]) === BEFORE[FNS[4]].src, 'log_login_attempt: الفرق الوحيد هو الثابت ٥');
const adSrc = await src(FNS[0]);
ok(undo(adSrc, [["(public.config_int('death_announce_window_days', 30) + 1)", '31'],
  ["make_interval(days => public.config_int('death_announce_window_days', 30))", "interval '30 days'"]]).replace(/  v_content := coalesce[\s\S]*?v_name\)\);/, '')
  === BEFORE[FNS[0]].src.replace(/  v_content := coalesce[\s\S]*?راجعون'\);/, ''), 'announce_death: خارج المدة والقالب لا شيء تغيّر');
for (const f of FNS) ok(await acl(db, f) === BEFORE[f].a, `${f.split('(')[0]}: الصلاحيات كما هي`);

// ٢) السلوك عند الافتراضي = القديم
ok(await deathRun() === DEATH_BEFORE, 'announce_death عند الافتراضي = القديم (النص، الإشعار، الحداثة، الأدوار)');
ok(await slaRun() === SLA_BEFORE, 'approvals_sla_tick عند الافتراضي = القديم');
ok(JSON.stringify((await report()).totals) === REPORT_BEFORE, 'approvals_report عند الافتراضي = القديم');
ok(JSON.stringify({ o: await attempts('O'), a: await attempts('A') }) === ATT_BEFORE, 'sms_login_attempts عند الافتراضي = القديم (المالك والمدير)');
ok(await alertAt('96551234567') === ALERT_BEFORE, 'log_login_attempt عند الافتراضي = القديم (الخامسة)');
ok(JSON.stringify(await reserveRun(undefined)) === JSON.stringify(RES_BEFORE[1]), 'reserve_kwtsms_send صيغة ١ = القديم حرفياً');
ok(JSON.stringify(await reserveRun(2)) === JSON.stringify(RES_BEFORE[2]), 'reserve_kwtsms_send صيغة ٢ = القديم حرفياً');

// ٣) المفاتيح تغيّر السلوك
const setc = async (k, v) => db.query(`update public.app_config set value = $2::jsonb where key = $1`, [k, JSON.stringify(v)]);
const reset = async () => db.exec(`update public.app_config set value = default_value where value <> default_value`);
await setc('death_announce_window_days', 7);
let d = JSON.parse(await deathRun());
ok(d.male5.news && d.fem10.err === 'death_not_recent' && d.nodate10.err === 'death_not_recent', 'المدة ٧ أيام: وفاة ٥ أيام تُعلن، و١٠ أيام (بتاريخ أو بلا تاريخ) تُرفض');
await setc('death_announce_window_days', 60);
d = JSON.parse(await deathRun());
ok(d.male40.news && d.nodate40.news && d.male32.news, 'المدة ٦٠ يوماً: وفاة ٤٠ يوماً تُعلن');
await reset();
d = JSON.parse(await deathRun());
ok(d.male31.news && d.male32.err === 'death_not_recent' && d.nodate40.err === 'death_not_recent', 'الافتراضي ٣٠ (+ هامش يوم): ٣١ تُعلن و٣٢ لا');
await setc('death_announce_template_male', 'رحم الله {name}\nالفاتحة');
await setc('death_announce_template_female', 'رحم الله الفقيدة {name}');
d = JSON.parse(await deathRun());
ok(d.male5.news.content === 'رحم الله زيد المحمدعلي\nالفاتحة\n\nالدفن: مقبرة الصليبيخات', 'القالب الجديد للرجل + سطر الدفن', d.male5.news.content);
ok(d.fem10.news.content.startsWith('رحم الله الفقيدة مريم المحمدعلي'), 'القالب الجديد للمرأة (شجرة النساء)');
ok(d.custom.news.content.startsWith('نص مخصص'), 'النص المكتوب في المربّع يتقدّم على القالب');
ok(d.male5.note.title === 'انتقل إلى رحمة الله تعالى' && d.fem10.note.title === 'انتقلت إلى رحمة الله تعالى', 'عنوان الإشعار كما هو');
await reset();

await setc('approvals_info_hours', 24);
let s = JSON.parse(await slaRun());
ok(s.rem.length === 5 && s.rem.includes(R[1]) && s.rem.includes(R[2]) && !s.rem.includes(R[0]), 'المهلة ٢٤ ساعة: ٣٠ و٤٧ تُذكَّر أيضاً، و٢٠ لا');
ok(await overdue() === 5, 'والتقرير: ٥ متأخرة');
await setc('approvals_info_hours', 72);
s = JSON.parse(await slaRun());
ok(s.rem.length === 2 && s.rem.includes(R[4]) && !s.rem.includes(R[3]), 'المهلة ٧٢ ساعة: ٨٠ فقط (+ المراجعة)');
ok(await overdue() === 2, 'والتقرير: ٢ متأخرة');
await reset();

await setc('sms_suspicious_per_hour', 4);
let sp = await suspicious();
ok(sp.total === 2 && sp.items.length === 2, '«مريب» ٤: الرقمان (٦ و٤)', JSON.stringify(sp));
ok(await alertAt('96551234567') === 4, 'والتنبيه عند الرابعة');
await setc('sms_suspicious_per_hour', 7);
sp = await suspicious();
ok(sp.total === 0, '«مريب» ٧: لا أحد');
ok(await alertAt('96551234567') === 7, 'والتنبيه عند السابعة');
await reset();

// p_format ٣: رد JSON بالنص
let res3 = await reserveRun(3);
const j3 = JSON.parse(res3[0]);
ok(j3.action === 'send' && j3.sender === null && j3.template === 'عائلة المحمدعلي: رمز الدخول {code}. لا تشاركه مع أحد.'
  && j3.template_en.startsWith('Your Al-Mohammadali'), 'صيغة ٣: send بـ JSON فيه القالبان والمرسل null', res3[0]);
ok(res3[1] === 'blocked' && res3[2] === 'blocked:N' && JSON.parse(res3[4]).sender === 'MYAPP', 'صيغة ٣: المحجوب كما هو، والمرسل المحفوظ داخل JSON', JSON.stringify(res3));
await setc('sms_otp_template', 'عائلة المحمدعلي — رمزك {code}');
ok(JSON.parse((await reserveRun(3))[0]).template === 'عائلة المحمدعلي — رمزك {code}', 'صيغة ٣: النص الجديد من الإعدادات');
await reset();
await db.exec(`alter table public.app_config rename to app_config_x`);
res3 = await tx(async () => { const r1 = await reserve('e', '8', 3); const n = await val(db, `select count(*)::int from public.kwtsms_deliveries`); return [r1, n]; });
ok(JSON.parse(res3[0]).action === 'send' && JSON.parse(res3[0]).template === null && res3[1] === 1, 'تعذّرت قراءة النص ← send بلا نص والحجز محفوظ (لا تعطيل للدخول)', JSON.stringify(res3));
ok((await reserveRun(2))[0] === 'send', 'وصيغة ٢ لا تقرأ الإعدادات أصلاً');
await db.exec(`alter table public.app_config_x rename to app_config`);
// غياب المفتاح ← الثابت القديم
await db.exec(`delete from public.app_config where key in ('approvals_info_hours', 'sms_suspicious_per_hour', 'death_announce_window_days', 'death_announce_template_male')`);
ok(await deathRun() === DEATH_BEFORE && await slaRun() === SLA_BEFORE && JSON.stringify({ o: await attempts('O'), a: await attempts('A') }) === ATT_BEFORE,
  'مفاتيح محذوفة ← الثوابت القديمة (السلوك نفسه)');
await db.exec(`delete from public.app_config; drop trigger trg_app_config_guard on public.app_config;`);
await db.exec(mig('config').slice(mig('config').indexOf('-- ═══ ٦) البذور')));   // إعادة البذور فقط
await db.exec(`create trigger trg_app_config_guard before insert or update on public.app_config for each row execute function private.app_config_guard()`);

// ٤) الصلاحيات بعد الترحيل
for (const k of ['M', 'MON', 'S', 'FA', 'FM', 'PEND']) {
  const x = await as(db, k, `select public.announce_death('${D.male5}', null, null, false)`);
  ok(!x.ok && x.code === '42501', `announce_death مرفوضة على ${k}`, x.err);
}
for (const k of ['M', 'S', 'FA', 'PEND']) ok((await report(k)).err === '42501', `approvals_report مرفوضة على ${k}`);
for (const k of ['M', 'MON', 'FA']) ok((await attempts(k)).err === '42501', `sms_login_attempts مرفوضة على ${k}`);
for (const who of ['anon', 'authenticated']) {
  ok(!(await canExec(db, who, FNS[5])) && !(await canExec(db, who, FNS[4])) && !(await canExec(db, who, FNS[1])), `الحجز والتسجيل والمهلة: لا تنفيذ لـ ${who}`);
}
ok(await canExec(db, 'service_role', FNS[5]) && await canExec(db, 'service_role', FNS[4]), 'الحجز والتسجيل للخدمة');
let x = await as(db, 'anon', `select public.announce_death('${D.male5}', null, null, false)`);
ok(!x.ok, 'anon لا يعلن وفاة');

// ══════════ التراجع ══════════
await db.exec(rb('reads'));
for (const f of FNS) ok(await md5fn(db, f) === BEFORE[f].m && await acl(db, f) === BEFORE[f].a, `التراجع: ${f.split('(')[0]} كما كانت حرفياً`);
ok(await deathRun() === DEATH_BEFORE && await slaRun() === SLA_BEFORE, 'التراجع: السلوك القديم');
ok(JSON.stringify(await reserveRun(3)) === JSON.stringify(RES_BEFORE[2]), 'بعد التراجع: صيغة ٣ ترد مثل ٢ (الدالة الطرفية الجديدة تستعمل نصها المدمج)');
x = await db.exec(rb('reads')).then(() => ({ ok: true }), e => ({ ok: false, err: e.message }));
ok(x.ok, 'التراجع مرتين بلا خطأ', x.err);
// تراجع app_config بعده يمر (لا دالة تقرأ config_* بقيت)
x = await db.exec(rb('config')).then(() => ({ ok: true }), e => ({ ok: false, err: e.message }));
ok(x.ok, 'بعده تراجع app_config يمر', x.err);
await db.exec(mig('config'));
await db.exec(mig('reads'));
ok(await deathRun() === DEATH_BEFORE && JSON.parse((await reserveRun(3))[0]).action === 'send', 'إعادة التطبيق بعد التراجع تعمل');
x = await db.exec(rb('config')).then(() => ({ ok: true }), e => ({ ok: false, err: e.message }));
ok(!x.ok && /announce_death/.test(x.err), 'وتراجع app_config قبل هذا التراجع يُرفض (يحمي الدوال)', x.err);
t.done();
