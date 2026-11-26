// تجربة 20261126180000_photo_add_request («نبّهه يضيف صورة» + التذكير التلقائي) على قاعدة محلية معزولة (لا تلمس السيرفر).
// القاعدة = نفس قاعدة photo_change_request.test.mjs (base.sql + حارس الأقارب وprofile_has_login + حارس مرسل الإشعار
// + نظام الإشعارات v2 + فئات الدفع، ومُطلِق الدفع بديل يسجّل ما كان سيُرسَل) + الترحيل المطبَّق 20261111160000،
// ومشغّل no_photo_for_females الحي، وapp_config مبسّط، وpg_cron بديل (جدول cron.job).
// المراحل: قبل الترحيل (الحي اليوم) · بعده · بعد التراجع (ثم إعادة التطبيق).
// التشغيل: cd supabase/tests/family_links && node photo_add_request.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? '', (e.query ?? '').slice(0, 300)); process.exit(2); });

const REPO = fileURLToPath(new URL('../../', import.meta.url));
const read = p => readFileSync(`${REPO}/${p}`, 'utf8');
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody, rest] = base.split('-- ─── المشغّلات');
const baseTriggers = rest.slice(rest.indexOf('\n') + 1);
const grab = (src, name, end = '$function$;') => {
  const i = src.indexOf(`create or replace function public.${name}(`);
  if (i < 0) throw new Error(`missing ${name}`);
  return src.slice(i, src.indexOf(end, i) + end.length);
};
const preFns = ['adopt_tree_profile', 'merge_member_into_tree', 'women_auto_merge_wife']
  .map(n => grab(read('rollback/20261001150000_protect_family_links_rollback.sql'), n)).join('\n\n');
