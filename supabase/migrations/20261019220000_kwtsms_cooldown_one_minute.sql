-- مهلة رمز الدخول لنفس الرقم: «دقيقة» بدل ٣ دقائق (طلب المالك ٢٠٢٦-١٠-١٩ «خلها دقيقة»)
-- داخلياً ٥٠ ثانية — أقل شوي من مهلة Supabase نفسها (٦٠ ثانية) حتى ما تتصادم المهلتان ويطلع للعضو «تعذّر إرسال»؛
-- قبل الدقيقة يرد Supabase بـ«كثرة الطلبات» بنفسه. باقي الحدود كما هي: ٥ رموز بالساعة لكل رقم، ٥ بالثانية و١٠٠ بالساعة
-- للكل. التراجع: supabase/rollback/20261019220000_kwtsms_cooldown_one_minute_rollback.sql (يرجّع ٣ دقائق)
create or replace function public.reserve_kwtsms_send(p_event text, p_phone text, p_test boolean)
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_now timestamptz := clock_timestamp(); v_existing text;
begin
  if p_event !~ '^[a-f0-9]{64}$' or p_phone !~ '^[a-f0-9]{64}$' or p_test is null then
    raise exception 'Invalid reservation';
  end if;
  -- Serializes short reservations across Edge instances; never held during a provider call.
  perform pg_advisory_xact_lock(19200000, 1);
  delete from public.kwtsms_deliveries where created_at < v_now - interval '2 days';
  select outcome into v_existing from public.kwtsms_deliveries where event_hash = p_event;
  if found then return case when v_existing = 'accepted' then 'accepted' else 'blocked' end; end if;
  if exists (select 1 from public.kwtsms_deliveries where phone_hash = p_phone
      and created_at > v_now - interval '50 seconds')
    or (select count(*) from public.kwtsms_deliveries where phone_hash = p_phone
      and created_at > v_now - interval '1 hour') >= 5
    or (select count(*) from public.kwtsms_deliveries
      where created_at > v_now - interval '1 second') >= 5
    or (select count(*) from public.kwtsms_deliveries
      where created_at > v_now - interval '1 hour') >= 100 then
    return 'blocked';
  end if;
  insert into public.kwtsms_deliveries(event_hash,phone_hash,test_mode,created_at)
    values (p_event,p_phone,p_test,v_now);
  return 'send';
end;
$function$;
