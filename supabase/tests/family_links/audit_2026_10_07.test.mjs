// تجربة إصلاحات فحص ٢٠٢٦-١٠-٠٧ (موافقة المالك) على قاعدة محلية معزولة (لا تلمس السيرفر) —
// قبل التعديل (ملفات التراجع = تعريفات الحي) وبعده وبعد التراجع:
//   ١) ع-١  الرفع للأعضاء المفعّلين فقط (+ صورة المسجّل المعلّق نفسه)، لا رفع «للقصص»، حدود المستودعات
//   ٢) م-٤  announce_death للمالك والمدير فقط، ولوفاة حديثة (بتاريخ ≤ ٣٠ يوماً أو سُجّلت خلال ٣٠ يوماً)
//   ٣) م-٣  الحذف من شجرة النساء للمالك والمدير فقط، والمراقب يضيف ويعدّل كما هو
//   ٤) ن-٧  app_settings للمالك بـ current_user_role()، والمشاريع تقبل current_profile_id()
// ثم يتأكد أن التراجع يعيد السياسات والدالة والمستودعات حرفياً كما كانت.
// التشغيل: cd supabase/tests/family_links && node audit_2026_10_07.test.mjs
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
const NAMES = ['20261007120000_storage_uploads_active_members', '20261007130000_announce_death_admin_recent',
  '20261007140000_women_delete_admin_only', '20261007150000_owner_policies_by_role'];
const mig = NAMES.map(n => readFileSync(`${REPO}/migrations/${n}.sql`, 'utf8'));
// ملفات التراجع = ما على السيرفر الحي اليوم (السياسات من pg_policies، والدالة md5 مطابق)
const live = NAMES.map(n => readFileSync(`${REPO}/rollback/${n}_rollback.sql`, 'utf8'));
const LIVE_MD5 = 'c983835d0bbd169c55f53d73253b104f';

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const P = {
  O: id(1), A: id(2), MON: id(3), S: id(4), M1: id(10), M2: id(11), CH: id(12), PEND: id(20), FRZ: id(21),
  LP: id(30), LU: id(31), OU: id(32), STR: id(40),
  DR1: id(50), DR2: id(51), DOLD: id(52), DUND: id(53), LREC: id(54), LOLD: id(55), DTOM: id(56), DFUT: id(57), DR3: id(58),
  WREC: id(60), WDATED: id(61), WDEL1: id(62), WDEL2: id(63), WDEL3: id(64), WEDIT: id(65),
  PRJ1: id(70), PRJ2: id(71), PRJL: id(72),
};
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

