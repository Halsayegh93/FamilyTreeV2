-- ═══════════════════════════════════════════════════════════════════════════
-- الإشعارات المجدولة (Scheduled Notifications)
-- المدير يقدر يجدول إشعار يُرسل في وقت محدد لاحقاً. تنطلق من الخادم عبر pg_cron
-- حتى لو جوال المدير مقفول — كل دقيقة نفحص الإشعارات المستحقة ونرسلها.
--
-- التدفّق:
--   1) التطبيق يُدرج صفاً في scheduled_notifications مع scheduled_for مستقبلي.
--   2) pg_cron كل دقيقة ينادي dispatch_due_scheduled_notifications().
--   3) الدالة تُدرج صف notifications (لمركز الإشعارات داخل التطبيق) وتنادي
--      edge function push-on-notification لإرسال APNs، ثم تعلّم الصف "sent".
-- ═══════════════════════════════════════════════════════════════════════════

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- 1) الجدول
create table if not exists public.scheduled_notifications (
    id                 uuid primary key default gen_random_uuid(),
    title              text not null,
    body               text not null,
    kind               text not null default 'admin_broadcast',
    -- NULL = broadcast للجميع، أو مصفوفة معرّفات الأعضاء المستهدفين
    target_member_ids  uuid[],
    scheduled_for      timestamptz not null,
    status             text not null default 'pending'
        check (status in ('pending', 'sent', 'canceled')),
    created_by         uuid,
    created_at         timestamptz not null default now(),
    sent_at            timestamptz
);

create index if not exists idx_scheduled_notifications_due
    on public.scheduled_notifications(status, scheduled_for);

-- 2) RLS — الإدارة (owner/admin) فقط تقدر تجدول/تطّلع/تلغي
alter table public.scheduled_notifications enable row level security;

drop policy if exists "scheduled_notifications_select_admin" on public.scheduled_notifications;
create policy "scheduled_notifications_select_admin" on public.scheduled_notifications
for select
using (public.current_user_role() in ('owner', 'admin'));

drop policy if exists "scheduled_notifications_insert_admin" on public.scheduled_notifications;
create policy "scheduled_notifications_insert_admin" on public.scheduled_notifications
for insert
with check (public.current_user_role() in ('owner', 'admin'));

drop policy if exists "scheduled_notifications_update_admin" on public.scheduled_notifications;
create policy "scheduled_notifications_update_admin" on public.scheduled_notifications
for update
using (public.current_user_role() in ('owner', 'admin'));

drop policy if exists "scheduled_notifications_delete_admin" on public.scheduled_notifications;
create policy "scheduled_notifications_delete_admin" on public.scheduled_notifications
for delete
using (public.current_user_role() in ('owner', 'admin'));

-- 3) دالة الإرسال — تُدرج الإشعارات المستحقة وتطلق push لكل منها
create or replace function public.dispatch_due_scheduled_notifications()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    rec       record;
    mid       uuid;
    proj_url  text := 'https://poxyxsgvzwmnmewytsiw.supabase.co';
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
            -- broadcast للجميع
            insert into public.notifications (target_member_id, title, body, kind, created_by)
            values (null, rec.title, rec.body, rec.kind, rec.created_by);

            perform net.http_post(
                url     := proj_url || '/functions/v1/push-on-notification',
                headers := '{"Content-Type": "application/json"}'::jsonb,
                body    := jsonb_build_object('record', jsonb_build_object(
                    'target_member_id', null,
                    'title', rec.title,
                    'body',  rec.body,
                    'kind',  rec.kind
                ))
            );
        else
            -- أعضاء محددون — صف + push لكل عضو
            foreach mid in array rec.target_member_ids loop
                insert into public.notifications (target_member_id, title, body, kind, created_by)
                values (mid, rec.title, rec.body, rec.kind, rec.created_by);

                perform net.http_post(
                    url     := proj_url || '/functions/v1/push-on-notification',
                    headers := '{"Content-Type": "application/json"}'::jsonb,
                    body    := jsonb_build_object('record', jsonb_build_object(
                        'target_member_id', mid,
                        'title', rec.title,
                        'body',  rec.body,
                        'kind',  rec.kind
                    ))
                );
            end loop;
        end if;

        update public.scheduled_notifications
        set status = 'sent', sent_at = now()
        where id = rec.id;
    end loop;
end;
$$;

-- 4) جدولة pg_cron — كل دقيقة (idempotent)
do $$
begin
    if exists (select 1 from cron.job where jobname = 'dispatch-scheduled-notifications') then
        perform cron.unschedule('dispatch-scheduled-notifications');
    end if;
end $$;

select cron.schedule(
    'dispatch-scheduled-notifications',
    '* * * * *',
    $$ select public.dispatch_due_scheduled_notifications(); $$
);
