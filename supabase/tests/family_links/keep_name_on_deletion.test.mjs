// تجربة حذف الحساب (finalize_account_deletion) على قاعدة محلية معزولة (لا تلمس السيرفر):
// قبل التعديل (نص ملف التراجع = النسخة الحية) ← بعد التعديل ← بعد التراجع.
// المطلوب بعد التعديل: الاسم يبقى في الشجرة، وكل ما سواه يُحذف كما كان، وروابط العائلة لا تنقطع.
// التشغيل: cd supabase/tests/family_links && node keep_name_on_deletion.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message); process.exit(2); });
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody] = base.split('-- ─── المشغّلات');
const fix = readFileSync(`${REPO}/migrations/20261005190000_keep_name_on_account_deletion.sql`, 'utf8');
const rollback = readFileSync(`${REPO}/rollback/20261005190000_keep_name_on_account_deletion_rollback.sql`, 'utf8');

const FATHER = '00000000-0000-0000-0000-0000000000f1';
const ME = '00000000-0000-0000-0000-0000000000a1';
const SON = '00000000-0000-0000-0000-0000000000c1';

let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('  ✓', m); } else { fail++; console.log('  ✗', m); } };

async function freshDb() {
  const db = new PGlite();
  await db.exec(baseBody);
  await db.exec(`
    create table public.account_deletion_jobs (auth_user_id uuid primary key, profile_id uuid not null,
      phase text default 'prepared', storage_files jsonb default '[]', created_at timestamptz default now());
    create table public.news (id uuid primary key default gen_random_uuid(), author_id uuid, posted_by uuid, content text);
    create table public.news_comments (id uuid primary key default gen_random_uuid(), author_id uuid, content text);
    create table public.news_likes (id uuid primary key default gen_random_uuid(), member_id uuid);
    create table public.news_poll_votes (id uuid primary key default gen_random_uuid(), member_id uuid);
    create table public.diwaniyas (id uuid primary key default gen_random_uuid(), owner_id uuid);
    create table public.projects (id uuid primary key default gen_random_uuid(), owner_id uuid);
    insert into public.profiles (id, first_name, full_name, father_id, role, status) values
      ('${FATHER}', 'اياد', 'اياد عبدالحميد المحمدعلي', null, 'member', 'active');
    insert into public.profiles (id, first_name, full_name, father_id, phone_number, email, birth_date, photo_url, bio,
      role, status, family_name) values
      ('${ME}', 'عبدالله', 'عبدالله اياد عبدالحميد المحمدعلي', '${FATHER}', '+96550000000', 'x@y.z', '2000-01-01',
       'https://p/x.jpg', '[{"t":"سيرة"}]', 'member', 'active', 'المحمدعلي');
    insert into public.profiles (id, first_name, full_name, father_id, role, status) values
      ('${SON}', 'حسن', 'حسن عبدالله اياد المحمدعلي', '${ME}', 'member', 'active');
    insert into public.women_members (id, first_name, full_name, parent_id, gender, birth_date, photo_url, linked_user_id)
      values ('${FATHER}', 'اياد', 'اياد عبدالحميد', null, 'male', null, null, null),
             ('${ME}', 'عبدالله', 'عبدالله اياد عبدالحميد المحمدعلي', '${FATHER}', 'male', '2000-01-01', 'https://p/x.jpg', null);
    insert into auth.users (id, phone) values ('${ME}', '96550000000');
    insert into public.account_deletion_jobs (auth_user_id, profile_id) values ('${ME}', '${ME}');
    insert into public.news (author_id, content) values ('${ME}', 'خبر');
    insert into public.news_comments (author_id, content) values ('${ME}', 'تعليق');
    insert into public.device_tokens (member_id, token) values ('${ME}', 't');
    insert into public.notifications (target_member_id, title) values ('${ME}', 'إشعار');
    insert into public.admin_requests (member_id, requester_id, request_type, status) values ('${ME}', '${ME}', 'tree_edit', 'pending');
  `);
  return db;
}

async function runCase(label, sql, keepsName) {
  console.log(`\n— ${label}`);
  const db = await freshDb();
  await db.exec(sql);
  // finalize يعمل بمفتاح الخدمة فقط
  await db.exec(`select set_config('request.jwt.claims', '{"role":"service_role"}', false)`);
  await db.query(`select public.finalize_account_deletion($1::uuid)`, [ME]);
  const p = (await db.query(`select * from public.profiles where id = $1`, [ME])).rows[0];
  const w = (await db.query(`select * from public.women_members where id = $1`, [ME])).rows[0];
  const son = (await db.query(`select father_id from public.profiles where id = $1`, [SON])).rows[0];
  const count = async t => (await db.query(`select count(*)::int as n from public.${t} where ${t === 'news' || t === 'news_comments' ? 'author_id' : t === 'notifications' ? 'target_member_id' : 'member_id'} = $1`, [ME])).rows[0].n;
  if (keepsName) {
    ok(p.full_name === 'عبدالله اياد عبدالحميد المحمدعلي' && p.first_name === 'عبدالله', `الاسم يبقى في الشجرة: «${p.full_name}»`);
    ok(w.full_name === 'عبدالله اياد عبدالحميد المحمدعلي', `ويبقى في شجرة النساء: «${w.full_name}»`);
  } else {
    ok(p.full_name === 'عضو محذوف' && w.full_name === 'عضو محذوف', `قبل التعديل: «${p.full_name}» (السلوك القديم)`);
  }
  ok(p.phone_number === null && p.email === null && p.birth_date === null && p.photo_url === null, 'الرقم والبريد والميلاد والصورة حُذفت');
  ok(p.status === 'deleted' && p.role === 'member', `الحالة deleted والدور member (${p.status}/${p.role})`);
  ok(p.father_id === FATHER && son.father_id === ME, 'روابط العائلة باقية (أبوه وابنه)');
  ok(w.parent_id === FATHER && w.birth_date === null && w.photo_url === null, 'عقدة النساء مربوطة بأبيه وبلا بيانات شخصية');
  ok(await count('news') === 0 && await count('news_comments') === 0 && await count('device_tokens') === 0
     && await count('notifications') === 0 && await count('admin_requests') === 0, 'المحتوى والأجهزة والإشعارات والطلبات حُذفت');
  const job = (await db.query(`select phase from public.account_deletion_jobs where auth_user_id = $1`, [ME])).rows[0];
  ok(job.phase === 'data_deleted', 'المهمة انتهت (data_deleted)');
  // غير مفتاح الخدمة مرفوض
  await db.exec(`select set_config('request.jwt.claims', '{"role":"authenticated","sub":"${ME}"}', false)`);
  let denied = false;
  try { await db.query(`select public.finalize_account_deletion($1::uuid)`, [ME]); } catch { denied = true; }
  ok(denied, 'غير مفتاح الخدمة لا يستطيع تشغيلها');
}

await runCase('قبل التعديل (النسخة الحية)', rollback, false);
await runCase('بعد التعديل', fix, true);
await runCase('بعد التراجع', rollback, false);
console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