const descendantGuard = read('migrations/20261024120000_descendant_edit_guard.sql');
const senderGuard = grab(read('migrations/20261004220000_staff_status_and_notification_sender.sql'), 'guard_notification_sender');
const prefs = read('migrations/20260922250000_notification_prefs.sql');
const pushFns = grab(prefs, 'notification_category', '$$;') + '\n' + grab(prefs, 'notification_push_allowed', '$$;');
const notificationsV2 = read('migrations/20261031210000_notifications_v2.sql');
const applied = read('migrations/20261111160000_photo_change_request.sql');
const fix = read('migrations/20261126180000_photo_add_request.sql');
const undo = read('rollback/20261126180000_photo_add_request_rollback.sql');

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
// O مالك · O2 مالك ثانٍ بلا صورة · A مدير بلا صورة · MON مراقب بلا صورة · S مشرف · FA مدير موقوف · M عضو له صورة
// X/Y/Z أعضاء مسجّلون بلا صورة · F أنثى مسجّلة (لا صور للإناث) · FR موقوف بلا صورة · PN معلّق بلا صورة
// D متوفى بلا صورة له حساب · T بلا حساب ولا صورة · MV حسابه بمعرّف آخر (AV) بلا صورة · NONE غير موجود
const P = { O: id(1), A: id(2), MON: id(3), O2: id(4), S: id(5), FA: id(6), M: id(10), X: id(11), Y: id(12), Z: id(13),
            F: id(14), FR: id(15), PN: id(16), D: id(17), T: id(18), MV: id(19), AV: id(30), NONE: id(99) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

async function setup(stage) {
  const db = new PGlite();
  await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers);
  await db.exec(`
    alter table public.profiles add column if not exists is_photo_hidden boolean not null default false;
    alter table public.notifications add column if not exists request_id uuid,
      add column if not exists request_type text, add column if not exists details jsonb,
      add column if not exists subject_member_id uuid;`);
  await db.exec(descendantGuard);
  await db.exec(`${senderGuard}
    create trigger trg_a_guard_notification_sender before insert on public.notifications
      for each row execute function public.guard_notification_sender();`);
  await db.exec(notificationsV2);
  await db.exec(`${pushFns}
    create table public.push_calls (target uuid, kind text, title text, body text);
    create or replace function public.trigger_push_on_notification() returns trigger language plpgsql security definer
      set search_path to 'public' as $function$
    begin
      if not public.notification_push_allowed(new.target_member_id, coalesce(new.kind, ''), new.subject_member_id) then
        return new;
      end if;
      insert into public.push_calls values (new.target_member_id, new.kind, new.title, new.body);
      return new;
    end; $function$;
    create trigger trg_push_on_notification after insert on public.notifications
      for each row execute function public.trigger_push_on_notification();`);
  // الحي (٢٠٢٦-١١-٢٦): لا صور للإناث — يفرّغ أي صورة لأنثى
  await db.exec(`
    create or replace function public.trg_no_photo_for_females() returns trigger language plpgsql set search_path to 'public' as $f$
    begin
      if lower(coalesce(new.gender,'')) = 'female' then new.avatar_url := null; new.photo_url := null; end if;
      return new;
    end $f$;
    create trigger no_photo_for_females before insert or update on public.profiles
      for each row execute function public.trg_no_photo_for_females();`);
  // app_config (الأعمدة التي يكتبها الترحيل) وpg_cron بديل
  await db.exec(`
    create table public.app_config (key text primary key, value jsonb not null, default_value jsonb not null, kind text not null,
      min_value numeric, max_value numeric, category text not null, label_ar text not null, help_ar text,
      is_public boolean not null default false, sort integer not null default 0,
      check (kind <> 'int' or ((value #>> '{}')::numeric between coalesce(min_value, -1e9) and coalesce(max_value, 1e9))));
    insert into public.app_config (key, value, default_value, kind, min_value, max_value, category, label_ar, sort)
      values ('photo_reminder_days', '30', '30', 'int', 0, 365, 'tree', 'تذكير من بلا صورة', 64);
    create schema cron;
    create table cron.job (jobid serial primary key, jobname text unique, schedule text, command text);
    create function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as $f$
      insert into cron.job (jobname, schedule, command) values (p_name, p_schedule, p_command)
      on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command returning jobid $f$;
    create function cron.unschedule(p_name text) returns boolean language sql as $f$
      with d as (delete from cron.job where jobname = p_name returning 1) select exists (select 1 from d) $f$;`);
  await db.exec(applied);
  if (stage !== 'before') await db.exec(fix);
  await db.exec(`
    grant usage on schema auth to authenticated;
    grant select, update on public.profiles to authenticated;
    insert into profiles(id, first_name, full_name, gender, role, status, avatar_url, is_deceased) values
      ('${P.O}', 'مالك', 'المالك الأول', 'male', 'owner', 'active', 'https://x/avatars/o.jpg', false),
      ('${P.O2}', 'مالك٢', 'المالك الثاني', 'male', 'owner', 'active', null, false),
      ('${P.A}', 'مدير', 'المدير الأول', 'male', 'admin', 'active', null, false),
      ('${P.MON}', 'مراقب', 'المراقب الأول', 'male', 'monitor', 'active', null, false),
      ('${P.S}', 'مشرف', 'المشرف الأول', 'male', 'supervisor', 'active', 'https://x/avatars/s.jpg', false),
      ('${P.FA}', 'موقوف', 'مدير موقوف', 'male', 'admin', 'frozen', null, false),
      ('${P.M}', 'محمد', 'محمد علي المحمدعلي', 'male', 'member', 'active', 'https://x/avatars/m.jpg?v=1', false),
      ('${P.X}', 'خالد', 'خالد علي المحمدعلي', 'male', 'member', 'active', null, false),
      ('${P.Y}', 'يوسف', 'يوسف علي المحمدعلي', 'male', 'member', 'active', '  ', false),
      ('${P.Z}', 'زيد', 'زيد علي المحمدعلي', null, 'member', 'active', null, false),
      ('${P.F}', 'فاطمة', 'فاطمة علي المحمدعلي', 'female', 'member', 'active', null, false),
      ('${P.FR}', 'فارس', 'فارس علي المحمدعلي', 'male', 'member', 'frozen', null, false),
      ('${P.PN}', 'بدر', 'بدر علي المحمدعلي', 'male', 'pending', 'pending', null, false),
      ('${P.D}', 'راحل', 'راحل علي المحمدعلي', 'male', 'member', 'active', null, true),
      ('${P.T}', 'شجرة', 'بلا حساب المحمدعلي', 'male', 'member', 'active', null, false),
      ('${P.MV}', 'سالم', 'سالم علي المحمدعلي', 'male', 'member', 'active', null, false);
    insert into auth.users(id, raw_app_meta_data) values
      ('${P.O}', '{}'), ('${P.O2}', '{}'), ('${P.A}', '{}'), ('${P.MON}', '{}'), ('${P.S}', '{}'), ('${P.FA}', '{}'),
      ('${P.M}', '{}'), ('${P.X}', '{}'), ('${P.Y}', '{}'), ('${P.Z}', '{}'), ('${P.F}', '{}'), ('${P.FR}', '{}'),
      ('${P.PN}', '{}'), ('${P.D}', '{}'), ('${P.AV}', '{"profile_id": "${P.MV}"}');`);
  return db;
}