async function setup(stage) {
  const db = new PGlite();
  await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers);
  await db.exec(`
    create schema storage;
    create table storage.buckets (id text primary key, public boolean default true, file_size_limit bigint, allowed_mime_types text[]);
    create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid, metadata jsonb);
    create or replace function storage.foldername(name text) returns text[] language plpgsql immutable as $function$
    declare _parts text[];
    begin
      select string_to_array(name, '/') into _parts;
      return _parts[1 : array_length(_parts,1) - 1];
    end $function$;
    alter table storage.objects enable row level security;
    create policy avatars_select_authenticated on storage.objects for select to authenticated using (true);
    -- سياسة رفع الأخبار الحية (لا يغيّرها التعديل)
    create policy news_insert_admin on storage.objects for insert to authenticated
      with check ((bucket_id = 'news') and (public.current_user_role() = any (array['owner','admin','monitor','supervisor'])));
    insert into storage.buckets values ('avatars', true, null, null),
      ('family-archive', true, 104857600, array['application/pdf','image/jpeg','image/png','image/heic','image/webp']),
      ('family-gallery', true, 26214400, array['image/jpeg','image/png','image/heic','image/webp']),
      ('gallery', true, null, null), ('news', true, null, null),
      ('stories', true, 5242880, array['image/jpeg','image/png','image/webp']);

    create or replace function public.avatar_target_id(object_name text) returns uuid language sql immutable set search_path to 'public' as $function$
      select case
        when lower(split_part(object_name, '.', 1))
             ~ '^(cover_)?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then replace(lower(split_part(object_name, '.', 1)), 'cover_', '')::uuid
        else null
      end $function$;
    create or replace function public.is_descendant_of_caller(target uuid) returns boolean language sql stable security definer set search_path to 'public' as $function$
      with recursive ancestors as (
        select father_id as ancestor_id from public.profiles where id = target
        union all
        select p.father_id from public.profiles p join ancestors a on p.id = a.ancestor_id where p.father_id is not null)
      select coalesce((select status = 'active' from public.profiles where id = auth.uid()), false)
        and coalesce((select exists (select 1 from ancestors where ancestor_id = auth.uid())), false) $function$;

    create table public.news (id uuid primary key default gen_random_uuid(), created_at timestamptz default now(),
      author_name text not null, author_role text not null, role_color text not null, content text not null, type text not null,
      image_url text, poll_options jsonb, author_id uuid, approval_status text, approved_by uuid, approved_at timestamptz,
      image_urls jsonb not null default '[]', poll_question text, posted_by uuid);
    create table public.death_announcements (member_id uuid primary key, tree text not null default 'men',
      news_id uuid references public.news(id) on delete set null, announced_by uuid, created_at timestamptz not null default now());
    alter table public.notifications add column details jsonb;

    create table public.app_settings (id uuid primary key default gen_random_uuid(), women_tree_enabled boolean default true);
    alter table public.app_settings enable row level security;
    create policy "Authenticated users can read app_settings" on public.app_settings for select to authenticated using (true);
    create table public.projects (id uuid primary key, owner_id uuid, title text);
    alter table public.projects enable row level security;
    create policy projects_select_authenticated on public.projects for select to authenticated using (true);
    alter table public.women_members enable row level security;
    create policy women_members_select on public.women_members for select to authenticated using (true);

    grant usage on schema auth to authenticated; grant usage on schema storage to authenticated;
    grant select, insert, update, delete on storage.objects to authenticated;
    grant select on storage.buckets to authenticated;
    grant select, insert, update, delete on public.women_members, public.app_settings, public.projects to authenticated;
    grant select on public.profiles to authenticated;
    grant select, insert on public.notifications to authenticated;`);
  for (const sql of live) await db.exec(sql);                 // الحي اليوم
  if (stage !== 'before') for (const sql of mig) await db.exec(sql);
  if (stage === 'rolledback') for (const sql of live) await db.exec(sql);

  const today = `(now() at time zone 'Asia/Kuwait')::date`;
  await db.exec(`
    -- عقدة الأب في شجرة النساء (المرآة تربط الابن بها)
    insert into women_members(id, first_name, full_name, gender) values ('${P.M1}', 'أحمد', 'عضو ١', 'male');
    insert into profiles(id, first_name, full_name, gender, role, status, father_id, is_deceased, death_date) values
      ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active', null, false, null),
      ('${P.A}', 'بدر', 'مدير', 'male', 'admin', 'active', null, false, null),
      ('${P.MON}', 'علي', 'مراقب', 'male', 'monitor', 'active', null, false, null),
      ('${P.S}', 'سعد', 'مشرف', 'male', 'supervisor', 'active', null, false, null),
      ('${P.M1}', 'أحمد', 'عضو ١', 'male', 'member', 'active', null, false, null),
      ('${P.M2}', 'حمد', 'عضو ٢', 'male', 'member', 'active', null, false, null),
      ('${P.CH}', 'ابن', 'ابن عضو ١', 'male', 'member', 'active', '${P.M1}', false, null),
      ('${P.PEND}', 'جديد', 'مسجّل معلّق', 'male', 'pending', 'pending', null, false, null),
      ('${P.FRZ}', 'مجمّد', 'عضو مجمّد', 'male', 'member', 'frozen', null, false, null),
      ('${P.LP}', 'مربوط', 'عضو بحساب مربوط', 'male', 'member', 'active', null, false, null),
      ('${P.DR1}', 'متوفى', 'وفاة حديثة ١', 'male', 'member', 'active', null, true, ${today} - 5),
      ('${P.DR2}', 'متوفى', 'وفاة حديثة ٢', 'male', 'member', 'active', null, true, ${today} - 30),
      ('${P.DOLD}', 'جد', 'وفاة قديمة', 'male', 'member', 'active', null, true, date '2001-03-04'),
      ('${P.DUND}', 'جد', 'متوفى قديم بلا تاريخ', 'male', 'member', 'active', null, true, null),
      ('${P.LREC}', 'حي', 'تُسجَّل وفاته الآن بلا تاريخ', 'male', 'member', 'active', null, false, null),
      ('${P.LOLD}', 'حي', 'سُجّلت وفاته قبل ٤٠ يوماً بلا تاريخ', 'male', 'member', 'active', null, false, null),
      ('${P.DTOM}', 'متوفى', 'تاريخ الغد (فارق التوقيت)', 'male', 'member', 'active', null, true, ${today} + 1),
      ('${P.DFUT}', 'متوفى', 'تاريخ بعد ٣ أيام', 'male', 'member', 'active', null, true, ${today} + 3),
      ('${P.DR3}', 'متوفى', 'وفاة حديثة ٣', 'male', 'member', 'active', null, true, ${today});
    insert into auth.users(id, phone, raw_app_meta_data) values
      ('${P.O}', null, '{}'), ('${P.A}', null, '{}'), ('${P.MON}', null, '{}'), ('${P.S}', null, '{}'),
      ('${P.M1}', null, '{}'), ('${P.M2}', null, '{}'), ('${P.PEND}', null, '{}'), ('${P.FRZ}', null, '{}'),
      ('${P.LU}', null, '{"profile_id": "${P.LP}"}'), ('${P.OU}', null, '{"profile_id": "${P.O}"}'), ('${P.STR}', null, '{}');
    insert into women_members(id, first_name, full_name, gender, is_deceased, death_date) values
      ('${P.WREC}', 'هند', 'تُسجَّل وفاتها الآن', 'female', false, null),
      ('${P.WDATED}', 'مريم', 'وفاة حديثة بتاريخ', 'female', true, ${today} - 2),
      ('${P.WDEL1}', 'سارة', 'حذف ١', 'female', false, null),
      ('${P.WDEL2}', 'نورة', 'حذف ٢', 'female', false, null),
      ('${P.WDEL3}', 'لطيفة', 'حذف ٣', 'female', false, null),
      ('${P.WEDIT}', 'فاطمة', 'تعديل', 'female', false, null);
    insert into app_settings(id, women_tree_enabled) values ('${id(90)}', true);
    insert into projects(id, owner_id, title) values ('${P.PRJ1}', '${P.M1}', 'مشروع ١'), ('${P.PRJ2}', '${P.M2}', 'مشروع ٢'),
      ('${P.PRJL}', '${P.LP}', 'مشروع الحساب المربوط');
    insert into storage.objects(bucket_id, name) values ('avatars', '${P.PEND}.jpg'), ('avatars', '${P.M2}.jpg');
    -- تسجيل وفاة الآن (تعديل) — يختمها المشغّل بعد التعديل
    update profiles set is_deceased = true where id in ('${P.LREC}', '${P.LOLD}');
    update women_members set is_deceased = true where id = '${P.WREC}';`);
  if (stage === 'after') await db.exec(`update death_marks set marked_at = now() - interval '40 days' where member_id = '${P.LOLD}'`);
  return db;
}

