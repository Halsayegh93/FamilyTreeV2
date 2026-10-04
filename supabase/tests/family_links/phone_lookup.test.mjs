// تجربة البحث بالرقم وتحرير الرقم على قاعدة محلية معزولة (لا تلمس السيرفر).
// كل استدعاء بدور authenticated وJWT المتصل، قبل التعديل وبعده وبعد التراجع.
// التشغيل: cd supabase/tests/family_links && node phone_lookup.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, (e.query ?? '').slice(0, 200)); process.exit(2); });
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody, rest] = base.split('-- ─── المشغّلات');
const baseTriggers = rest.slice(rest.indexOf('\n') + 1);
const grab = (src, name) => { const i = src.indexOf(`create or replace function public.${name}(`); return src.slice(i, src.indexOf('$function$;', i) + '$function$;'.length); };
const preFns = ['adopt_tree_profile', 'merge_member_into_tree', 'women_auto_merge_wife']
  .map(n => grab(readFileSync(`${REPO}/rollback/20261001150000_protect_family_links_rollback.sql`, 'utf8'), n)).join('\n\n');
const fix = readFileSync(`${REPO}/migrations/20261004210000_phone_lookup_hardening.sql`, 'utf8');
const rollback = readFileSync(`${REPO}/rollback/20261004210000_phone_lookup_hardening_rollback.sql`, 'utf8');
// النسخة الحية قبل التعديل = نص ملف التراجع (مطابق لبصمة السيرفر) + دوال لم تكن في القاعدة المصغّرة.
const liveBefore = `
alter table auth.users add column created_at timestamptz default now(), add column last_sign_in_at timestamptz,
  add column phone_confirmed_at timestamptz, add column updated_at timestamptz;
create or replace function public.is_approved_member() returns boolean language sql stable security definer
  set search_path to 'public' as $$
  select coalesce(public.current_user_role() = any(array['member','supervisor','monitor','admin','owner']), false); $$;
create or replace function public.find_profile_id_by_auth_phone(p_auth_phone text, p_exclude uuid default null)
  returns uuid language sql stable security definer set search_path to 'public' as $$ select null::uuid $$;
revoke execute on function public.find_profile_id_by_auth_phone(text, uuid) from public;
grant execute on function public.find_profile_id_by_auth_phone(text, uuid) to authenticated;
create or replace function public.family_archive_validate_category_key() returns trigger language plpgsql as $f$
begin return new; end $f$;
create or replace function public.trg_profiles_deceased_no_admin_role() returns trigger language plpgsql as $f$
begin return new; end $f$;
create or replace function public.notification_category(p_kind text, p_target uuid, p_subject uuid) returns text
  language sql immutable as $f$
  select case
    when p_kind in ('admin_broadcast', 'app_update', 'test') then null
    when p_kind = 'news_like' then 'likes'
    when p_kind = 'news_comment' then 'comments'
    when p_kind = 'news_published' then 'news'
    when p_kind like 'admin_edit%' and p_subject is not null and p_subject = p_target then 'profile'
    when p_kind in ('join_approved', 'account_activated', 'role_change', 'request_rejected')
      or p_kind like '%\\_approved' or p_kind like '%\\_rejected' then 'requests'
    else 'admin_activity'
  end; $f$;
grant usage on schema auth to authenticated;
${rollback.split('grant execute on function public.find_profile_id_by_auth_phone')[0]}
revoke execute on function public.find_profiles_by_phone(text) from public;
grant execute on function public.find_profiles_by_phone(text) to authenticated;
revoke execute on function public.release_orphan_auth_phone(text) from public;
grant execute on function public.release_orphan_auth_phone(text) to authenticated;`;

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const P = { O: id(1), A: id(2), M: id(3), T: id(4), PEND: id(5), NEWU: id(6), FROZ: id(7),
  ORPH_OLD: id(20), ORPH_NEW: id(21), ORPH_SEEN: id(22), LINKED: id(23) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

async function setup() {
  const db = new PGlite();
  await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers); await db.exec(liveBefore);
  await db.exec(`
    insert into profiles(id, first_name, full_name, gender, role, status, phone_number) values
      ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active', '90000001'),
      ('${P.A}', 'بدر', 'المدير', 'male', 'admin', 'active', '90000002'),
      ('${P.M}', 'حسن', 'عضو', 'male', 'member', 'active', '90000003'),
      ('${P.T}', 'طاهر', 'سجل شجرة لم يدخل', 'male', 'member', 'active', '50000001'),
      ('${P.PEND}', 'جديد', 'مسجّل معلّق', 'male', 'pending', 'pending', '50000002'),
      ('${P.FROZ}', 'مجمد', 'مجمّد', 'male', 'member', 'frozen', '90000009'),
      ('${P.LINKED}', 'مربوط', 'عضو له حساب', 'male', 'member', 'active', '60000004');
    insert into auth.users(id, phone, created_at, last_sign_in_at) values
      ('${P.O}', '96590000001', now() - interval '90 days', now()),
      ('${P.A}', '96590000002', now() - interval '90 days', now()),
      ('${P.M}', '96590000003', now() - interval '90 days', now()),
      ('${P.PEND}', '96550000002', now() - interval '1 day', now()),
      ('${P.FROZ}', '96590000009', now() - interval '90 days', now()),
      ('${P.NEWU}', '96550000001', now(), now()),                                   -- دخول أول لصاحب سجل الشجرة T
      ('${P.ORPH_OLD}', '96560000001', now() - interval '3 days', now() - interval '3 days'),  -- حساب يتيم قديم
      ('${P.ORPH_NEW}', '96560000002', now() - interval '10 minutes', now() - interval '10 minutes'), -- يسجّل الآن
      ('${P.ORPH_SEEN}', '96560000003', now() - interval '5 days', now() - interval '2 hours'), -- قديم لكنه دخل اليوم
      ('${P.LINKED}', '96560000004', now() - interval '30 days', now());`);
  return db;
}

