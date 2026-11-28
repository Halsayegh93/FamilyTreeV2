// تجربة 20261127130000_family_tree_men_only (شجرة العائلة للرجال فقط — البنت في شجرة النساء) على قاعدة محلية
// معزولة (لا تلمس السيرفر): فوق الحي — حماية روابط العائلة (20261001150000) + add_family_child و move_child_gender
// بنسختهما الحية (٢٠٢٦-١١-٢٧). قبل الحارس (الثغرة) ← بعده ← بعد التراجع.
// التشغيل: cd supabase/tests/family_links && node family_tree_men_only.test.mjs
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
const links = readFileSync(`${REPO}/migrations/20261001150000_protect_family_links.sql`, 'utf8');
const MIG = '20261127130000_family_tree_men_only';
const mig = readFileSync(`${REPO}/migrations/${MIG}.sql`, 'utf8');
const rb = readFileSync(`${REPO}/rollback/${MIG}_rollback.sql`, 'utf8');

// نسختا الحي (pg_get_functiondef ٢٠٢٦-١١-٢٧) لما يكتب الجنس: add_family_child و move_child_gender — حرفياً.
const live = `
create schema if not exists private;
create table public.app_config (key text primary key, value jsonb);
alter table public.notifications add column subject_member_id uuid;
create or replace function public.child_name_key(t text) returns text language sql immutable as $$ select lower(btrim(coalesce(t, ''))) $$;

CREATE OR REPLACE FUNCTION public.add_family_child(p_parent_id uuid, p_name text, p_gender text DEFAULT 'male'::text, p_birth date DEFAULT NULL::date, p_deceased boolean DEFAULT false, p_death date DEFAULT NULL::date, p_sort integer DEFAULT 0, p_parent_full_name text DEFAULT ''::text)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  g text := lower(coalesce(p_gender, 'male'));
  new_id uuid := gen_random_uuid();
  nm text := trim(coalesce(p_name, ''));
  chained text := case when coalesce(trim(p_parent_full_name), '') = '' then nm else nm || ' ' || trim(p_parent_full_name) end;
  my_role text := coalesce(public.current_user_role(), '');
  me uuid := public.current_profile_id();
  staff boolean := my_role in ('owner', 'admin', 'monitor');
  v_limit int; v_today int; me_first text;
begin
  if not (staff or (p_parent_id = any (array[auth.uid(), me]) and my_role in ('member', 'supervisor'))) then
    raise exception 'not_authorized';
  end if;
  if nm = '' then raise exception 'name_required'; end if;
  if g = 'female' then
    insert into public.women_members(id, first_name, full_name, parent_id, gender, is_deceased, birth_date, death_date, sort_order)
    values (new_id, nm, chained, p_parent_id, 'female', coalesce(p_deceased, false), p_birth,
      case when p_deceased then p_death else null end, coalesce(p_sort, 0));
  else
    if not staff then
      if p_parent_id is distinct from me then raise exception 'not_authorized'; end if;
      v_limit := coalesce((select (c.value #>> '{}')::int from public.app_config c where c.key = 'self_child_daily_limit'), 5);
      select count(*) into v_today from public.profiles p
       where p.father_id = me and p.created_at >= date_trunc('day', now() at time zone 'Asia/Kuwait') at time zone 'Asia/Kuwait';
      if v_limit <= 0 or v_today >= v_limit then
        raise exception 'وصلت حد الإضافة اليومي — أكمل غداً أو اطلب من الإدارة' using errcode = '42501', hint = 'daily_limit';
      end if;
      if exists (select 1 from public.profiles p where p.father_id = me
                 and public.child_name_key(p.first_name) = public.child_name_key(nm)) then
        raise exception 'هذا الاسم مسجّل عندك' using errcode = '23505', hint = 'child_duplicate';
      end if;
      perform set_config('family.self_child', 'on', true);
    end if;
    insert into public.profiles(id, first_name, full_name, father_id, gender, status, role,
      is_deceased, birth_date, death_date, sort_order, is_phone_verified, is_hr_member)
    values (new_id, nm, chained, p_parent_id, 'male', 'active', 'member', coalesce(p_deceased, false), p_birth,
      case when p_deceased then p_death else null end, coalesce(p_sort, 0), false, false);
    if not staff then
      perform set_config('family.self_child', '', true);
      me_first := coalesce((select nullif(btrim(p.first_name), '') from public.profiles p where p.id = me), 'عضو');
      insert into public.notifications (target_member_id, title, body, kind, created_by, subject_member_id)
      select p.id, 'إضافة ابن للشجرة', me_first || ' أضاف ابنه «' || nm || '» للشجرة', 'admin_edit_child_add', me, new_id
        from public.profiles p where p.role in ('owner', 'admin') and p.status = 'active' and p.id <> me;
    end if;
  end if;
  return new_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.move_child_gender(p_child_id uuid, p_to_gender text)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  g text := lower(coalesce(p_to_gender, ''));
  pr public.profiles%rowtype; wm public.women_members%rowtype; new_id uuid;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor') then raise exception 'not_authorized'; end if;
  if g = 'female' then
    select * into pr from public.profiles where id = p_child_id;
    if not found then
      update public.women_members set gender = 'female', photo_url = null, avatar_url = null where id = p_child_id;
      return p_child_id;
    end if;
    insert into public.women_members(id, first_name, full_name, parent_id, gender, is_deceased, birth_date, death_date, is_hidden_from_tree, sort_order)
    values (gen_random_uuid(), pr.first_name, coalesce(nullif(pr.full_name, ''), pr.first_name), pr.father_id, 'female',
      coalesce(pr.is_deceased, false), pr.birth_date, pr.death_date, coalesce(pr.is_hidden_from_tree, false), coalesce(pr.sort_order, 0))
    returning id into new_id;
    delete from public.profiles where id = p_child_id;
    return new_id;
  elsif g = 'male' then
    select * into wm from public.women_members where id = p_child_id;
    if not found then
      update public.profiles set gender = 'male' where id = p_child_id;
      return p_child_id;
    end if;
    insert into public.profiles(id, first_name, full_name, father_id, gender, status, role,
      is_deceased, birth_date, death_date, is_hidden_from_tree, sort_order, is_phone_verified, is_hr_member)
    values (gen_random_uuid(), wm.first_name, coalesce(nullif(wm.full_name, ''), wm.first_name), wm.parent_id, 'male', 'active', 'member',
      coalesce(wm.is_deceased, false), wm.birth_date, wm.death_date, coalesce(wm.is_hidden_from_tree, false), coalesce(wm.sort_order, 0), false, false)
    returning id into new_id;
    delete from public.women_members where id = p_child_id;
    return new_id;
  else
    return p_child_id;
  end if;
end;
$function$;
grant usage on schema auth, private to authenticated, anon, service_role;
grant select, insert, update, delete on public.profiles, public.women_members, public.notifications to authenticated, service_role;
`;

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const P = { G: id(1), O: id(2), M: id(3), W: id(4), X1: id(5), X2: id(6), S1: id(7), S2: id(8), WN: id(9), W2: id(10) };

