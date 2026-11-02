-- حساب مراجعة أبل (طلب المالك ٢٠٢٦-١٠-٢٩): قائمة الحسابات على السيرفر،
-- محتواها لا يراه إلا صاحبها والإدارة، لا إشعارات منها، مخفية من قوائم الأعضاء، وتنظيف بأمر المالك أو تلقائياً.

insert into public.app_config(key, value, default_value, kind, category, sort, label_ar, help_ar, min_value, max_value, is_public)
values ('review_account_ids', '["f20a2fd2-67e2-44ae-a336-9f12e12bd13c"]'::jsonb, '[]'::jsonb, 'json', 'members', 96,
        'حسابات مراجعة Apple',
        'محتواها لا يراه إلا صاحبها والإدارة، لا تُرسل إشعارات لغيرها، ومخفية من قوائم الأعضاء.', null, null, false),
       ('review_account_cleanup_days', '7'::jsonb, '7'::jsonb, 'int', 'members', 97,
        'تنظيف محتوى حساب المراجعة (أيام)',
        'يُحذف يومياً محتوى حسابات المراجعة الأقدم من هذا العدد من الأيام.', 1, 90, false)
on conflict (key) do nothing;

create or replace function public.review_account_ids()
returns uuid[] language sql stable security definer set search_path = '' as $$
  select coalesce(array(select x::uuid from public.app_config c, jsonb_array_elements_text(c.value) x
                        where c.key = 'review_account_ids' and jsonb_typeof(c.value) = 'array'), '{}'::uuid[]);
$$;

-- ٢ و٥: الصف يظهر لصاحبه وللإدارة فقط إذا كان صاحبه حساب مراجعة
alter policy profiles_select_self_or_approved on public.profiles using (
  (id = auth.uid()) or ((select public.is_approved_member())
    and (not coalesce(id in (select unnest(public.review_account_ids())), false) or (select public.is_moderator()))));

alter policy news_select_approved_or_owner_or_moderator on public.news using (
  ((approval_status = 'approved' and not coalesce(coalesce(author_id, posted_by) in (select unnest(public.review_account_ids())), false)))
  or author_id = auth.uid() or posted_by = auth.uid() or (select public.is_moderator()));

alter policy news_comments_select_authenticated on public.news_comments using (
  auth.uid() is not null and (not coalesce(author_id in (select unnest(public.review_account_ids())), false)
    or author_id = auth.uid() or (select public.is_moderator())));

alter policy news_likes_select_authenticated on public.news_likes using (
  auth.uid() is not null and (not coalesce(member_id in (select unnest(public.review_account_ids())), false)
    or member_id = auth.uid() or (select public.is_moderator())));

alter policy diwaniyas_select_authenticated on public.diwaniyas using (
  auth.uid() is not null and ((approval_status = 'approved' and not coalesce(owner_id in (select unnest(public.review_account_ids())), false))
    or owner_id = auth.uid() or (select public.is_moderator())));

alter policy projects_select_authenticated on public.projects using (
  auth.uid() is not null and ((select public.is_moderator()) or owner_id = auth.uid()
    or (is_hidden = false and approval_status = 'approved' and not coalesce(owner_id in (select unnest(public.review_account_ids())), false))));

alter policy family_archive_select_authenticated on public.family_archive using (
  auth.uid() is not null and ((approval_status = 'approved' and is_hidden = false
      and not coalesce(coalesce(uploaded_by, '00000000-0000-0000-0000-000000000000'::uuid) in (select unnest(public.review_account_ids())), false))
    or current_user_role() = any(array['owner','admin']) or uploaded_by = auth.uid()));

-- ٣: أي إشعار يطلع بسبب حساب المراجعة لغيره يُلغى (اسم الزناد يسبق باقي الزنادات أبجدياً)
create or replace function public.trg_mute_review_account_notifications()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() = any(public.review_account_ids())
     and new.target_member_id is distinct from auth.uid()
     and coalesce(new.kind, '') <> 'review_account_activity' then
    return null;
  end if;
  return new;
