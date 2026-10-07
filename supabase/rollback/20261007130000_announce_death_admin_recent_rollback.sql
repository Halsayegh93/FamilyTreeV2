-- تراجع 20261007130000: إعلان الوفاة كما كان على السيرفر الحي قبل ٢٠٢٦-١٠-٠٧
-- (المالك والمدير والمراقب، بلا شرط حداثة — تعيد الثغرة م-٤، للطوارئ فقط).
-- الدالة منسوخة حرفياً من pg_get_functiondef — md5(prosrc) = c983835d0bbd169c55f53d73253b104f

drop trigger if exists trg_mark_death_recorded on public.profiles;
drop trigger if exists trg_mark_death_recorded on public.women_members;
drop function if exists public.trg_mark_death_recorded();
drop table if exists public.death_marks;

CREATE OR REPLACE FUNCTION public.announce_death(p_member_id uuid, p_content text DEFAULT NULL::text, p_burial text DEFAULT NULL::text, p_notify boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role     text := coalesce(public.current_user_role(), 'anonymous');
  v_caller   uuid := public.current_profile_id();
  v_tree     text := 'men';
  v_name     text;
  v_deceased boolean;
  v_female   boolean := false;
  v_verb     text;
  v_burial   text := nullif(btrim(coalesce(p_burial, '')), '');
  v_content  text;
  v_body     text;
  v_news_id  uuid;
begin
  if v_caller is null or v_role not in ('owner', 'admin', 'monitor') then
    raise exception 'announce_death: not allowed' using errcode = '42501';
  end if;

  select p.full_name, coalesce(p.is_deceased, false), coalesce(p.gender, '') = 'female'
    into v_name, v_deceased, v_female
  from public.profiles p
  where p.id = p_member_id;

  if not found then
    v_tree := 'women';
    select w.full_name, w.is_deceased, coalesce(w.gender, 'female') = 'female'
      into v_name, v_deceased, v_female
    from public.women_members w
    where w.id = p_member_id;
    if not found then
      raise exception 'announce_death: member not found' using errcode = 'P0002';
    end if;
  end if;

  if not coalesce(v_deceased, false) then
    raise exception 'announce_death: member is not deceased' using errcode = '22023';
  end if;

  insert into public.death_announcements (member_id, tree, announced_by)
  values (p_member_id, v_tree, v_caller)
  on conflict (member_id) do nothing;
  if not found then
    raise exception 'announce_death: already announced' using errcode = '23505';
  end if;

  v_name := btrim(coalesce(v_name, ''));
  v_verb := case when v_female then 'انتقلت إلى رحمة الله تعالى'
                 else 'انتقل إلى رحمة الله تعالى' end;

  v_content := coalesce(nullif(btrim(coalesce(p_content, '')), ''),
    v_verb || ' ' || v_name || E'\n'
    || case when v_female then 'تغمّدها الله بواسع رحمته وأسكنها فسيح جناته'
            else 'تغمّده الله بواسع رحمته وأسكنه فسيح جناته' end
    || E'\n' || 'إنا لله وإنا إليه راجعون');
  if v_burial is not null then
    v_content := v_content || E'\n\n' || 'الدفن: ' || v_burial;
  end if;

  insert into public.news
    (author_id, posted_by, author_name, author_role, role_color, content, type,
     image_urls, poll_options, approval_status, approved_by, approved_at)
  values
    (null, v_caller, 'إدارة العائلة', 'الإدارة',
     case v_role when 'owner' then 'gold' when 'admin' then 'purple' else 'green' end,
     v_content, 'وفاة', '[]'::jsonb, '[]'::jsonb,
     'approved', v_caller, timezone('utc', now()))
  returning id into v_news_id;

  update public.death_announcements
     set news_id = v_news_id
   where member_id = p_member_id;

  if p_notify then
    v_body := v_name || E'\n' || 'إنا لله وإنا إليه راجعون';
    if v_burial is not null then
      v_body := v_body || E'\n' || 'الدفن: ' || v_burial;
    end if;

    insert into public.notifications (target_member_id, title, body, kind, created_by, details)
    values (null, v_verb, v_body, 'admin_broadcast', v_caller,
            jsonb_build_object('type', 'death_announcement',
                               'member_id', p_member_id,
                               'tree', v_tree,
                               'news_id', v_news_id));
  end if;

  return v_news_id;
end;
$function$;
