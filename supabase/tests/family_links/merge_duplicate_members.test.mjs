// تجربة 20261127240000_merge_duplicate_members («دمج» في «المكرر والأخطاء»، موافقة المالك ٢٠٢٦-١١-٢٧) على قاعدة محلية
// معزولة (لا تلمس السيرفر): فوق حماية روابط العائلة (20261001150000 + 20261001190000) + profile_has_login الحي،
// ومشغّل إشعار «عدّلت الإدارة بياناتك» بنسخة مصغّرة تحترم family.merging كما في الحي (notify_member_change).
// قبل الترحيل (الدالة غير موجودة) ← بعده (الحراس، المعاينة، النقل، الملء والتعارض، شجرة النساء) ← بعد التراجع.
// التشغيل: cd supabase/tests/family_links && node merge_duplicate_members.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? '', (e.query ?? '').slice(0, 300)); process.exit(2); });
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody, rest] = base.split('-- ─── المشغّلات');
const baseTriggers = rest.slice(rest.indexOf('\n') + 1);
const grab = (src, name) => { const i = src.indexOf(`create or replace function public.${name}(`); return src.slice(i, src.indexOf('$function$;', i) + '$function$;'.length); };
const preFns = ['adopt_tree_profile', 'merge_member_into_tree', 'women_auto_merge_wife']
  .map(n => grab(readFileSync(`${REPO}/rollback/20261001150000_protect_family_links_rollback.sql`, 'utf8'), n)).join('\n\n');
const chain = ['20261001150000_protect_family_links', '20261001190000_carry_own_women_node_links']
  .map(n => readFileSync(`${REPO}/migrations/${n}.sql`, 'utf8'));
const MIG = '20261127240000_merge_duplicate_members';
const mig = readFileSync(`${REPO}/migrations/${MIG}.sql`, 'utf8');
const rb = readFileSync(`${REPO}/rollback/${MIG}_rollback.sql`, 'utf8');

