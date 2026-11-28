-- «مين يشوف وش» في لوحة الإدارة — جدول الأدوار على السيرفر (مقترح «أدوار الإدارة» بموافقة المالك ٢٠٢٦-١١-٠٧،
-- samples/admin-roles). قاعدة المالك: «كل شي يكون على قاعدة البيانات، ما نبي التطبيق كل شوي».
-- APPLIED 2026-11-07 بموافقة المالك.
-- التراجع: supabase/rollback/20261107200000_admin_role_matrix_rollback.sql
-- التجربة المحلية: cd supabase/tests/family_links && node admin_role_matrix.test.mjs
--
-- مفتاح واحد في app_config: admin_role_matrix (json) — لكل دور (المدير، المراقب، المشرف) ما يظهر له من الأقسام الستة
-- (areas) ومن بطاقات «اليوم» وصفوف الأقسام (items)، وكل خانة "edit" (يشوف ويعدّل) أو "read" (يشوف بس) أو "none"
-- (ما يشوف)، والرقم الرابع في «يحتاج انتباهك» (attention_fourth: messages · tree_issues · reports).
-- • المالكان (الاثنين) دائماً كل شي — لا يدخلان الجدول (لا يقفل إعداد خاطئ أحداً منهما).
-- • خانة أو دور غائب = افتراضي التطبيق (= هذه القيمة نفسها، `AdminRoleMatrix.swift`).
-- • الجدول للظهور فقط؛ الصلاحيات الفعلية تبقى في حرّاس السيرفر الحالية. لذلك يرفض الفحص فتح ما يحرسه السيرفر للمالك
--   وحده لغيره: قسم «التطبيق» و app.settings و team.sms و team.registration و team.devices تبقى "none".
-- • ما فتحه المقترح لغير المالك مسموح على السيرفر من قبل (لا تغيير صلاحيات هنا): فريق الإدارة (profiles)،
--   الاستخدام (app_usage_stats · get_active_members_now · admin_membership_counts للمالك والمدير)، إحصاء الأفراد للمراقب
--   (members_masked · women_members · app_usage_stats = is_moderator)، إعدادات مسار الموافقات للقراءة (app_settings
--   للجميع، والتعديل للمالك). sms_admin_overview · sms_balance_status · sms_login_attempts وأجهزة الأعضاء والأرقام
--   الممنوعة تبقى للمالك.
-- القيم يقرؤها كل مسجّل عبر app_config() (ليست عامة)، والتعديل للمالك عبر set_app_config الموجودة.

