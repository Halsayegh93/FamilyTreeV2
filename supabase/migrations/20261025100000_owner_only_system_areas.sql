-- «التطبيق» و«الفريق والأمان» للمالك فقط (طلب المالك ٢٠٢٦-١٠-٢٤): ما كان المدير يقرؤه أو يديره من بيانات القسمين
-- صار للمالك وحده — السيرفر يطبّق ما أخفاه التطبيق (CLAUDE.md «أي صلاحية في جدول الأدوار لازم يطبّقها السيرفر أيضاً»).
-- طُبِّق على السيرفر الحي ٢٠٢٦-١٠-٢٥ (المالك: «اربط السيرفر بالتعديلات»؛ md5 الدوال طابقت قبل التطبيق، ونُشرت kwtsms-admin v5 للمالك فقط). التراجع: supabase/rollback/20261025100000_owner_only_system_areas_rollback.sql
-- التجربة المحلية: cd supabase/tests/family_links && node owner_only_system_areas.test.mjs
--
-- أ) الدوال (قراءة):
--    • sms_admin_overview() · sms_balance_status() · sms_login_attempts(int) — المالك فقط (كان المالك والمدير؛ المدير
--      يرى محاولات الدخول بأرقام مخفية). «recipients» في النظرة تصير 'owner'.
--    • app_config() — القيم تبقى لكل الأعضاء (التطبيقان يقرآنها للعمل)، وتصفّح الإعدادات (meta، categories، can_edit)
--      للمالك فقط.
-- ب) التنبيهات: «رصيد رسائل الدخول قليل» (finish_kwtsms_send، kwtsms_balance_check) و«محاولات دخول مريبة»
--    (log_login_attempt) تصل المالك وحده — صفحتها لم تعد للمدير.
-- ج) الجداول (RLS) — ما يخصّ العضو نفسه (أجهزته، فكّ ربط جهازه) كما هو:
--    • device_tokens: أجهزة الآخرين قراءةً وحذفاً — المالك (كان المالك والمدير).
--    • device_revocations: قراءة الآخرين وإضافتها وتعديلها وحذفها — المالك.
--    • banned_phones: القراءة — المالك (الكتابة له أصلاً).
--    • app_config_history: القراءة — المالك.
--    • family_names: الكتابة — المالك («أسماء العوائل والفروع» في «التطبيق»)؛ القراءة لكل مسجّل كما هي.
--
-- الدوال تُعدَّل في مكانها: يُقرأ تعريفها الحي ويُستبدل شرط الدور وحده — والترحيل كله يفشل إن لم يوجد النص القديم مرة
-- واحدة بالضبط (أي إن تغيّرت الدالة بعد كتابة هذا الملف). CREATE OR REPLACE يُبقي المالك والصلاحيات (GRANT) كما هي.
-- التعاريف الحية وقت الكتابة (md5 لـ pg_get_functiondef، ٢٠٢٦-١٠-٢٥):
--   sms_admin_overview 1b907847ebd98f8ae077b2cbb1ab6c5c · sms_balance_status cbcbca6e6bb5b00c7c223a7a854a486c ·
--   sms_login_attempts 75074896d6449ec8bb8e2b737c5fe332 · app_config 415ace6352adde583c73321cfeac2bd8 ·
--   finish_kwtsms_send 958eb4fc309a72384eab90cf8bb0b760 · kwtsms_balance_check 9e4a4d0c274b5c9e26e3591d54861700 ·
--   log_login_attempt 79e8b1c1eaa9aa27c8fc699a1f72ce3e
--
-- خارج هذا الملف (للعلم): دالة الحافة kwtsms-admin تقبل المالك والمدير لإجراءات القراءة (balance، senderid، coverage،
-- status، validate) — `handler.ts` السطر `profileAllowed(profile, ["owner", "admin"])` يصير `["owner"]` ثم نشرها.


-- أ + ب) الدوال: الشرط القديم ← الجديد (مرة واحدة بالضبط في كل دالة)
do $patch$
declare
  r record;
  d text;
  n int;