async function as(db, who, sql, params = []) {
  const claims = !who ? '' : JSON.stringify(typeof who === 'string'
    ? { sub: who, role: 'authenticated' }
    : { sub: who.sub, role: 'authenticated', app_metadata: { profile_id: who.pid } });
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [claims]);
  if (who) await db.exec('set role authenticated');
  try { const r = await db.query(sql, params); return { ok: true, rows: r.rows, n: r.affectedRows ?? r.rows.length }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint }; }
  finally { if (who) await db.exec('reset role'); await db.query(`select set_config('request.jwt.claims', '', false)`); }
}
const up = (db, who, bucket, name) => as(db, who, `insert into storage.objects(bucket_id, name) values ($1, $2) returning id`, [bucket, name]);
const LINKED = { sub: P.LU, pid: P.LP };          // حساب دخول معرّفه غير معرّف ملفه
const OWNER_MOVED = { sub: P.OU, pid: P.O };     // المالك بعد نقل حسابه (app_metadata.profile_id)

async function snapshot(db) {
  return JSON.stringify((await db.query(`
    select (select json_agg(row_to_json(p) order by tablename, policyname) from (
              select schemaname, tablename, policyname, cmd, roles::text, qual, with_check from pg_policies
              where tablename in ('objects', 'women_members', 'app_settings', 'projects')) p) pol,
           (select json_agg(row_to_json(b) order by id) from storage.buckets b) buckets,
           (select md5(prosrc) from pg_proc where proname = 'announce_death') fn,
           to_regclass('public.death_marks') is not null marks,
           (select count(*) from pg_trigger where tgname = 'trg_mark_death_recorded') trg`)).rows[0]);
}

