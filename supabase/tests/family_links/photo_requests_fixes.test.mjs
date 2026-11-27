// تجربة 20261126200000_photo_requests_fixes (إصلاحات المراجعة F4) على قاعدة محلية معزولة (لا تلمس السيرفر).
// القاعدة = قاعدة photo_add_request.test.mjs (base.sql + الحرّاس + الإشعارات v2 + مُطلِق دفع بديل يسجّل ما كان سيُرسَل
// + no_photo_for_females + app_config + pg_cron بديل) + المطبَّق 20261111160000 و20261126180000 (الحي اليوم)
// + admin_requests بعمودي details/new_value كالحي + daughter_son_lineage.
// المراحل: قبل الترحيل (الحي اليوم — الأخطاء ظاهرة) · بعده · تنظيف المتوفين المفتوحين · بعد التراجع (ثم إعادة التطبيق).
// التشغيل: cd supabase/tests/family_links && node photo_requests_fixes.test.mjs
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
const p1 = read('migrations/20261126180000_photo_add_request.sql');
const fix = read('migrations/20261126200000_photo_requests_fixes.sql');
const undo = read('rollback/20261126200000_photo_requests_fixes_rollback.sql');
// بلاغ المالك ٢٠٢٦-١١-٢٧: أبناء البنات المسجّلون بلا صورة يُذكَّرون مثل غيرهم (private.photo_nudge_listed بلا استثنائهم)
const dsons = read('migrations/20261127100000_photo_nudge_daughter_sons.sql');
const dsonsUndo = read('rollback/20261127100000_photo_nudge_daughter_sons_rollback.sql');


