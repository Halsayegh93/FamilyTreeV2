// تجربة 20261111160000_photo_change_request («طلب تغيير الصورة») على قاعدة محلية معزولة (لا تلمس السيرفر).
// القاعدة = base.sql + الحراس الحية التي تمسّ الطلب: حارس الأقارب وprofile_has_login (20261024120000)،
// حارس مرسل الإشعار (20261004220000)، نظام الإشعارات v2 (20261031210000: ختم المرسل + «تعديل بيانات» للإدارة)،
// وفئات الدفع (20260922250000) — ومُطلِق الدفع بديل محلي يسجّل ما كان سيُرسَل (net.http_post غير متاح هنا).
// المراحل: قبل الترحيل (التطبيق يتعامل مع غياب الدالة) · بعده · بعد التراجع.
// التشغيل: cd supabase/tests/family_links && node photo_change_request.test.mjs
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
const fix = read('migrations/20261111160000_photo_change_request.sql');
const undo = read('rollback/20261111160000_photo_change_request_rollback.sql');

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
// O مالك · A مدير · MON مراقب · S مشرف · FA مدير موقوف · M عضو له صورة · M2 عضو أخفى صورته بنفسه
// MV عضو حسابه بمعرّف آخر (AV + app_metadata.profile_id) · D متوفى له حساب · T بلا حساب · X عضو عادي
const P = { O: id(1), A: id(2), MON: id(3), S: id(5), FA: id(6), M: id(10), M2: id(11), MV: id(12), D: id(13), T: id(14),
            X: id(15), AV: id(30), NONE: id(99) };
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
  // مُطلِق الدفع: نفس بوابة الفئات (notification_push_allowed)، ويسجّل بدل net.http_post
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
  if (stage !== 'before') await db.exec(fix);
  await db.exec(`
    grant usage on schema auth to authenticated;
    grant select, update on public.profiles to authenticated;
    insert into profiles(id, first_name, full_name, gender, role, status, avatar_url, is_deceased, is_photo_hidden) values
      ('${P.O}', 'مالك', 'المالك الأول', 'male', 'owner', 'active', null, false, false),
      ('${P.A}', 'مدير', 'المدير الأول', 'male', 'admin', 'active', null, false, false),
      ('${P.MON}', 'مراقب', 'المراقب الأول', 'male', 'monitor', 'active', null, false, false),
      ('${P.S}', 'مشرف', 'المشرف الأول', 'male', 'supervisor', 'active', null, false, false),
      ('${P.FA}', 'موقوف', 'مدير موقوف', 'male', 'admin', 'frozen', null, false, false),
      ('${P.M}', 'محمد', 'محمد علي حسن المحمدعلي', 'male', 'member', 'active', 'https://x/avatars/m.jpg?v=1', false, false),
      ('${P.M2}', 'خالد', 'خالد علي حسن المحمدعلي', 'male', 'member', 'active', 'https://x/avatars/m2.jpg?v=1', false, true),
      ('${P.MV}', 'سالم', 'سالم علي حسن المحمدعلي', 'male', 'member', 'active', 'https://x/avatars/mv.jpg?v=1', false, false),
      ('${P.D}', 'راحل', 'راحل علي حسن المحمدعلي', 'male', 'member', 'active', 'https://x/avatars/d.jpg?v=1', true, false),
      ('${P.T}', 'شجرة', 'بلا حساب علي المحمدعلي', 'male', 'member', 'active', 'https://x/avatars/t.jpg?v=1', false, false),
      ('${P.X}', 'عادي', 'عضو عادي', 'male', 'member', 'active', null, false, false);
    insert into auth.users(id, raw_app_meta_data) values
      ('${P.O}', '{}'), ('${P.A}', '{}'), ('${P.MON}', '{}'), ('${P.S}', '{}'), ('${P.FA}', '{}'), ('${P.M}', '{}'),
      ('${P.M2}', '{}'), ('${P.D}', '{}'), ('${P.X}', '{}'), ('${P.AV}', '{"profile_id": "${P.MV}"}');`);
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
/** دالة سيرفر (SECURITY DEFINER) تعمل بجلسة مستخدم — مثل decide_admin_request عند اعتماد صورة مقترحة */
async function definerAs(db, who, sql, params = []) {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify(claims(who))]);
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint }; }
  finally { await db.query(`select set_config('request.jwt.claims', '', false)`); }
}
const q = async (db, sql, params = []) => (await db.query(sql, params)).rows;
const ask = (db, who, member, reason, hide = false) =>
  as(db, who, `select public.request_photo_change($1, $2, $3) as id`, [member, reason, hide]);