const snaps = {};
for (const stage of ['before', 'after', 'rolledback']) {
  const after = stage === 'after';
  console.log(`\n══════ ${{ before: 'قبل التعديل (السيرفر اليوم)', after: 'بعد التعديل', rolledback: 'بعد التراجع' }[stage]} ══════`);
  const db = await setup(stage);
  snaps[stage] = await snapshot(db);
  const fn = (await db.query(`select md5(prosrc) m from pg_proc where proname = 'announce_death'`)).rows[0].m;
  if (stage !== 'after') check(`announce_death = نسخة الحي (md5 ${LIVE_MD5.slice(0, 8)}…)`, fn === LIVE_MD5, fn);
  else console.log(`   md5(prosrc) announce_death بعد التعديل = ${fn}`);

  // ─── ١) الرفع ───
  console.log('— ١) الرفع إلى المستودعات العامة (ع-١):');
  const vuln = (label, r) => check(`${label}: ${after ? 'مرفوض' : 'يمر (الثغرة)'}`, after ? !r.ok : r.ok, r.err ?? '');
  const same = (label, r, ok) => check(`${label} — كما هو`, ok ? r.ok : !r.ok, r.err ?? '');
  vuln('غريب بلا ملف يرفع stories/x/evil.html', await up(db, P.STR, 'stories', 'x/evil.html'));
  vuln('معلّق يرفع إلى stories', await up(db, P.PEND, 'stories', `${P.PEND}/a.jpg`));
  check(`عضو مفعّل يرفع إلى stories: ${after ? 'مرفوض (الميزة أُزيلت)' : 'يمر'}`, after ? !(await up(db, P.M1, 'stories', `${P.M1}/a.jpg`)).ok : true);
  vuln('معلّق يرفع للمكتبة documents/x.pdf', await up(db, P.PEND, 'family-archive', 'documents/x.pdf'));
  vuln('مجمّد يرفع للمكتبة', await up(db, P.FRZ, 'family-archive', 'books/y.pdf'));
  vuln('غريب يرفع للمكتبة', await up(db, P.STR, 'family-archive', 'other/z.jpg'));
  same('عضو مفعّل يرفع للمكتبة', await up(db, P.M1, 'family-archive', 'documents/m1.pdf'), true);
  same('عضو مفعّل خارج المجلّدات الأربعة مرفوض', await up(db, P.M1, 'family-archive', 'evil/m1.pdf'), false);
  same('المسجّل المعلّق يرفع صورته عند التسجيل <هو>.jpg', await up(db, P.PEND, 'avatars', `${P.PEND}.jpg`), true);
  vuln('غريب بلا ملف يرفع <معرّفه>.jpg', await up(db, P.STR, 'avatars', `${P.STR}.jpg`));
  vuln('مجمّد يرفع صورته', await up(db, P.FRZ, 'avatars', `${P.FRZ}.jpg`));
  vuln('معلّق يرفع photo_suggestion باسمه', await up(db, P.PEND, 'avatars', `photo_suggestion_${P.PEND}_x.jpg`));
  vuln('معلّق يرفع project_photo باسمه', await up(db, P.PEND, 'avatars', `project_photo_${P.PEND}_x.jpg`));
  vuln('غريب يرفع project_logo باسمه', await up(db, P.STR, 'avatars', `project_logo_${P.STR}_p_1.jpg`));
  same('عضو مفعّل: صورته', await up(db, P.M1, 'avatars', `${P.M1}.jpg`), true);
  same('عضو مفعّل: غلافه cover_<هو>', await up(db, P.M1, 'avatars', `cover_${P.M1}.jpg`), true);
  same('عضو مفعّل: اقتراح صورة باسمه', await up(db, P.M1, 'avatars', `photo_suggestion_${P.M1}_y.jpg`), true);
  same('عضو مفعّل: صورة ابنه', await up(db, P.M1, 'avatars', `${P.CH}.jpg`), true);
  same('عضو مفعّل: صورة مشروع وشعار باسمه', await up(db, P.M1, 'avatars', `project_photo_${P.M1}_z.jpg`), true);
  same('عضو مفعّل: صورة عضو آخر مرفوضة', await up(db, P.M1, 'avatars', `${P.M2}.jpg`), false);
  same('عضو مفعّل: اقتراح باسم غيره مرفوض', await up(db, P.M1, 'avatars', `photo_suggestion_${P.M2}_q.jpg`), false);
  same('المراقب: صورة شجرة النساء women_<id>', await up(db, P.MON, 'avatars', `women_${P.WEDIT}.jpg`), true);
  same('المشرف: صورة عضو', await up(db, P.S, 'avatars', `${P.M2}.jpg`), true);
  let r = await up(db, LINKED, 'avatars', `project_photo_${P.LP}_w.jpg`);
  check(`حساب مربوط بملف آخر: project_photo_<ملفه> ${after ? 'يمر (current_profile_id)' : 'مرفوض (اليوم)'}`, after ? r.ok : !r.ok, r.err ?? '');
  r = await up(db, LINKED, 'avatars', `${P.LP}.jpg`);
  check(`حساب مربوط بملف آخر: صورة ملفه ${after ? 'تمر' : 'مرفوضة (اليوم)'}`, after ? r.ok : !r.ok, r.err ?? '');
  vuln('معلّق يرفع في مجلّده بالمعرض gallery', await up(db, P.PEND, 'gallery', `${P.PEND}/a.jpg`));
  same('عضو مفعّل في مجلّده بالمعرض', await up(db, P.M1, 'gallery', `${P.M1}/a.jpg`), true);
  same('عضو مفعّل في مجلّد غيره بالمعرض مرفوض', await up(db, P.M1, 'gallery', `${P.M2}/a.jpg`), false);
  vuln('معلّق يرفع لمعرض العضو member-gallery', await up(db, P.PEND, 'member-gallery', `${P.PEND}/a.jpg`));
  same('عضو مفعّل يرفع news (للإدارة)', await up(db, P.M1, 'news', `news/${P.M1}/a.jpg`), false);
  same('المشرف يرفع news', await up(db, P.S, 'news', `news/${P.S}/a.jpg`), true);
  r = await as(db, P.PEND, `update storage.objects set metadata = '{"v":2}' where bucket_id = 'avatars' and name = $1 returning id`, [`${P.PEND}.jpg`]);
  check('المعلّق يستبدل صورته (upsert) — كما هو', r.ok && r.n >= 1, r.err ?? `صفوف ${r.n}`);
  r = await as(db, P.M1, `update storage.objects set metadata = '{"v":2}' where bucket_id = 'avatars' and name = $1 returning id`, [`${P.M2}.jpg`]);
  check('عضو لا يستبدل صورة غيره — كما هو', r.ok && r.n === 0, r.err ?? `صفوف ${r.n}`);
  const b = Object.fromEntries((await db.query(`select id, file_size_limit::text l, array_to_string(allowed_mime_types, ',') m from storage.buckets`)).rows.map(x => [x.id, x]));
  if (after) {
    const img = 'image/jpeg,image/png,image/heic,image/webp';
    check('حدود avatars/news/gallery/family-gallery: صور ≤ ١٠ ميغابايت',
      ['avatars', 'news', 'gallery', 'family-gallery'].every(k => b[k].l === '10485760' && b[k].m === img), JSON.stringify(b.avatars));
    check('حدود المكتبة: pdf + صور ≤ ٢٥ ميغابايت', b['family-archive'].l === '26214400' && b['family-archive'].m === 'application/pdf,' + img, JSON.stringify(b['family-archive']));
  } else check('المستودعات كما على الحي (avatars بلا حد، المكتبة ١٠٠ ميغابايت)', b.avatars.l === null && b['family-archive'].l === '104857600');

  // ─── ٢) إعلان الوفاة ───
  console.log('— ٢) announce_death (م-٤):');
  const ann = (who, m) => as(db, who, `select public.announce_death($1, $2, null, true) as id`, [m, 'نص حر']);
  r = await ann(P.MON, P.DR1);
  check(`المراقب ينشر إعلان وفاة: ${after ? 'مرفوض 42501' : 'يمر (خلاف جدول الأدوار)'}`, after ? (!r.ok && /not allowed/.test(r.err)) : r.ok, r.err ?? '');
  r = await ann(P.S, P.DR1); same('المشرف مرفوض', r, false);
  r = await ann(P.M1, P.DR1); same('العضو مرفوض', r, false);
  r = await ann(P.A, P.DR2); same('المدير: وفاة بتاريخ قبل ٣٠ يوماً', r, true);
  r = await ann(P.A, P.DR2); check('المكرر مرفوض (already announced) — كما هو', !r.ok && /already announced/.test(r.err), r.err ?? '');
  r = await ann(P.A, P.DOLD);
  check(`المدير: وفاة قديمة بتاريخ ٢٠٠١: ${after ? 'مرفوض death_not_recent' : 'يمر (الثغرة)'}`, after ? (!r.ok && r.hint === 'death_not_recent') : r.ok, r.err ?? '');
  r = await ann(P.O, P.DUND);
  check(`المالك: متوفى قديم بلا تاريخ ولا ختم: ${after ? 'مرفوض' : 'يمر (الثغرة)'}`, after ? (!r.ok && r.hint === 'death_not_recent') : r.ok, r.err ?? '');
  r = await ann(P.A, P.LREC); same('المدير: وفاة سُجّلت الآن بلا تاريخ (المربّع الآلي)', r, true);
  r = await ann(P.O, P.WREC); same('المالك: وفاة امرأة سُجّلت الآن بلا تاريخ (شجرة النساء)', r, true);
  r = await ann(P.A, P.WDATED); same('المدير: امرأة بتاريخ وفاة حديث', r, true);
  r = await ann(P.A, P.DTOM); same('المدير: تاريخ الغد (فارق توقيت الجهاز)', r, true);
  r = await ann(P.A, P.DFUT);
  check(`المدير: تاريخ بعد ٣ أيام: ${after ? 'مرفوض' : 'يمر'}`, after ? !r.ok : r.ok, r.err ?? '');
  r = await ann(P.A, P.LOLD);
  check(`المدير: سُجّلت قبل ٤٠ يوماً بلا تاريخ: ${after ? 'مرفوض' : 'يمر'}`, after ? (!r.ok && r.hint === 'death_not_recent') : r.ok, r.err ?? '');
  r = await ann(P.A, P.M1); check('حي مرفوض (not deceased) — كما هو', !r.ok && /not deceased/.test(r.err), r.err ?? '');
  r = await ann(OWNER_MOVED, P.DR3);
  check(`المالك بعد نقل حسابه (app_metadata) ينشر`, r.ok, r.err ?? '');
  const news = (await db.query(`select count(*)::int n from news where type = 'وفاة' and approval_status = 'approved'`)).rows[0].n;
  check(`أخبار الوفاة المنشورة: ${after ? 6 : 11}`, news === (after ? 6 : 11), `${news}`);
  if (after) {
    const marks = (await db.query(`select count(*)::int n from death_marks`)).rows[0].n;
    check('death_marks: تسجيل الوفاة بالتعديل فقط (٣ ختمات: رجلان + امرأة)', marks === 3, `${marks}`);
    r = await as(db, P.A, `select * from death_marks`);
    check('death_marks غير مقروء من التطبيقات', !r.ok, r.err ?? '');
  }

  // ─── ٣) الحذف من شجرة النساء ───
  console.log('— ٣) الحذف من شجرة النساء (م-٣):');
  const wexists = async w => (await db.query(`select count(*)::int n from women_members where id = $1`, [w])).rows[0].n === 1;
  r = await as(db, P.MON, `delete from women_members where id = $1 returning id`, [P.WDEL1]);
  check(`المراقب يحذف: ${after ? 'لا يُحذف شيء' : 'يُحذف (خلاف جدول الأدوار)'}`, r.ok && (after ? (r.n === 0 && await wexists(P.WDEL1)) : !(await wexists(P.WDEL1))), r.err ?? `صفوف ${r.n}`);
  r = await as(db, P.MON, `update women_members set full_name = 'فاطمة (معدّل)' where id = $1 returning id`, [P.WEDIT]);
  check('المراقب يعدّل — كما هو', r.ok && r.n === 1, r.err ?? `صفوف ${r.n}`);
  r = await as(db, P.MON, `insert into women_members(id, first_name, full_name, gender) values ($1, 'جديدة', 'جديدة', 'female') returning id`, [id(66)]);
  check('المراقب يضيف — كما هو', r.ok && r.n === 1, r.err ?? '');
  r = await as(db, P.A, `delete from women_members where id = $1 returning id`, [P.WDEL2]);
  check('المدير يحذف — كما هو', r.ok && r.n === 1 && !(await wexists(P.WDEL2)), r.err ?? `صفوف ${r.n}`);
  r = await as(db, P.O, `delete from women_members where id = $1 returning id`, [P.WDEL3]);
  check('المالك يحذف — كما هو', r.ok && r.n === 1, r.err ?? `صفوف ${r.n}`);
  r = await as(db, P.S, `delete from women_members where id = $1 returning id`, [id(66)]);
  check('المشرف لا يحذف — كما هو', r.ok && r.n === 0, r.err ?? `صفوف ${r.n}`);
  r = await as(db, P.M1, `update women_members set full_name = 'x' where id = $1 returning id`, [P.WEDIT]);
  check('العضو لا يعدّل — كما هو', r.ok && r.n === 0, r.err ?? `صفوف ${r.n}`);

  // ─── ٤) سياسات المالك والملكية ───
  console.log('— ٤) app_settings والمشاريع (ن-٧):');
  const setS = who => as(db, who, `update app_settings set women_tree_enabled = not women_tree_enabled returning id`);
  r = await setS(P.O); check('المالك يعدّل الإعدادات — كما هو', r.ok && r.n === 1, r.err ?? `صفوف ${r.n}`);
  r = await setS(OWNER_MOVED);
  check(`المالك بعد نقل حسابه (app_metadata): ${after ? 'يعدّل' : 'لا يعدّل (يرجع المفتاح بصمت)'}`, r.ok && r.n === (after ? 1 : 0), r.err ?? `صفوف ${r.n}`);
  r = await setS(P.A); check('المدير لا يعدّل (للقراءة) — كما هو', r.ok && r.n === 0, r.err ?? `صفوف ${r.n}`);
  r = await setS(P.M1); check('العضو لا يعدّل — كما هو', r.ok && r.n === 0, r.err ?? `صفوف ${r.n}`);
  const setP = (who, p) => as(db, who, `update projects set title = title || '.' where id = $1 returning id`, [p]);
  r = await setP(P.M1, P.PRJ1); check('صاحب المشروع يعدّله — كما هو', r.ok && r.n === 1, r.err ?? `صفوف ${r.n}`);
  r = await setP(P.M1, P.PRJ2); check('عضو لا يعدّل مشروع غيره — كما هو', r.ok && r.n === 0, r.err ?? `صفوف ${r.n}`);
  r = await setP(P.A, P.PRJ2); check('المدير يعدّل أي مشروع — كما هو', r.ok && r.n === 1, r.err ?? `صفوف ${r.n}`);
  r = await setP(LINKED, P.PRJL);
  check(`حساب مربوط يعدّل مشروع ملفه: ${after ? 'يمر' : 'لا (اليوم)'}`, r.ok && r.n === (after ? 1 : 0), r.err ?? `صفوف ${r.n}`);
  r = await as(db, LINKED, `delete from projects where id = $1 returning id`, [P.PRJL]);
  check(`حساب مربوط يحذف مشروع ملفه: ${after ? 'يمر' : 'لا (اليوم)'}`, r.ok && r.n === (after ? 1 : 0), r.err ?? `صفوف ${r.n}`);
  r = await as(db, P.M2, `delete from projects where id = $1 returning id`, [P.PRJ1]);
  check('عضو لا يحذف مشروع غيره — كما هو', r.ok && r.n === 0, r.err ?? `صفوف ${r.n}`);
  await db.close();
}
check('التراجع يعيد السياسات والمستودعات والدالة حرفياً كما على الحي', snaps.before === snaps.rolledback);
check('التعديل غيّر فعلاً', snaps.before !== snaps.after);
console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
