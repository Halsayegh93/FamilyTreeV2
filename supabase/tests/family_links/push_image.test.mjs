// تجربة 20261125120000_push_image («صورة الإشعار») على قاعدة محلية معزولة — لا تلمس السيرفر.
// مشغّل الدفع بتعريفه الحيّ (٢٠٢٦-١١-٢٥) و`net.http_post` وهمي يحفظ ما يُرسل. يثبت: بلا صورة المُرسَل حرفياً كما كان،
// مسار push/<uuid>.jpg يصل image_path، المسارات الأخرى تُهمل، المجدول ينقل details لموعده (عام ولأعضاء)،
// إعادة التطبيق بلا أثر، والتراجع يعيد الدالتين حرفياً ويحذف العمود.
// التشغيل: cd supabase/tests/family_links && npm install && node push_image.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../../', import.meta.url));
const MIG = readFileSync(`${REPO}/migrations/20261125120000_push_image.sql`, 'utf8');
const RB = readFileSync(`${REPO}/rollback/20261125120000_push_image_rollback.sql`, 'utf8');
let pass = 0, fail = 0;
const ok = (c, m, x = '') => { if (c) { pass++; console.log('✓', m); } else { fail++; console.log('✗', m, x); } };

const db = new PGlite();
await db.exec(`
create schema private;
create schema net;
create table private.app_secrets (key text primary key, value text);
insert into private.app_secrets values ('push_webhook_secret', 's3cret');
create table public.app_settings (notifications_paused boolean not null default false);
insert into public.app_settings default values;
create table public.notifications (id uuid primary key default gen_random_uuid(), target_member_id uuid, title text, body text,
  kind text, created_by uuid, created_at timestamptz default now(), is_read boolean, request_id uuid, request_type text,
  details jsonb, subject_member_id uuid);
create table public.scheduled_notifications (id uuid primary key default gen_random_uuid(), title text not null, body text not null,
  kind text not null default 'admin_broadcast', target_member_ids uuid[], scheduled_for timestamptz not null,
  status text not null default 'pending', created_by uuid, created_at timestamptz not null default now(), sent_at timestamptz);
create table public.posted (n serial, url text, headers jsonb, body jsonb);
create function net.http_post(url text, headers jsonb, body jsonb) returns bigint language plpgsql as $$
begin insert into public.posted (url, headers, body) values (url, headers, body); return 1; end $$;
create function public.notification_push_allowed(p_target uuid, p_kind text, p_subject uuid) returns boolean
language sql as $$ select true $$;
`);

// التعريف الحيّ (pg_get_functiondef على السيرفر ٢٠٢٦-١١-٢٥)
await db.exec(`
CREATE OR REPLACE FUNCTION public.trigger_push_on_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_secret text;
begin
  -- نسخ البثّ العام تُدرَج من داخل مُطلِق التفريخ (depth > 1): الدفع خرج
  -- مسبقاً مرة واحدة من الصف المشترك، فلا نكرّره آلاف المرات.
  if pg_trigger_depth() > 1
     and coalesce(new.kind, '') in ('admin_broadcast', 'app_update') then
    return new;
  end if;

  -- زر إيقاف الإشعارات
  if coalesce((select s.notifications_paused from public.app_settings s limit 1), false) then
    return new;
  end if;

  -- إضافة ابن عادية: داخل التطبيق فقط، والجوال لـ«راجعه»
  if coalesce((new.details ->> 'self_child')::boolean, false) and not coalesce((new.details ->> 'review')::boolean, false) then
    return new;
  end if;
  -- العضو أطفأ هذا النوع — يبقى الإشعار داخل التطبيق بلا push
  if not public.notification_push_allowed(new.target_member_id, coalesce(new.kind, ''), new.subject_member_id) then
    return new;
  end if;

  select value into v_secret from private.app_secrets where key = 'push_webhook_secret';
  perform net.http_post(
    url := 'https://poxyxsgvzwmnmewytsiw.supabase.co/functions/v1/push-on-notification'::text,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', coalesce(v_secret, '')
    ),
    body := jsonb_build_object(
      'record', jsonb_build_object(
        'target_member_id', new.target_member_id,
        'title', new.title,
        'body', new.body,
        'kind', coalesce(new.kind, 'notification'),
        'request_id', new.request_id,
        'request_type', new.request_type,
        'notification_id', new.id
      )
    )
  );
  return new;
end;
$function$;
create trigger trg_push_on_notification after insert on public.notifications
  for each row execute function public.trigger_push_on_notification();

CREATE OR REPLACE FUNCTION public.dispatch_due_scheduled_notifications()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    rec record;
    mid uuid;
begin
    for rec in
        select * from public.scheduled_notifications
        where status = 'pending'
          and scheduled_for <= now()
        order by scheduled_for
        limit 50
        for update skip locked
    loop
        if rec.target_member_ids is null
           or array_length(rec.target_member_ids, 1) is null then
            -- إشعار عام — الإدراج وحده يشغّل التريغر الذي يتكفّل بالدفع
            insert into public.notifications (target_member_id, title, body, kind, created_by)
            values (null, rec.title, rec.body, rec.kind, rec.created_by);
        else
            foreach mid in array rec.target_member_ids loop
                insert into public.notifications (target_member_id, title, body, kind, created_by)
                values (mid, rec.title, rec.body, rec.kind, rec.created_by);
            end loop;
        end if;

        update public.scheduled_notifications
        set status = 'sent', sent_at = now()
        where id = rec.id;
    end loop;
end;
$function$;
`);