let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

const db = new PGlite();
await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers); await db.exec(links); await db.exec(live);
await db.exec(`
  insert into profiles(id, first_name, full_name, gender, role, status) values ('${P.G}', 'صلاح', 'صلاح الجد', 'male', 'member', 'active');
  insert into women_members(id, first_name, full_name, gender) values ('${P.G}', 'صلاح', 'صلاح الجد', 'male');
  insert into profiles(id, first_name, full_name, gender, role, status, father_id) values
    ('${P.O}', 'مالك', 'مالك صلاح', 'male', 'owner', 'active', '${P.G}'),
    ('${P.M}', 'حسن', 'حسن صلاح', 'male', 'member', 'active', '${P.G}'),
    ('${P.S1}', 'سعود', 'سعود حسن صلاح', 'male', 'member', 'active', '${P.M}'),
    ('${P.S2}', 'ناصر', 'ناصر حسن صلاح', 'male', 'member', 'active', '${P.M}');
  -- حساب امرأة (بلا أب، مخفية) + الصفّان القديمان المخالفان (أنثى + أب، مخفيتان) كما في الحي
  insert into profiles(id, first_name, full_name, gender, role, status, is_hidden_from_tree) values
    ('${P.W}', 'نورة', 'نورة', 'female', 'member', 'active', true);
  insert into profiles(id, first_name, full_name, gender, role, status, is_hidden_from_tree, father_id) values
    ('${P.X1}', 'مريم', 'مريم صلاح', 'female', 'member', 'active', true, '${P.G}'),
    ('${P.X2}', 'سارة', 'سارة صلاح', 'female', 'member', 'active', true, '${P.G}');
  -- بنت في شجرة النساء (للنقل إلى ذكر)
  insert into women_members(id, first_name, full_name, parent_id, gender) values ('${P.WN}', 'خطأ', 'خطأ حسن', '${P.M}', 'female');
  insert into auth.users(id) values ('${P.O}'), ('${P.M}'), ('${P.W}'), ('${P.X1}'), ('${P.X2}'), ('${P.W2}');`);

