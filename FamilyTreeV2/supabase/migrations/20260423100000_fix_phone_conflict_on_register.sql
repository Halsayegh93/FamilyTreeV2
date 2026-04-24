-- إصلاح تعارض الرقم عند إعادة التسجيل
-- عندما يُحذف المستخدم ثم يحاول التسجيل مجدداً:
-- إذا كان الرقم موجوداً في عضو آخر بالشجرة → نحرر الرقم من العضو القديم
-- ثم يُكمل التسجيل ويُنشأ admin_request للمراجعة

create or replace function public.free_phone_for_reregistration(
  p_phone text,
  p_new_member_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing_id uuid;
  v_normalized text;
begin
  -- تطبيع الرقم (8 أرقام كويتية)
  v_normalized := public.normalize_kuwait_phone(p_phone);

  if v_normalized is null or v_normalized = '' then
    return;
  end if;

  -- البحث عن أي عضو آخر عنده نفس الرقم (غير المستخدم الجديد نفسه)
  select id into v_existing_id
  from public.profiles
  where phone_number = v_normalized
    and id <> p_new_member_id
  limit 1;

  if v_existing_id is not null then
    -- تحرير الرقم من العضو القديم لإتاحة التسجيل الجديد
    -- يبقى العضو القديم في الشجرة بدون رقم حتى يراجعه المدير ويدمجه
    update public.profiles
    set phone_number = null
    where id = v_existing_id;

    -- إشعار داخلي للمدراء بوجود تعارض يحتاج مراجعة
    insert into public.notifications (target_member_id, title, body, kind, created_by)
    select
      p.id,
      'تعارض رقم عند التسجيل',
      format('الرقم %s كان مرتبطاً بعضو في الشجرة وتم تحريره للتسجيل الجديد. يُرجى مراجعة الطلب وإجراء الدمج إذا لزم.', v_normalized),
      'admin_request',
      p_new_member_id
    from public.profiles p
    where p.role in ('admin', 'supervisor');
  end if;
end;
$$;

-- منح صلاحية الاستدعاء للمستخدمين المصادق عليهم
grant execute on function public.free_phone_for_reregistration(text, uuid) to authenticated;