// نسخ الحي لما تلمسه الدالة (أعمدة وجداول ودوال مساعدة)
const live = `
alter table public.notifications add column subject_member_id uuid references public.profiles(id) on delete set null;
alter table public.women_members add column hidden_children uuid[];
create table public.death_marks (member_id uuid primary key, marked_at timestamptz default now());
create table public.join_requests (id uuid primary key default gen_random_uuid(), suggested_father_id uuid);
create or replace function public.profile_has_login(p_id uuid) returns boolean language sql stable security definer
  set search_path to '' as $$
  select exists (select 1 from auth.users u where u.id = p_id or u.raw_app_meta_data ->> 'profile_id' = p_id::text); $$;
create or replace function public.review_account_ids() returns uuid[] language sql stable as $$ select '{}'::uuid[] $$;
-- notify_member_change (مصغّر): «عدّلت الإدارة بياناتك» للعضو حين تعدّل الإدارة سجله — إلا أثناء نقل سجل (family.merging)
create or replace function public.notify_member_change() returns trigger language plpgsql security definer
  set search_path to '' as $function$
declare v_actor uuid := public.current_profile_id();
begin
  if current_setting('family.merging', true) = 'on' then return null; end if;
  if v_actor is null or v_actor = new.id then return null; end if;
  if new is distinct from old then
    insert into public.notifications (target_member_id, title, body, kind, created_by, subject_member_id)
    values (new.id, 'عدّلت الإدارة بياناتك', 'تغيّر', 'my_profile_change', v_actor, new.id);
  end if;
  return null;
end; $function$;
create trigger trg_zz_notify_member_change after update on public.profiles for each row execute function public.notify_member_change();
grant usage on schema auth to authenticated, anon;
grant select on all tables in schema public to authenticated;
`;

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
// O مالك · ADM مدير · MON مراقب · MEM عضو · G الجد · G2 جد آخر
// K/R «حسن» مكرّران تحت G (R له ابنان وبنت وزوجة وأم) · K2/R2 تعارض الميلاد · KL (له حساب) /R3 · RL له حساب · RS مراقب
// S1 ابن R (له حساب) · S2 ابن R · D1 بنت R · W1 زوجة R · MOM أم R · OX ابن G2 (أب مختلف)
// شجرة النساء: F أب · WA/WB «سارة» مكرّرتان (WB أم C1، ميلاد) · WL لها حساب · WC بنت أخرى
const P = { O: id(1), ADM: id(2), MON: id(3), MEM: id(4), G: id(5), G2: id(6), K: id(10), R: id(11), K2: id(12), R2: id(13),
  KL: id(14), R3: id(15), RL: id(16), RS: id(17), S1: id(20), S2: id(21), D1: id(22), W1: id(23), MOM: id(24), OX: id(25),
  F: id(30), WA: id(31), WB: id(32), WL: id(33), C1: id(34), WC: id(35), GAL: id(40), REQ: id(41), N1: id(42), N2: id(43) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

const db = new PGlite();
await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers);
for (const m of chain) await db.exec(m);
await db.exec(live);
await db.exec(`
  insert into profiles(id, first_name, full_name, gender, role, status) values
    ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active'),
    ('${P.ADM}', 'مدير', 'المدير', 'male', 'admin', 'active'),
    ('${P.MON}', 'مراقب', 'المراقب', 'male', 'monitor', 'active'),
    ('${P.MEM}', 'عضو', 'العضو', 'male', 'member', 'active'),
    ('${P.G}', 'صالح', 'صالح الجد', 'male', 'member', 'active'),
    ('${P.G2}', 'ناصر', 'ناصر الجد', 'male', 'member', 'active'),
    ('${P.F}', 'خالد', 'خالد', 'male', 'member', 'active');
  -- عقد الآباء في شجرة النساء (المرآة لا تنشئها لمن بلا أب)
  insert into women_members(id, first_name, full_name, gender) values
    ('${P.G}', 'صالح', 'صالح الجد', 'male'), ('${P.G2}', 'ناصر', 'ناصر الجد', 'male'), ('${P.F}', 'خالد', 'خالد', 'male');
  insert into profiles(id, first_name, full_name, gender, role, status, father_id, birth_date) values
    ('${P.K}', 'حسن', 'حسن صالح', 'male', 'member', 'active', '${P.G}', null),
    ('${P.R}', 'حسن', 'حسن صالح الجد', 'male', 'member', 'active', '${P.G}', '1950-01-01'),
    ('${P.K2}', 'علي', 'علي صالح', 'male', 'member', 'active', '${P.G}', '1960-01-01'),
    ('${P.R2}', 'علي', 'علي صالح', 'male', 'member', 'active', '${P.G}', '1961-05-05'),
    ('${P.KL}', 'بدر', 'بدر صالح', 'male', 'member', 'active', '${P.G}', null),
    ('${P.R3}', 'بدر', 'بدر صالح', 'male', 'member', 'active', '${P.G}', null),
    ('${P.RL}', 'بدر', 'بدر صالح ٢', 'male', 'member', 'active', '${P.G}', null),
    ('${P.RS}', 'بدر', 'بدر صالح ٣', 'male', 'monitor', 'active', '${P.G}', null),
    ('${P.OX}', 'حسن', 'حسن ناصر', 'male', 'member', 'active', '${P.G2}', null),
    ('${P.S1}', 'يوسف', 'يوسف حسن', 'male', 'member', 'active', '${P.R}', null),
    ('${P.S2}', 'عمر', 'عمر حسن', 'male', 'member', 'active', '${P.R}', null);
  update profiles set sons_ids = array['${P.K}', '${P.R}']::uuid[] where id = '${P.G}';
  insert into women_members(id, first_name, full_name, parent_id, gender) values
    ('${P.MOM}', 'فاطمة', 'فاطمة ناصر', '${P.G2}', 'female'),
    ('${P.D1}', 'مريم', 'مريم حسن', '${P.R}', 'female'),
    ('${P.WA}', 'سارة', 'سارة خالد', '${P.F}', 'female'),
    ('${P.WB}', 'سارة', 'سارة خالد', '${P.F}', 'female'),
    ('${P.WC}', 'هند', 'هند خالد', '${P.F}', 'female');
  insert into women_members(id, first_name, full_name, parent_id, gender, linked_user_id) values
    ('${P.WL}', 'سارة', 'سارة خالد ٢', '${P.F}', 'female', '${P.MEM}');
  insert into women_members(id, first_name, full_name, husband_id, gender) values ('${P.W1}', 'نورة', 'نورة', '${P.R}', 'female');
  insert into women_members(id, first_name, full_name, mother_id, parent_id, gender) values ('${P.C1}', 'جود', 'جود', '${P.WB}', '${P.G2}', 'female');
  update women_members set mother_id = '${P.MOM}' where id = '${P.R}';
  update women_members set birth_date = '1980-02-02' where id = '${P.WB}';
  update women_members set hidden_children = array['${P.D1}', '${P.R}']::uuid[] where id = '${P.G}';
  insert into member_gallery_photos(id, member_id) values ('${P.GAL}', '${P.R}');
  insert into admin_requests(id, member_id, requester_id, request_type, status) values ('${P.REQ}', '${P.R}', '${P.MON}', 'tree_edit', 'pending');
  insert into notifications(id, target_member_id, title, kind) values ('${P.N1}', '${P.R}', 'قديم', 'x');
  insert into notifications(id, target_member_id, title, kind, subject_member_id) values ('${P.N2}', '${P.O}', 'عن حسن', 'admin_edit', '${P.R}');
  insert into death_marks(member_id) values ('${P.R}');
  insert into join_requests(suggested_father_id) values ('${P.R}');
  insert into auth.users(id) values ('${P.O}'), ('${P.ADM}'), ('${P.MON}'), ('${P.MEM}'), ('${P.S1}'), ('${P.KL}');
  insert into auth.users(id, raw_app_meta_data) values (gen_random_uuid(), jsonb_build_object('profile_id', '${P.RL}'));`);

