// تجربة حراس «ربط بالشجرة» على قاعدة محلية معزولة (لا تلمس السيرفر).
// التشغيل: cd supabase/tests/family_links && node merge_guards.test.mjs
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
const chain = ['20261001150000_protect_family_links', '20261001190000_carry_own_women_node_links', '20261004150000_notifications_start_at_login']
  .map(n => readFileSync(`${REPO}/migrations/${n}.sql`, 'utf8'));
const guard = readFileSync(`${REPO}/migrations/20261004180000_merge_guard_live_accounts.sql`, 'utf8');
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const P = { O: id(1), G: id(2), LIVE: id(3), MON: id(4), TREE: id(5), N1: id(7), N2: id(8), N3: id(9), ADM: id(10), TREE2: id(11) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };
for (const stage of ['before', 'after']) {
  console.log(`\n══════ ${stage === 'before' ? 'قبل الحراس (السيرفر قبل اليوم)' : 'بعد الحراس'} ══════`);
  const db = new PGlite();
  await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers);
  for (const m of chain) await db.exec(m);
  if (stage === 'after') await db.exec(guard);
  const q = async (s, p) => (await db.query(s, p)).rows;
  await db.exec(`
    insert into profiles(id, first_name, full_name, gender, role, status) values
      ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active'),
      ('${P.G}', 'صلاح', 'صلاح الجد', 'male', 'member', 'active');
    insert into women_members(id, first_name, full_name, gender) values ('${P.G}', 'صلاح', 'صلاح الجد', 'male');
    insert into profiles(id, first_name, full_name, gender, role, status, father_id) values
      ('${P.LIVE}', 'حسن', 'حسن صلاح', 'male', 'member', 'active', '${P.G}'),
      ('${P.MON}', 'علي', 'علي صلاح', 'male', 'monitor', 'active', '${P.G}'),
      ('${P.TREE}', 'طاهر', 'طاهر صلاح', 'male', 'member', 'active', '${P.G}'),
      ('${P.TREE2}', 'ناصر', 'ناصر صلاح', 'male', 'member', 'active', '${P.G}'),
      ('${P.ADM}', 'بدر', 'بدر صلاح', 'male', 'admin', 'active', '${P.G}');
    insert into profiles(id, first_name, full_name, gender, role, status) values
      ('${P.N1}', 'حسن', 'حسن (تسجيل)', 'male', 'pending', 'pending'),
      ('${P.N2}', 'علي', 'علي (تسجيل)', 'male', 'pending', 'pending'),
      ('${P.N3}', 'طاهر', 'طاهر (تسجيل)', 'male', 'pending', 'pending');
    insert into auth.users(id) values ('${P.O}'), ('${P.LIVE}'), ('${P.MON}'), ('${P.ADM}'), ('${P.N1}'), ('${P.N2}'), ('${P.N3}');
    insert into device_tokens(member_id, token) values ('${P.LIVE}', 'tok-live-000000000000000000');`);
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: P.O, role: 'authenticated' })]);
  const merge = async (n, t) => (await q(`select public.merge_member_into_tree($1, $2) r`, [n, t]))[0].r;
  const exists = async x => (await q(`select 1 from profiles where id = $1`, [x])).length === 1;
  const after = stage === 'after';

  const r1 = await merge(P.N1, P.LIVE);
  check(`دمج في ملف عضو له حساب دخول: ${after ? 'مرفوض' : 'يُقبل ويُحذف ملفه (الخلل)'}`, after ? r1.success === false && await exists(P.LIVE) : r1.success === true && !(await exists(P.LIVE)), r1.message);
  const r2 = await merge(P.N2, P.MON);
  check(`دمج في ملف مراقب: ${after ? 'مرفوض' : 'يُقبل (الخلل)'}`, after ? r2.success === false && await exists(P.MON) : r2.success === true, r2.message);
  const r3 = await merge(P.ADM, P.TREE2);
  const admRole = (await q(`select role from profiles where id = $1`, [P.ADM]))[0]?.role;
  check(`دمج حساب مدير في سجل شجرة: ${after ? 'مرفوض ودوره باقٍ' : 'يُقبل وينزل دوره (الخلل)'}`, after ? r3.success === false && admRole === 'admin' : r3.success === true && admRole === 'member', `${r3.message} · الدور=${admRole}`);
  const r4 = await merge(P.N3, P.TREE);
  check('الدمج العادي (تسجيل معلّق ← سجل شجرة بلا دخول) ما زال يعمل', r4.success === true && !(await exists(P.TREE)), r4.message);
}
console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
