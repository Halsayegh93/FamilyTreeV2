-- رسائل الدخول · فحص الوصول التلقائي (طلب المالك ٢٠٢٦-١٠-٢٣ «حط وقت الوصول الرسالة بعد الطلب في القسم»)
-- كل دقيقة: pg_cron «kwtsms-status-sweep» ← kwtsms_status_sweep_job() ← net.http_post للدالة الطرفية kwtsms-cron
-- {"action":"status_sweep"} بنفس سرّ «فحص الرصيد اليومي» ← تطلب من KWT حالة كل رسالة مقبولة عمرها ١–٣٠ دقيقة
-- ولم تصل لحالة نهائية، وتحفظها بـ record_kwtsms_delivery_status (فتظهر في تفاصيل الطلب مع وقت الفحص).
-- KWT لا تعطي ساعة الوصول للجوال؛ «وصلت خلال» = أول فحص قال «وصلت» (دقة دقيقة تقريباً).
-- التراجع: supabase/rollback/20261023110000_kwtsms_status_sweep_rollback.sql

-- الرسائل التي تحتاج فحصاً (للدالة الطرفية فقط): مقبولة، ليست تجريبية، عمرها ١–٣٠ دقيقة، حالتها غير نهائية،
-- ولم تُفحص خلال آخر دقيقتين — ٢٠ أقصى (حد KWT وحد وقت الدالة)
create function public.kwtsms_pending_status_checks(p_limit int default 20) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(x.provider_msgid order by x.created_at), '[]'::jsonb)
    from (select d.provider_msgid, d.created_at
            from public.kwtsms_deliveries d
           where d.outcome = 'accepted' and d.provider_msgid is not null and not d.test_mode
             and d.created_at between now() - interval '30 minutes' and now() - interval '60 seconds'
             and (d.delivery_status is null
                  or lower(d.delivery_status) not in ('delivered', 'failed', 'rejected', 'expired', 'undelivered',
                                                      'err029', 'err030'))
             and (d.delivery_checked_at is null or d.delivery_checked_at < now() - interval '2 minutes')
           order by d.created_at
           limit least(greatest(coalesce(p_limit, 20), 1), 20)) x;
$$;
revoke all on function public.kwtsms_pending_status_checks(int) from public, anon, authenticated;
grant execute on function public.kwtsms_pending_status_checks(int) to service_role;

-- نداء الدالة الطرفية (مهمة pg_cron فقط) — نفس نمط kwtsms_daily_balance_job؛ لا شيء ينتظر ← لا نداء
create function public.kwtsms_status_sweep_job() returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_secret text;
begin
  if not exists (select 1 from public.kwtsms_deliveries d
                  where d.outcome = 'accepted' and d.provider_msgid is not null and not d.test_mode
                    and d.created_at between now() - interval '30 minutes' and now() - interval '60 seconds') then
    return null;
  end if;
  select s.value into v_secret from private.app_secrets s where s.key = 'push_webhook_secret';
  if coalesce(v_secret, '') = '' then
    raise warning 'kwtsms_status_sweep_job: push_webhook_secret missing';
    return null;
  end if;
  return net.http_post(
    url := 'https://poxyxsgvzwmnmewytsiw.supabase.co/functions/v1/kwtsms-cron'::text,
    body := jsonb_build_object('action', 'status_sweep'),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', v_secret),
    timeout_milliseconds := 30000
  );
end;
$$;
revoke all on function public.kwtsms_status_sweep_job() from public, anon, authenticated, service_role;

select cron.schedule('kwtsms-status-sweep', '* * * * *', 'select public.kwtsms_status_sweep_job()');