const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
// O مالك له صورة · A مدير بلا صورة · MON مراقب بلا صورة · M عضو له صورة · X/Y/Z مسجّلون بلا صورة برقم
// F أنثى · FR موقوف بلا صورة · PN معلّق · DS ابن بنت مسجّل بلا صورة · NP مسجّل بلا رقم · DV جهاز بلا حساب دخول
// D متوفى · T بلا حساب ولا جهاز
const P = { O: id(1), A: id(2), MON: id(3), M: id(10), X: id(11), Y: id(12), Z: id(13), F: id(14), FR: id(15), PN: id(16),
            DS: id(17), NP: id(18), DV: id(19), D: id(20), T: id(21) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

async function seed(db) {
  await db.exec(`
    grant usage on schema auth to authenticated;
    grant select, update on public.profiles to authenticated;
    insert into profiles(id, first_name, full_name, gender, role, status, avatar_url, phone_number, is_deceased) values
      ('${P.O}', 'مالك', 'المالك الأول', 'male', 'owner', 'active', 'https://x/avatars/o.jpg', '55500001', false),
      ('${P.A}', 'مدير', 'المدير الأول', 'male', 'admin', 'active', null, '55500002', false),
      ('${P.MON}', 'مراقب', 'المراقب الأول', 'male', 'monitor', 'active', null, '55500003', false),
      ('${P.M}', 'محمد', 'محمد علي المحمدعلي', 'male', 'member', 'active', 'https://x/avatars/m.jpg', '55500010', false),
      ('${P.X}', 'خالد', 'خالد علي المحمدعلي', 'male', 'member', 'active', null, '55500011', false),
      ('${P.Y}', 'يوسف', 'يوسف علي المحمدعلي', 'male', 'member', 'active', null, '55500012', false),
      ('${P.Z}', 'زيد', 'زيد علي المحمدعلي', 'male', 'member', 'active', null, '55500013', false),
      ('${P.F}', 'فاطمة', 'فاطمة علي المحمدعلي', 'female', 'member', 'active', null, '55500014', false),
      ('${P.FR}', 'فارس', 'فارس علي المحمدعلي', 'male', 'member', 'frozen', null, '55500015', false),
      ('${P.PN}', 'بدر', 'بدر علي المحمدعلي', 'male', 'pending', 'pending', null, '55500016', false),
      ('${P.DS}', 'فهد', 'فهد ناصر العتيبي', 'male', 'member', 'active', null, '55500017', false),
      ('${P.NP}', 'نايف', 'نايف علي المحمدعلي', 'male', 'member', 'active', null, '  ', false),
      ('${P.DV}', 'داود', 'داود علي المحمدعلي', 'male', 'member', 'active', null, '55500019', false),
      ('${P.D}', 'راحل', 'راحل علي المحمدعلي', 'male', 'member', 'active', null, '55500020', true),
      ('${P.T}', 'شجرة', 'بلا حساب المحمدعلي', 'male', 'member', 'active', null, '55500021', false);
    insert into auth.users(id, raw_app_meta_data) values
      ('${P.O}', '{}'), ('${P.A}', '{}'), ('${P.MON}', '{}'), ('${P.M}', '{}'), ('${P.X}', '{}'), ('${P.Y}', '{}'),
      ('${P.Z}', '{}'), ('${P.F}', '{}'), ('${P.FR}', '{}'), ('${P.PN}', '{}'), ('${P.DS}', '{}'), ('${P.NP}', '{}'),
      ('${P.D}', '{}');
    insert into device_tokens(member_id, token) values ('${P.DV}', 'tok-dv');
    insert into daughter_son_lineage(profile_id) values ('${P.DS}');`);
}

/** stage: before = قبل 200000 (180000) · after = + 200000 (الحي اليوم ٢٠٢٦-١١-٢٧) · dsons = + 20261127100000 */
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
  await db.exec(`
    create schema if not exists private;
    alter table public.admin_requests add column if not exists details text, add column if not exists new_value text;
    create table public.daughter_son_lineage (profile_id uuid primary key references public.profiles(id) on delete cascade);`);
  await db.exec(applied);
  await db.exec(p1);
  await seed(db);
  if (stage === 'after' || stage === 'dsons') await db.exec(fix);
  if (stage === 'dsons') {
    // «حساب المراجعة» (الحي: app_config.review_account_ids) — بديل صغير في القاعدة المعزولة
    await db.exec(`create table if not exists public.test_review_ids(id uuid);
      create or replace function public.review_account_ids() returns uuid[] language sql stable as
      $f$ select coalesce(array_agg(id), '{}'::uuid[]) from public.test_review_ids $f$;`);
    await db.exec(dsons);
  }
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

const askAll = (db, who, ids) => ids === undefined
  ? as(db, who, `select public.request_photo_add_all() as n`)
  : as(db, who, `select public.request_photo_add_all($1::uuid[]) as n`, [ids]);
const tick = async db => Number((await q(db, `select public.photo_requests_remind_tick() as n`))[0].n);
const openReq = async (db, member) => (await q(db, `select * from photo_change_requests where member_id = $1 and resolved_at is null`, [member]))[0];
const lastReq = async (db, member) => (await q(db, `select * from photo_change_requests where member_id = $1 order by requested_at desc limit 1`, [member]))[0];
const notesFor = async (db, member) => q(db, `select * from notifications where target_member_id = $1 and kind = 'photo_change_request' order by created_at, title`, [member]);
const allNotes = async db => q(db, `select target_member_id as t from notifications where kind = 'photo_change_request'`);
const ago = (db, member, interval) => db.exec(`update photo_change_requests set notified_at = now() - interval '${interval}' where member_id = '${member}' and resolved_at is null`);
const hidden = async (db, member) => (await q(db, `select is_photo_hidden from profiles where id = $1`, [member]))[0].is_photo_hidden;
/** طلب صورة معلّق عند الإدارة بأشكاله الحية */
async function pendingPhoto(db, member, shape, status = 'pending') {
  const rows = {
    treeEdit: ['tree_edit', `{"v": 3, "notes": "تعديل صورة بعد تجاوز حد التعديلات", "action": "add_photo", "newPhotoUrl": "https://x/avatars/photo_suggestion_1.jpg"}`, 'add_photo'],
    detailsOnly: ['tree_edit', `{"v":3,"action":"add_photo","newPhotoUrl":"https://x/avatars/photo_suggestion_2.jpg"}`, null],
    suggestion: ['photo_suggestion', null, 'https://x/avatars/photo_suggestion_3.jpg'],
    textOnly: ['tree_edit', 'إضافة', 'إضافة'],
    editName: ['tree_edit', `{"v": 3, "action": "edit_name", "newName": "خالد"}`, 'edit_name'],
  }[shape];
  return (await q(db, `insert into admin_requests (member_id, requester_id, request_type, status, details, new_value)
    values ($1, $1, $2, $3, $4, $5) returning id`, [member, rows[0], status, rows[1], rows[2]]))[0].id;
}
const sortIds = a => JSON.stringify([...a].sort());

// ══════ قبل الترحيل (الحي اليوم) — الأخطاء ظاهرة ══════
{
  console.log('\n══════ قبل الترحيل (الحي اليوم) ══════');
  const db = await setup('before');
  await pendingPhoto(db, P.X, 'treeEdit');
  let r = await ask(db, P.A, P.X, '');
  check('V9 اليوم: أرسل صورته للموافقة ومع ذلك «نبّهه» يمرّ', r.ok, r.err ?? '');
  await ago(db, P.X, '4 days');
  check('V9 اليوم: والتذكير التلقائي يذكّره رغم أن صورته بانتظار الموافقة', await tick(db) === 1);
  r = await ask(db, P.A, P.FR, '');
  check('V12 اليوم: «نبّهه» يصل لحساب موقوف', r.ok, r.err ?? '');
  const before = (await allNotes(db)).length;
  r = await askAll(db, P.O);
  const sent = (await allNotes(db)).slice(before).map(n => n.t);
  check('S-1 اليوم: «نبّههم كلهم» يشمل ابن البنت ومن بلا رقم (القائمة لا تعرضهما)', r.ok && sent.includes(P.DS) && sent.includes(P.NP),
    r.err ?? JSON.stringify(sent));
}

// ══════ بعد الترحيل ══════
{
  console.log('\n══════ بعد الترحيل ══════');
  const db = await setup('after');
  const t = (await q(db, `select to_regprocedure('public.request_photo_add_all()') as old,
    to_regprocedure('public.request_photo_add_all(uuid[])') as neu,
    (select count(*)::int from pg_trigger where tgname = 'trg_zzzz_photo_change_deceased') as trg`))[0];
  check('البنية: request_photo_add_all(uuid[]) مكان القديمة، ومشغّل الوفاة', !t.old && !!t.neu && t.trg === 1, JSON.stringify(t));
  let r = await as(db, P.A, `select private.photo_pending_approval($1)`, [P.X]);
  check('الدالتان الداخليتان لا تُنفَّذان من التطبيق', !r.ok, r.err ?? '');

  // ── V9: صورة بانتظار الموافقة ──
  const xPending = await pendingPhoto(db, P.X, 'treeEdit');
  r = await ask(db, P.A, P.X, '');
  check('V9: tree_edit add_photo معلّق → «نبّهه» مرفوض (photo_pending)', !r.ok && r.hint === 'photo_pending', r.err);
  await pendingPhoto(db, P.Y, 'detailsOnly');
  r = await ask(db, P.A, P.Y, '');
  check('V9: الإجراء في details وحده (بلا new_value) → مرفوض أيضاً', !r.ok && r.hint === 'photo_pending', r.err);
  await pendingPhoto(db, P.Z, 'suggestion');
  r = await ask(db, P.MON, P.Z, '');
  check('V9: صورة مقترحة معلّقة (photo_suggestion) → مرفوض للمراقب أيضاً', !r.ok && r.hint === 'photo_pending', r.err);
  check('… ولا طلب ولا إشعار', !(await openReq(db, P.Z)) && (await notesFor(db, P.Z)).length === 0);
  await db.exec(`update admin_requests set status = 'approved' where id = '${xPending}'`);
  await pendingPhoto(db, P.X, 'textOnly');
  await pendingPhoto(db, P.X, 'editName');
  r = await ask(db, P.A, P.X, '');
  check('V9: بعد البتّ فيه (approved) + طلبات أخرى نصية وتعديل اسم → «نبّهه» يعمل', r.ok, r.err ?? '');
  r = await ask(db, P.A, P.M, '');
  check('مسار «غيّر» كما هو: له صورة بسبب فارغ مرفوض (bad_reason)', !r.ok && r.hint === 'bad_reason', r.err);
  await pendingPhoto(db, P.M, 'suggestion');
  r = await ask(db, P.A, P.M, 'الصورة غير واضحة');
  check('مسار «غيّر» كما هو: له صورة وصورة مقترحة معلّقة → الطلب يمرّ', r.ok, r.err ?? '');

  // التذكير يتخطّى من أرسل صورته
  await ago(db, P.X, '4 days');
  const again = await pendingPhoto(db, P.X, 'treeEdit');
  check('V9: التذكير التلقائي يتخطّى من صورته بانتظار الموافقة', await tick(db) === 0);
  check('… وطلبه يبقى مفتوحاً (يُغلقه المشغّل حين تُعتمد صورته)', !!(await openReq(db, P.X)));
  await db.exec(`update admin_requests set status = 'rejected' where id = '${again}'`);
  check('… رُفضت صورته → يعود التذكير', await tick(db) === 1);

  // ── V12: الموقوف والمعلّق ──
  r = await ask(db, P.A, P.FR, '');
  check('V12: «نبّهه» لحساب موقوف مرفوض (account_frozen)', !r.ok && r.hint === 'account_frozen', r.err);
  r = await ask(db, P.A, P.PN, '');
  check('V12: … وللمعلّق (account_frozen)', !r.ok && r.hint === 'account_frozen', r.err);
  check('… ولا إشعار لأيّهما', (await notesFor(db, P.FR)).length === 0 && (await notesFor(db, P.PN)).length === 0);
  await db.exec(`update profiles set avatar_url = 'https://x/avatars/fr.jpg' where id = '${P.FR}'`);
  r = await ask(db, P.A, P.FR, 'الصورة غير مناسبة');
  check('مسار «غيّر» للموقوف كما كان (الحي) — بلا تغيير', r.ok, r.err ?? '');
}

// ══════ S-1: «نبّههم كلهم» بقاعدة القائمة ══════
{
  console.log('\n══════ «نبّههم كلهم» بقاعدة القائمة ══════');
  const db = await setup('after');
  await pendingPhoto(db, P.Z, 'treeEdit');
  const shown = [P.X, P.Y, P.Z, P.F, P.FR, P.PN, P.DS, P.NP, P.DV, P.D, P.T, P.M, P.A, P.O];
  let b = (await allNotes(db)).length;
  let r = await askAll(db, P.A, shown);
  let sent = (await allNotes(db)).slice(b).map(n => n.t);
  // المؤهَّل: X · Y · DV (جهاز بلا حساب — نفس فئات app_usage_members). يُستثنى: Z (صورته بانتظار الموافقة) · F أنثى ·
  // FR موقوف · PN معلّق · DS ابن بنت · NP بلا رقم · D متوفى · T بلا حساب ولا جهاز · M/O لهما صورة · A المتصل.
  // MON مؤهَّل لكنه ليس في المعرّفات المعروضة فلا يُنبَّه.
  check('S-1: المعرّفات المعروضة يُعاد فحصها — ٣ فقط (X · Y · DV)', r.ok && Number(r.rows[0].n) === 3
    && sortIds(sent) === sortIds([P.X, P.Y, P.DV]), r.err ?? `${r.rows?.[0]?.n} ${JSON.stringify(sent)}`);
  check('… بنص «أضف» وbulk', (await notesFor(db, P.DV))[0]?.details?.bulk === true
    && (await notesFor(db, P.DV))[0]?.title === 'أضف صورتك الشخصية');
  b = (await allNotes(db)).length;
  r = await askAll(db, P.A);
  sent = (await allNotes(db)).slice(b).map(n => n.t);
  check('بلا معامل (نداء P1 القديم): كل من تنطبق عليه القاعدة — المراقب وحده بقي', r.ok && Number(r.rows[0].n) === 1
    && sortIds(sent) === sortIds([P.MON]), r.err ?? JSON.stringify(sent));
  r = await askAll(db, P.A, []);
  check('مصفوفة فارغة: 0', r.ok && Number(r.rows[0].n) === 0, r.err ?? '');
  r = await askAll(db, P.A, shown);
  check('التكرار فوراً: 0 (نُبّهوا خلال ٧ أيام)', r.ok && Number(r.rows[0].n) === 0, r.err ?? '');
  for (const [who, name] of [[P.MON, 'المراقب'], [P.X, 'العضو'], [null, 'بلا دخول']]) {
    r = await askAll(db, who, shown);
    check(`${name}: مرفوض (not_allowed)`, !r.ok && r.hint === 'not_allowed', r.err);
  }
  await ago(db, P.X, '8 days');
  await db.exec(`update profiles set status = 'frozen' where id = '${P.X}'`);
  r = await askAll(db, P.O, [P.X]);
  check('أُوقف بعد عرض القائمة: لا يُنبَّه ولو أرسله التطبيق', r.ok && Number(r.rows[0].n) === 0, r.err ?? `${r.rows?.[0]?.n}`);
  await db.exec(`update profiles set status = 'active' where id = '${P.X}'`);
  r = await askAll(db, P.O, [P.X]);
  check('… رجع مفعّلاً بعد ٨ أيام: يُنبَّه (المالك)', r.ok && Number(r.rows[0].n) === 1, r.err ?? `${r.rows?.[0]?.n}`);
}

// ══════ V24: الوفاة تغلق طلب الصورة ══════
{
  console.log('\n══════ الوفاة تغلق طلب الصورة ══════');
  const db = await setup('after');
  let r = await ask(db, P.A, P.M, 'الصورة غير واضحة', true);
  check('طلب تغيير بإخفاء الصورة', r.ok && await hidden(db, P.M) === true && (await openReq(db, P.M))?.hid_photo === true, r.err ?? '');
  r = await as(db, P.A, `update profiles set is_deceased = true where id = $1`, [P.M]);
  let req = await lastReq(db, P.M);
  check('المدير يسجّل الوفاة → الطلب يُغلق (cancelled) باسمه', r.ok && !(await openReq(db, P.M)) && req.resolution === 'cancelled'
    && req.resolved_by === P.A, r.err ?? JSON.stringify(req));
  check('… وتظهر الصورة التي أخفاها الطلب', await hidden(db, P.M) === false);
  await ask(db, P.A, P.X, '');
  await db.exec(`update profiles set is_photo_hidden = true where id = '${P.X}'`);
  await db.exec(`update profiles set is_deceased = true where id = '${P.X}'`);
  req = await lastReq(db, P.X);
  check('بلا مستخدم (صيانة): يُغلق أيضاً، وresolved_by فارغ', !(await openReq(db, P.X)) && req.resolution === 'cancelled'
    && req.resolved_by === null, JSON.stringify(req));
  check('… وما أخفاه العضو بنفسه يبقى مخفياً', await hidden(db, P.X) === true);
  await ask(db, P.A, P.Y, '');
  await db.exec(`update profiles set first_name = 'يوسف٢' where id = '${P.Y}'`);
  check('تعديل آخر (لا وفاة) لا يغلق الطلب', !!(await openReq(db, P.Y)));
}

// ══════ تنظيف: مفتوح لمتوفى قبل الترحيل ══════
{
  console.log('\n══════ تنظيف المفتوح لمتوفى ══════');
  const db = await setup('before');
  await ask(db, P.A, P.M, 'الصورة غير واضحة', true);
  await db.exec(`update profiles set is_deceased = true where id = '${P.M}'`);
  check('قبل الترحيل: توفي وطلبه مفتوح وصورته مخفية (V24)', !!(await openReq(db, P.M)) && await hidden(db, P.M) === true);
  await db.exec(fix);
  const req = await lastReq(db, P.M);
  check('الترحيل يغلقه (cancelled) ويُظهر الصورة', !(await openReq(db, P.M)) && req.resolution === 'cancelled'
    && await hidden(db, P.M) === false, JSON.stringify(req));
}

// ══════ بعد التراجع ══════
{
  console.log('\n══════ بعد التراجع ══════');
  const db = await setup('after');
  await db.exec(undo);
  const t = (await q(db, `select to_regprocedure('public.request_photo_add_all()') as old,
    to_regprocedure('public.request_photo_add_all(uuid[])') as neu,
    (select count(*)::int from pg_trigger where tgname = 'trg_zzzz_photo_change_deceased') as trg,
    to_regprocedure('private.photo_pending_approval(uuid)') as f1, to_regprocedure('private.photo_nudge_listed(uuid,uuid,text)') as f2`))[0];
  check('القديمة رجعت، والجديدة والمشغّل والداخليتان محذوفة', !!t.old && !t.neu && t.trg === 0 && !t.f1 && !t.f2, JSON.stringify(t));
  let r = await ask(db, P.A, P.FR, '');
  check('request_photo_change كما في 180000 (الموقوف يمرّ)', r.ok, r.err ?? '');
  r = await askAll(db, P.O);
  check('request_photo_add_all() القديمة تعمل', r.ok, r.err ?? '');
  await db.exec(fix);
  r = await ask(db, P.A, P.PN, '');
  check('الترحيل يُعاد بعد التراجع ويعمل', !r.ok && r.hint === 'account_frozen', r.err);
}

// ══════ 20261127100000: أبناء البنات في «نبّههم كلهم» ══════
{
  console.log('\n══════ أبناء البنات (20261127100000) ══════');
  const listed = async (db, member, me = P.O, role = 'owner') =>
    (await q(db, `select private.photo_nudge_listed($1, $2, $3) as ok`, [member, me, role]))[0].ok;
  const shown = [P.X, P.Y, P.Z, P.F, P.FR, P.PN, P.DS, P.NP, P.DV, P.D, P.T, P.M, P.A, P.O];
  // قبله (الحي اليوم): ابن البنت المسجّل بلا صورة خارج القاعدة — لا يصله «نبّههم كلهم» ولو عرضه التطبيق
  let db = await setup('after');
  check('قبله: ابن البنت المسجّل بلا صورة خارج القاعدة', await listed(db, P.DS) === false);
  let b = (await allNotes(db)).length;
  let r = await askAll(db, P.A, shown);
  let sent = (await allNotes(db)).slice(b).map(n => n.t);
  check('قبله: «نبّههم كلهم» لا يصله', r.ok && !sent.includes(P.DS), r.err ?? JSON.stringify(sent));

  db = await setup('dsons');
  check('بعده: ابن البنت المسجّل بلا صورة في القاعدة', await listed(db, P.DS) === true);
  b = (await allNotes(db)).length;
  r = await askAll(db, P.A, shown);
  sent = (await allNotes(db)).slice(b).map(n => n.t);
  // (لا صورة معلّقة لـ Z هنا — فهو مؤهَّل مثل X وY)
  check('بعده: «نبّههم كلهم» = X · Y · Z · DV · DS (ابن البنت معهم)', r.ok && Number(r.rows[0].n) === 5
    && sortIds(sent) === sortIds([P.X, P.Y, P.Z, P.DV, P.DS]), r.err ?? `${r.rows?.[0]?.n} ${JSON.stringify(sent)}`);
  check('… بنص «أضف» وbulk', (await notesFor(db, P.DS))[0]?.title === 'أضف صورتك الشخصية'
    && (await notesFor(db, P.DS))[0]?.details?.bulk === true);
  // كل شرط آخر باقٍ — على ابن بنت أيضاً
  const DS2 = id(30);
  await db.exec(`insert into profiles(id, first_name, full_name, gender, role, status, phone_number) values
      ('${DS2}', 'سعد', 'سعد ناصر العتيبي', 'male', 'member', 'active', null);
    insert into auth.users(id, raw_app_meta_data) values ('${DS2}', '{}');
    insert into daughter_son_lineage(profile_id) values ('${DS2}');`);
  check('ابن بنت بلا رقم: خارج القاعدة (الرقم شرط)', await listed(db, DS2) === false);
  await db.exec(`update profiles set phone_number = '55500030' where id = '${DS2}'`);
  check('… برقمه: في القاعدة', await listed(db, DS2) === true);
  await db.exec(`update profiles set status = 'frozen' where id = '${DS2}'`);
  check('ابن بنت موقوف: خارج القاعدة', await listed(db, DS2) === false);
  await db.exec(`update profiles set status = 'active', avatar_url = 'https://x/avatars/ds2.jpg' where id = '${DS2}'`);
  check('ابن بنت له صورة: خارج القاعدة', await listed(db, DS2) === false);
  await db.exec(`update profiles set avatar_url = null where id = '${DS2}'; delete from auth.users where id = '${DS2}'`);
  check('ابن بنت بلا حساب ولا جهاز: خارج القاعدة', await listed(db, DS2) === false);
  await db.exec(`insert into auth.users(id, raw_app_meta_data) values ('${DS2}', '{}')`);
  check('ابن بنت هو المتصل: خارج القاعدة', await listed(db, DS2, DS2, 'member') === false);
  await db.exec(`update profiles set is_deceased = true where id = '${DS2}'`);
  check('ابن بنت متوفى: خارج القاعدة', await listed(db, DS2) === false);
  for (const [who, name] of [[P.F, 'الأنثى'], [P.FR, 'الموقوف'], [P.PN, 'المعلّق'], [P.NP, 'بلا رقم'], [P.D, 'المتوفى'],
                             [P.T, 'بلا حساب ولا جهاز'], [P.M, 'من له صورة']]) {
    check(`بعده: ${name} ما زال خارج القاعدة`, await listed(db, who) === false);
  }
  await db.exec(`update profiles set avatar_url = null where id = '${P.O}'`);
  check('بعده: المالك بلا صورة خارج القاعدة للمدير وداخلها للمالك الآخر',
    await listed(db, P.O, P.A, 'admin') === false && await listed(db, P.O, id(99), 'owner') === true);
  await db.exec(`update profiles set avatar_url = 'https://x/avatars/o.jpg' where id = '${P.O}'`);
  r = await as(db, P.A, `select private.photo_nudge_listed($1, $2, 'owner')`, [P.DS, P.A]);
  check('بعده: الدالة الداخلية لا تُنفَّذ من التطبيق', !r.ok, r.err ?? '');
  // «حساب المراجعة» خارج القاعدة (المالك ٢٠٢٦-١١-٢٧)
  check('حساب المراجعة قبل تعليمه: في القاعدة', await listed(db, P.DS) === true);
  await db.exec(`insert into public.test_review_ids values ('${P.DS}')`);
  check('حساب المراجعة: خارج القاعدة', await listed(db, P.DS) === false);
  await db.exec(`delete from public.test_review_ids`);
  // الطلب الفردي والتذكير التلقائي لم يستثنيا ابن البنت أصلاً — لا تغيير
  const db2 = await setup('dsons');
  r = await ask(db2, P.A, P.DS, '');
  check('«نبّهه» الفردي لابن البنت يعمل (كما كان)', r.ok, r.err ?? '');
  await ago(db2, P.DS, '4 days');
  check('… والتذكير التلقائي يذكّره', await tick(db2) === 1);

  // التراجع: يرجع الحي حرفياً (ابن البنت خارج القاعدة)
  const before = (await q(await setup('after'), `select pg_get_functiondef('private.photo_nudge_listed(uuid,uuid,text)'::regprocedure) as d`))[0].d;
  const db3 = await setup('dsons');
  await db3.exec(dsonsUndo);
  const after = (await q(db3, `select pg_get_functiondef('private.photo_nudge_listed(uuid,uuid,text)'::regprocedure) as d`))[0].d;
  check('التراجع: الدالة كما في 200000 حرفياً', before === after);
  check('التراجع: ابن البنت خارج القاعدة من جديد', await listed(db3, P.DS) === false);
  r = await as(db3, P.A, `select private.photo_nudge_listed($1, $2, 'owner')`, [P.DS, P.A]);
  check('التراجع: الدالة الداخلية ما زالت لا تُنفَّذ من التطبيق', !r.ok, r.err ?? '');
  await db3.exec(dsons);
  check('الترحيل يُعاد بعد التراجع ويعمل', await listed(db3, P.DS) === true);
}

console.log(`\n${pass} نجح · ${fail} فشل`);
process.exit(fail ? 1 : 0);
