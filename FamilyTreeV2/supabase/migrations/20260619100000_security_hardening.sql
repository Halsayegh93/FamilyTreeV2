-- ═══════════════════════════════════════════════════════════════════════════
-- تحصين أمني شامل (Security hardening) — 2026-06-19
-- يعالج ثغرات أكّدها الفحص:
--   A) profiles: سياسات قديمة متساهلة من remote_schema لم تُحذف تسمح لأي عضو
--      مسجّل بتعديل/إدراج أي ملف شخصي (انتحال). نحذفها ونُبقي السياسات المُدارة.
--   B) news_comments / news_likes: مقروءة بدون تسجيل دخول (using true) → نقيّدها.
--   C) family-archive في التخزين: مقروءة بدون تسجيل دخول → نقيّدها.
--   D) push-on-notification: تُنادى فقط من dispatch (cron). نمرّر سرّاً مشتركاً
--      حتى لا يقدر أي شخص استدعاءها لبثّ إشعار. (الدالة تتحقق من السرّ.)
-- ملاحظة: الإرسال الفوري يستخدم push-admins/push-notify (موثّقة) ولا يتأثر.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── A) profiles: حذف السياسات الواسعة المتبقّية من remote_schema ──────────────
-- التعديل المفتوح للجميع (الثغرة الفعلية):
drop policy if exists "Allow users to update profiles" on public.profiles;
drop policy if exists "Users can update their own profiles" on public.profiles;
drop policy if exists "Admins and Supervisors can update any profile" on public.profiles;
drop policy if exists "Admins can delete any profile" on public.profiles;

-- الإدراج بأي دور (يسمح بحقن ملف "owner/admin" مزيّف):
drop policy if exists "Allow authenticated users to insert profiles" on public.profiles;
drop policy if exists "profiles_insert_authenticated" on public.profiles;
drop policy if exists "profiles_insert_self" on public.profiles;

-- إدراج آمن: المُشرفون يضيفون أي دور؛ العضو العادي (تسجيل/إضافة ابن) يقتصر على
-- pending/member فقط — يمنع رفع الصلاحية عبر الإدراج (لا trigger على INSERT).
create policy "profiles_insert_safe" on public.profiles
  for insert
  to public
  with check (
    auth.uid() is not null
    and (
      public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
      or coalesce(role, 'pending') in ('pending', 'member')
    )
  );

-- تبقى السياسات المُدارة كما هي (آمنة):
--   profiles_select_self_or_active  (SELECT)
--   profiles_update_self_or_moderator  (UPDATE: self أو owner/admin/monitor/supervisor)
--   profiles_delete_admin_or_owner  (DELETE)
-- والـ trigger trg_prevent_role_self_promotion يمنع تغيير الدور/الحالة للأعضاء.

-- ── B) news_comments / news_likes: تتطلّب تسجيل دخول للقراءة ───────────────────
drop policy if exists "Anyone can select likes" on public.news_likes;
create policy "news_likes_select_authenticated" on public.news_likes
  for select using (auth.uid() is not null);

drop policy if exists "Anyone can select comments" on public.news_comments;
create policy "news_comments_select_authenticated" on public.news_comments
  for select using (auth.uid() is not null);

-- ── C) family-archive (storage): قراءة للمسجّلين فقط ─────────────────────────
drop policy if exists "family_archive_storage_read" on storage.objects;
create policy "family_archive_storage_read"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'family-archive' and auth.uid() is not null);

-- ── D) سرّ webhook لـ push-on-notification ───────────────────────────────────
-- يُخزَّن في جدول خاص (private) لا يملك anon/authenticated صلاحية USAGE على مخططه،
-- فلا يقرأه إلا دالة dispatch (security definer) وترسله كترويسة x-webhook-secret.
-- نفس القيمة مضبوطة كسرّ للدالة عبر `supabase secrets set PUSH_WEBHOOK_SECRET=…`.
create schema if not exists private;
revoke all on schema private from anon, authenticated;

create table if not exists private.app_secrets (
    key   text primary key,
    value text not null
);
revoke all on private.app_secrets from anon, authenticated;

insert into private.app_secrets (key, value)
values ('push_webhook_secret', 'e98f1601b391ffdbce361a2d694f5eedd4240810c3f87085')
on conflict (key) do update set value = excluded.value;

-- إعادة تعريف دالة الإرسال لتمرير الترويسة x-webhook-secret
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
    v_secret  text;
    hdrs      jsonb;
begin
    select value into v_secret from private.app_secrets where key = 'push_webhook_secret';
    hdrs := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', coalesce(v_secret, '')
    );
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
            insert into public.notifications (target_member_id, title, body, kind, created_by)
            values (null, rec.title, rec.body, rec.kind, rec.created_by);

            perform net.http_post(
                url     := proj_url || '/functions/v1/push-on-notification',
                headers := hdrs,
                body    := jsonb_build_object('record', jsonb_build_object(
                    'target_member_id', null,
                    'title', rec.title,
                    'body',  rec.body,
                    'kind',  rec.kind
                ))
            );
        else
            foreach mid in array rec.target_member_ids loop
                insert into public.notifications (target_member_id, title, body, kind, created_by)
                values (mid, rec.title, rec.body, rec.kind, rec.created_by);

                perform net.http_post(
                    url     := proj_url || '/functions/v1/push-on-notification',
                    headers := hdrs,
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
