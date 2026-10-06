// تجربة البحث بالاسم عند التسجيل (search_members_by_name) على قاعدة محلية معزولة (لا تلمس السيرفر):
// قبل التعديل (نص ملف التراجع = النسخة الحية) ← بعد التعديل ← بعد التراجع.
// التشغيل: cd supabase/tests/family_links && node name_search.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message); process.exit(2); });
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const fix = readFileSync(`${REPO}/migrations/20261005180000_name_search_ignore_family.sql`, 'utf8');
const rollback = readFileSync(`${REPO}/rollback/20261005180000_name_search_ignore_family_rollback.sql`, 'utf8');

const db = new PGlite();
await db.exec(`
  create table public.profiles (id uuid primary key, full_name text, role text);
  create table public.family_names (id serial, name text);
  insert into public.family_names(name) values ('المحمدعلي'), ('العلي'), ('الصايغ');
  insert into public.profiles values
    ('00000000-0000-0000-0000-000000000001', 'عبدالله اياد عبدالحميد حسن موسى محمدعلي حسن المحمدعلي', 'member'),
    ('00000000-0000-0000-0000-000000000002', 'عبدالله عبدالحميد عبدالله حسن علي حسين علي عبدالله المحمدعلي', 'member'),
    ('00000000-0000-0000-0000-000000000003', 'حمد اياد عبدالحميد حسن موسى محمدعلي حسن المحمدعلي', 'member'),
    ('00000000-0000-0000-0000-000000000004', 'محمد علي حسن العلي', 'member'),
    ('00000000-0000-0000-0000-000000000005', 'عبدالله اياد عبدالحميد', 'pending');
`);

let pass = 0, fail = 0;
const ok = (cond, msg) => { if (cond) { pass++; console.log('  ✓', msg); } else { fail++; console.log('  ✗', msg); } };
const search = async q => (await db.query(`select member_id::text as id, match_score from public.search_members_by_name($1)`, [q])).rows;
const ids = rows => rows.map(r => r.id.slice(-1)).join(',');

async function checks(label, fixed) {
  console.log(`\n— ${label}`);
  const a = await search('عبدالله اياد المحمدعلي');
  ok(fixed ? ids(a) === '1' : ids(a) === '', `«عبدالله اياد المحمدعلي» ${fixed ? 'يجد عبدالله بن اياد وحده' : 'لا يجد شيئاً (الخلل)'} → [${ids(a)}]`);
  const b = await search('عبدالله اياد');
  ok(ids(b) === '1', `«عبدالله اياد» يجد عبدالله بن اياد → [${ids(b)}]`);
  const c = await search('عبدالله اياد عبدالحميد المحمدعلي');
  ok(ids(c) === '1', `أربعة أجزاء مع العائلة يجد الصحيح → [${ids(c)}]`);
  const d = await search('محمد احمد المحمدعلي');
  ok(ids(d) === '', `اسم غير موجود لا يطابق أحداً → [${ids(d)}]`);
  const e = await search('عبدالله المحمدعلي');
  ok(ids(e) === '', `الاسم الأول + العائلة فقط لا يطابق (يحتاج جزأين) → [${ids(e)}]`);
  const f = await search('محمد علي العلي');
  ok(ids(f) === '4', `«العلي» عائلة تُستبعد و«علي» اسم يبقى → [${ids(f)}]`);
  const g = await search('عبدالله عبدالحميد عبدالله');
  // الجزء المكرر يُحسب مرة (distinct) — سلوك قديم لم يتغيّر: نفس النتيجة قبل التعديل وبعده
  ok(ids(g) === '1,2', `بلا اسم عائلة يبقى السلوك كما هو → [${ids(g)}]`);
  ok(!ids(await search('عبدالله اياد عبدالحميد')).includes('5'), 'المعلّق (role pending) لا يظهر في النتائج');
}

await db.exec(rollback);
await checks('قبل التعديل (النسخة الحية)', false);
await db.exec(fix);
await checks('بعد التعديل', true);
await db.exec(rollback);
await checks('بعد التراجع (رجعت كما كانت)', false);

console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
