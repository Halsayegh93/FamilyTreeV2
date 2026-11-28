// تجربة 20261127180000_join_completion_ask على قاعدة محلية معزولة (لا تلمس السيرفر):
//   «طلب استكمال البيانات» من مربّعات «الوارد» — الإدارة تحدّد الناقص ← إشعار رسمي للعضو ← العضو يرسل من جديد،
//   والطلب يبقى معلّقاً، ثم التراجع.
// التشغيل: cd supabase/tests/family_links && node join_completion_ask.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message); process.exit(2); });
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody, rest] = base.split('-- ─── المشغّلات');
const baseTriggers = rest.slice(rest.indexOf('\n') + 1);
const grab = (src, name) => { const i = src.indexOf(`create or replace function public.${name}(`); return src.slice(i, src.indexOf('$function$;', i) + '$function$;'.length); };
const preFns = ['adopt_tree_profile', 'merge_member_into_tree', 'women_auto_merge_wife']
  .map(n => grab(readFileSync(`${REPO}/rollback/20261001150000_protect_family_links_rollback.sql`, 'utf8'), n)).join('\n\n');
const mig = readFileSync(`${REPO}/migrations/20261127180000_join_completion_ask.sql`, 'utf8');
const undo = readFileSync(`${REPO}/rollback/20261127180000_join_completion_ask_rollback.sql`, 'utf8');

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
// O مالك · AD مدير · MON مراقب · S مشرف · M عضو · J1 منضمّ معلّق (من العائلة) · J2 منضمّ ثانٍ · L عضو محدود بطلب نسب
const P = { O: id(1), AD: id(2), MON: id(3), S: id(4), M: id(5), J1: id(20), J2: id(21), L: id(22) };
const R = { j1: id(101), j2: id(102), lin: id(103), done: id(104), other: id(105) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

const db = new PGlite();
await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers);
await db.exec(`
  alter table public.admin_requests add column if not exists details text, add column if not exists admin_reply text,
    add column if not exists created_at timestamptz default now();
  grant usage on schema auth to authenticated;
  grant select on all tables in schema public to authenticated;
  insert into profiles(id, first_name, full_name, gender, role, status, birth_date, family_name) values
    ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active', null, null),
    ('${P.AD}', 'مدير', 'المدير', 'male', 'admin', 'active', null, null),
    ('${P.MON}', 'مراقب', 'المراقب', 'male', 'monitor', 'active', null, null),
    ('${P.S}', 'مشرف', 'المشرف', 'male', 'supervisor', 'active', null, null),
    ('${P.M}', 'عضو', 'عضو', 'male', 'member', 'active', null, null),
    ('${P.J1}', 'سالم', 'سالم', 'male', 'pending', 'pending', null, 'المحمدعلي'),
    ('${P.J2}', 'هند', 'هند خالد', 'female', 'pending', 'pending', '2000-01-01', 'المحمدعلي'),
    ('${P.L}', 'محمد', 'محمد حسن حسين الموسى', 'male', 'member', 'active', '2003-01-01', 'الموسى');
  insert into admin_requests(id, member_id, requester_id, request_type, status, details) values
    ('${R.j1}', '${P.J1}', '${P.J1}', 'join_request', 'pending', 'طلب انضمام جديد|family_signup:1'),
    ('${R.j2}', '${P.J2}', '${P.J2}', 'link_request', 'pending', 'طلب ربط|family_signup:1'),
    ('${R.lin}', '${P.L}', '${P.L}', 'lineage_request', 'pending',
      '{"v":4,"kind":"outside_typed","mother_typed_name":"فاطمة","mother_family":"المحمدعلي","mother_name":"فاطمة المحمدعلي","father_name":"حسن حسين الموسى"}'),
    ('${R.done}', '${P.J2}', '${P.J2}', 'join_request', 'approved', null),
    ('${R.other}', '${P.M}', '${P.M}', 'name_change', 'pending', null);
  insert into auth.users(id) values ('${P.O}'), ('${P.AD}'), ('${P.MON}'), ('${P.S}'), ('${P.M}'), ('${P.J1}'), ('${P.J2}'), ('${P.L}');`);

async function as(who, sql, params = []) {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: who, role: 'authenticated' })]);
  await db.exec('set role authenticated');
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint }; }
  finally { await db.exec('reset role'); }
}
const ask = (who, req, fields, note = null) => as(who, `select public.ask_join_completion($1, $2::text[], $3) as id`, [req, fields, note]);
const mine = async who => (await as(who, `select public.my_completion_ask() as a`)).rows?.[0]?.a ?? null;
const answer = (who, values) => as(who, `select public.answer_completion_ask($1::jsonb)`, [JSON.stringify(values)]);
const req = async rid => (await db.query(`select * from admin_requests where id = $1`, [rid])).rows[0];
const notes = async (to, kind) => (await db.query(`select * from notifications where target_member_id = $1 and kind = $2 order by created_at`, [to, kind])).rows;

console.log('\n══════ قبل الإضافة ══════');
check('الدالة غير موجودة', !(await ask(P.O, R.j1, ['full_name'])).ok);

