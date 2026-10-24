-- مؤشرات الاستخدام التفصيلية (طلب المالك ٢٠٢٦-١٠-٢٢ «الاثنين معا»): كم دخل كل عضو، كم دقيقة قضى، وأي شاشة يفتح أكثر.
--
-- الجدول: صف واحد لكل (عضو + يوم)، فيه عدد الجلسات، مجموع الثواني، وعدد فتح كل شاشة (jsonb).
--   • يوم = تاريخ الكويت. الثواني تُقصّ عند ساعة لكل جلسة (لا تُحسب فترة متروكة مفتوحة).
--   • أسماء الشاشات من قائمة مسموحة ثابتة بطول ≤ ٤٠ حرفاً ولا تتجاوز ٦٠ شاشة في الصف (تمنع إدخال أي نص حر).
--   • الحفظ ٩٠ يوماً؛ تنظيف محدود (٢٠٠ صف) في كل تسجيل.
-- التسجيل: log_app_session(p_seconds, p_screen) — للأعضاء المفعّلين فقط (المعلّق والمجمّد ما يسجّلون).
-- القراءة: app_usage_engagement(p_days) — للمالك والمدير فقط (غيرهما 42501).
-- التراجع: supabase/rollback/20261022110000_app_usage_sessions_rollback.sql

create table public.app_usage_member_day (
  member_id uuid not null references public.profiles(id) on delete cascade,
  day       date not null,
  sessions  int  not null default 0 check (sessions >= 0),
  seconds   int  not null default 0 check (seconds >= 0),
  screens   jsonb not null default '{}'::jsonb check (jsonb_typeof(screens) = 'object'),
  primary key (member_id, day)
);
create index app_usage_member_day_day on public.app_usage_member_day (day);
alter table public.app_usage_member_day enable row level security;
revoke all on public.app_usage_member_day from public, anon, authenticated;

-- تسجيل جلسة (التطبيق يستدعيها عند الخروج من الشاشة/التطبيق ومعها مدة الجلسة)
create function public.log_app_session(p_seconds int, p_screen text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_me    uuid := public.current_profile_id();
  v_role  text := public.current_user_role();
  v_day   date := (now() at time zone 'Asia/Kuwait')::date;
  v_secs  int  := least(greatest(coalesce(p_seconds, 0), 0), 3600);
  v_screen text := nullif(btrim(coalesce(p_screen, '')), '');
  v_keep  date := v_day - 90;
begin
  -- العضو المفعّل فقط (المعلّق والمجمّد والزائر بلا تسجيل)
  if v_me is null or coalesce(v_role, '') in ('', 'pending', 'frozen', 'deleted') then
    return;
  end if;
  if v_screen is not null and (length(v_screen) > 40 or v_screen !~ '^[a-z][a-z0-9_]*$') then
    raise exception 'Invalid screen name' using errcode = '22023';
  end if;
  insert into public.app_usage_member_day (member_id, day, sessions, seconds)
  values (v_me, v_day, 1, v_secs)
  on conflict (member_id, day) do update
    set sessions = public.app_usage_member_day.sessions + 1,
        seconds  = least(public.app_usage_member_day.seconds + excluded.seconds, 86400);

  -- عدّ الشاشة: الشاشة الجديدة تُضاف ما دام الصف دون ٦٠ شاشة، والمعروفة تزيد دائماً
  if v_screen is not null then
    update public.app_usage_member_day m
       set screens = jsonb_set(m.screens, array[v_screen], to_jsonb(coalesce((m.screens ->> v_screen)::int, 0) + 1))
     where m.member_id = v_me and m.day = v_day
       and (m.screens ? v_screen
            or (select count(*) from jsonb_object_keys(m.screens)) < 60);
  end if;

  delete from public.app_usage_member_day
   where (member_id, day) in (select m.member_id, m.day from public.app_usage_member_day m
                               where m.day < v_keep order by m.day limit 200);
end;
$$;
revoke all on function public.log_app_session(int, text) from public, anon;
grant execute on function public.log_app_session(int, text) to authenticated;

-- القراءة (المالك والمدير): آخر p_days يوماً — لكل يوم الجلسات والأعضاء والدقائق، وأكثر الشاشات، وأكثر الأعضاء استخداماً
create function public.app_usage_engagement(p_days int default 30) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_days int := least(greatest(coalesce(p_days, 30), 1), 90);
  v_from date := (now() at time zone 'Asia/Kuwait')::date - (v_days - 1);
  v_daily jsonb;
  v_screens jsonb;
  v_members jsonb;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin') then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'sessions', d.sessions,
                                               'members', d.members, 'minutes', d.minutes)
                            order by d.day), '[]'::jsonb)
    into v_daily
    from (select m.day, sum(m.sessions)::int sessions, count(*)::int members, (sum(m.seconds) / 60)::int minutes
            from public.app_usage_member_day m
           where m.day >= v_from
           group by m.day) d;

  select coalesce(jsonb_agg(s.item order by s.uses desc), '[]'::jsonb)
    into v_screens
    from (select jsonb_build_object('screen', k.key, 'opens', sum(k.value::int)) item,
                 sum(k.value::int) uses
            from public.app_usage_member_day m, jsonb_each(m.screens) k
           where m.day >= v_from
           group by k.key
           order by uses desc
           limit 15) s;

  select coalesce(jsonb_agg(x.item order by x.sessions desc), '[]'::jsonb)
    into v_members
    from (select jsonb_build_object('member_id', g.member_id, 'name', coalesce(nullif(btrim(p.full_name), ''), p.first_name),
                                    'days', g.days, 'sessions', g.sessions, 'minutes', g.minutes) item,
                 g.sessions
            from (select m.member_id, count(*)::int days, sum(m.sessions)::int sessions,
                         (sum(m.seconds) / 60)::int minutes
                    from public.app_usage_member_day m
                   where m.day >= v_from
                   group by m.member_id
                   order by sum(m.sessions) desc
                   limit 20) g
            left join public.profiles p on p.id = g.member_id) x;

  return jsonb_build_object('days', v_days, 'from', v_from, 'generated_at', now(),
                            'daily', v_daily, 'screens', v_screens, 'members', v_members);
end;
$$;
revoke all on function public.app_usage_engagement(int) from public, anon;
grant execute on function public.app_usage_engagement(int) to authenticated;
