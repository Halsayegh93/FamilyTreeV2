-- حظر الأعضاء على السيرفر (قرار المالك ٢٠٢٦-١٠-٢٩ «نعم اصلح»، Apple 1.2): الحظر يتبع العضو على كل أجهزته.
-- • الجدول القديم blocked_users (فاضٍ، يكتبه الأندرويد مباشرة) يصير member_blocks، وتبقى واجهة توافق باسم blocked_users
--   (security_invoker — نفس RLS) حتى يتحوّل الأندرويد إلى الدوال؛ finalize_account_deletion يمسح عبرها كما كان.
-- • block_member يرسل للإدارة بلاغ «عضو محظور» (content_report) + إشعار — مكان بلاغ التطبيق (BlockMemberFlow.swift:112)،
--   فالتطبيقات توقف بلاغها الخاص بعد التحديث. البلاغ مرة واحدة لكل حظر جديد.
-- • لا مراسلة بين الأعضاء في القاعدة، فلا منع تواصل على السيرفر؛ إخفاء محتوى المحظور يبقى في التطبيقات.

alter table public.blocked_users rename to member_blocks;
alter table public.member_blocks rename constraint blocked_users_pkey to member_blocks_pkey;
alter table public.member_blocks rename constraint blocked_users_blocker_id_fkey to member_blocks_blocker_id_fkey;
alter table public.member_blocks rename constraint blocked_users_blocked_id_fkey to member_blocks_blocked_id_fkey;
alter table public.member_blocks alter column created_at set default now();
alter table public.member_blocks add constraint member_blocks_not_self check (blocker_id <> blocked_id);
create index if not exists member_blocks_blocked_idx on public.member_blocks (blocked_id);

drop policy if exists blocked_users_select on public.member_blocks;
drop policy if exists blocked_users_insert on public.member_blocks;
drop policy if exists blocked_users_delete on public.member_blocks;
alter table public.member_blocks enable row level security;
create policy member_blocks_select on public.member_blocks for select to authenticated
  using (blocker_id = any (array[auth.uid(), public.current_profile_id()]) or public.is_team(auth.uid()));
create policy member_blocks_insert on public.member_blocks for insert to authenticated
  with check (blocker_id = any (array[auth.uid(), public.current_profile_id()]) and public.is_approved_member());
create policy member_blocks_delete on public.member_blocks for delete to authenticated
  using (blocker_id = any (array[auth.uid(), public.current_profile_id()]));
-- upsert الأندرويد (merge-duplicates) يحتاج UPDATE على صفوفه فقط
create policy member_blocks_update on public.member_blocks for update to authenticated
  using (blocker_id = any (array[auth.uid(), public.current_profile_id()]))
  with check (blocker_id = any (array[auth.uid(), public.current_profile_id()]));
revoke all on public.member_blocks from anon;
revoke all on public.member_blocks from authenticated;
grant select, insert, update, delete on public.member_blocks to authenticated;

-- توافق مؤقت للأندرويد (from('blocked_users') select/upsert/delete)
create view public.blocked_users with (security_invoker = true) as
  select blocker_id, blocked_id, created_at from public.member_blocks;
revoke all on public.blocked_users from anon, authenticated;
grant select, insert, update, delete on public.blocked_users to authenticated;

create or replace function public.block_member(p_member uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  me       uuid := public.current_profile_id();
  t_name   text;
  r_name   text;
  added    boolean;
  req_id   uuid;
  v_details text;
begin
  if auth.uid() is null or me is null then
    raise exception 'not_authenticated' using errcode = '42501', hint = 'not_authenticated';
  end if;
  if not public.is_approved_member() then
    raise exception 'حسابك غير مفعّل' using errcode = '42501', hint = 'not_allowed';
  end if;
  if p_member is null or p_member = me or p_member = auth.uid() then
    raise exception 'لا يمكنك حظر نفسك' using errcode = '22023', hint = 'self_block';
  end if;
  select coalesce(nullif(btrim(p.full_name), ''), p.first_name) into t_name from public.profiles p where p.id = p_member;
  if not found then
    raise exception 'العضو غير موجود' using errcode = 'P0002', hint = 'member_not_found';
  end if;
  insert into public.member_blocks (blocker_id, blocked_id) values (me, p_member)
  on conflict do nothing;
  added := found;
  if added then
    select coalesce(nullif(btrim(p.full_name), ''), p.first_name, '') into r_name from public.profiles p where p.id = me;
    v_details := '[عضو محظور] ' || coalesce(t_name, '') || ' — السبب: حظره أحد الأعضاء بسبب الإساءة — يرجى مراجعة محتواه وحسابه';
    insert into public.admin_requests (member_id, requester_id, request_type, status, details, new_value)
    values (me, me, 'content_report', 'pending', v_details, p_member::text)
    returning id into req_id;
    insert into public.notifications (target_member_id, title, body, kind, created_by, request_id, request_type)
    select h.id, 'بلاغ على محتوى',
           coalesce(nullif(r_name, ''), 'عضو') || ' أبلغ عن عضو محظور: ' || coalesce(t_name, '')
             || ' — حظره بسبب الإساءة — يرجى مراجعة محتواه وحسابه',
           'content_report', me, req_id, 'content_report'
      from public.profiles h
     where h.status = 'active' and h.role in ('owner', 'admin', 'supervisor') and h.id <> me;
  end if;
  return jsonb_build_object('ok', true, 'blocked', true, 'already_blocked', not added, 'request_id', req_id);
end $$;

create or replace function public.unblock_member(p_member uuid)
returns boolean language plpgsql security definer set search_path to 'public' as $$
declare n int;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501', hint = 'not_authenticated';
  end if;
  delete from public.member_blocks
   where blocker_id = any (array[auth.uid(), public.current_profile_id()]) and blocked_id = p_member;
  get diagnostics n = row_count;
  return n > 0;
end $$;

create or replace function public.my_blocked_ids()
returns setof uuid language sql stable security definer set search_path to 'public' as $$
  select distinct b.blocked_id from public.member_blocks b
   where auth.uid() is not null and b.blocker_id = any (array[auth.uid(), public.current_profile_id()]);
$$;

revoke all on function public.block_member(uuid) from public, anon;
revoke all on function public.unblock_member(uuid) from public, anon;
revoke all on function public.my_blocked_ids() from public, anon;
grant execute on function public.block_member(uuid) to authenticated;
grant execute on function public.unblock_member(uuid) to authenticated;
grant execute on function public.my_blocked_ids() to authenticated;