async function as(db, who, sql, params = []) {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: who, role: 'authenticated' })]);
  await db.exec('set role authenticated');
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message }; }
  finally { await db.exec('reset role'); }
}
const lookup = (db, who, phone) => as(db, who, `select id, role, status from public.find_profiles_by_phone($1)`, [phone]);
const release = async (db, who, phone) => { const r = await as(db, who, `select public.release_orphan_auth_phone($1) r`, [phone]); return r.ok ? r.rows[0].r : `خطأ: ${r.err}`; };
const authPhone = async (db, u) => (await db.query(`select phone from auth.users where id = $1`, [u])).rows[0]?.phone ?? null;

for (const stage of ['before', 'after', 'rolledback']) {
  const after = stage === 'after';
  console.log(`\n══════ ${{ before: 'قبل التعديل (السيرفر اليوم)', after: 'بعد التعديل', rolledback: 'بعد التراجع' }[stage]} ══════`);
  const db = await setup();
  if (stage !== 'before') await db.exec(fix);
  if (stage === 'rolledback') await db.exec(rollback);

  console.log('— البحث بالرقم:');
  for (const fmt of ['+96550000001', '96550000001', '50000001', '0096550000001']) {
    const r = await lookup(db, P.NEWU, fmt);
    check(`دخول أول (بلا ملف) يجد سجله في الشجرة برقم جلسته (${fmt})`, r.ok && r.rows.length === 1 && r.rows[0].id === P.T, r.err ?? `${r.rows.length} نتيجة`);
  }
  let r = await lookup(db, P.PEND, '+96550000002');
  check('المسجّل المعلّق يجد ملفه برقمه (تسجيل الآيفون)', r.ok && r.rows.some(x => x.id === P.PEND), r.err ?? '');
  r = await lookup(db, P.NEWU, '+96590000001');
  check(`دخول أول يبحث برقم المالك: ${after ? 'لا شيء' : 'يكشف المالك (الثغرة)'}`, r.ok && (after ? r.rows.length === 0 : r.rows.some(x => x.id === P.O)), r.err ?? `${r.rows.length} نتيجة`);
  r = await lookup(db, P.PEND, '90000002');
  check(`المعلّق يبحث برقم المدير: ${after ? 'لا شيء' : 'يكشف المدير (الثغرة)'}`, r.ok && (after ? r.rows.length === 0 : r.rows.some(x => x.id === P.A)), r.err ?? `${r.rows.length} نتيجة`);
  r = await lookup(db, P.FROZ, '90000003');
  check(`المجمّد يبحث برقم عضو: ${after ? 'لا شيء' : 'يكشفه (الثغرة)'}`, r.ok && (after ? r.rows.length === 0 : r.rows.length === 1), r.err ?? `${r.rows.length} نتيجة`);
  r = await lookup(db, P.M, '+96560000004');
  check('العضو المفعّل يفحص رقماً جديداً «لعضو آخر؟» (تغيير الرقم)', r.ok && r.rows.length === 1 && r.rows[0].id === P.LINKED, r.err ?? '');
  r = await lookup(db, P.O, '50000002');
  check('المالك يبحث بأي رقم', r.ok && r.rows.length === 1, r.err ?? '');

  r = await as(db, P.M, `select public.find_profile_id_by_auth_phone('96590000001') x`);
  check(`find_profile_id_by_auth_phone للعضو: ${after ? 'ممنوعة' : 'مسموحة'}`, after ? !r.ok : r.ok, r.err ?? '');

  console.log('— تحرير الرقم:');
  check('رقم حساب يتيم قديم يُحرَّر', await release(db, P.M, '+96560000001') === 'released' && await authPhone(db, P.ORPH_OLD) === null);
  const notes = (await db.query(`select count(*)::int n from notifications where title = 'تحرير رقم لتغيير الرقم'`)).rows[0].n;
  check('إشعار التحرير يصل المالك والمدير', notes === 2, `${notes}`);
  const rn = await release(db, P.M, '+96560000002');
  check(`حساب يسجّل الآن (قبل ١٠ دقائق): ${after ? 'لا يُلمس ويُحال للإدارة' : 'يُفك رقمه (الثغرة)'}`,
    after ? rn === 'linked' && await authPhone(db, P.ORPH_NEW) === '96560000002' : rn === 'released', rn);
  const rs = await release(db, P.M, '96560000003');
  check(`حساب قديم دخل قبل ساعتين: ${after ? 'لا يُلمس' : 'يُفك رقمه'}`, after ? rs === 'linked' && await authPhone(db, P.ORPH_SEEN) === '96560000003' : rs === 'released', rs);
  check('رقم عضو له حساب: لا يُلمس', await release(db, P.M, '+96560000004') === 'linked' && await authPhone(db, P.LINKED) === '96560000004');
  check('رقم غير مستخدم: free', await release(db, P.M, '+96570000000') === 'free');
  check('رقم غير صالح', await release(db, P.M, '123') === 'invalid_phone');
  check('المعلّق ممنوع من التحرير', (await release(db, P.PEND, '+96560000001')).startsWith('خطأ'));

  const cfg = (await db.query(`select string_agg(proname || '=' || coalesce(array_to_string(proconfig, ','), '-'), ' ' order by proname) s
    from pg_proc where proname in ('family_archive_validate_category_key','trg_profiles_deceased_no_admin_role','trg_profiles_protect_delete','notification_category')`)).rows[0].s;
  check(`search_path للدوال الأربع: ${after ? 'ثابت' : 'بلا تثبيت'}`, after ? (cfg.match(/search_path=public/g) ?? []).length === 4 : !cfg.includes('search_path'), cfg);
  const cat = (await db.query(`select public.notification_category('news_like', null, null) a, public.notification_category('join_approved', null, null) b, public.notification_category('x_rejected', null, null) c`)).rows[0];
  check('notification_category نفس النتائج', cat.a === 'likes' && cat.b === 'requests' && cat.c === 'requests', JSON.stringify(cat));
}
console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
