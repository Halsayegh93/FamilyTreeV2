-- فحص ٢٠٢٦-١٠-٢٤ — دفعة السيرفر (موافقة المالك «كمل كل الاصلاحات»)
-- التراجع: rollback/20261024130000_audit_server_batch_rollback.sql (يعيد الحي حرفياً)
-- تجربة: cd supabase/tests/family_links && node audit_2026_10_24.test.mjs
--
-- ١) دوال «عائلتي» في شجرة النساء للعضو المفعّل فقط: كانت تعمل لأي حساب له عقدة (المعلّق والمجمّد)
--    — set_self_wife كان يربط أي بنت غير متزوجة كزوجة. الآن my_active_women_node() = العقدة للمفعّل فقط.
--    حذف/تعديل البنت: لا لمن لها حساب دخول، والمتوفاة يحذفها المالك/المدير فقط (مثل remove_self_child).
-- ٢) الشجرة للمالك/المدير/المراقب: add_family_child (لغير أبنائك) و move_child_gender كانا يقبلان المشرف.
-- ٣) آخر دخول للأعضاء (get_members_last_signin) للمالك/المدير/المراقب بالهوية الموحّدة — كان المشرف
--    والإداري المجمّد يقرؤونه.
-- ٤) الأخبار: تعديل أي خبر للمالك/المدير/المشرف (كان المراقب أيضاً، وهو خارج مجال المحتوى)؛ صور الأخبار:
--    العضو المفعّل يرفع في مجلده news/<معرّفه>/ (كانت صور العضو تُرفض بصمت)، والحذف/الاستبدال للمحتوى.
-- ٥) طلبات المراجعة: الحذف النهائي للمالك/المدير (كان المراقب والمشرف يحذفون ويتجاوزون مسار الموافقات)،
--    وصاحب الطلب يسحب طلبه المعلّق (كان «سحب الطلب» لا يحذف شيئاً).
-- ٦) قفل محتوى الطلب داخل مسار الموافقات: بعد دخول الطلب للمسار (stage) لا يتغيّر نوعه ولا صاحبه ولا
--    تفاصيله من التطبيقات — كان المختص يبدّلها بعد اعتماد المدير.
-- ٧) ملفات المكتبة: سرد/توقيع ملفات family-archive لما يراه العضو في المكتبة فقط (المعتمد غير المخفي،
--    وما رفعه، والإدارة كل شيء). المستودع يبقى عاماً حتى تُحدَّث الأندرويد والموقع (المرحلة ٢).
-- ٨) لا سرد لملفات المستودعات العامة لغير المسجّلين (gallery، news، family-gallery، stories) — الروابط
--    العامة تعمل كما هي؛ السرد صار للمسجّلين فقط.

-- ─── ١) شجرة النساء ───
create or replace function public.my_active_women_node()
 returns uuid
 language sql
 stable
 security definer
 set search_path to 'public'
as $$
  select case when coalesce(public.current_user_role(), '') in ('member', 'supervisor', 'monitor', 'admin', 'owner')
              then public.my_women_node() end;
$$;
revoke all on function public.my_active_women_node() from public, anon;
grant execute on function public.my_active_women_node() to authenticated;

do $$
declare
  f regprocedure;
  def text;
begin
  for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public'
              and p.proname in ('add_self_mother', 'set_self_mother', 'set_self_wife', 'remove_self_wife',
                                'reorder_self_women_children', 'add_self_wife', 'set_self_wife_hidden')
  loop
    def := pg_get_functiondef(f);
    if position('public.my_women_node()' in def) > 0 then
      execute replace(def, 'public.my_women_node()', 'public.my_active_women_node()');
    end if;
  end loop;
end $$;

