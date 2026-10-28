-- تقليل ما نجمعه (طلب المالك ٢٠٢٦-١٠-٢٧ «نعم طبّق اقتراحات ما نجمعه»):
-- ١) إحصاءات الاستخدام أرقام عامة: الشاشات تُعدّ لكل يوم بلا عضو (app_usage_screen_day)، وسجل العضو اليومي
--    (للعدّ فقط: أعضاء وجلسات ودقائق) يُحفظ ٣٠ يوماً بدل ٩٠ وبلا شاشاته، و«الأكثر استخداماً» بالأسماء لا يُرجع.
-- ٢) حذف جداول «الموارد البشرية» الفارغة غير المستخدمة (hr_notes · hr_documents · hr_contact_log).
-- (أخطاء التطبيق تُمسح بعد ٣٠ يوماً أصلاً — cleanup-app-diagnostics؛ ومحاولات الدخول ٣٠ يوماً.)
-- التراجع: supabase/rollback/20261027170000_data_minimization_rollback.sql

create table if not exists public.app_usage_screen_day (
  day date not null,
  screen text not null,
  opens int not null default 0,
  primary key (day, screen)
);
alter table public.app_usage_screen_day enable row level security;   -- بلا سياسات: الدوال وحدها

insert into public.app_usage_screen_day (day, screen, opens)
select m.day, k.key, sum(k.value::int) from public.app_usage_member_day m, jsonb_each(m.screens) k
 group by m.day, k.key
on conflict (day, screen) do update set opens = excluded.opens;

update public.app_usage_member_day set screens = '{}'::jsonb where screens <> '{}'::jsonb;
delete from public.app_usage_member_day where day < (now() at time zone 'Asia/Kuwait')::date - 30;

create or replace function public.log_app_session(p_seconds integer, p_screen text)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_me    uuid := public.current_profile_id();
  v_role  text := public.current_user_role();
  v_day   date := (now() at time zone 'Asia/Kuwait')::date;
  v_secs  int  := least(greatest(coalesce(p_seconds, 0), 0), 3600);
  v_screen text := nullif(btrim(coalesce(p_screen, '')), '');
begin
  -- العضو المفعّل فقط (المعلّق والمجمّد والزائر بلا تسجيل)
  if v_me is null or coalesce(v_role, '') in ('', 'pending', 'frozen', 'deleted') then
    return;
  end if;
  if v_screen is not null and (length(v_screen) > 40 or v_screen !~ '^[a-z][a-z0-9_]*$') then
    raise exception 'Invalid screen name' using errcode = '22023';
  end if;
  -- سجل العضو اليومي للعدّ فقط (بلا شاشات)
  insert into public.app_usage_member_day (member_id, day, sessions, seconds)
  values (v_me, v_day, 1, v_secs)
  on conflict (member_id, day) do update
    set sessions = public.app_usage_member_day.sessions + 1,
        seconds  = least(public.app_usage_member_day.seconds + excluded.seconds, 86400);

  -- الشاشة تُعدّ عامةً لليوم بلا عضو (حدّ ٦٠ شاشة جديدة لليوم)
  if v_screen is not null
     and (exists (select 1 from public.app_usage_screen_day s where s.day = v_day and s.screen = v_screen)
          or (select count(*) from public.app_usage_screen_day s where s.day = v_day) < 60) then
    insert into public.app_usage_screen_day (day, screen, opens) values (v_day, v_screen, 1)
    on conflict (day, screen) do update set opens = public.app_usage_screen_day.opens + 1;
  end if;

  delete from public.app_usage_member_day
   where (member_id, day) in (select m.member_id, m.day from public.app_usage_member_day m
                               where m.day < v_day - 30 order by m.day limit 200);
  delete from public.app_usage_screen_day
   where (day, screen) in (select s.day, s.screen from public.app_usage_screen_day s
                            where s.day < v_day - 90 order by s.day limit 200);
end;
$function$;

create or replace function public.app_usage_engagement(p_days integer default 30)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_days int := least(greatest(coalesce(p_days, 30), 1), 90);
  v_from date := (now() at time zone 'Asia/Kuwait')::date - (v_days - 1);
  v_daily jsonb;
  v_screens jsonb;
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
    from (select jsonb_build_object('screen', x.screen, 'opens', sum(x.opens)) item, sum(x.opens) uses
            from public.app_usage_screen_day x
           where x.day >= v_from
           group by x.screen
           order by uses desc
           limit 15) s;

  -- «الأكثر استخداماً» بالأسماء أُلغي (أرقام عامة فقط)
  return jsonb_build_object('days', v_days, 'from', v_from, 'generated_at', now(),
                            'daily', v_daily, 'screens', v_screens, 'members', '[]'::jsonb);
end;
$function$;

drop table if exists public.hr_notes;
drop table if exists public.hr_documents;
drop table if exists public.hr_contact_log;