const claims = who => who === P.AV
  ? { sub: P.AV, role: 'authenticated', app_metadata: { profile_id: P.MV } }
  : { sub: who, role: 'authenticated' };
/** جلسة تطبيق (authenticated) — RLS والصلاحيات مفعّلة */
async function as(db, who, sql, params = []) {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [who ? JSON.stringify(claims(who)) : '']);
  await db.exec('set role authenticated');
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint, code: e.code }; }
  finally { await db.exec('reset role'); await db.query(`select set_config('request.jwt.claims', '', false)`); }
}
const q = async (db, sql, params = []) => (await db.query(sql, params)).rows;
const ask = (db, who, member, reason, hide = false) =>
  as(db, who, `select public.request_photo_change($1, $2, $3) as id`, [member, reason, hide]);
const askAll = (db, who) => as(db, who, `select public.request_photo_add_all() as n`);
const tick = async db => Number((await q(db, `select public.photo_requests_remind_tick() as n`))[0].n);
const openReq = async (db, member) => (await q(db, `select * from photo_change_requests where member_id = $1 and resolved_at is null`, [member]))[0];
const notesFor = async (db, member) => q(db, `select * from notifications where target_member_id = $1 and kind = 'photo_change_request' order by created_at, title`, [member]);
const pushesFor = async (db, member) => q(db, `select * from push_calls where target = $1 and kind = 'photo_change_request'`, [member]);
const allNotes = async db => q(db, `select target_member_id as t from notifications where kind = 'photo_change_request'`);
const ago = (db, reqId, interval) => db.exec(`update photo_change_requests set notified_at = now() - interval '${interval}' where id = '${reqId}'`);
const setCfg = (db, key, v) => db.exec(`update app_config set value = '${v}' where key = '${key}'`);

// ══════ قبل الترحيل (الحي اليوم) ══════
{
  console.log('\n══════ قبل الترحيل (الحي اليوم) ══════');
  const db = await setup('before');
  let r = await ask(db, P.A, P.X, '');
  check('«نبّهه» بسبب فارغ: الحي يرفض (bad_reason) — التطبيق يعرض «تحتاج تحديث السيرفر»', !r.ok && r.hint === 'bad_reason', r.err);
  r = await askAll(db, P.O);
  check('التنبيه الجماعي غير موجود (التطبيق يعرض «تحتاج تحديث السيرفر»)', !r.ok && /does not exist/.test(r.err), r.err);
  r = await as(db, P.X, `select notified_at from photo_change_requests`);
  check('العضو لا يقرأ notified_at اليوم (التطبيق يرجع للأعمدة القديمة)', !r.ok && /permission denied/.test(r.err), r.err);
}

