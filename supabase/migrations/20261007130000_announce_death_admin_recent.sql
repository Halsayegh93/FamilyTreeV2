-- إعلان الوفاة: للمالك والمدير فقط، ولوفاة حديثة فقط
-- (فحص ٢٠٢٦-١٠-٠٧، البند م-٤ — موافقة المالك ٢٠٢٦-١٠-٠٧)
--
-- كانت announce_death تقبل المراقب، وتنشر خبراً «معتمداً» بنص حر وإشعاراً لكل الأجهزة لأي متوفى
-- مهما قدُم (١٣٥ متوفى بلا تاريخ) — شرط الحداثة (DeathRecency، ٣٠ يوماً) كان في التطبيق فقط.
--
-- بعد التعديل:
--   • المالك والمدير فقط (جدول الأدوار: «اعتماد المحتوى» و«إرسال الإشعارات») — غيرهما 42501
--     (التطبيقات تعرض «ما عندك صلاحية نشر إعلان الوفاة»).
--   • الوفاة حديثة، بقاعدة التطبيقات نفسها (DeathRecency.isRecent / allowsOffer):
--       – بتاريخ وفاة: خلال آخر ٣٠ يوماً بتوقيت الكويت، بهامش يوم لفارق توقيت الأجهزة
--         (اليوم−٣١ … اليوم+١).
--       – بلا تاريخ: التطبيقات تعرض المربّع لحظة تسجيل الوفاة فقط، فالسيرفر يشترط أن الوفاة
--         سُجّلت (is_deceased صار true) خلال ٣٠ يوماً. لذلك جدول جديد death_marks يختم وقت
--         التسجيل بمشغّل على profiles و women_members (عند التعديل فقط: إضافة متوفى قديم ليست
--         «تسجيل وفاة»). من سُجّلت وفاتهم قبل اليوم بلا تاريخ لا ختم لهم → لا إعلان (المقصود).
--     غير الحديثة: P0001 + hint = death_not_recent.
--   • «أُعلن عنه من قبل» كما هو (23505)، والنص والدفن والإشعار كما هي.
-- لا تغيير في البيانات: الجدول الجديد فارغ ويُملأ من الآن فصاعداً.
--
-- التراجع: supabase/rollback/20261007130000_announce_death_admin_recent_rollback.sql
-- التجربة: supabase/tests/family_links/audit_2026_10_07.test.mjs

-- ─── ختم وقت تسجيل الوفاة ───
create table if not exists public.death_marks (
  member_id uuid primary key,                       -- profiles.id أو women_members.id
  marked_at timestamptz not null default now()      -- آخر مرة صار فيها is_deceased = true
);
alter table public.death_marks enable row level security;
-- بلا سياسات: لا قراءة ولا كتابة من التطبيقات، تقرؤه announce_death وحدها
revoke all on table public.death_marks from anon, authenticated;

create or replace function public.trg_mark_death_recorded()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if coalesce(new.is_deceased, false) and not coalesce(old.is_deceased, false) then
    insert into public.death_marks (member_id, marked_at)
    values (new.id, now())
    on conflict (member_id) do update set marked_at = excluded.marked_at;
  end if;
  return null;
end;
$function$;
revoke execute on function public.trg_mark_death_recorded() from public, anon, authenticated;

drop trigger if exists trg_mark_death_recorded on public.profiles;
create trigger trg_mark_death_recorded after update of is_deceased on public.profiles
  for each row execute function public.trg_mark_death_recorded();
drop trigger if exists trg_mark_death_recorded on public.women_members;
create trigger trg_mark_death_recorded after update of is_deceased on public.women_members
  for each row execute function public.trg_mark_death_recorded();

-- ─── الدالة (نص الحي نفسه + الدور + الحداثة) ───
create or replace function public.announce_death(p_member_id uuid, p_content text DEFAULT NULL::text, p_burial text DEFAULT NULL::text, p_notify boolean DEFAULT true)
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
  v_death    date;
  v_today    date := (now() at time zone 'Asia/Kuwait')::date;
begin
  if v_caller is null or v_role not in ('owner', 'admin') then
    raise exception 'announce_death: not allowed' using errcode = '42501';
  end if;

  select p.full_name, coalesce(p.is_deceased, false), coalesce(p.gender, '') = 'female', p.death_date
    into v_name, v_deceased, v_female, v_death
  from public.profiles p
  where p.id = p_member_id;

  if not found then
    v_tree := 'women';
    select w.full_name, w.is_deceased, coalesce(w.gender, 'female') = 'female', w.death_date
      into v_name, v_deceased, v_female, v_death
    from public.women_members w
    where w.id = p_member_id;
    if not found then
      raise exception 'announce_death: member not found' using errcode = 'P0002';
    end if;
  end if;

  if not coalesce(v_deceased, false) then
    raise exception 'announce_death: member is not deceased' using errcode = '22023';
  end if;

  if not (case
            when v_death is not null then v_death between v_today - 31 and v_today + 1
            else exists (select 1 from public.death_marks m
                         where m.member_id = p_member_id
                           and m.marked_at > now() - interval '30 days')
          end) then
    raise exception 'announce_death: death is not recent'
      using errcode = 'P0001', hint = 'death_not_recent';
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
