// قاعدة معزولة: إشعار واحد لكل مستلم، ولا دفع قبل اكتمال الطلب.
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
await db.exec(`
create table profiles(id uuid primary key, full_name text, first_name text, role text, status text);
create table admin_requests(id uuid primary key, requester_id uuid, member_id uuid, request_type text, status text, details text);
create table notifications(id uuid default gen_random_uuid(), target_member_id uuid, title text, body text,
kind text, created_by uuid, is_read boolean, request_id uuid, request_type text, subject_member_id uuid, details jsonb);
create table push_attempts(notification_id uuid);
create function mock_push() returns trigger language plpgsql as $$ begin
 insert into push_attempts values(new.id); return new; end $$;
create trigger push after insert on notifications for each row execute function mock_push();
create function old_profile_notice() returns trigger language plpgsql as $$ begin
 insert into notifications(body) values('قديم'); return new; end $$;
create trigger trg_notify_admins_new_pending_member after insert on profiles
for each row execute function old_profile_notice();`);
await db.exec(readFileSync(new URL('../../migrations/20261006120000_single_join_notification.sql', import.meta.url), 'utf8'));
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const count = async table => Number((await db.query(`select count(*) n from ${table}`)).rows[0].n);
await db.query(`insert into profiles values
($1,'مالك','مالك','owner','active'),($2,'مدير','مدير','admin','active'),
($3,'مراقب مجمد','مراقب','monitor','frozen'),($4,'عضو','عضو','member','active'),
($5,'حسن المحمدعلي','حسن','pending','pending')`, [id(1),id(2),id(3),id(4),id(5)]);
assert.equal(await count('notifications'), 0, 'إنشاء الملف لا يولّد إشعاراً');
const insertRequest = async (n, type='link_request', status='pending') => db.query(
 `insert into admin_requests values($1,$2,$2,$3,$4,'تفاصيل المطابقات')`, [id(n), id(5), type, status]);
await insertRequest(10);
assert.equal(await count('notifications'), 2, 'إشعار واحد لكل إداري نشط');
assert.equal(await count('push_attempts'), 2, 'دفع واحد لكل إشعار');
const notices = (await db.query('select * from notifications')).rows;
assert(notices.every(n => n.body === 'حسن المحمدعلي قدّم طلب انضمام جديد'));
assert(notices.every(n => n.request_id === id(5) && n.request_type === 'join_request' && n.details.join_request_id === id(10)));
await db.query(`insert into notifications(target_member_id,kind,request_type,body)
values(null,'link_request','join_request','نسخة قديمة')`);
assert.equal(await count('notifications'), 2, 'نسخة التطبيق القديمة لا تكرّر السجل');
assert.equal(await count('push_attempts'), 2, 'نسخة التطبيق القديمة لا تكرّر دفع قاعدة البيانات');
await insertRequest(11, 'tree_edit');
await insertRequest(12, 'link_request', 'approved');
assert.equal(await count('notifications'), 2, 'أنواع أخرى وطلبات مكتملة لا تنتج إشعار انضمام');
// إعادة تنفيذ المشغّل لنفس الطلب لا تضيف صفاً أو دفعة ثانية.
await db.exec(`create trigger replay after insert on admin_requests for each row
execute function notify_admins_on_saved_join_request();`);
await insertRequest(13);
assert.equal(await count('notifications'), 4);
assert.equal(await count('push_attempts'), 4);
await db.exec('begin');
await insertRequest(14);
await db.exec('rollback');
assert.equal(await count('notifications'), 4, 'فشل المعاملة لا يترك إشعاراً');
await db.close();
console.log('PASS: saved join notification, recipients, legacy dedup, replay, rollback');