// ══════ بعد الترحيل ══════
{
  console.log('\n══════ بعد الترحيل ══════');
  const db = await setup('after');

  // ── البنية ──
  const cfg = await q(db, `select key, value from app_config where key like 'photo_request_%' order by key`);
  check('مفتاحا الإعداد: كل 3 أيام · حتى 3 تذكيرات', cfg.length === 2 && cfg[0].key === 'photo_request_max_reminders'
    && cfg[0].value === 3 && cfg[1].key === 'photo_request_remind_days' && cfg[1].value === 3, JSON.stringify(cfg));
  const job = await q(db, `select schedule, command from cron.job where jobname = 'photo-requests-remind'`);
  check('مهمة pg_cron يومياً 15:00 UTC (= 18:00 الكويت)', job.length === 1 && job[0].schedule === '0 15 * * *'
    && job[0].command === 'select public.photo_requests_remind_tick()', JSON.stringify(job));
  let r = await as(db, P.O, `select public.photo_requests_remind_tick()`);
  check('التذكير داخلي: لا ينفّذه حتى المالك من التطبيق', !r.ok && /permission denied/.test(r.err), r.err);

  // ── «نبّهه» الفردي (بلا صورة) ──
  for (const [who, name] of [[P.S, 'المشرف'], [P.FA, 'المدير الموقوف'], [P.X, 'العضو'], [null, 'بلا دخول']]) {
    r = await ask(db, who, P.Y, '');
    check(`${name}: «نبّهه» مرفوض (not_allowed)`, !r.ok && r.hint === 'not_allowed', r.err);
  }
  r = await ask(db, P.A, P.F, '');
  check('أنثى بلا صورة: مرفوض (female_no_photo) — المشغّل يفرّغ صور الإناث', !r.ok && r.hint === 'female_no_photo', r.err);
  r = await ask(db, P.A, P.D, '');
  check('متوفى: مرفوض (deceased)', !r.ok && r.hint === 'deceased', r.err);
  r = await ask(db, P.A, P.T, '');
  check('بلا حساب: مرفوض (no_account)', !r.ok && r.hint === 'no_account', r.err);
  r = await ask(db, P.MON, P.O2, '');
  check('المراقب ينبّه مالكاً: مرفوض (owner_protected)', !r.ok && r.hint === 'owner_protected', r.err);
  r = await ask(db, P.A, P.A, '');
  check('لنفسه: مرفوض (own_profile)', !r.ok && r.hint === 'own_profile', r.err);
  r = await ask(db, P.A, P.X, 'س'.repeat(201));
  check('سبب أطول من ٢٠٠: مرفوض (bad_reason)', !r.ok && r.hint === 'bad_reason', r.err);

  r = await ask(db, P.MON, P.X, '', true);
  const xId = r.rows?.[0]?.id;
  let req = await openReq(db, P.X);
  check('المراقب ينبّه عضواً بلا صورة بسبب فارغ: طلب مفتوح بلا سبب ولا إخفاء', r.ok && req?.id === xId && req.reason === ''
    && req.hide_photo === false && req.hid_photo === false && req.reminders_sent === 0, r.err ?? JSON.stringify(req));
  let notes = await notesFor(db, P.X);
  check('إشعار «أضف صورتك الشخصية» واحد بنصّه', notes.length === 1 && notes[0].title === 'أضف صورتك الشخصية'
    && notes[0].body === 'تطلب منك الإدارة إضافة صورة شخصية لملفك.', `${notes[0]?.title} | ${notes[0]?.body}`);
  check('… النوع نفسه (الضغط يفتح المربّع)، photo_add في التفاصيل، المرسل «الإدارة»', notes[0]?.kind === 'photo_change_request'
    && notes[0]?.details?.photo_add === true && notes[0]?.details?.photo_change_request_id === xId
    && notes[0]?.details?.sender?.type === 'admin' && !notes[0]?.details?.sender?.name, JSON.stringify(notes[0]?.details));
  check('… ومُطلِق الدفع يرسله', (await pushesFor(db, P.X)).length === 1);
  check('… والصورة لا تُخفى (لا صورة)', (await q(db, `select is_photo_hidden from profiles where id = $1`, [P.X]))[0].is_photo_hidden === false);

  r = await ask(db, P.A, P.Y, '   ');
  check('صورة من مسافات = بلا صورة: «نبّهه» يعمل', r.ok && (await notesFor(db, P.Y))[0]?.title === 'أضف صورتك الشخصية', r.err ?? '');
  r = await ask(db, P.O, P.O2, '');
  check('المالك ينبّه المالك الثاني: مسموح', r.ok, r.err ?? '');

  // ── التكرار وعدّ التذكير ──
  r = await ask(db, P.A, P.X, '');
  req = await openReq(db, P.X);
  check('«ذكّره الحين» خلال دقيقة: نفس الطلب، بلا إشعار، والعدّاد لا يتحرك', r.ok && r.rows[0].id === xId
    && (await notesFor(db, P.X)).length === 1 && req.reminders_sent === 0, r.err ?? JSON.stringify(req));
  await ago(db, xId, '2 minutes');
  r = await ask(db, P.A, P.X, '');
  req = await openReq(db, P.X);
  notes = await notesFor(db, P.X);
  check('بعد دقيقة: إشعار جديد بنص «أضف» ويُعدّ تذكيراً (reminders_sent = 1)', r.ok && notes.length === 2
    && notes[1].title === 'أضف صورتك الشخصية' && req.reminders_sent === 1, JSON.stringify(req));

  // ── له صورة: كما كان حرفياً ──
  r = await ask(db, P.A, P.M, '');
  check('عضو له صورة بسبب فارغ: مرفوض (bad_reason) كما كان', !r.ok && r.hint === 'bad_reason', r.err);
  r = await ask(db, P.A, P.M, 'الصورة غير واضحة');
  const mId = r.rows?.[0]?.id;
  notes = await notesFor(db, P.M);
  check('عضو له صورة: «طلب تغيير الصورة الشخصية» بالسبب (بلا تغيير)', r.ok && notes.length === 1
    && notes[0].title === 'طلب تغيير الصورة الشخصية' && notes[0].body === 'يرجى تغيير صورتك الشخصية — السبب: الصورة غير واضحة.'
    && notes[0].details?.photo_add === false, `${notes[0]?.title} | ${notes[0]?.body}`);

  // ── القراءة ──
  r = await as(db, P.X, `select id, reason, notified_at, reminders_sent from photo_change_requests where resolved_at is null`);
  check('العضو يقرأ notified_at وreminders_sent لطلبه (مربّعه مرة لكل إشعار)', r.ok && r.rows.length === 1
    && r.rows[0].id === xId && r.rows[0].reminders_sent === 1 && !!r.rows[0].notified_at, r.err ?? JSON.stringify(r.rows));
  r = await as(db, P.X, `select requested_by from photo_change_requests`);
  check('… ولا يقرأ من طلب (يبقى «الإدارة»)', !r.ok && /permission denied/.test(r.err), r.err ?? '');
  r = await as(db, P.MON, `select member_id, notified_at, reminders_sent from photo_change_requests where resolved_at is null`);
  check('المراقب يقرأ كل المفتوح بأعمدته الجديدة (قائمة «مسجّلون بلا صورة»)', r.ok && r.rows.length === 4, r.err ?? `${r.rows?.length}`);
  r = await as(db, P.S, `select id from photo_change_requests`);
  check('المشرف لا يرى شيئاً', r.ok && r.rows.length === 0, r.err ?? '');
  r = await as(db, P.X, `update photo_change_requests set reminders_sent = 0`);
  check('لا كتابة مباشرة على العدّاد', !r.ok, r.err ?? '');

  // ── «نبّههم كلهم» ──
  for (const [who, name] of [[P.MON, 'المراقب'], [P.S, 'المشرف'], [P.FA, 'المدير الموقوف'], [P.X, 'العضو'], [null, 'بلا دخول']]) {
    r = await askAll(db, who);
    check(`${name}: «نبّههم كلهم» مرفوض (not_allowed)`, !r.ok && r.hint === 'not_allowed', r.err);
  }
  const before = (await allNotes(db)).length;
  r = await askAll(db, P.A);
  let sent = (await allNotes(db)).slice(before).map(n => n.t);
  // المؤهَّل للمدير: Z (جنس غير محدّد) · MON (مراقب بلا صورة) · MV (حساب بمعرّف آخر). يُستثنى: A (المتصل) · O/O2 (مالك)
  // · X/Y (نُبّها خلال ٧ أيام) · M/S (لهما صورة) · F (أنثى) · FR (موقوف) · PN (معلّق) · D (متوفى) · T (بلا حساب) · FA (موقوف)
  const want = [P.MON, P.Z, P.MV].sort();
  check('المدير: يرجع العدد = ٣ والإشعار وصل الثلاثة وحدهم', r.ok && Number(r.rows[0].n) === 3
    && JSON.stringify([...sent].sort()) === JSON.stringify(want), r.err ?? `${r.rows?.[0]?.n} ${JSON.stringify(sent)}`);
  req = await openReq(db, P.Z);
  notes = await notesFor(db, P.Z);
  check('… طلب «أضف» جديد لكل واحد، إشعار واحد بنصّه وbulk في التفاصيل', req && req.reason === '' && req.reminders_sent === 0
    && notes.length === 1 && notes[0].title === 'أضف صورتك الشخصية' && notes[0].details?.bulk === true, JSON.stringify(req));
  r = await askAll(db, P.A);
  check('التكرار فوراً: 0 (كلهم نُبّهوا خلال ٧ أيام)', r.ok && Number(r.rows[0].n) === 0, r.err ?? `${r.rows?.[0]?.n}`);
  const zId = req.id;
  await ago(db, zId, '8 days');
  r = await askAll(db, P.A);
  req = await openReq(db, P.Z);
  check('طلب أُشعر قبل ٨ أيام: يُعاد تنبيهه (نفس الطلب) ويُعدّ تذكيراً', r.ok && Number(r.rows[0].n) === 1 && req.id === zId
    && req.reminders_sent === 1 && (await notesFor(db, P.Z)).length === 2, r.err ?? JSON.stringify(req));
  const b2 = (await allNotes(db)).length;
  r = await askAll(db, P.O);
  sent = (await allNotes(db)).slice(b2).map(n => n.t);
  check('المالك: يشمل المدير (بلا صورة) والمالك الثاني نُبّه للتو فيُستثنى — ١', r.ok && Number(r.rows[0].n) === 1
    && sent.length === 1 && sent[0] === P.A, r.err ?? JSON.stringify(sent));

  // ── التذكير التلقائي ──
  let n = await tick(db);
  check('التذكير الآن: لا شيء (كلهم أُشعروا اليوم)', n === 0, `${n}`);
  await ago(db, xId, '3 days');
  const xBefore = await openReq(db, P.X);
  n = await tick(db);
  req = await openReq(db, P.X);
  notes = await notesFor(db, P.X);
  check('بعد ٣ أيام تقويمية: تذكير واحد لخالد', n === 1 && notes.length === 3, `${n} ${notes.length}`);
  check('… «تذكير: أضف صورتك الشخصية» / «ما زالت الإدارة بانتظار صورتك الشخصية.»', notes[2]?.title === 'تذكير: أضف صورتك الشخصية'
    && notes[2]?.body === 'ما زالت الإدارة بانتظار صورتك الشخصية.', `${notes[2]?.title} | ${notes[2]?.body}`);
  check('… النوع نفسه، رقم التذكير، المرسل «الإدارة» بلا اسم، والدفع', notes[2]?.kind === 'photo_change_request'
    && notes[2]?.details?.reminder === 2 && notes[2]?.created_by === null && notes[2]?.details?.sender?.type === 'admin'
    && (await pushesFor(db, P.X)).length === 3, JSON.stringify(notes[2]?.details));
  check('… notified_at = الآن وreminders_sent + 1', req.reminders_sent === xBefore.reminders_sent + 1
    && new Date(req.notified_at) > new Date(xBefore.notified_at), JSON.stringify(req));
  n = await tick(db);
  check('تشغيل ثانٍ في اليوم نفسه: لا شيء', n === 0, `${n}`);

  await ago(db, mId, '4 days');
  n = await tick(db);
  notes = await notesFor(db, P.M);
  check('طلب تغيير (له صورة): «تذكير: غيّر صورتك الشخصية» بالسبب', n === 1 && notes.at(-1)?.title === 'تذكير: غيّر صورتك الشخصية'
    && notes.at(-1)?.body === 'ما زالت الإدارة بانتظار صورتك الجديدة — السبب: الصورة غير واضحة.', `${n} ${notes.at(-1)?.body}`);

  await db.exec(`update photo_change_requests set reminders_sent = 3 where id = '${xId}'`);
  await ago(db, xId, '5 days');
  check('بلغ الحدّ (3 من 3): لا تذكير', await tick(db) === 0);
  await setCfg(db, 'photo_request_max_reminders', '5');
  check('المالك رفع الحدّ إلى 5: يُذكَّر', await tick(db) === 1);
  await ago(db, xId, '5 days');
  await setCfg(db, 'photo_request_remind_days', '0');
  check('«كل 0 يوم» = مطفأ', await tick(db) === 0);
  await setCfg(db, 'photo_request_remind_days', '7');
  check('كل ٧ أيام: بعد ٥ أيام لا تذكير', await tick(db) === 0);
  await setCfg(db, 'photo_request_remind_days', '3');
  await setCfg(db, 'photo_request_max_reminders', '0');
  check('«حتى 0 تذكيرات» = مطفأ', await tick(db) === 0);
  await setCfg(db, 'photo_request_max_reminders', '3');
  await db.exec(`delete from app_config where key in ('photo_request_remind_days', 'photo_request_max_reminders')`);
  await db.exec(`update photo_change_requests set reminders_sent = 0 where id = '${xId}'`);
  check('مفتاحان غائبان = الافتراضي (3 · 3)', await tick(db) === 1);

  // المجمّد/المتوفى/المعلّق يُتخطّون
  const yId = (await openReq(db, P.Y)).id;
  await ago(db, yId, '5 days');
  await db.exec(`update profiles set status = 'frozen' where id = '${P.Y}'`);
  check('عضو أُوقف حسابه: لا تذكير', await tick(db) === 0);
  await db.exec(`update profiles set status = 'active', is_deceased = true where id = '${P.Y}'`);
  check('عضو توفي: لا تذكير', await tick(db) === 0);
  await db.exec(`update profiles set is_deceased = false where id = '${P.Y}'; delete from auth.users where id = '${P.Y}'`);
  check('حذف حسابه (لا دخول): لا تذكير', await tick(db) === 0);
  await db.exec(`insert into auth.users(id, raw_app_meta_data) values ('${P.Y}', '{}')`);
  check('رجع حسابه: يُذكَّر', await tick(db) === 1);

  // العضو يضيف صورته ← الطلب يُغلق، ولا تذكير بعده
  r = await as(db, P.X, `update profiles set avatar_url = 'https://x/avatars/x.jpg?v=1' where id = $1`, [P.X]);
  check('العضو يضيف صورته → الطلب يُغلق (photo_changed)', r.ok && !(await openReq(db, P.X))
    && (await q(db, `select resolution from photo_change_requests where id = $1`, [xId]))[0].resolution === 'photo_changed', r.err ?? '');
  await db.exec(`update photo_change_requests set notified_at = now() - interval '9 days' where member_id = '${P.X}'`);
  check('… والطلب المغلق لا يُذكَّر', await tick(db) === 0);
  const b3 = (await allNotes(db)).length;
  r = await askAll(db, P.O);
  check('… ولا يدخل «نبّههم كلهم» (له صورة الآن) — والباقون نُبّهوا خلال ٧ أيام: 0', r.ok && Number(r.rows[0].n) === 0
    && (await allNotes(db)).length === b3, r.err ?? `${r.rows?.[0]?.n}`);

  // الإلغاء كما كان
  r = await as(db, P.MON, `select public.cancel_photo_change($1) as ok`, [P.Z]);
  check('«إلغاء التنبيه» (المراقب) يغلق طلب الإضافة', r.ok && r.rows[0].ok === true && !(await openReq(db, P.Z)), r.err ?? '');
  await db.exec(`update photo_change_requests set notified_at = now() - interval '9 days' where member_id = '${P.Z}'`);
  check('… ولا تذكير لطلب ملغى', await tick(db) === 0);

  // إعادة التطبيق لا تمسّ اختيار المالك
  await db.exec(`insert into app_config (key, value, default_value, kind, min_value, max_value, category, label_ar, sort)
    values ('photo_request_remind_days', '5', '3', 'int', 0, 30, 'tree', 'x', 65)`);
  await db.exec(fix);
  check('إعادة الترحيل: يبقى «كل 5 أيام» (on conflict do nothing) ومهمة واحدة',
    (await q(db, `select value from app_config where key = 'photo_request_remind_days'`))[0].value === 5
    && (await q(db, `select count(*)::int as n from cron.job where jobname = 'photo-requests-remind'`))[0].n === 1);
}