const def = async (fn) => (await db.query(`select pg_get_functiondef('public.${fn}()'::regprocedure) d`)).rows[0].d;
const PUSH0 = await def('trigger_push_on_notification');
const DISPATCH0 = await def('dispatch_due_scheduled_notifications');
const ID = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const IMG = 'push/0f8fad5b-d9cb-469f-a165-70867728950e.jpg';
const lastRecord = async () => (await db.query(`select body from public.posted order by n desc limit 1`)).rows[0]?.body?.record;
const postedCount = async () => Number((await db.query(`select count(*) c from public.posted`)).rows[0].c);
const insert = (target, details) => db.query(
  `insert into public.notifications (id, target_member_id, title, body, kind, details) values ($1, $2, 'عنوان', 'نص', 'admin_broadcast', $3::jsonb)`,
  [ID(Math.floor(Math.random() * 1e9)), target, details == null ? null : JSON.stringify(details)]);

// قبل الترحيل: شكل ما يُرسل اليوم
await db.query(`insert into public.notifications (id, target_member_id, title, body, kind) values ($1, $2, 'عنوان', 'نص', 'admin_broadcast')`, [ID(1), ID(9)]);
const before = await lastRecord();

await db.exec(MIG);
const PUSH1 = await def('trigger_push_on_notification');
ok(PUSH1 !== PUSH0 && PUSH1.includes("'image_path'"), 'مشغّل الدفع رُقّع');
ok(PUSH1.includes("-- زر إيقاف الإشعارات") && PUSH1.includes("-- إضافة ابن عادية"), 'الترقيعات السابقة باقية');

await db.query(`insert into public.notifications (id, target_member_id, title, body, kind) values ($1, $2, 'عنوان', 'نص', 'admin_broadcast')`, [ID(2), ID(9)]);
const after = await lastRecord();
ok(JSON.stringify({ ...after, notification_id: null }) === JSON.stringify({ ...before, notification_id: null }) && !('image_path' in after),
   'بلا صورة: المُرسَل حرفياً كما كان (بلا مفتاح image_path)', JSON.stringify(after));