// who: معرّف مستخدم (authenticated) | 'maint' (SQL صيانة بلا JWT) | 'service' (مفتاح الخدمة بلا sub)
async function run(who, sql, flags = {}) {
  try {
    return await db.transaction(async tx => {
      const claims = who === 'maint' ? '' : JSON.stringify(who === 'service' ? { role: 'service_role' } : { sub: who, role: 'authenticated' });
      await tx.query(`select set_config('request.jwt.claims', $1, true)`, [claims]);
      for (const [k, v] of Object.entries(flags)) await tx.query(`select set_config($1, $2, true)`, [k, v]);
      if (who === 'service') await tx.exec('set local role service_role');
      else if (who !== 'maint') await tx.exec('set local role authenticated');
      const r = await tx.query(sql);
      return { ok: true, rows: r.rows };
    });
  } catch (e) {
    return { ok: false, err: e.message, hint: e.hint };
  }
}
const q = async sql => (await db.query(sql)).rows;
const rejected = r => !r.ok && r.hint === 'family_tree_men_only';
const femaleChild = (newId, father = P.M) => `insert into public.profiles(id, first_name, full_name, father_id, gender, role, status)
  values ('${newId}', 'فاطمة', 'فاطمة حسن صلاح', '${father}', 'female', 'member', 'active')`;

// ── قبل الحارس: الثغرة ──
console.log('— قبل الحارس (السيرفر اليوم) —');
{
  const r = await run(P.O, femaleChild(id(50)));
  check('المالك يدرج أنثى بأب في profiles (الثغرة)', r.ok, r.err);
  await db.exec(`delete from profiles where id = '${id(50)}'`);
}

await db.exec(mig);
console.log('— بعد الحارس —');

