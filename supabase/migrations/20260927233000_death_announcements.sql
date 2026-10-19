-- إعلان الوفاة (طلب المالك 2026-09-27)
--
-- عند تسجيل وفاة عضو يطلع للإدارة مربّع «إعلان وفاة» — بضغطة «نشر الإعلان»:
--   ١) منشور في الأخبار من نوع «وفاة» باسم «إدارة العائلة» (الرئيسية تبرزه ٣٠ يوماً)
--   ٢) إشعار لكل الأعضاء: admin_broadcast بلا هدف ← يتفرّع لكل عضو، والدفع يخرج مرة واحدة
-- مرة واحدة فقط لكل شخص (جدول death_announcements).
-- المالك والمدير والمراقب فقط — نفس من يعتمد الوفيات. المراقب لا يملك البثّ العام
-- (سياسة notifications)، فالدالة ترسله عنه في هذه الحالة وحدها بعد التحقق.
-- الشخص من شجرة الرجال (profiles) أو شجرة النساء (women_members)، والصيغة حسب الجنس:
-- «انتقل/انتقلت إلى رحمة الله تعالى».
-- details في الإشعار بلا v/changes عمداً: النسخ القديمة تتجاهله (تعرضه كإعلان إدارة)،
-- والجديدة تقرأ type = death_announcement فتعرضه بشكل الوفاة.
--
-- التراجع (بالترتيب):
--   drop function if exists public.announce_death(uuid, text, text, boolean);
--   drop table if exists public.death_announcements;

create table if not exists public.death_announcements (
  member_id    uuid primary key,          -- profiles.id أو women_members.id
  tree         text not null default 'men' check (tree in ('men', 'women')),
  news_id      uuid references public.news(id) on delete set null,
  announced_by uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default timezone('utc', now())
);

alter table public.death_announcements enable row level security;

-- القراءة لكل مسجّل (التطبيق يعرف هل أُعلن عنه)، والكتابة عبر الدالة فقط
drop policy if exists death_announcements_select on public.death_announcements;
create policy death_announcements_select on public.death_announcements
  for select to authenticated using (true);

create or replace function public.announce_death(
  p_member_id uuid,
  p_content   text    default null,   -- نص الإعلان كما حرّره الإداري (فارغ = النص الافتراضي)
  p_burial    text    default null,   -- موعد الدفن ومكانه (اختياري)
  p_notify    boolean default true    -- إرسال إشعار لكل الأعضاء
) returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
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

  -- شجرة الرجال أولاً (الرجل المنسوخ في شجرة النساء يحمل نفس المعرّف)
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

  -- مرة واحدة لكل شخص
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
$$;

revoke all on function public.announce_death(uuid, text, text, boolean) from public, anon;
grant execute on function public.announce_death(uuid, text, text, boolean) to authenticated;