create or replace function private.admin_role_matrix_problem(p jsonb)
returns text
language plpgsql
immutable
set search_path to ''
as $function$
declare
  v_role  text;
  v_row   jsonb;
  v_key   text;
  v_val   jsonb;
  v_areas constant text[] := array['inbox', 'family', 'occasions', 'metrics', 'team', 'app'];
  v_items constant text[] := array[
    'today.attention', 'today.census', 'today.system_status', 'today.megaphone',
    'inbox.messages', 'inbox.photos', 'inbox.approval_settings',
    'occasions.upcoming', 'occasions.announce', 'occasions.cards', 'occasions.published',
    'metrics.family', 'metrics.approvals',
    'team.members', 'team.usage', 'team.sms', 'team.registration', 'team.devices',
    'app.settings'];
  v_owner_only constant text[] := array['app.settings', 'team.sms', 'team.registration', 'team.devices'];
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    return 'الجدول يجب أن يكون كائناً بالأدوار';
  end if;
  for v_role, v_row in select * from jsonb_each(p) loop
    if v_role not in ('admin', 'monitor', 'supervisor') then
      return 'دور غير معروف في الجدول: ' || v_role || ' (المالكان دائماً كل شي ولا يدخلان الجدول)';
    end if;
    if jsonb_typeof(v_row) <> 'object' then
      return 'صفّ ' || v_role || ' يجب أن يكون كائناً';
    end if;
    for v_key in select jsonb_object_keys(v_row) loop
      if v_key not in ('areas', 'items', 'attention_fourth') then
        return 'مفتاح غير معروف في صفّ ' || v_role || ': ' || v_key;
      end if;
    end loop;
    if v_row ? 'attention_fourth'
       and coalesce(v_row ->> 'attention_fourth', '') not in ('messages', 'tree_issues', 'reports') then
      return 'الرقم الرابع لـ' || v_role || ' يجب أن يكون messages أو tree_issues أو reports';
    end if;
    if v_row ? 'areas' then
      if jsonb_typeof(v_row -> 'areas') <> 'object' then return 'أقسام ' || v_role || ' يجب أن تكون كائناً'; end if;
      for v_key, v_val in select * from jsonb_each(v_row -> 'areas') loop
        if not (v_key = any (v_areas)) then return 'قسم غير معروف: ' || v_key; end if;
        if jsonb_typeof(v_val) <> 'string' or (v_val #>> '{}') not in ('edit', 'read', 'none') then
          return 'قيمة ' || v_role || '.' || v_key || ' يجب أن تكون edit أو read أو none';
        end if;
        if v_key = 'app' and (v_val #>> '{}') <> 'none' then
          return 'قسم «التطبيق» للمالك وحده — لا يُفتح لـ' || v_role;
        end if;
      end loop;
    end if;
    if v_row ? 'items' then
      if jsonb_typeof(v_row -> 'items') <> 'object' then return 'خانات ' || v_role || ' يجب أن تكون كائناً'; end if;
      for v_key, v_val in select * from jsonb_each(v_row -> 'items') loop
        if not (v_key = any (v_items)) then return 'خانة غير معروفة: ' || v_key; end if;
        if jsonb_typeof(v_val) <> 'string' or (v_val #>> '{}') not in ('edit', 'read', 'none') then
          return 'قيمة ' || v_role || '.' || v_key || ' يجب أن تكون edit أو read أو none';
        end if;
        if v_key = any (v_owner_only) and (v_val #>> '{}') <> 'none' then
          return v_key || ' يحرسه السيرفر للمالك وحده — لا يُفتح لـ' || v_role;
        end if;
      end loop;
    end if;
  end loop;
  return null;
end;
$function$;

create or replace function private.app_config_role_matrix_guard()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare v_msg text;
begin
  v_msg := private.admin_role_matrix_problem(new.default_value);
  if v_msg is not null then
    raise exception 'الافتراضي لـ %: %', new.key, v_msg using errcode = '22023', hint = 'bad_value';
  end if;
  v_msg := private.admin_role_matrix_problem(new.value);
  if v_msg is not null then
    raise exception '%', v_msg using errcode = '22023', hint = 'bad_value';
  end if;
  return new;
end;
$function$;

revoke all on function private.admin_role_matrix_problem(jsonb) from public, anon, authenticated;
revoke all on function private.app_config_role_matrix_guard() from public, anon, authenticated;

drop trigger if exists trg_app_config_role_matrix_guard on public.app_config;
create trigger trg_app_config_role_matrix_guard
  before insert or update on public.app_config
  for each row when (new.key = 'admin_role_matrix')
  execute function private.app_config_role_matrix_guard();

-- القيمة = المقترح المعتمد (نفس افتراضي التطبيق)
insert into public.app_config (key, value, default_value, kind, category, label_ar, help_ar, rules, is_public, sort)
select 'admin_role_matrix', m, m, 'json', 'general',
       'مين يشوف وش في لوحة الإدارة',
       'لكل دور (المدير، المراقب، المشرف): الأقسام الستة وبطاقات «اليوم» وصفوف الأقسام — edit يشوف ويعدّل، read يشوف بس، none ما يشوف. المالكان دائماً كل شي. الصلاحيات الفعلية يحرسها السيرفر.',
       '{}'::jsonb, false, 95
  from (select $json${
  "admin": {
    "areas": {"inbox": "edit", "family": "edit", "occasions": "edit", "metrics": "read", "team": "read", "app": "none"},
    "items": {
      "today.attention": "read", "today.census": "read", "today.system_status": "none", "today.megaphone": "edit",
      "inbox.messages": "edit", "inbox.photos": "edit", "inbox.approval_settings": "read",
      "occasions.upcoming": "edit", "occasions.announce": "edit", "occasions.cards": "edit", "occasions.published": "read",
      "metrics.family": "read", "metrics.approvals": "read",
      "team.members": "read", "team.usage": "read", "team.sms": "none", "team.registration": "none", "team.devices": "none",
      "app.settings": "none"
    },
    "attention_fourth": "messages"
  },
  "monitor": {
    "areas": {"inbox": "edit", "family": "edit", "occasions": "read", "metrics": "read", "team": "none", "app": "none"},
    "items": {
      "today.attention": "read", "today.census": "read", "today.system_status": "none", "today.megaphone": "none",
      "inbox.messages": "none", "inbox.photos": "edit", "inbox.approval_settings": "none",
      "occasions.upcoming": "read", "occasions.announce": "none", "occasions.cards": "none", "occasions.published": "none",
      "metrics.family": "read", "metrics.approvals": "none",
      "team.members": "none", "team.usage": "none", "team.sms": "none", "team.registration": "none", "team.devices": "none",
      "app.settings": "none"
    },
    "attention_fourth": "tree_issues"
  },
  "supervisor": {
    "areas": {"inbox": "edit", "family": "none", "occasions": "edit", "metrics": "none", "team": "none", "app": "none"},
    "items": {
      "today.attention": "read", "today.census": "none", "today.system_status": "none", "today.megaphone": "none",
      "inbox.messages": "none", "inbox.photos": "none", "inbox.approval_settings": "none",
      "occasions.upcoming": "read", "occasions.announce": "none", "occasions.cards": "edit", "occasions.published": "none",
      "metrics.family": "none", "metrics.approvals": "none",
      "team.members": "none", "team.usage": "none", "team.sms": "none", "team.registration": "none", "team.devices": "none",
      "app.settings": "none"
    },
    "attention_fourth": "reports"
  }
}$json$::jsonb) d(m)
on conflict (key) do nothing;
