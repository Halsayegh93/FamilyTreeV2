// تجربة 20261019130000 (إشعارات شجرة النساء: إضافة زوجة/بنت/أم فقط) على قاعدة محلية معزولة — لا تلمس السيرفر.
// التشغيل: cd supabase/tests/family_links && node women_notify_additions_only.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, (e.query ?? '').slice(0, 300)); process.exit(2); });
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const MIG = '20261019140000_women_notify_female_deletes';
const MIG0 = '20261019130000_women_notify_additions_only';
const mig = readFileSync(`${REPO}/migrations/${MIG}.sql`, 'utf8');
const rb = readFileSync(`${REPO}/rollback/${MIG0}_rollback.sql`, 'utf8');
const mig0 = readFileSync(`${REPO}/migrations/${MIG0}.sql`, 'utf8');
const rb1 = readFileSync(`${REPO}/rollback/${MIG}_rollback.sql`, 'utf8');
const db = new PGlite();
await db.exec(`
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create table public.profiles (id uuid primary key, role text, status text);
create table public.women_members (id uuid primary key, first_name text default '', full_name text default '',
  parent_id uuid, husband_id uuid, mother_id uuid, gender text default 'female', birth_date date, death_date date,
  is_deceased boolean default false, is_married boolean, is_hidden_from_tree boolean default false);
create table public.notifications (id uuid primary key default gen_random_uuid(), target_member_id uuid,
  created_by uuid, title text, body text, kind text, is_read boolean default false);
`);
await db.exec(rb); // الحي الحالي
await db.exec(`create trigger trg_women_activity_log after insert or delete or update on public.women_members
  for each row execute function public.log_women_change_to_activity();`);
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
await db.exec(`insert into public.profiles values ('${id(1)}','owner','active'),('${id(2)}','admin','active'),
  ('${id(3)}','supervisor','active'),('${id(4)}','member','active'),('${id(5)}','admin','frozen');`);
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('✓', m); } else { fail++; console.log('✗', m); } };
const count = async (where = 'true') => Number((await db.query(`select count(*)::int n from public.notifications where ${where}`)).rows[0].n);
const reset = () => db.exec('delete from public.notifications; delete from public.women_members;');

// قبل الترحيل: تعديل نسخة رجل يطلع إشعار (المشكلة)
await reset();
await db.exec(`insert into public.women_members (id, full_name, gender) values ('${id(10)}','حسن علي المحمدعلي','male');`);
await db.exec(`update public.women_members set full_name = 'حسن علي صلاح المحمدعلي' where id = '${id(10)}';`);
ok(await count(`kind='women_edit'`) === 3, 'قبل: تعديل نسخة رجل يُشعر ٣ مسؤولين (المشكلة)');

await db.exec(mig0);
await db.exec(mig);
await reset();
await db.exec(`insert into public.women_members (id, full_name, gender) values ('${id(10)}','حسن علي المحمدعلي','male');`);
ok(await count() === 0, 'بعد: إضافة نسخة رجل بلا إشعار');
await db.exec(`update public.women_members set full_name = 'حسن علي صلاح المحمدعلي', birth_date = '1990-05-01' where id = '${id(10)}';`);
ok(await count() === 0, 'بعد: تعديل نسخة رجل بلا إشعار');
await db.exec(`insert into public.women_members (id, full_name, gender, husband_id) values ('${id(11)}','فاطمة أحمد','female','${id(10)}');`);
ok(await count(`kind='women_add' and body like 'أُضيفت زوجة: فاطمة أحمد — زوجة حسن علي صلاح المحمدعلي'`) === 3, 'بعد: إضافة زوجة تُشعر ٣ مسؤولين باسمها واسم زوجها');
await db.exec(`insert into public.women_members (id, full_name, gender, parent_id) values ('${id(12)}','زينب حسن علي صلاح المحمدعلي','female','${id(10)}');`);
ok(await count(`body like 'أُضيفت بنت: زينب%بنت حسن علي صلاح المحمدعلي'`) === 3, 'بعد: إضافة بنت تُشعر باسمها واسم أبيها');
await db.exec(`insert into public.women_members (id, full_name, gender) values ('${id(13)}','مريم يوسف','female');`);
ok(await count(`body = 'أُضيفت إلى شجرة النساء: مريم يوسف'`) === 3, 'بعد: إضافة أم/امرأة بلا رابط تُشعر');
const before = await count();
await db.exec(`update public.women_members set full_name = 'فاطمة أحمد علي', husband_id = null where id = '${id(11)}';`);
ok(await count(`kind='women_edit' and body = 'فاطمة أحمد علي — الاسم · الزوج'`) === 3, 'بعد: تعديل امرأة يُشعر بالحقول المتغيّرة');
await db.exec(`update public.women_members set mother_id = '${id(13)}' where id = '${id(12)}';`);
ok(await count(`kind='women_edit' and body like '%— الأم'`) === 3, 'بعد: ربط بنت بأمها يُشعر');
await db.exec(`update public.women_members set full_name = full_name where id = '${id(12)}';`);
const mid = await count();
ok(mid === before + 6, 'بعد: حفظ بلا تغيير حقيقي بلا إشعار');
await db.exec(`delete from public.women_members where id = '${id(13)}';`);
ok(await count(`kind='women_delete' and body = 'حُذفت من شجرة النساء: مريم يوسف'`) === 3, 'بعد: حذف امرأة يُشعر');
const mid2 = await count();
await db.exec(`insert into public.women_members (id, full_name, gender) values ('${id(20)}','رجل مؤقت','male');`);
await db.exec(`delete from public.women_members where id = '${id(20)}';`);
ok(await count() === mid2, 'بعد: حذف نسخة رجل بلا إشعار');
ok(await count(`target_member_id = '${id(4)}' or target_member_id = '${id(5)}'`) === 0, 'العضو العادي والمجمّد ما يوصلهم');
await db.exec(`set request.jwt.claim.sub = '${id(2)}';`);
await db.exec(`insert into public.women_members (id, full_name, gender, parent_id) values ('${id(14)}','نور حسن','female','${id(10)}');`);
ok(await count(`body like 'أُضيفت بنت: نور حسن%'`) === 2 && await count(`body like 'أُضيفت بنت: نور حسن%' and target_member_id='${id(2)}'`) === 0, 'من أضاف ما يوصله إشعار');
await db.exec(`reset request.jwt.claim.sub;`);

await db.exec(rb1);
await reset();
await db.exec(`insert into public.women_members (id, full_name, gender) values ('${id(30)}','هدى','female');`);
await db.exec(`delete from public.women_members where id = '${id(30)}';`);
ok(await count(`kind='women_delete'`) === 0 && await count(`kind='women_add'`) === 3, 'بعد تراجع ١٤٠٠٠٠: حذف المرأة بلا إشعار (نسخة ١٣٠٠٠٠)');
await db.exec(rb);
await reset();
await db.exec(`insert into public.women_members (id, full_name, gender) values ('${id(10)}','حسن','male');`);
await db.exec(`update public.women_members set full_name = 'حسن علي' where id = '${id(10)}';`);
ok(await count(`kind='women_edit'`) === 3, 'بعد التراجع: يرجع السلوك القديم');
console.log(`\n${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