create or replace function public.remove_self_woman_child(p_child_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me uuid := public.my_active_women_node();
  c public.women_members%rowtype;
begin
  if me is null then raise exception 'no_node'; end if;
  select * into c from public.women_members where id = p_child_id and parent_id = me;
  if not found then
    raise exception 'not_your_child';
  end if;
  -- لها حساب دخول — ملف عضوة حقيقي لا يحذفه الأب
  if c.linked_user_id is not null then
    raise exception 'لهذه البنت حساب — يحذفها المالك أو المدير' using errcode = '42501', hint = 'has_account';
  end if;
  -- المتوفاة سجلّ نسب — للمالك والمدير فقط
  if coalesce(c.is_deceased, false) and coalesce(public.current_user_role(), '') not in ('owner', 'admin') then
    raise exception 'سجل متوفاة — يحذفه المالك أو المدير' using errcode = '42501', hint = 'deceased_protected';
  end if;
  delete from public.women_members where id = p_child_id;
end; $function$;

create or replace function public.update_self_woman_child(p_child_id uuid, p_first_name text, p_full_name text, p_birth date, p_deceased boolean, p_death date)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me uuid := public.my_active_women_node();
  c public.women_members%rowtype;
begin
  if me is null then raise exception 'no_node'; end if;
  select * into c from public.women_members where id = p_child_id and parent_id = me;
  if not found then
    raise exception 'not_your_child';
  end if;
  -- لها حساب دخول — تعدّل بياناتها بنفسها أو عبر الإدارة
  if c.linked_user_id is not null then
    raise exception 'لهذه البنت حساب — تعدّل بياناتها بنفسها أو عبر الإدارة' using errcode = '42501', hint = 'has_account';
  end if;
  update public.women_members
     set first_name  = coalesce(nullif(trim(p_first_name), ''), first_name),
         full_name   = coalesce(nullif(trim(p_full_name), ''), full_name),
         birth_date  = p_birth,
         is_deceased = coalesce(p_deceased, false),
         death_date  = case when p_deceased then p_death else null end
   where id = p_child_id;
end; $function$;

-- ─── ٢) الشجرة: المشرف خارجها ───
do $$
declare
  def text;
