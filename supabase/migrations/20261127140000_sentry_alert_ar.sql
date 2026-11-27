-- تنبيه الأخطاء بالعربي (طلب المالك ٢٠٢٦-١١-٢٧: إيميلات Sentry إنجليزية — «ابيها بالعربي»).
-- مطبَّق على الحي ٢٠٢٦-١١-٢٧، والدالة sentry-alert-ar منشورة (المفتاح SENTRY_ALERT_KEY في أسرار Supabase)؛ تجربة node ١٧/١٧.
-- الدالة الطرفية `sentry-alert-ar` تستقبل نداء Sentry وترسل للمالك إيميلاً عربياً + إشعار إدارة (push).
--
--  ١) private.sentry_alert_log — آخر إرسال لكل خطأ (رقم الخطأ في Sentry): إيميل واحد لكل خطأ كل ٦ ساعات على الأكثر.
--  ٢) sentry_alert_claim(p_issue, p_hours) — حجز ذرّي: true = أرسل الآن (وسُجّل)، false = أُرسل خلال المدة.
--  ٣) sentry_alert_release(p_issue) — يلغي الحجز إن فشل الإرسال (حتى يُعاد في النداء التالي).
--  ٤) sentry_alert_notify_owners(p_title, p_body) — إشعار `app_error` للمالكَين المفعّلَين (يمرّ بمُطلِق الدفع
--     `trigger_push_on_notification` كبقية إشعارات الإدارة، وتصنيفه في `notification_category` = admin_activity).
-- الثلاث لمفتاح الخدمة وحده (الدالة الطرفية) — لا تنفيذ للتطبيقات.
--
-- التراجع: supabase/rollback/20261127140000_sentry_alert_ar_rollback.sql

create table if not exists private.sentry_alert_log (
  issue_id     text primary key check (issue_id ~ '^[0-9]{1,20}$'),
  last_sent_at timestamptz not null default now(),
  sent_count   int not null default 1
);
alter table private.sentry_alert_log enable row level security;
revoke all on private.sentry_alert_log from public, anon, authenticated, service_role;

create or replace function public.sentry_alert_claim(p_issue text, p_hours int default 6)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_rows int;
begin
  if p_issue is null or p_issue !~ '^[0-9]{1,20}$' then
    raise exception 'Invalid issue id' using errcode = '22023';
  end if;
  insert into private.sentry_alert_log as l (issue_id, last_sent_at, sent_count)
  values (p_issue, now(), 1)
  on conflict (issue_id) do update
    set last_sent_at = now(), sent_count = l.sent_count + 1
    where l.last_sent_at <= now() - make_interval(hours => greatest(coalesce(p_hours, 6), 1));
  get diagnostics v_rows = row_count;
  -- تنظيف خفيف: ما مضى عليه ٩٠ يوماً
  delete from private.sentry_alert_log where last_sent_at < now() - interval '90 days';
  return v_rows > 0;
end;
$$;

create or replace function public.sentry_alert_release(p_issue text)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  update private.sentry_alert_log
     set last_sent_at = '-infinity'::timestamptz, sent_count = greatest(sent_count - 1, 0)
   where issue_id = p_issue;
end;
$$;

create or replace function public.sentry_alert_notify_owners(p_title text, p_body text)
returns int
language plpgsql security definer set search_path = '' as $$
declare v_rows int;
begin
  insert into public.notifications (target_member_id, title, body, kind, created_by, is_read)
  select p.id, left(coalesce(nullif(trim(p_title), ''), 'خطأ في التطبيق'), 200), left(coalesce(p_body, ''), 500),
         'app_error', null, false
    from public.profiles p
   where p.role = 'owner' and p.status = 'active';
  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

revoke all on function public.sentry_alert_claim(text, int) from public, anon, authenticated;
revoke all on function public.sentry_alert_release(text) from public, anon, authenticated;
revoke all on function public.sentry_alert_notify_owners(text, text) from public, anon, authenticated;
grant execute on function public.sentry_alert_claim(text, int) to service_role;
grant execute on function public.sentry_alert_release(text) to service_role;
grant execute on function public.sentry_alert_notify_owners(text, text) to service_role;
