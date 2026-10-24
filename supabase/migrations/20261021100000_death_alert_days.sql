-- مدة تنبيه «وفاة لم يُعلن عنها» في لوحة الإدارة — من السيرفر لا من التطبيق (طلب المالك ٢٠٢٦-١٠-٢١:
-- «في اشياء بالسيرفر تتعدل و تتعدل بالتطبيق مو لازم كل مره تنبني» + «قصّر المدة لـ٧ أيام»).
-- التطبيقات تقرأ app_settings.death_alert_days (القراءة لكل مسجّل بسياسة app_settings نفسها) — تغييره هنا يظهر فوراً
-- في الآيفون والأندرويد بلا نسخة جديدة. الإعلان نفسه يبقى ٣٠ يوماً (announce_death لم تتغيّر).
-- التراجع: supabase/rollback/20261021100000_death_alert_days_rollback.sql
alter table public.app_settings
  add column if not exists death_alert_days integer not null default 7
    check (death_alert_days between 1 and 30);