begin
  for r in
    select * from (values
      ('public.sms_admin_overview()',
       $o$coalesce(public.current_user_role(), '') not in ('owner', 'admin')$o$,
       $n$coalesce(public.current_user_role(), '') <> 'owner'$n$),
      ('public.sms_admin_overview()',
       $o$'recipients', 'owner_admins'$o$,
       $n$'recipients', 'owner'$n$),
      ('public.sms_balance_status()',
       $o$coalesce(public.current_user_role(), '') not in ('owner', 'admin')$o$,
       $n$coalesce(public.current_user_role(), '') <> 'owner'$n$),
      ('public.sms_login_attempts(integer)',
       $o$coalesce(v_role, '') not in ('owner', 'admin')$o$,
       $n$coalesce(v_role, '') <> 'owner'$n$),
      ('public.app_config()',
       $o$if v_role in ('owner', 'admin') then$o$,
       $n$if v_role = 'owner' then$n$),
      ('public.finish_kwtsms_send(text,text,text,numeric,numeric,text)',
       $o$where p.role in ('owner', 'admin') and p.status = 'active';$o$,
       $n$where p.role = 'owner' and p.status = 'active';$n$),
      ('public.kwtsms_balance_check(numeric)',
       $o$where p.role in ('owner', 'admin') and p.status = 'active';$o$,
       $n$where p.role = 'owner' and p.status = 'active';$n$),
      ('public.log_login_attempt(text,text)',
       $o$where p.role in ('owner', 'admin') and p.status = 'active';$o$,
       $n$where p.role = 'owner' and p.status = 'active';$n$)
    ) v(sig, old_text, new_text)
  loop
    d := pg_get_functiondef(r.sig::regprocedure);
    n := (length(d) - length(replace(d, r.old_text, ''))) / length(r.old_text);
    if n <> 1 then
      raise exception 'owner_only_system_areas: % — expected the old text once, found % (the live function changed?)', r.sig, n;
    end if;
    execute replace(d, r.old_text, r.new_text);
  end loop;
end
$patch$;

-- ج) الجداول
drop policy if exists device_tokens_select_self_or_admin on public.device_tokens;
create policy device_tokens_select_self_or_owner on public.device_tokens
  for select to authenticated
  using (member_id = auth.uid() or public.current_user_role() = 'owner');

drop policy if exists device_tokens_admin_delete on public.device_tokens;
create policy device_tokens_owner_delete on public.device_tokens
  for delete to public
  using (public.current_user_role() = 'owner');

drop policy if exists device_revocations_select on public.device_revocations;
create policy device_revocations_select on public.device_revocations
  for select to authenticated
  using (member_id = auth.uid() or public.current_user_role() = 'owner');

drop policy if exists device_revocations_insert_admin on public.device_revocations;
create policy device_revocations_insert_owner on public.device_revocations
  for insert to authenticated
  with check (public.current_user_role() = 'owner');

drop policy if exists device_revocations_update_admin on public.device_revocations;
create policy device_revocations_update_owner on public.device_revocations
  for update to authenticated
  using (public.current_user_role() = 'owner')
  with check (public.current_user_role() = 'owner');

drop policy if exists device_revocations_delete on public.device_revocations;
create policy device_revocations_delete on public.device_revocations
  for delete to authenticated
  using (member_id = auth.uid() or public.current_user_role() = 'owner');

drop policy if exists banned_phones_select on public.banned_phones;
create policy banned_phones_select on public.banned_phones
  for select to public
  using (public.current_user_role() = 'owner');

drop policy if exists app_config_history_owner_admin_read on public.app_config_history;
create policy app_config_history_owner_read on public.app_config_history
  for select to authenticated
  using (coalesce(public.current_user_role(), '') = 'owner');

drop policy if exists family_names_write on public.family_names;
create policy family_names_write on public.family_names
  for all to public
  using (public.current_user_role() = 'owner')
  with check (public.current_user_role() = 'owner');