async function as(who, sql, params = []) {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: who, role: 'authenticated' })]);
  await db.exec('set role authenticated');
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, code: e.code, hint: e.hint }; }
  finally { await db.exec('reset role'); }
}
const merge = (who, keep, remove, dry = false) => as(who, `select public.merge_duplicate_members($1, $2, $3) r`, [keep, remove, dry]);
const one = async (sql, p = []) => (await db.query(sql, p)).rows[0];
const exists = async (tbl, x) => (await db.query(`select 1 from ${tbl} where id = $1`, [x])).rows.length === 1;

// ─── قبل الترحيل ───
const before = await merge(P.ADM, P.K, P.R);
check('قبل الترحيل: الدالة غير موجودة', !before.ok && /does not exist/.test(before.err), before.err);

await db.exec(mig);
console.log('\n══════ بعد الترحيل ══════');

// ─── الصلاحيات ───
const asMem = await merge(P.MEM, P.K, P.R);
check('العضو: مرفوض 42501', !asMem.ok && asMem.code === '42501', asMem.err);
const asMon = await merge(P.MON, P.K, P.R);
check('المراقب: مرفوض 42501 (المالك والمدير فقط)', !asMon.ok && asMon.code === '42501', asMon.err);
const anon = await one(`select has_function_privilege('anon', 'public.merge_duplicate_members(uuid,uuid,boolean)', 'execute') a`);
check('غير المسجّل لا ينفّذها', anon.a === false);
const fn = await one(`select prosecdef s, proconfig c from pg_proc where proname = 'merge_duplicate_members'`);
check('SECURITY DEFINER و search_path فارغ', fn.s === true && (fn.c ?? []).some(x => /search_path=("")?$/.test(x)), JSON.stringify(fn.c));

