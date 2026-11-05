-- حذف الحساب (قرار المالك ٢٠٢٦-١٠-٢٩ «نعم اصلح»، سياسة الخصوصية م٩: التنفيذ خلال ٧ أيام):
-- • نص رسالة التأكيد بعد الحذف (delete-account يرسلها عبر KWT SMS بأفضل جهد).
-- • طلب حذف حساب معلّق أكثر من N أيام (افتراضياً ٥) → إشعار تصعيد للمالك والمدراء مرة واحدة (خطوة 'escalated' في admin_request_steps).
--   مهمة pg_cron مستقلة كل ساعة؛ لا تمسّ approvals_sla_tick ولا escalated_at (يعمل والمسار مطفأ أو مفعّل).

insert into public.app_config (key, value, default_value, kind, max_length, category, label_ar, help_ar, is_public, sort)
values ('account_deleted_sms',
        to_jsonb('تم حذف حسابك في تطبيق عائلة المحمدعلي بناءً على طلبك.'::text),
        to_jsonb('تم حذف حسابك في تطبيق عائلة المحمدعلي بناءً على طلبك.'::text),
        'text', 70, 'sms', 'رسالة تأكيد حذف الحساب',
        'رسالة SMS تصل رقم العضو بعد اكتمال حذف حسابه. رسالة واحدة: ٧٠ حرفاً عربياً كحد أقصى.',
        false, 40),
       ('account_delete_escalate_days', '5'::jsonb, '5'::jsonb, 'int', null, 'approvals',
        'تصعيد طلب حذف الحساب بعد (أيام)',
        'إذا بقي طلب حذف الحساب بلا تنفيذ هذا العدد من الأيام يصل المالك والمدراء تنبيه. السياسة تلتزم بالتنفيذ خلال ٧ أيام.',
        false, 90)
on conflict (key) do nothing;
update public.app_config set min_value = 1, max_value = 7 where key = 'account_delete_escalate_days';

create or replace function public.account_delete_deadline_tick()
returns integer language plpgsql security definer set search_path to 'public' as $$
declare
  r     public.admin_requests%rowtype;
  days  integer := least(greatest(public.config_int('account_delete_escalate_days', 5), 1), 7);
  n     integer := 0;
  nm    text;
  d     integer;
begin
  for r in
    select * from public.admin_requests a
     where a.request_type = 'account_delete' and a.status = 'pending'
       and a.created_at < now() - make_interval(days => days)
       and not exists (select 1 from public.admin_request_steps s
                        where s.request_id = a.id and s.action = 'escalated' and s.note like 'مهلة حذف الحساب%')
     order by a.created_at
     for update skip locked
  loop
    nm := coalesce((select nullif(btrim(p.full_name), '') from public.profiles p where p.id = r.member_id), 'عضو');
    d  := floor(extract(epoch from (now() - r.created_at)) / 86400)::integer;
    insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note)
    values (r.id, null, 'system', 'escalated', 'مهلة حذف الحساب: ' || d || ' أيام بلا تنفيذ');
    perform public.approvals_notify(array(select public.approvals_manager_ids()),
      'عاجل: طلب حذف حساب متأخر',
      'طلب حذف حساب «' || nm || '» معلّق منذ ' || d || ' أيام — سياسة الخصوصية تلزم بالتنفيذ خلال ٧ أيام',
      null, r.id, r.request_type, r.stage, 'escalated');
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.account_delete_deadline_tick() from public, anon, authenticated;

select cron.unschedule('account-delete-deadline') where exists (select 1 from cron.job where jobname = 'account-delete-deadline');
select cron.schedule('account-delete-deadline', '7 * * * *', 'select public.account_delete_deadline_tick()');