const cancel = (db, who, member) => as(db, who, `select public.cancel_photo_change($1) as ok`, [member]);
const openReq = async (db, member) => (await q(db, `select * from photo_change_requests where member_id = $1 and resolved_at is null`, [member]))[0];
const notesFor = async (db, member) => q(db, `select * from notifications where target_member_id = $1 and kind = 'photo_change_request' order by created_at`, [member]);
const pushesFor = async (db, member) => q(db, `select * from push_calls where target = $1 and kind = 'photo_change_request'`, [member]);
const profile = async (db, pid) => (await q(db, `select * from profiles where id = $1`, [pid]))[0];
const memberChangeCount = async (db, admin) => Number((await q(db,
  `select count(*)::int as n from notifications where target_member_id = $1 and kind = 'member_change'`, [admin]))[0].n);

// ══════ قبل الترحيل ══════
{
  console.log('\n══════ قبل الترحيل (السيرفر اليوم) ══════');
  const db = await setup('before');
  const r = await ask(db, P.A, P.M, 'الصورة غير واضحة');
  check('الدالة غير موجودة → خطأ (التطبيق يعرض «تحتاج تحديث السيرفر» ولا ينهار)', !r.ok && /does not exist/.test(r.err), r.err);
  const t = await as(db, P.M, `select id from photo_change_requests where member_id = $1`, [P.M]);
  check('الجدول غير موجود → خطأ (مربّع العضو لا يظهر)', !t.ok, t.err);
  const u = await as(db, P.M, `update profiles set avatar_url = 'https://x/avatars/m.jpg?v=9' where id = $1`, [P.M]);
  check('رفع الصورة يعمل كما هو', u.ok, u.err ?? '');
}

