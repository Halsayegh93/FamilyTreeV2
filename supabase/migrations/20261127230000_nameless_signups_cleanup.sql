-- مطبَّق على الحي ٢٠٢٦-١١-٢٧ بعد تجربة begin…rollback (التجربة بيوم واحد وجدت التسعة بالضبط؛ بـ٣٠ يوماً لا يُحذف أحد قبل ١٨ ديسمبر)
-- «أرقام بدون أسماء»: حذف تلقائي بعد ٣٠ يوماً لمن أدخل رمز الدخول ولم يكمل نموذج التسجيل (قرار المالك ٢٠٢٦-١١-٢٧ «نفذ كلها»).
-- الشرط: ملف بلا اسم، حالته «معلّق»، دوره عضو/معلّق، بلا أب، بلا طلب مراجعة باسمه، بلا صفّ نسب، ليس حساب المراجعة، وأقدم من ٣٠ يوماً.
-- يحذف أجهزته وإشعاراته ثم ملفه ثم حساب الدخول — لا بيانات له غير الرقم. يقدر يسجّل من جديد في أي وقت.
-- التراجع: select cron.unschedule('nameless-signups-cleanup'); drop function private.cleanup_nameless_signups(integer);
create or replace function private.cleanup_nameless_signups(p_days integer default 30)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare ids uuid[]; n integer;
begin
  select coalesce(array_agg(p.id), '{}') into ids
    from public.profiles p
    join auth.users u on u.id = p.id
   where nullif(btrim(coalesce(p.full_name, '')), '') is null
     and nullif(btrim(coalesce(p.first_name, '')), '') is null
     and coalesce(p.status, 'pending') = 'pending'
     and coalesce(p.role, 'pending') in ('member', 'pending')
     and p.father_id is null
     and p.created_at < now() - make_interval(days => greatest(p_days, 1))
     and p.id <> all (coalesce((select array_agg(r) from public.review_account_ids() r), '{}'))
     and not exists (select 1 from public.admin_requests r where r.requester_id = p.id or r.member_id = p.id)
     and not exists (select 1 from public.daughter_son_lineage d where d.profile_id = p.id)
     and not exists (select 1 from public.women_members w where w.id = p.id or w.linked_user_id = p.id);
  n := coalesce(array_length(ids, 1), 0);
  if n = 0 then return 0; end if;
  delete from public.device_tokens where member_id = any (ids);
  delete from public.notifications where target_member_id = any (ids);
  delete from public.profiles where id = any (ids);
  delete from auth.users where id = any (ids);
  return n;
end;
$function$;
revoke all on function private.cleanup_nameless_signups(integer) from public, anon, authenticated;

select cron.schedule('nameless-signups-cleanup', '40 3 * * *', 'select private.cleanup_nameless_signups(30)');
