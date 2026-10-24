-- مؤشرات استخدام التطبيق اليومية (طلب المالك ٢٠٢٦-١٠-٢٢: «مؤشرات دقيقة على استخدام التطبيق»، والأيام: آخر ٧ / ٣٠ / ٩٠ يوماً)
--
-- التعريف = نفس «العضو الفعّال» في app_usage_stats: رقم + جهاز مسجّل + آخر ظهور = أحدث دخول أو تحديث للجهاز.
--   اليوم  = ظهر منذ بداية اليوم (٠٠:٠٠ بتوقيت الكويت)  ← مباشر
--   ٧ أيام  = ظهر خلال آخر ٧ أيام متحركة
--   ٣٠ يوماً = ظهر خلال آخر ٣٠ يوماً متحركة
-- اللقطة اليومية تُؤخذ ٠٠:٠٠ الكويت (٢١:٠٠ UTC) لليوم المنتهي: فيها «٢٤ ساعة» و«٧ أيام» و«٣٠ يوماً» كما كانت في تلك اللحظة.
-- ملاحظة صدق: آخر ظهور = آخر حدث فقط، فلا يُعرف من الجدول كم مرة دخل العضو في اليوم، بل من ظهر في النافذة.
--
-- التخزين: جدول app_usage_daily (لا تصل له التطبيقات مباشرة)، يُكتب من مهمة pg_cron فقط، ويُحفظ سنة.
-- القراءة: app_usage_trend(p_days) للمالك والمدير فقط (غيرهما 42501)، ترجع صفوف الأيام الماضية من اللقطات + اليوم الحالي مباشرة.
-- التراجع: supabase/rollback/20261022100000_app_usage_trend_rollback.sql

create table public.app_usage_daily (
  day        date primary key,
  active_1d  int  not null check (active_1d  >= 0),
  active_7d  int  not null check (active_7d  >= 0),
  active_30d int  not null check (active_30d >= 0),
  members    int  not null check (members    >= 0),
  taken_at   timestamptz not null default now()
);
alter table public.app_usage_daily enable row level security;
revoke all on public.app_usage_daily from public, anon, authenticated;

-- عدّ الفعّالين لنافذة زمنية واحدة (داخلية)
create function public.app_usage_count_since(p_since timestamptz) returns int
language sql stable set search_path = '' as $$
  select count(*)::int
    from public.profiles p
    left join auth.users u on u.id = p.id
   where coalesce(p.is_deceased, false) = false
     and p.role <> 'pending'
     and nullif(trim(p.phone_number), '') is not null
     and exists (select 1 from public.device_tokens d where d.member_id = p.id)
     and greatest(u.last_sign_in_at,
                  (select max(d.updated_at) from public.device_tokens d where d.member_id = p.id)) >= p_since;
$$;
revoke all on function public.app_usage_count_since(timestamptz) from public, anon, authenticated, service_role;

-- إجمالي الأعضاء الفعّالين الآن (للمقام: كم من الأعضاء الفعليين)
create function public.app_usage_member_total() returns int
language sql stable set search_path = '' as $$
  select count(*)::int from public.profiles p
   where coalesce(p.is_deceased, false) = false and p.role <> 'pending'
     and nullif(trim(p.phone_number), '') is not null
     and exists (select 1 from public.device_tokens d where d.member_id = p.id);
$$;
revoke all on function public.app_usage_member_total() from public, anon, authenticated, service_role;

-- لقطة اليوم المنتهي (تُستدعى من pg_cron فقط)
create function public.record_app_usage_day() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_now timestamptz := now();
  v_day date := (v_now at time zone 'Asia/Kuwait')::date - 1;
begin
  insert into public.app_usage_daily (day, active_1d, active_7d, active_30d, members, taken_at)
  values (v_day,
          public.app_usage_count_since(v_now - interval '1 day'),
          public.app_usage_count_since(v_now - interval '7 days'),
          public.app_usage_count_since(v_now - interval '30 days'),
          public.app_usage_member_total(),
          v_now)
  on conflict (day) do update
    set active_1d = excluded.active_1d, active_7d = excluded.active_7d, active_30d = excluded.active_30d,
        members = excluded.members, taken_at = excluded.taken_at;
  -- الحفظ سنة: حذف محدود في كل لقطة
  delete from public.app_usage_daily where day < v_day - 365;
end;
$$;
revoke all on function public.record_app_usage_day() from public, anon, authenticated, service_role;

-- القراءة للمالك والمدير: آخر p_days يوماً (١–٩٠)، مع اليوم الحالي مباشرة
create function public.app_usage_trend(p_days int default 30) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_days int := least(greatest(coalesce(p_days, 30), 1), 90);
  v_today date := (now() at time zone 'Asia/Kuwait')::date;
  v_midnight timestamptz := v_today::timestamp at time zone 'Asia/Kuwait';
  v_rows jsonb;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin') then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'day', d.day, 'active_1d', d.active_1d, 'active_7d', d.active_7d, 'active_30d', d.active_30d,
           'members', d.members, 'live', false) order by d.day), '[]'::jsonb)
    into v_rows
    from public.app_usage_daily d
   where d.day >= v_today - v_days and d.day < v_today;
  return jsonb_build_object(
    'days', v_days,
    'generated_at', now(),
    'history', v_rows,
    'today', jsonb_build_object(
      'day', v_today,
      'active_1d', public.app_usage_count_since(v_midnight),
      'active_7d', public.app_usage_count_since(now() - interval '7 days'),
      'active_30d', public.app_usage_count_since(now() - interval '30 days'),
      'members', public.app_usage_member_total(),
      'live', true));
end;
$$;
revoke all on function public.app_usage_trend(int) from public, anon;
grant execute on function public.app_usage_trend(int) to authenticated;

-- الجدولة: ٢١:٠٠ UTC = ٠٠:٠٠ الكويت كل يوم
select cron.schedule('app-usage-daily', '0 21 * * *', 'select public.record_app_usage_day()');