// ١. إدراج أنثى بأب
{
  const r = await run(P.O, femaleChild(id(51)));
  check('المالك: إدراج أنثى بأب مرفوض', rejected(r), r.err);
  check('رسالة عربية', /شجرة العائلة للرجال فقط/.test(r.err ?? ''), r.err);
  const r2 = await run(P.M, femaleChild(id(52)).replace("'active')", "'pending')"));
  check('العضو (addChild المباشر): إدراج بنته مرفوض', rejected(r2), r2.err);
  const r3 = await run(P.O, femaleChild(id(53)).replace("'female'", "' Female '"));
  check('«Female» بحروف ومسافات مرفوض', rejected(r3), r3.err);
  check('لا صفّ أُضيف', (await q(`select count(*)::int n from profiles where id in ('${id(51)}','${id(52)}','${id(53)}')`))[0].n === 0);
}
// ٢. حساب امرأة (بلا أب) وابن ذكر
{
  const r = await run(P.W2, `insert into public.profiles(id, first_name, full_name, gender, role, status, is_hidden_from_tree)
    values ('${P.W2}', 'هيا', 'هيا', 'female', 'pending', 'pending', true)`);
  check('تسجيل امرأة (أنثى بلا أب) يمر', r.ok, r.err);
  const r2 = await run(P.O, `insert into public.profiles(id, first_name, full_name, father_id, gender, role, status)
    values ('${id(54)}', 'محمد', 'محمد حسن صلاح', '${P.M}', 'male', 'member', 'active')`);
  check('إدراج ابن ذكر بأب يمر', r2.ok, r2.err);
  const r3 = await run(P.O, `insert into public.profiles(id, first_name, full_name, father_id, role, status)
    values ('${id(55)}', 'بلا', 'بلا جنس', '${P.M}', 'member', 'active')`);
  check('إدراج بلا جنس (null) بأب يمر', r3.ok, r3.err);
}
// ٣. الصفّان القديمان لا يُمسّان
{
  const r = await run(P.O, `update public.profiles set first_name = 'مريم٢' where id = '${P.X1}'`);
  check('القديم: تعديل الاسم يمر', r.ok, r.err);
  const r2 = await run(P.O, `update public.profiles set gender = 'female', father_id = '${P.G}' where id = '${P.X1}'`);
  check('القديم: إعادة إرسال الجنس والأب نفسهما يمر', r2.ok, r2.err);
  const r3 = await run('maint', `update public.profiles set is_hidden_from_tree = true, gender = 'female' where id = '${P.X2}'`);
  check('القديم: صيانة تلمس الجنس بنفس القيمة تمر', r3.ok, r3.err);
  const r4 = await run(P.O, `update public.profiles set father_id = '${P.M}' where id = '${P.X2}'`);
  check('القديم: تغيير الأب لأب آخر مرفوض', rejected(r4), r4.err);
  const r5 = await run(P.O, `update public.profiles set father_id = null where id = '${P.X2}'`);
  check('القديم: فكّ الأب (تصحيح) يمر', r5.ok, r5.err);
  const rows = await q(`select id, gender, father_id from profiles where id in ('${P.X1}','${P.X2}') order by id`);
  check('القديم X1 باقٍ أنثى بأبيه', rows[0].gender === 'female' && rows[0].father_id === P.G);
  check('القديم X2 بلا أب بعد الفك', rows[1].father_id === null);
}
// ٤. تعديل الجنس إلى أنثى (updateMemberGender) وربط امرأة بأب
{
  const r = await run(P.O, `update public.profiles set gender = 'female' where id = '${P.S1}'`);
  check('تعديل جنس ابن له أب إلى أنثى مرفوض', rejected(r), r.err);
  check('بقي ذكراً', (await q(`select gender from profiles where id = '${P.S1}'`))[0].gender === 'male');
  const r2 = await run(P.O, `update public.profiles set father_id = '${P.G}' where id = '${P.W}'`);
  check('ربط حساب امرأة بأب في شجرة الرجال مرفوض', rejected(r2), r2.err);
  const r3 = await run(P.O, `update public.profiles set gender = 'female', husband_id = '${P.M}' where id = '${P.W}'`);
  check('linkWife (أنثى بلا أب + زوج) يمر', r3.ok, r3.err);
  const r4 = await run(P.O, `update public.profiles set gender = 'male' where id = '${P.S2}'`);
  check('تعديل الجنس إلى ذكر يمر', r4.ok, r4.err);
}
// ٥. move_child_gender
{
  const r = await run(P.O, `select public.move_child_gender('${P.S2}', 'female') as nid`);
  check('move_child_gender ابن → بنت يعمل', r.ok, r.err);
  if (r.ok) {
    const nid = r.rows[0].nid;
    const w = await q(`select gender, parent_id from women_members where id = '${nid}'`);
    check('البنت في شجرة النساء تحت أبيها', w[0]?.gender === 'female' && w[0]?.parent_id === P.M);
    check('ملفها في profiles حُذف', (await q(`select count(*)::int n from profiles where id = '${P.S2}'`))[0].n === 0);
  }
  const r2 = await run(P.O, `select public.move_child_gender('${P.WN}', 'male') as nid`);
  check('move_child_gender بنت → ابن يعمل', r2.ok, r2.err);
  if (r2.ok) check('الابن في profiles ذكر بأبيه', (await q(`select gender, father_id from profiles where id = '${r2.rows[0].nid}'`))[0]?.gender === 'male');
}
// ٦. add_family_child
{
  const r = await run(P.O, `select public.add_family_child('${P.M}', 'لطيفة', 'female') as nid`);
  check('add_family_child بنت يعمل', r.ok, r.err);
  if (r.ok) {
    check('البنت في women_members', (await q(`select gender from women_members where id = '${r.rows[0].nid}'`))[0]?.gender === 'female');
    check('ولا شيء في profiles', (await q(`select count(*)::int n from profiles where id = '${r.rows[0].nid}'`))[0].n === 0);
  }
  const r2 = await run(P.O, `select public.add_family_child('${P.M}', 'خالد', 'male') as nid`);
  check('add_family_child ابن يعمل', r2.ok, r2.err);
  // ابن العضو لنفسه يمرّ بحارس الدور الحي (family.self_child) غير الموجود في base.sql — المسار نفسه إدراج 'male' كالمالك أعلاه
  const r3 = await run(P.M, `select public.add_family_child('${P.M}', 'منيرة', 'female') as nid`);
  check('add_family_child العضو لبنته يعمل (شجرة النساء)', r3.ok, r3.err);
}
// ٧. أعلام الصيانة
{
  const r = await run('maint', femaleChild(id(60)));
  check('صيانة بلا علم: مرفوض', rejected(r), r.err);
  const r2 = await run('maint', femaleChild(id(61)), { 'family.allow_female_profile': 'on' });
  check('صيانة بلا مستخدم + family.allow_female_profile: يمر', r2.ok, r2.err);
  const r3 = await run(P.O, femaleChild(id(62)), { 'family.allow_female_profile': 'on' });
  check('مستخدم + family.allow_female_profile: مرفوض', rejected(r3), r3.err);
  const r4 = await run('service', femaleChild(id(63)));
  check('مفتاح الخدمة بلا علم: مرفوض', rejected(r4), r4.err);
  const r5 = await run(P.O, femaleChild(id(64)), { 'family.gender_move': 'on' });
  check('العلم family.gender_move: يمر', r5.ok, r5.err);
  const r6 = await run('maint', femaleChild(id(65)));
  check('العلم محلي للمعاملة (لا يبقى بعدها)', rejected(r6), r6.err);
}

await db.exec(rb);
console.log('— بعد التراجع —');
{
  const r = await run(P.O, femaleChild(id(70)));
  check('بعد التراجع: الإدراج كما كان', r.ok, r.err);
  check('لا مشغّل ولا دالة', (await q(`select count(*)::int n from pg_trigger where tgname = 'trg_zzzz_family_tree_men_only'`))[0].n === 0
    && (await q(`select count(*)::int n from pg_proc where proname = 'family_tree_men_only'`))[0].n === 0);
}

console.log(`\n${pass} نجح · ${fail} فشل`);
process.exit(fail ? 1 : 0);