await insert(ID(9), { image_path: IMG });
ok((await lastRecord()).image_path === IMG, 'صورة push/<uuid>.jpg تصل image_path');
await insert(null, { image_path: IMG, sender: { type: 'admin' } });
const bc = await lastRecord();
ok(bc.image_path === IMG && bc.target_member_id === null, 'الإعلان العام (target null) يحمل الصورة');
for (const bad of ['news/abc.jpg', 'launch/0f8fad5b-d9cb-469f-a165-70867728950e.jpg', 'push/../avatars/x.jpg',
                   'push/0f8fad5b-d9cb-469f-a165-70867728950e.gif', '', 'push/0F8FAD5B-D9CB-469F-A165-70867728950E.jpg']) {
  await insert(ID(9), { image_path: bad });
  ok(!('image_path' in (await lastRecord())), `مسار مرفوض يُهمل: «${bad}»`);
}
await insert(ID(9), { other: 1 });
ok(!('image_path' in (await lastRecord())), 'details بلا صورة لا تضيف شيئاً');

// المجدول
const cols = (await db.query(`select column_name, data_type from information_schema.columns where table_name = 'scheduled_notifications' and column_name = 'details'`)).rows;
ok(cols.length === 1 && cols[0].data_type === 'jsonb', 'scheduled_notifications.details jsonb');
await db.query(`insert into public.scheduled_notifications (title, body, scheduled_for, details) values ('مجدول', 'عام', now() - interval '1 minute', $1::jsonb)`,
  [JSON.stringify({ image_path: IMG })]);
await db.query(`insert into public.scheduled_notifications (title, body, scheduled_for, target_member_ids, details) values ('مجدول', 'لأعضاء', now() - interval '1 minute', $1, $2::jsonb)`,
  [[ID(7), ID(8)], JSON.stringify({ image_path: IMG })]);
await db.query(`insert into public.scheduled_notifications (title, body, scheduled_for) values ('مجدول', 'بلا صورة', now() - interval '1 minute')`);
const n0 = await postedCount();
await db.exec(`select public.dispatch_due_scheduled_notifications()`);
const rows = (await db.query(`select target_member_id, body, details from public.notifications where title = 'مجدول' order by body, target_member_id`)).rows;
ok(rows.length === 4, 'المجدول: ٤ صفوف (عام + عضوان + بلا صورة)', JSON.stringify(rows));
ok(rows.filter(r => r.body !== 'بلا صورة').every(r => r.details?.image_path === IMG), 'details تنتقل لكل صف بصورة');
ok(rows.find(r => r.body === 'بلا صورة').details === null, 'المجدول بلا صورة: details فارغة كما كان');
const posted = (await db.query(`select body from public.posted order by n offset $1`, [n0])).rows.map(r => r.body.record);
ok(posted.length === 4 && posted.filter(r => r.image_path === IMG).length === 3 && posted.filter(r => !('image_path' in r)).length === 1,
   'دفع المجدول يحمل الصورة لمن له صورة فقط', JSON.stringify(posted));
ok(Number((await db.query(`select count(*) c from public.scheduled_notifications where status = 'sent'`)).rows[0].c) === 3, 'المجدول عُلِّم «أُرسل»');

// إعادة التطبيق بلا أثر
await db.exec(MIG);
ok((await def('trigger_push_on_notification')) === PUSH1, 'إعادة الترحيل لا تكرّر الترقيع');

// التراجع
await db.exec(RB);
ok((await def('trigger_push_on_notification')) === PUSH0, 'التراجع: مشغّل الدفع حرفياً كما كان');
ok((await def('dispatch_due_scheduled_notifications')) === DISPATCH0, 'التراجع: الموزّع حرفياً كما كان');
ok((await db.query(`select 1 from information_schema.columns where table_name = 'scheduled_notifications' and column_name = 'details'`)).rows.length === 0,
   'التراجع: العمود حُذف');
await db.query(`insert into public.notifications (id, target_member_id, title, body, kind) values ($1, $2, 'عنوان', 'نص', 'admin_broadcast')`, [ID(3), ID(9)]);
const back = await lastRecord();
ok(JSON.stringify({ ...back, notification_id: null }) === JSON.stringify({ ...before, notification_id: null }), 'بعد التراجع: المُرسَل كما كان');
await db.exec(RB);
ok((await def('trigger_push_on_notification')) === PUSH0, 'تكرار التراجع بلا أثر');

await db.close();
console.log(`\n${pass} نجح · ${fail} فشل`);
process.exit(fail ? 1 : 0);