begin
  def := pg_get_functiondef('public.add_family_child(uuid,text,text,date,boolean,date,integer,text)'::regprocedure);
  def := replace(def, 'if not (public.is_moderator() or p_parent_id = auth.uid()) then',
    'if not (coalesce(public.current_user_role(), '''') in (''owner'', ''admin'', ''monitor'')'
    || ' or (p_parent_id = any (array[auth.uid(), public.current_profile_id()])'
    || ' and coalesce(public.current_user_role(), '''') in (''member'', ''supervisor''))) then');
  if position('''monitor'')' in def) = 0 then raise exception 'add_family_child: النمط لم يُطابق'; end if;
  execute def;

  def := pg_get_functiondef('public.move_child_gender(uuid,text)'::regprocedure);
  def := replace(def, 'if not public.is_moderator() then',
    'if coalesce(public.current_user_role(), '''') not in (''owner'', ''admin'', ''monitor'') then');
  if position('''monitor'')' in def) = 0 then raise exception 'move_child_gender: النمط لم يُطابق'; end if;
  execute def;
end $$;

-- ─── ٣) آخر دخول ───
do $$
declare
  def text;
begin
  def := pg_get_functiondef('public.get_members_last_signin()'::regprocedure);
  def := replace(def,
    E'  select role into caller_role from public.profiles where id = public.current_profile_id();\n  if caller_role is null or caller_role not in (''owner'', ''admin'', ''monitor'', ''supervisor'') then',
    E'  caller_role := public.current_user_role();\n  if caller_role is null or caller_role not in (''owner'', ''admin'', ''monitor'') then');
  if position('caller_role := public.current_user_role();' in def) = 0 then
    raise exception 'get_members_last_signin: النمط لم يُطابق';
  end if;
  execute def;
end $$;

-- ─── ٤) الأخبار ───
drop policy if exists news_update_moderator on public.news;
create policy news_update_moderator on public.news for update
  using (public.current_user_role() = any (array['supervisor', 'admin', 'owner']))
  with check (public.current_user_role() = any (array['supervisor', 'admin', 'owner']));

create policy news_insert_member_own on storage.objects for insert to authenticated
  with check (bucket_id = 'news'
    and public.current_user_role() = 'member'
    and (storage.foldername(name))[1] = 'news'
    and (storage.foldername(name))[2] = any (array[auth.uid()::text, public.current_profile_id()::text])
    and array_length(storage.foldername(name), 1) = 2);
drop policy if exists news_update_admin on storage.objects;
create policy news_update_admin on storage.objects for update to authenticated
  using (bucket_id = 'news' and public.current_user_role() = any (array['owner', 'admin', 'supervisor']));
drop policy if exists news_delete_admin on storage.objects;
create policy news_delete_admin on storage.objects for delete to authenticated
  using (bucket_id = 'news' and public.current_user_role() = any (array['owner', 'admin', 'supervisor']));

-- ─── ٥) حذف طلبات المراجعة ───
drop policy if exists admin_requests_delete_by_scope on public.admin_requests;
create policy admin_requests_delete_by_scope on public.admin_requests for delete to authenticated
  using (public.current_user_role() = any (array['owner', 'admin']) and public.can_handle_admin_request(request_type));
create policy admin_requests_delete_own_pending on public.admin_requests for delete to authenticated
  using (status = 'pending'
    and requester_id = any (array[auth.uid(), public.current_profile_id()])
    and public.is_approved_member());

-- ─── ٦) قفل محتوى الطلب داخل المسار ───
create or replace function public.trg_admin_request_payload_lock()
 returns trigger
 language plpgsql
 security invoker
 set search_path to 'public'
as $function$
begin
  -- التطبيقات فقط (دوال السيرفر تكتب بصلاحية مالكها)، والطلب داخل مسار الموافقات
  if current_user <> 'authenticated' or old.stage is null then
    return new;
  end if;
  if (new.request_type, new.requester_id, new.member_id, new.details, new.new_value)
     is distinct from
     (old.request_type, old.requester_id, old.member_id, old.details, old.new_value) then
    raise exception 'محتوى الطلب لا يتغيّر بعد دخوله مسار الموافقات'
      using errcode = '42501', hint = 'payload_locked';
  end if;
  return new;
end;
$function$;
revoke all on function public.trg_admin_request_payload_lock() from public, anon;
drop trigger if exists trg_admin_request_payload_lock on public.admin_requests;
create trigger trg_admin_request_payload_lock before update on public.admin_requests
  for each row execute function public.trg_admin_request_payload_lock();

-- ─── ٧) ملفات المكتبة: ما يراه العضو فقط ───
drop policy if exists family_archive_storage_read on storage.objects;
create policy family_archive_storage_read on storage.objects for select to authenticated
  using (bucket_id = 'family-archive' and (
    public.current_user_role() = any (array['owner', 'admin'])
    or exists (
      select 1 from public.family_archive a
       where (a.file_url like '%/family-archive/' || storage.objects.name || '%'
              or a.thumbnail_url like '%/family-archive/' || storage.objects.name || '%')
         and public.is_approved_member()
         and ((a.approval_status = 'approved' and a.is_hidden = false)
              or a.uploaded_by = any (array[auth.uid(), public.current_profile_id()])))
    -- الرفع (upsert=false) يتحقق من وجود الملف — ملفك الذي رفعته للتو قبل حفظ سجله
    or owner_id = auth.uid()::text));

-- ─── ٨) لا سرد للمستودعات العامة لغير المسجّلين ───
drop policy if exists "Public Access to gallery" on storage.objects;
create policy "Public Access to gallery" on storage.objects for select to authenticated
  using (bucket_id = 'gallery');
drop policy if exists "Public Access to news" on storage.objects;
create policy "Public Access to news" on storage.objects for select to authenticated
  using (bucket_id = 'news');
drop policy if exists family_gallery_storage_read on storage.objects;
create policy family_gallery_storage_read on storage.objects for select to authenticated
  using (bucket_id = 'family-gallery');
drop policy if exists stories_public_read on storage.objects;
