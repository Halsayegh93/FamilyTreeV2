-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- self-service بنات «عائلتي»: تعديل/حذف/ترتيب بنات العضو نفسه (بلا صلاحية إدارية).
-- الكتابة المباشرة على women_members محصورة بالمدير عبر RLS؛ هذه الدوال تتجاوزها
-- بأمان وبنطاق محدود (فقط أبناء عقدة المستخدم parent_id = my_women_node()).

create or replace function public.update_self_woman_child(
  p_child_id uuid, p_first_name text, p_full_name text,
  p_birth date, p_deceased boolean, p_death date
) returns void language plpgsql security definer set search_path to 'public'
as $function$
declare me uuid := public.my_women_node();
begin
  if me is null then raise exception 'no_node'; end if;
  if not exists (select 1 from public.women_members where id = p_child_id and parent_id = me) then
    raise exception 'not_your_child';
  end if;
  update public.women_members
     set first_name  = coalesce(nullif(trim(p_first_name), ''), first_name),
         full_name   = coalesce(nullif(trim(p_full_name), ''), full_name),
         birth_date  = p_birth,
         is_deceased = coalesce(p_deceased, false),
         death_date  = case when p_deceased then p_death else null end
   where id = p_child_id;
end; $function$;

create or replace function public.remove_self_woman_child(p_child_id uuid)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare me uuid := public.my_women_node();
begin
  if me is null then raise exception 'no_node'; end if;
  if not exists (select 1 from public.women_members where id = p_child_id and parent_id = me) then
    raise exception 'not_your_child';
  end if;
  delete from public.women_members where id = p_child_id;
end; $function$;

create or replace function public.reorder_self_women_children(p_ids uuid[])
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare me uuid := public.my_women_node(); i int;
begin
  if me is null then raise exception 'no_node'; end if;
  if p_ids is null then return; end if;
  for i in 1 .. array_length(p_ids, 1) loop
    update public.women_members set sort_order = i - 1
     where id = p_ids[i] and parent_id = me;
  end loop;
end; $function$;

grant execute on function public.update_self_woman_child(uuid,text,text,date,boolean,date) to authenticated;
grant execute on function public.remove_self_woman_child(uuid) to authenticated;
grant execute on function public.reorder_self_women_children(uuid[]) to authenticated;;