// ══════ بعد الترحيل ══════
{
  console.log('\n══════ بعد الترحيل ══════');
  const db = await setup('after');

  // ── الأدوار والرفض ──
  for (const [who, name] of [[P.S, 'المشرف'], [P.X, 'العضو'], [P.FA, 'المدير الموقوف'], [null, 'بلا دخول']]) {
    const r = await ask(db, who, P.M, 'الصورة غير واضحة');
    check(`${name}: مرفوض (not_allowed)`, !r.ok && r.hint === 'not_allowed', r.err);
  }
  let r = await ask(db, P.A, P.D, 'الصورة غير واضحة');
  check('عضو متوفى: مرفوض (deceased)', !r.ok && r.hint === 'deceased', r.err);
  r = await ask(db, P.A, P.T, 'الصورة غير واضحة');
  check('عضو بلا حساب دخول: مرفوض (no_account)', !r.ok && r.hint === 'no_account', r.err);
  r = await ask(db, P.A, P.NONE, 'الصورة غير واضحة');
  check('عضو غير موجود: مرفوض (member_not_found)', !r.ok && r.hint === 'member_not_found', r.err);
  r = await ask(db, P.A, P.A, 'الصورة غير واضحة');
  check('لنفسه: مرفوض (own_profile)', !r.ok && r.hint === 'own_profile', r.err);
  r = await ask(db, P.MON, P.O, 'الصورة غير واضحة');
  check('المراقب يطلبه من المالك: مرفوض (owner_protected)', !r.ok && r.hint === 'owner_protected', r.err);
  r = await ask(db, P.A, P.M, '   ');
  check('سبب فارغ: مرفوض (bad_reason)', !r.ok && r.hint === 'bad_reason', r.err);
  r = await ask(db, P.A, P.M, 'س'.repeat(201));
  check('سبب أطول من ٢٠٠: مرفوض (bad_reason)', !r.ok && r.hint === 'bad_reason', r.err);
  check('لا طلبات ولا إشعارات بعد الرفض', (await q(db, `select 1 from photo_change_requests`)).length === 0
    && (await q(db, `select 1 from notifications where kind = 'photo_change_request'`)).length === 0);

  // ── المالك يطلب (بلا إخفاء) ──
  const mcBefore = await memberChangeCount(db, P.A);
  r = await ask(db, P.O, P.M, 'الصورة غير واضحة');
  const firstId = r.rows?.[0]?.id;
  check('المالك يطلب من عضو: يرجع معرّف الطلب', r.ok && !!firstId, r.err ?? '');
  let req = await openReq(db, P.M);
  check('طلب مفتوح واحد بالسبب ومن طلبه', req?.id === firstId && req.reason === 'الصورة غير واضحة' && req.requested_by === P.O
    && req.hide_photo === false && req.hid_photo === false);
  let notes = await notesFor(db, P.M);
  check('إشعار واحد للعضو', notes.length === 1);
  check('عنوان الإشعار ونصّه', notes[0]?.title === 'طلب تغيير الصورة الشخصية'
    && notes[0]?.body === 'يرجى تغيير صورتك الشخصية — السبب: الصورة غير واضحة.', `${notes[0]?.title} | ${notes[0]?.body}`);
  check('الإشعار: المرسل «الإدارة» بلا اسم للعضو، ورقم الطلب في التفاصيل', notes[0]?.details?.sender?.type === 'admin'
    && !notes[0]?.details?.sender?.name && notes[0]?.details?.photo_change_request_id === firstId
    && notes[0]?.subject_member_id === P.M && notes[0]?.created_by === P.O, JSON.stringify(notes[0]?.details));
  check('مُطلِق الدفع يرسله (فئة admin_activity مفعّلة افتراضياً)', (await pushesFor(db, P.M)).length === 1);
  check('الصورة باقية ظاهرة (بلا إخفاء)', (await profile(db, P.M)).is_photo_hidden === false);
  check('الطلب لا يولّد «تعديل بيانات» للإدارة', await memberChangeCount(db, P.A) === mcBefore);

  // ── التكرار (منع الإزعاج) ──
  r = await ask(db, P.A, P.M, 'الصورة غير مناسبة');
  req = await openReq(db, P.M);
  check('طلب ثانٍ خلال دقيقة: نفس المعرّف والسبب الجديد ومن طلبه', r.ok && r.rows[0].id === firstId
    && req.reason === 'الصورة غير مناسبة' && req.requested_by === P.A, r.err ?? '');
  check('… بلا إشعار جديد ولا دفع', (await notesFor(db, P.M)).length === 1 && (await pushesFor(db, P.M)).length === 1);
  await db.exec(`update photo_change_requests set notified_at = now() - interval '2 minutes' where id = '${firstId}'`);
  r = await ask(db, P.MON, P.M, 'الصورة ليست لصاحب الحساب.');
  notes = await notesFor(db, P.M);
  check('بعد دقيقة: المراقب يكرّره ← نفس الطلب وإشعار تذكير جديد', r.ok && r.rows[0].id === firstId && notes.length === 2
    && notes[1].body === 'يرجى تغيير صورتك الشخصية — السبب: الصورة ليست لصاحب الحساب.', notes[1]?.body ?? r.err);
  check('طلب مفتوح واحد فقط للعضو', (await q(db, `select 1 from photo_change_requests where member_id = $1`, [P.M])).length === 1);
  r = await db.query(`insert into photo_change_requests(member_id, reason) values ($1, 'تكرار')`, [P.M]).then(() => ({ ok: true }), e => ({ ok: false, err: e.message }));
  check('الفهرس الفريد يمنع طلباً مفتوحاً ثانياً ولو من SQL', !r.ok, r.err ?? '');

  // ── الإخفاء ──
  r = await ask(db, P.A, P.MV, 'الصورة غير مناسبة', true);
  req = await openReq(db, P.MV);
  check('المدير يطلب مع الإخفاء: الصورة تُخفى (is_photo_hidden) ويُسجَّل أن الطلب أخفاها',
    r.ok && (await profile(db, P.MV)).is_photo_hidden === true && req.hide_photo && req.hid_photo, r.err ?? '');
  r = await ask(db, P.MON, P.M2, 'الصورة غير واضحة', true);
  req = await openReq(db, P.M2);
  check('أخفاها العضو بنفسه قبلُ: تبقى مخفية والطلب لا يدّعي إخفاءها',
    r.ok && (await profile(db, P.M2)).is_photo_hidden === true && req.hide_photo && !req.hid_photo, r.err ?? '');

  // ── القراءة (RLS) ولا كتابة مباشرة ──
  r = await as(db, P.M, `select id, reason, hide_photo, requested_at from photo_change_requests where resolved_at is null`);
  check('العضو يقرأ طلبه المفتوح فقط', r.ok && r.rows.length === 1 && r.rows[0].id === firstId, r.err ?? JSON.stringify(r.rows));
  r = await as(db, P.AV, `select id, member_id from photo_change_requests where resolved_at is null`);
  check('حساب بمعرّف آخر (app_metadata) يقرأ طلب ملفه', r.ok && r.rows.length === 1 && r.rows[0].member_id === P.MV, r.err ?? '');
  r = await as(db, P.M, `select requested_by from photo_change_requests`);
  check('العضو لا يقرأ من طلب (الأعضاء يرون «الإدارة»)', !r.ok && /permission denied/.test(r.err), r.err ?? '');
  r = await as(db, P.MON, `select id, member_id, reason from photo_change_requests where resolved_at is null`);
  check('المراقب يقرأ كل الطلبات المفتوحة', r.ok && r.rows.length === 3, r.err ?? `${r.rows?.length}`);
  r = await as(db, P.S, `select id from photo_change_requests`);
  check('المشرف لا يرى شيئاً', r.ok && r.rows.length === 0, r.err ?? '');
  r = await as(db, P.X, `select id from photo_change_requests`);
  check('عضو آخر لا يرى طلبات غيره', r.ok && r.rows.length === 0, r.err ?? '');
  r = await as(db, P.M, `insert into photo_change_requests(member_id, reason) values ($1, 'من التطبيق')`, [P.X]);
  check('لا إدراج مباشر من التطبيقات', !r.ok, r.err ?? '');
  r = await as(db, P.M, `update photo_change_requests set resolved_at = now(), resolution = 'cancelled' where member_id = $1`, [P.M]);
  check('العضو لا يغلق طلبه بنفسه', !r.ok, r.err ?? '');
  r = await as(db, P.A, `delete from photo_change_requests where member_id = $1`, [P.M]);
  check('ولا الإدارة تحذف مباشرة', !r.ok, r.err ?? '');

  // ── ما لا يحلّ الطلب ──
  r = await as(db, P.M, `update profiles set avatar_url = null where id = $1`, [P.M]);
  check('حذف العضو صورته لا يغلق الطلب', r.ok && !!(await openReq(db, P.M)), r.err ?? '');
  await db.exec(`update profiles set avatar_url = 'https://cdn/avatars/m.jpg' where id = '${P.M}'`);
  check('إعادة كتابة الرابط بلا مستخدم (صيانة) لا تغلقه', !!(await openReq(db, P.M)));
  r = await as(db, P.M, `update profiles set first_name = 'محمد' where id = $1`, [P.M]);
  check('تعديل حقل آخر لا يغلقه', r.ok && !!(await openReq(db, P.M)), r.err ?? '');

  // ── العضو يغيّر صورته ──
  const mcOwner = await memberChangeCount(db, P.O);
  r = await as(db, P.M, `update profiles set avatar_url = 'https://x/avatars/m.jpg?v=2' where id = $1`, [P.M]);
  req = (await q(db, `select * from photo_change_requests where id = $1`, [firstId]))[0];
  check('العضو يرفع صورة جديدة → الطلب يُغلق (photo_changed، بواسطته)', r.ok && req.resolved_at && req.resolution === 'photo_changed'
    && req.resolved_by === P.M, r.err ?? JSON.stringify(req));
  check('الإدارة يصلها «تعديل بيانات» العادي عن الصورة', await memberChangeCount(db, P.O) === mcOwner + 1);
  r = await as(db, P.M, `select id from photo_change_requests where resolved_at is null`);
  check('مربّع العضو لا يظهر بعدها (لا طلب مفتوح)', r.ok && r.rows.length === 0);
  r = await as(db, P.AV, `update profiles set avatar_url = 'https://x/avatars/mv.jpg?v=2' where id = $1`, [P.MV]);
  check('حساب بمعرّف آخر يغيّر صورته → يُغلق ويُظهر ما أخفاه الطلب',
    r.ok && !(await openReq(db, P.MV)) && (await profile(db, P.MV)).is_photo_hidden === false, r.err ?? '');
  r = await definerAs(db, P.A, `update profiles set avatar_url = 'https://x/avatars/m2.jpg?v=2' where id = $1`, [P.M2]);
  req = (await q(db, `select * from photo_change_requests where member_id = $1 order by requested_at desc limit 1`, [P.M2]))[0];
  check('اعتماد صورته المقترحة (دالة سيرفر بجلسة المدير) → يُغلق، بواسطة المدير',
    r.ok && req.resolution === 'photo_changed' && req.resolved_by === P.A, r.err ?? JSON.stringify(req));
  check('… وما أخفاه العضو بنفسه يبقى مخفياً', (await profile(db, P.M2)).is_photo_hidden === true);

  // ── الإلغاء ──
  r = await ask(db, P.A, P.M, 'الصورة غير مناسبة', true);
  const secondId = r.rows?.[0]?.id;
  check('طلب جديد بعد الإغلاق = صفّ جديد (السجل يبقى)', r.ok && secondId && secondId !== firstId
    && (await q(db, `select 1 from photo_change_requests where member_id = $1`, [P.M])).length === 2, r.err ?? '');
  check('… وإشعار جديد (لا طلب مفتوح قبله)', (await notesFor(db, P.M)).length === 3);
  r = await cancel(db, P.S, P.M);
  check('المشرف لا يلغي (not_allowed)', !r.ok && r.hint === 'not_allowed', r.err);
  r = await cancel(db, P.X, P.M);
  check('العضو لا يلغي (not_allowed)', !r.ok && r.hint === 'not_allowed', r.err);
  r = await cancel(db, P.MON, P.M);
  req = (await q(db, `select * from photo_change_requests where id = $1`, [secondId]))[0];
  check('المراقب يلغي → true، cancelled، والصورة تظهر', r.ok && r.rows[0].ok === true && req.resolution === 'cancelled'
    && req.resolved_by === P.MON && (await profile(db, P.M)).is_photo_hidden === false, r.err ?? JSON.stringify(req));
  r = await cancel(db, P.A, P.M);
  check('إلغاء بلا طلب مفتوح → false', r.ok && r.rows[0].ok === false, r.err ?? '');

  // ── تفضيلات الدفع ──
  await db.exec(`update profiles set notification_prefs = '{"admin_activity": false}' where id = '${P.X}'`);
  r = await ask(db, P.A, P.X, 'الصورة غير واضحة');
  check('عضو أطفأ «مستجدات الإدارة»: الإشعار داخل التطبيق بلا دفع (كبقية الإشعارات)',
    r.ok && (await notesFor(db, P.X)).length === 1 && (await pushesFor(db, P.X)).length === 0, r.err ?? '');
  r = await ask(db, P.O, P.A, 'الصورة غير واضحة');
  check('المالك يطلبه من مدير (له حساب) — مسموح', r.ok, r.err ?? '');
}

