-- طلب المالك ٢٠٢٦-١١-٠٥: إضافة الابن بلا موافقة. المفتاح self_child_daily_limit يبقى 0 حتى ينزل بناء 50.
-- ١) add_family_child: يرفض للعضو الاسم المكرر تحت نفس الأب وتاريخ الميلاد في المستقبل.
-- ٢) إشعار الإدارة: «تمت إضافة ابن»، و«راجعه» عند الشك؛ تنبيه الجوال للمشكوك فقط.
-- ٣) photo_reminder_days: مدة رجوع تنبيه الصورة (0 = مطفأ).
create or replace function public.child_name_key(p text)
returns text language sql immutable set search_path = '' as $$
  select translate(regexp_replace(lower(coalesce(p, '')), '[\sً-ْـ]', '', 'g'), 'أإآٱةى', 'ااااهي');
$$;

do $do$
declare
  d text;
  a text;
begin
  select pg_get_functiondef('public.add_family_child(uuid,text,text,date,boolean,date,integer,text)'::regprocedure) into d;
  a := $x$perform set_config('family.self_child', 'on', true);$x$;
  if position(a in d) = 0 then raise exception 'add_family_child: expected text not found'; end if;
  execute replace(d, a, $x$if p_birth is not null and p_birth > (now() at time zone 'Asia/Kuwait')::date then
      raise exception 'تاريخ الميلاد في المستقبل' using errcode = '22023', hint = 'child_birth_future';
    end if;
    if exists (select 1 from public.profiles p where p.father_id = me
               and public.child_name_key(p.first_name) = public.child_name_key(nm)) then
      raise exception 'هذا الاسم مسجّل عندك' using errcode = '23505', hint = 'child_duplicate';
    end if;
    $x$ || a);

  select pg_get_functiondef('public.notify_member_change()'::regprocedure) into d;
  a := $x$  for admin_id in$x$;
  if position(a in d) = 0 then raise exception 'notify: expected text not found'; end if;
  d := replace(d, a, $x$  -- العضو أضاف ابنه بنفسه: «تمت إضافة ابن»، و«راجعه» إن تطابق الاسم الكامل مع غيره أو الميلاد مع أخ
  if not v_women and v_action = 'add' and current_setting('family.self_child', true) = 'on' then
    v_title := 'تمت إضافة ابن';
    v_body := v_actor_name || ' أضاف ابنه ' || coalesce(v_row ->> 'first_name', v_who);
    v_details := v_details || jsonb_build_object('self_child', true, 'review', exists (
      select 1 from public.profiles p where p.id <> v_subject and (
        public.child_name_key(p.full_name) = public.child_name_key(v_row ->> 'full_name')
        or (p.father_id = v_actor and p.birth_date is not null and p.birth_date = (v_row ->> 'birth_date')::date))));
  end if;

$x$ || a);
  execute d;

  select pg_get_functiondef('public.trigger_push_on_notification()'::regprocedure) into d;
  a := $x$-- العضو أطفأ هذا النوع$x$;
  if position(a in d) = 0 then raise exception 'push: expected text not found'; end if;
  execute replace(d, a, $x$-- إضافة ابن عادية: داخل التطبيق فقط، والجوال لـ«راجعه»
  if coalesce((new.details ->> 'self_child')::boolean, false) and not coalesce((new.details ->> 'review')::boolean, false) then
    return new;
  end if;
  $x$ || a);
end $do$;

insert into public.app_config (key, value, default_value, kind, min_value, max_value, category, label_ar, help_ar, is_public, sort)
values ('photo_reminder_days', '30'::jsonb, '30'::jsonb, 'int', 0, 365, 'tree',
        'تذكير من بلا صورة (بعد كم يوم يرجع)', 'مربع «كمّل ملفك بصورة» يطلع مرة ويرجع بعد هذه المدة إن ضغط «لاحقاً». 0 = مطفأ.', false, 64)
on conflict (key) do nothing;
