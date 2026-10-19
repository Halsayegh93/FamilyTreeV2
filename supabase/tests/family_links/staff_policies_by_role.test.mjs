// تجربة 20261007160000 (سياسات الإدارة الخمس بالهوية الموحّدة) على قاعدة محلية معزولة (لا تلمس السيرفر) —
// قبل التعديل (ملف التراجع = تعريفات الحي حرفياً) وبعده وبعد التراجع:
//   home_sections_write · web_sessions_admin_select · web_push_subs_admin_select · web_relatives_select/_write
// المتوقع: الأدوار كما هي، المجمّد يفقد صلاحيته، والحساب المنقول (app_metadata.profile_id) يحتفظ بها.
// التشغيل: cd supabase/tests/family_links && node staff_policies_by_role.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, (e.query ?? '').slice(0, 300)); process.exit(2); });
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody] = base.split('-- ─── المشغّلات');
const NAME = '20261007160000_staff_policies_by_role';
const mig = readFileSync(`${REPO}/migrations/${NAME}.sql`, 'utf8');
const live = readFileSync(`${REPO}/rollback/${NAME}_rollback.sql`, 'utf8');

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const P = { O: id(1), A: id(2), MON: id(3), S: id(4), M: id(5), FA: id(6), FM: id(7), PEND: id(8),
  LA: id(9), LU: id(10), STR: id(11) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

async function setup(stage) {
  const db = new PGlite();
  await db.exec(baseBody);
  await db.exec(`
    create table public.home_sections (id uuid primary key default gen_random_uuid(), title text not null);
    create table public.web_sessions (id uuid primary key default gen_random_uuid(), member_id uuid not null);
    create table public.web_push_subscriptions (id uuid primary key default gen_random_uuid(), member_id uuid not null);
    -- web_relatives موجودة في base.sql
    alter table public.home_sections enable row level security;
    alter table public.web_sessions enable row level security;
    alter table public.web_push_subscriptions enable row level security;
    alter table public.web_relatives enable row level security;
    create policy home_sections_select on public.home_sections for select to authenticated using (true);
    create policy web_sessions_self_select on public.web_sessions for select using (member_id = auth.uid());
    create policy web_push_subs_self_select on public.web_push_subscriptions for select using (member_id = auth.uid());
    grant usage on schema auth to authenticated;
    grant select, insert, update, delete on public.home_sections, public.web_sessions,
      public.web_push_subscriptions, public.web_relatives to authenticated;
    grant select on public.profiles to authenticated;`);
  await db.exec(live);                                   // الحي اليوم
  if (stage !== 'before') await db.exec(mig);
  if (stage === 'rolledback') await db.exec(live);
  await db.exec(`
    insert into profiles(id, first_name, full_name, role, status) values
      ('${P.O}', 'مالك', 'المالك', 'owner', 'active'), ('${P.A}', 'بدر', 'مدير', 'admin', 'active'),
      ('${P.MON}', 'علي', 'مراقب', 'monitor', 'active'), ('${P.S}', 'سعد', 'مشرف', 'supervisor', 'active'),
      ('${P.M}', 'أحمد', 'عضو', 'member', 'active'), ('${P.FA}', 'مجمّد', 'مدير مجمّد', 'admin', 'frozen'),
      ('${P.FM}', 'مجمّد', 'مراقب مجمّد', 'monitor', 'frozen'), ('${P.PEND}', 'جديد', 'معلّق', 'pending', 'pending'),
      ('${P.LA}', 'منقول', 'مدير بحساب منقول', 'admin', 'active');
    insert into auth.users(id, raw_app_meta_data) values ('${P.LU}', '{"profile_id": "${P.LA}"}');
    insert into home_sections(title) values ('قسم');
    insert into web_sessions(member_id) values ('${P.M}'), ('${P.PEND}');
    insert into web_push_subscriptions(member_id) values ('${P.M}');
    insert into web_relatives(man_id, name) values ('${P.M}', 'قريب');`);
  return db;
}

async function as(db, who, sql) {
  const claims = JSON.stringify(typeof who === 'string'
    ? { sub: who, role: 'authenticated' }
    : { sub: who.sub, role: 'authenticated', app_metadata: { profile_id: who.pid } });
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [claims]);
  await db.exec('set role authenticated');
  try { const r = await db.query(sql); return { ok: true, n: r.affectedRows || r.rows.length, rows: r.rows }; }
  catch (e) { return { ok: false, n: 0, err: e.message }; }
  finally { await db.exec('reset role'); await db.query(`select set_config('request.jwt.claims', '', false)`); }
}
const MOVED = { sub: P.LU, pid: P.LA };

