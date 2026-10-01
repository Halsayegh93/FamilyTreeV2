-- تراجع عن 20261001190000_carry_own_women_node_links.sql
-- يعيد repoint_women_node كما طُبّقت في 20261001150000 (بلا نقل روابط الشخص نفسه).
-- ⚠️ بعد التراجع: نقل ملف عضو لمعرّف جديد قد يُضيّع أمّه في شجرة النساء.

create or replace function public.repoint_women_node(p_old uuid, p_new uuid)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  c record;
begin
  if p_old is null or p_new is null or p_old = p_new
     or not exists (select 1 from public.women_members where id = p_old) then
    return;
  end if;

  -- للمعرّف الجديد عقدة (المزامنة تنشئها غالباً) — وإلا نسخة من القديمة
  insert into public.women_members
  select (jsonb_populate_record(
            null::public.women_members,
            to_jsonb(w) || jsonb_build_object('id', p_new)
         )).*
    from public.women_members w
   where w.id = p_old
  on conflict (id) do nothing;

  for c in
    select con.conrelid::regclass as tbl, att.attname as col
      from pg_constraint con
      join pg_attribute att
        on att.attrelid = con.conrelid and att.attnum = con.conkey[1]
     where con.contype = 'f'
       and con.confrelid = 'public.women_members'::regclass
       and array_length(con.conkey, 1) = 1
  loop
    -- بلا تخطٍّ صامت: فشل أي نقل يُلغي العملية كلها بدل فصل أحد
    execute format('update %s set %I = $1 where %I = $2', c.tbl, c.col, c.col)
      using p_new, p_old;
  end loop;
end;
$function$;

revoke all on function public.repoint_women_node(uuid, uuid) from public, anon, authenticated;
