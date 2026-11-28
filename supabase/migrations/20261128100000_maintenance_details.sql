-- مطبَّق على الحي ٢٠٢٦-١١-٢٨ بعد تجربة begin…rollback
-- طلب المالك ٢٠٢٦-١١-٢٨: سبب الصيانة يكتبه المالك ويظهر للأعضاء في شاشة «التطبيق تحت الصيانة».
-- عمود واحد في app_settings (بلا وقت رجوع — «ما نحط وقت للرجوع»). القراءة لكل مسجّل والتعديل للمالك
-- بالسياستين الموجودتين نفسيهما («Authenticated users can read app_settings» / «Owner can update app_settings»).
-- فارغ أو null = السطر الافتراضي في التطبيق. الحد ٢٠٠ حرف.
alter table public.app_settings
  add column if not exists maintenance_message text;

alter table public.app_settings
  drop constraint if exists app_settings_maintenance_message_len;
alter table public.app_settings
  add constraint app_settings_maintenance_message_len
  check (maintenance_message is null or char_length(maintenance_message) <= 200);

comment on column public.app_settings.maintenance_message is
  'سبب الصيانة الظاهر للأعضاء (≤ ٢٠٠ حرف)؛ null/فارغ = النص الافتراضي. يكتبه المالك من «التطبيق ← حالة التطبيق ← وضع الصيانة».';
