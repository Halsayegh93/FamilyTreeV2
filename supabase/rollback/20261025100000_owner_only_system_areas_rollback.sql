-- تراجع 20261025100000_owner_only_system_areas: يرجع المدير كما كان (قراءة «الفريق والأمان» و«التطبيق»، تنبيهات
-- KWT SMS للمالك والمدير، أجهزة الآخرين والأرقام المحظورة وسجل الإعدادات، وكتابة أسماء العوائل).
-- الدوال: الشرط الجديد ← القديم (مرة واحدة بالضبط)، فتعود نصوصها كما كانت حرفياً (نفس md5 المذكورة في الترحيل).


do $unpatch$
declare
  r record;
  d text;
  n int;
begin
  for r in
    select * from (values
      ('public.sms_admin_overview()',
       $n$coalesce(public.current_user_role(), '') <> 'owner'$n$,
       $o$coalesce(public.current_user_role(), '') not in ('owner', 'admin')$o$),
      ('public.sms_admin_overview()',
       $n$'recipients', 'owner'$n$,
       $o$'recipients', 'owner_admins'$o$),
      ('public.sms_balance_status()',
       $n$coalesce(public.current_user_role(), '') <> 'owner'$n$,
       $o$coalesce(public.current_user_role(), '') not in ('owner', 'admin')$o$),
      ('public.sms_login_attempts(integer)',
       $n$coalesce(v_role, '') <> 'owner'$n$,
       $o$coalesce(v_role, '') not in ('owner', 'admin')$o$),
      ('public.app_config()',
       $n$if v_role = 'owner' then$n$,
       $o$if v_role in ('owner', 'admin') then$o$),
      ('public.finish_kwtsms_send(text,text,text,numeric,numeric,text)',
       $n$where p.role = 'owner' and p.status = 'active';$n$,
       $o$where p.role in ('owner', 'admin') and p.status = 'active';$o$),
      ('public.kwtsms_balance_check(numeric)',
       $n$where p.role = 'owner' and p.status = 'active';$n$,
       $o$where p.role in ('owner', 'admin') and p.status = 'active';$o$),
      ('public.log_login_attempt(text,text)',
       $n$where p.role = 'owner' and p.status = 'active';$n$,
       $o$where p.role in ('owner', 'admin') and p.status = 'active';$o$)
    ) v(sig, new_text, old_text)
  loop
    d := pg_get_functiondef(r.sig::regprocedure);
    n := (length(d) - length(replace(d, r.new_text, ''))) / length(r.new_text);
    if n <> 1 then
      raise exception 'owner_only_system_areas rollback: % — expected the new text once, found %', r.sig, n;
    end if;
    execute replace(d, r.new_text, r.old_text);
  end loop;
end
$unpatch$;

drop policy if exists device_tokens_select_self_or_owner on public.device_tokens;
create policy device_tokens_select_self_or_admin on public.device_tokens
  for select to authenticated
  using ((member_id = auth.uid()) or (public.current_user_role() = any (array['owner'::text, 'admin'::text])));

drop policy if exists device_tokens_owner_delete on public.device_tokens;
create policy device_tokens_admin_delete on public.device_tokens
  for delete to public
  using (public.current_user_role() = any (array['admin'::text, 'owner'::text]));

drop policy if exists device_revocations_select on public.device_revocations;
create policy device_revocations_select on public.device_revocations
  for select to authenticated
  using ((member_id = auth.uid()) or (public.current_user_role() = any (array['owner'::text, 'admin'::text])));

drop policy if exists device_revocations_insert_owner on public.device_revocations;
create policy device_revocations_insert_admin on public.device_revocations
  for insert to authenticated
  with check (public.current_user_role() = any (array['owner'::text, 'admin'::text]));

drop policy if exists device_revocations_update_owner on public.device_revocations;
create policy device_revocations_update_admin on public.device_revocations
  for update to authenticated
  using (public.current_user_role() = any (array['owner'::text, 'admin'::text]))
  with check (public.current_user_role() = any (array['owner'::text, 'admin'::text]));

drop policy if exists device_revocations_delete on public.device_revocations;
create policy device_revocations_delete on public.device_revocations
  for delete to authenticated
  using ((member_id = auth.uid()) or (public.current_user_role() = any (array['owner'::text, 'admin'::text])));

drop policy if exists banned_phones_select on public.banned_phones;
create policy banned_phones_select on public.banned_phones
  for select to public
  using (public.current_user_role() = any (array['admin'::text, 'owner'::text]));

drop policy if exists app_config_history_owner_read on public.app_config_history;
create policy app_config_history_owner_admin_read on public.app_config_history
  for select to authenticated
  using (coalesce(public.current_user_role(), '') = any (array['owner'::text, 'admin'::text]));

drop policy if exists family_names_write on public.family_names;
create policy family_names_write on public.family_names
  for all to public
  using (public.current_user_role() = any (array['owner'::text, 'admin'::text]))
  with check (public.current_user_role() = any (array['owner'::text, 'admin'::text]));