// ══════ بعد التراجع ══════
{
  console.log('\n══════ بعد التراجع ══════');
  const db = await setup('after');
  await ask(db, P.A, P.MV, 'الصورة غير مناسبة', true);
  await ask(db, P.A, P.M2, 'الصورة غير مناسبة', true);
  check('قبل التراجع: صورة مخفية بطلب', (await profile(db, P.MV)).is_photo_hidden === true);
  await db.exec(undo);
  check('التراجع يُظهر ما أخفاه طلب مفتوح', (await profile(db, P.MV)).is_photo_hidden === false);
  check('… ولا يمسّ ما أخفاه العضو بنفسه', (await profile(db, P.M2)).is_photo_hidden === true);
  const t = await q(db, `select to_regclass('public.photo_change_requests') as t,
    to_regprocedure('public.request_photo_change(uuid,text,boolean)') as f1, to_regprocedure('public.cancel_photo_change(uuid)') as f2,
    (select count(*)::int from pg_trigger where tgname = 'trg_zzzz_photo_change_resolve') as trg`);
  check('الجدول والدوال والمشغّل محذوفة', !t[0].t && !t[0].f1 && !t[0].f2 && t[0].trg === 0, JSON.stringify(t[0]));
  const u = await as(db, P.M, `update profiles set avatar_url = 'https://x/avatars/m.jpg?v=3' where id = $1`, [P.M]);
  check('رفع الصورة يعمل كما كان', u.ok, u.err ?? '');
  await db.exec(fix);
  check('الترحيل يُعاد تطبيقه بعد التراجع بلا خطأ', true);
}

console.log(`\n${pass} نجح · ${fail} فشل`);
process.exit(fail ? 1 : 0);