// ══════ بعد التراجع ══════
{
  console.log('\n══════ بعد التراجع ══════');
  const db = await setup('after');
  await ask(db, P.A, P.X, '');
  await ask(db, P.A, P.M, 'الصورة غير واضحة');
  await db.exec(undo);
  const t = (await q(db, `select to_regprocedure('public.request_photo_add_all()') as a,
    to_regprocedure('public.photo_requests_remind_tick()') as b,
    (select count(*)::int from cron.job where jobname = 'photo-requests-remind') as job,
    (select count(*)::int from information_schema.columns where table_name = 'photo_change_requests' and column_name = 'reminders_sent') as col,
    (select count(*)::int from app_config where key like 'photo_request_%') as cfg`))[0];
  check('الدالتان والمهمة والعمود والمفتاحان محذوفة', !t.a && !t.b && t.job === 0 && t.col === 0 && t.cfg === 0, JSON.stringify(t));
  const x = await openReq(db, P.X);
  check('طلب «أضف» المفتوح يبقى بسبب مقروء (القيد القديم ١–٢٠٠)', x?.reason === 'لا توجد صورة في ملفك', JSON.stringify(x));
  let r = await ask(db, P.A, P.Y, '');
  check('request_photo_change القديمة: السبب الفارغ مرفوض (bad_reason)', !r.ok && r.hint === 'bad_reason', r.err);
  r = await as(db, P.X, `select notified_at from photo_change_requests`);
  check('العضو لا يقرأ notified_at (كما كان)', !r.ok && /permission denied/.test(r.err), r.err);
  r = await as(db, P.X, `select id, reason from photo_change_requests where resolved_at is null`);
  check('… ويقرأ طلبه بالأعمدة القديمة (مربّع النسخ القديمة يعمل)', r.ok && r.rows.length === 1, r.err ?? '');
  r = await as(db, P.X, `update profiles set avatar_url = 'https://x/avatars/x.jpg' where id = $1`, [P.X]);
  check('إضافة الصورة تغلقه كما كان', r.ok && !(await openReq(db, P.X)), r.err ?? '');
  await db.exec(fix);
  r = await ask(db, P.A, P.Y, '');
  check('الترحيل يُعاد تطبيقه بعد التراجع ويعمل', r.ok, r.err ?? '');
}

console.log(`\n${pass} نجح · ${fail} فشل`);
process.exit(fail ? 1 : 0);