await db.exec(mig);
console.log('\n══════ بعد الإضافة ══════');
let r = await ask(P.S, R.j1, ['full_name']);
check('المشرف مرفوض', !r.ok && r.hint === 'not_allowed', r.hint ?? '');
r = await ask(P.M, R.j1, ['full_name']);
check('العضو مرفوض', !r.ok && r.hint === 'not_allowed', r.hint ?? '');
r = await ask(P.J1, R.j1, ['full_name']);
check('صاحب الطلب لا يطلب لنفسه', !r.ok && r.hint === 'not_allowed', r.hint ?? '');
r = await ask(P.O, R.j1, []);
check('بلا حقول مرفوض', !r.ok && r.hint === 'fields_required', r.hint ?? '');
r = await ask(P.O, R.j1, ['mother_name']);
check('اسم الوالدة ليس لطلب الانضمام', !r.ok && r.hint === 'bad_field', r.hint ?? '');
r = await ask(P.O, R.lin, ['birth_date']);
check('تاريخ الميلاد ليس لطلب النسب', !r.ok && r.hint === 'bad_field', r.hint ?? '');
r = await ask(P.O, R.done, ['full_name']);
check('طلب عولج من قبل', !r.ok && r.hint === 'already_handled', r.hint ?? '');
r = await ask(P.O, R.other, ['full_name']);
check('نوع طلب آخر مرفوض', !r.ok && r.hint === 'request_not_found', r.hint ?? '');
r = await ask(P.O, R.j1, ['full_name'], 'x'.repeat(201));
check('ملاحظة أطول من ٢٠٠ مرفوضة', !r.ok && r.hint === 'note_too_long', r.hint ?? '');
check('العضو لا يقرأ الجدول مباشرة', !(await as(P.J1, `select * from join_completion_asks`)).ok);

r = await ask(P.MON, R.j1, ['full_name', 'birth_date', 'full_name'], '  الاسم ناقص  ');
check('المراقب يطلب استكمال الاسم والميلاد', r.ok, r.err ?? '');
let n = await notes(P.J1, 'join_completion');
check('إشعار رسمي «يُرجى استكمال البيانات: …»', n.length === 1 && n[0].title === 'يُرجى استكمال البيانات'
  && n[0].body === 'يُرجى استكمال البيانات: الاسم الرباعي، تاريخ الميلاد.\nالاسم ناقص', n[0]?.body);
check('الطلب يبقى معلّقاً', (await req(R.j1)).status === 'pending');
let a = await mine(P.J1);
check('العضو يرى المطلوب (بلا تكرار)', a && a.kind === 'join' && JSON.stringify(a.fields) === '["full_name","birth_date"]' && a.note === 'الاسم ناقص',
  JSON.stringify(a));
check('غيره لا يرى طلبه', (await mine(P.J2)) === null);

r = await ask(P.AD, R.j1, ['full_name', 'gender']);
a = await mine(P.J1);
check('الطلب الجديد يحلّ محلّ القديم', r.ok && JSON.stringify(a.fields) === '["full_name","gender"]', JSON.stringify(a));
check('طلب مفتوح واحد', (await db.query(`select count(*)::int c from join_completion_asks where request_id = $1 and answered_at is null`, [R.j1])).rows[0].c === 1);

r = await answer(P.J1, {});
check('الاسم ما زال ناقصاً ← يُرفض', !r.ok && r.hint === 'missing_value', r.err ?? '');
await db.exec(`update profiles set full_name = 'سالم ناصر فهد علي' where id = '${P.J1}'`);
r = await answer(P.J1, {});
check('بعد حفظ الاسم: الجنس موجود ← يُقبل', r.ok, r.err ?? '');
check('الطلب أُغلق', (await mine(P.J1)) === null);
check('الطلب نفسه ما زال معلّقاً للإدارة', (await req(R.j1)).status === 'pending');
check('الإدارة (المالك والمدير والمراقب) بُلّغت', (await db.query(`select count(*)::int c from notifications where title = 'تم استكمال البيانات'`)).rows[0].c === 3);
r = await answer(P.J1, {});
check('لا طلب مفتوح ← no_ask', !r.ok && r.hint === 'no_ask', r.hint ?? '');

// استكمال التسجيل: اسم الوالدة
r = await ask(P.O, R.lin, ['mother_name'], 'يُرجى كتابة الاسم الرباعي');
a = await mine(P.L);
check('طلب النسب: kind = lineage', r.ok && a?.kind === 'lineage' && a.fields[0] === 'mother_name', JSON.stringify(a));
r = await answer(P.L, { mother_name: '  ' });
check('اسم الوالدة فارغ مرفوض', !r.ok && r.hint === 'name_required', r.hint ?? '');
r = await answer(P.L, { mother_name: 'فاطمة' });
check('كلمة واحدة مرفوضة', !r.ok && r.hint === 'name_required', r.hint ?? '');
r = await answer(P.L, { mother_name: 'فاطمة  عبدالله أحمد صالح' });
const lin = await req(R.lin);
const d = JSON.parse(lin.details);
check('الاسم يُكتب في الطلب المعلّق نفسه', r.ok && d.mother_typed_name === 'فاطمة عبدالله أحمد صالح'
  && d.mother_name === 'فاطمة عبدالله أحمد صالح المحمدعلي' && d.kind === 'outside_typed' && d.father_name === 'حسن حسين الموسى', r.err ?? lin.details);
check('طلب النسب ما زال معلّقاً', lin.status === 'pending');

// طلب عولج بعد السؤال: لا يظهر للعضو
await ask(P.O, R.j2, ['photo']);
check('الصورة مطلوبة ← يظهر', JSON.stringify((await mine(P.J2))?.fields) === '["photo"]');
await db.exec(`update admin_requests set status = 'approved' where id = '${R.j2}'`);
check('الطلب عولج ← لا يظهر', (await mine(P.J2)) === null);

await db.exec(undo);
console.log('\n══════ بعد التراجع ══════');
check('الدوال حُذفت', !(await ask(P.O, R.j1, ['full_name'])).ok);
check('الجدول حُذف', (await db.query(`select to_regclass('public.join_completion_asks') t`)).rows[0].t === null);
check('الطلبات باقية', (await req(R.j1)).status === 'pending');

console.log(`\n${pass} نجح · ${fail} فشل`);
process.exit(fail ? 1 : 0);