async function snapshot(db) {
  return JSON.stringify((await db.query(`select json_agg(row_to_json(p) order by tablename, policyname) j from (
    select tablename, policyname, cmd, roles::text, permissive, qual, with_check from pg_policies
    where tablename in ('home_sections', 'web_sessions', 'web_push_subscriptions', 'web_relatives')) p`)).rows[0].j);
}

const snaps = {};
for (const stage of ['before', 'after', 'rolledback']) {
  const after = stage === 'after';
  console.log(`\n══════ ${{ before: 'قبل التعديل (السيرفر اليوم)', after: 'بعد التعديل', rolledback: 'بعد التراجع' }[stage]} ══════`);
  const db = await setup(stage);
  snaps[stage] = await snapshot(db);
  // [الوصف، المتصل، اليوم، بعد]
  const who = [
    ['المالك', P.O, true, true], ['المدير', P.A, true, true], ['المراقب', P.MON, true, true],
    ['المشرف', P.S, true, true], ['العضو', P.M, false, false], ['المعلّق', P.PEND, false, false],
    ['مدير مجمّد', P.FA, true, false], ['مراقب مجمّد', P.FM, true, false], ['مدير بحساب منقول', MOVED, false, true],
  ];
  const writer = r => ['المالك', 'المدير', 'المراقب', 'مدير مجمّد', 'مراقب مجمّد', 'مدير بحساب منقول'].includes(r);

  console.log('— home_sections_write (المالك · المدير · المراقب):');
  for (const [label, w, today, then] of who) {
    const exp = (after ? then : today) && writer(label) && label !== 'المشرف';
    const r = await as(db, w, `insert into home_sections(title) values ('${label}')`);
    check(`${label} يضيف قسماً: ${exp ? 'يمر' : 'مرفوض'}`, exp ? r.ok : !r.ok, r.err ?? '');
    const u = await as(db, w, `update home_sections set title = title where true`);
    check(`${label} يعدّل الأقسام: ${exp ? 'يمر' : 'لا يمس صفاً'}`, u.ok && (exp ? u.n > 0 : u.n === 0), u.err ?? `صفوف ${u.n}`);
  }

  for (const [tbl, rows] of [['web_sessions', 2], ['web_push_subscriptions', 1]]) {
    console.log(`— ${tbl} (قراءة الإدارة: المالك · المدير · المراقب · المشرف):`);
    for (const [label, w, today, then] of who) {
      const exp = after ? then : today;
      const r = await as(db, w, `select id from ${tbl}`);
      const own = label === 'العضو' ? 1 : label === 'المعلّق' && tbl === 'web_sessions' ? 1 : 0;
      check(`${label} يقرأ جلسات الكل: ${exp ? 'نعم' : 'لا'}`, r.ok && r.n === (exp ? rows : own), r.err ?? `صفوف ${r.n}`);
    }
  }

  console.log('— web_relatives (قراءة: الإدارة الأربعة · كتابة: المالك · المدير · المراقب):');
  for (const [label, w, today, then] of who) {
    // web_relatives كانت تقرأ app_metadata من الـ JWT فالمنقول يمر قبل التعديل أيضاً
    const expRead = label === 'مدير بحساب منقول' ? true : (after ? then : today);
    const r = await as(db, w, `select id from web_relatives where name = 'قريب'`);
    check(`${label} يقرأ أقارب الموقع: ${expRead ? 'نعم' : 'لا'}`, r.ok && r.n === (expRead ? 1 : 0), r.err ?? `صفوف ${r.n}`);
    const expWrite = expRead && label !== 'المشرف';
    const w2 = await as(db, w, `insert into web_relatives(man_id, name) values ('${P.M}', '${label}')`);
    check(`${label} يضيف قريباً: ${expWrite ? 'يمر' : 'مرفوض'}`, expWrite ? w2.ok : !w2.ok, w2.err ?? '');
  }
  await db.close();
}
check('التراجع يعيد السياسات الخمس حرفياً كما على الحي', snaps.before === snaps.rolledback);
check('التعديل غيّر فعلاً', snaps.before !== snaps.after);
console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