// ─── الحراس ───
const expectHint = async (label, keep, remove, hint) => {
  const r = await merge(P.ADM, keep, remove);
  check(label, !r.ok && r.hint === hint && r.code === 'P0001', `${r.hint} · ${r.err}`);
};
await expectHint('الشخص نفسه: same_member', P.K, P.K, 'same_member');
await expectHint('أب مختلف: different_father', P.K, P.OX, 'different_father');
await expectHint('المحذوف له حساب (auth.users): remove_has_login', P.K, P.KL, 'remove_has_login');
await expectHint('المحذوف له حساب (profile_id في app_metadata): remove_has_login', P.K, P.RL, 'remove_has_login');
await expectHint('الاثنان لهما حساب: both_have_login', P.KL, P.RL, 'both_have_login');
await expectHint('المحذوف من الإدارة: staff_member', P.K, P.RS, 'staff_member');
await expectHint('المُبقى من الإدارة: staff_member', P.RS, P.R3, 'staff_member');
await expectHint('غير موجود: not_found', P.K, id(999), 'not_found');
await expectHint('رجل وامرأة: not_same_tree', P.K, P.WB, 'not_same_tree');
await expectHint('شجرة النساء — لها حساب: remove_has_login', P.WA, P.WL, 'remove_has_login');
await expectHint('شجرة النساء — عقدة رجل منسوخة: not_same_tree', P.WA, P.F, 'not_same_tree');
await expectHint('شجرة النساء — أصل مختلف: different_father', P.WA, P.MOM, 'different_father');

// ─── المعاينة (dry run) لا تغيّر شيئاً ───
const histBase = (await one(`select coalesce(max(id), 0)::int n from family_link_history`)).n;
const dry = await merge(P.O, P.K, P.R, true);
const d = dry.rows?.[0]?.r ?? {};
check('المعاينة: نجاح بالأعداد', dry.ok && d.dry_run === true && d.moved_children === 2 && d.moved_daughters === 1 && d.moved_wives === 1,
  JSON.stringify(d));
check('المعاينة: ما سيُملأ (الميلاد، الأم)', (d.filled ?? []).includes('birth_date') && (d.filled ?? []).includes('mother_id'), JSON.stringify(d.filled));
check('المعاينة: لا شيء تغيّر', await exists('profiles', P.R) && (await one(`select father_id from profiles where id = $1`, [P.S1])).father_id === P.R
  && (await one(`select birth_date from profiles where id = $1`, [P.K])).birth_date === null
  && (await one(`select coalesce(max(id), 0)::int n from family_link_history`)).n === histBase);
const merging = await one(`select coalesce(current_setting('family.merging', true), '') m`);
check('المعاينة: family.merging لا يبقى مفعّلاً', merging.m !== 'on', merging.m);