end $$;

drop trigger if exists aa0_mute_review_account on public.notifications;
create trigger aa0_mute_review_account before insert on public.notifications
  for each row execute function public.trg_mute_review_account_notifications();

-- ٥: تنظيف محتوى حسابات المراجعة (الأقدم من p_days يوم؛ ٠ = الكل). المالك فقط، أو المهمة اليومية.
create or replace function public.review_account_cleanup(p_days integer default 0)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  ids uuid[] := public.review_account_ids();
  cutoff timestamptz := now() - make_interval(days => greatest(coalesce(p_days, 0), 0));
  n_comments int; n_likes int; n_news int; n_diw int; n_proj int; n_arch int; n_notif int;
begin
  if auth.uid() is not null and coalesce(public.current_user_role(), '') <> 'owner' then
    raise exception 'owner only' using errcode = '42501';
  end if;
  if cardinality(ids) = 0 then return '{}'::jsonb; end if;
  delete from public.news_comments where author_id = any(ids) and created_at < cutoff; get diagnostics n_comments = row_count;
  delete from public.news_likes where member_id = any(ids) and created_at < cutoff; get diagnostics n_likes = row_count;
  delete from public.news where (author_id = any(ids) or posted_by = any(ids)) and created_at < cutoff; get diagnostics n_news = row_count;
  delete from public.diwaniyas where owner_id = any(ids) and created_at < cutoff; get diagnostics n_diw = row_count;
  delete from public.projects where owner_id = any(ids) and created_at < cutoff; get diagnostics n_proj = row_count;
  delete from public.family_archive where uploaded_by = any(ids) and created_at < cutoff; get diagnostics n_arch = row_count;
  delete from public.notifications where target_member_id = any(ids) and created_at < cutoff; get diagnostics n_notif = row_count;
  return jsonb_build_object('comments', n_comments, 'likes', n_likes, 'news', n_news, 'diwaniyas', n_diw,
                            'projects', n_proj, 'archive', n_arch, 'notifications', n_notif);
end $$;

revoke all on function public.review_account_cleanup(integer) from public, anon;
grant execute on function public.review_account_cleanup(integer) to authenticated;

select cron.schedule('review-account-cleanup', '30 0 * * *', $c$
  select public.review_account_cleanup(coalesce((select (value)::text::int from public.app_config
                                                  where key = 'review_account_cleanup_days'), 7));
$c$);

-- إضافة ١: إشعار للمالك أول ما يفتح حساب المراجعة التطبيق (مرة كل ٦ ساعات على الأكثر)
create or replace function public.trg_review_account_activity()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.id = any(public.review_account_ids())
     and new.last_active_at is not null
     and (old.last_active_at is null or new.last_active_at > old.last_active_at + interval '6 hours') then
    insert into public.notifications(target_member_id, title, body, kind, subject_member_id)
    select p.id, 'حساب مراجعة Apple', 'حساب المراجعة فتح التطبيق الحين — غالباً Apple بدأت المراجعة.',
           'review_account_activity', new.id
      from public.profiles p where p.role = 'owner';
  end if;
  return null;
end $$;

drop trigger if exists trg_review_account_activity on public.profiles;
create trigger trg_review_account_activity after update of last_active_at on public.profiles
  for each row execute function public.trg_review_account_activity();

-- إضافة ٢: إيقاف/تشغيل دخول حسابات المراجعة (المالك فقط) — false يمنع الدخول وتجديد الجلسة
create or replace function public.set_review_account_access(p_enabled boolean)
returns integer language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if coalesce(public.current_user_role(), '') <> 'owner' then
    raise exception 'owner only' using errcode = '42501';
  end if;
  update auth.users set banned_until = case when p_enabled then null else 'infinity'::timestamptz end
   where id = any(public.review_account_ids());
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.set_review_account_access(boolean) from public, anon;
grant execute on function public.set_review_account_access(boolean) to authenticated;