// ─── الدمج الفعلي ───
const real = await merge(P.ADM, P.K, P.R);
const r = real.rows?.[0]?.r ?? {};
check('الدمج: نجاح', real.ok && r.kept === P.K && r.removed === P.R && r.dry_run === false, real.err ?? JSON.stringify(r));
check('الدمج: الأعداد', r.moved_children === 2 && r.moved_daughters === 1 && r.moved_wives === 1 && r.moved_women === 2, JSON.stringify(r));
check('المكرر حُذف من الملفات وشجرة النساء', !(await exists('profiles', P.R)) && !(await exists('women_members', P.R)));
const sons = (await db.query(`select id, father_id from profiles where id in ($1, $2)`, [P.S1, P.S2])).rows;
check('الأبناء انتقلوا (profiles.father_id)', sons.length === 2 && sons.every(s => s.father_id === P.K));
const sonNodes = (await db.query(`select parent_id from women_members where id in ($1, $2)`, [P.S1, P.S2])).rows;
check('عقد الأبناء في شجرة النساء انتقلت', sonNodes.length === 2 && sonNodes.every(s => s.parent_id === P.K));
check('البنت انتقلت (women_members.parent_id)', (await one(`select parent_id from women_members where id = $1`, [P.D1])).parent_id === P.K);
check('الزوجة انتقلت (women_members.husband_id)', (await one(`select husband_id from women_members where id = $1`, [P.W1])).husband_id === P.K);
check('الأم انتقلت لعقدة المُبقى', (await one(`select mother_id from women_members where id = $1`, [P.K])).mother_id === P.MOM);
const kp = await one(`select birth_date::text b from profiles where id = $1`, [P.K]);
check('الميلاد مُلئ من المكرر', kp.b === '1950-01-01', kp.b);
const g = await one(`select sons_ids from profiles where id = $1`, [P.G]);
check('sons_ids بلا المكرر ولا تكرار', JSON.stringify(g.sons_ids) === JSON.stringify([P.K]), JSON.stringify(g.sons_ids));
const hc = await one(`select hidden_children from women_members where id = $1`, [P.G]);
check('hidden_children: المكرر صار المُبقى', hc.hidden_children.includes(P.K) && !hc.hidden_children.includes(P.R), JSON.stringify(hc.hidden_children));
check('الصورة انتقلت (member_gallery_photos)', (await one(`select member_id from member_gallery_photos where id = $1`, [P.GAL])).member_id === P.K);
check('الطلب انتقل (admin_requests.member_id)', (await one(`select member_id from admin_requests where id = $1`, [P.REQ])).member_id === P.K);
check('إشعارات المكرر نفسه حُذفت (لا تصل للمُبقى)', !(await exists('notifications', P.N1)));
check('الإشعار عنه انتقل (subject_member_id)', (await one(`select subject_member_id from notifications where id = $1`, [P.N2])).subject_member_id === P.K);
check('death_marks انتقل', (await one(`select count(*)::int n from death_marks where member_id = $1`, [P.K])).n === 1);
check('join_requests.suggested_father_id انتقل', (await one(`select count(*)::int n from join_requests where suggested_father_id = $1`, [P.K])).n === 1);
const notified = await one(`select count(*)::int n from notifications where kind = 'my_profile_change'`);
check('لا إشعار لأي عضو', notified.n === 0, String(notified.n));
const hist = await one(`select count(*)::int n, count(*) filter (where actor = '${P.ADM}')::int a, count(*) filter (where blocked)::int b from family_link_history where id > ${histBase}`);
check('كل تغيير رابط مسجّل باسم المدير، بلا محاولة مُنعت', hist.n >= 4 && hist.a === hist.n && hist.b === 0, JSON.stringify(hist));
check('family.merging لا يبقى مفعّلاً بعد الدمج', (await one(`select coalesce(current_setting('family.merging', true), '') m`)).m !== 'on');

// ─── التعارض ───
const cf = await merge(P.O, P.K2, P.R2);
const c = cf.rows?.[0]?.r ?? {};
check('تعارض الميلاد: يُسمح ويُذكر', cf.ok && (c.conflicts ?? []).some(x => x.field === 'birth_date') && !(c.filled ?? []).includes('birth_date'), JSON.stringify(c));
const k2 = await one(`select birth_date::text b from profiles where id = $1`, [P.K2]);
check('تعارض الميلاد: لا يُكتب فوق ميلاد المُبقى', k2.b === '1960-01-01', k2.b);

// ─── المُبقى له حساب ───
const kl = await merge(P.ADM, P.KL, P.R3);
check('المُبقى له حساب: يُسمح', kl.ok && !(await exists('profiles', P.R3)) && await exists('profiles', P.KL), kl.err);

// ─── شجرة النساء ───
const wdry = await merge(P.ADM, P.WA, P.WB, true);
check('شجرة النساء — المعاينة', wdry.ok && wdry.rows[0].r.tree === 'women' && wdry.rows[0].r.moved_children === 1, JSON.stringify(wdry.rows?.[0]?.r ?? wdry.err));
const w = await merge(P.ADM, P.WA, P.WB);
const wr = w.rows?.[0]?.r ?? {};
check('شجرة النساء — نجاح وحذف المكررة', w.ok && !(await exists('women_members', P.WB)), w.err ?? JSON.stringify(wr));
check('شجرة النساء — ابنتها انتقلت (mother_id)', (await one(`select mother_id from women_members where id = $1`, [P.C1])).mother_id === P.WA);
const wa = await one(`select birth_date::text b from women_members where id = $1`, [P.WA]);
check('شجرة النساء — الميلاد مُلئ', (wr.filled ?? []).includes('birth_date') && wa.b === '1980-02-02', wa.b);

// ─── التراجع ───
await db.exec(rb);
const gone = await merge(P.ADM, P.WA, P.WC);
check('بعد التراجع: الدالة غير موجودة', !gone.ok && /does not exist/.test(gone.err), gone.err);

console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
