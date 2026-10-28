-- تراجع 20261027170000_data_minimization — يعيد الدالتين والجداول (الشاشات لكل عضو والسجل الأقدم من ٣٠ يوماً لا تعود)
create table if not exists public.hr_notes (id uuid not null default gen_random_uuid() primary key, member_id uuid not null references public.profiles(id) on delete cascade, note text not null, created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), status text);
create table if not exists public.hr_documents (id uuid not null default gen_random_uuid() primary key, member_id uuid not null references public.profiles(id) on delete cascade, name text not null, file_url text not null, doc_type text, uploaded_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), status text);
create table if not exists public.hr_contact_log (id uuid not null default gen_random_uuid() primary key, member_id uuid not null references public.profiles(id) on delete cascade, reason text not null, summary text, channel text, contacted_by uuid not null references public.profiles(id), contacted_at timestamptz not null default now(), status text);
alter table public.hr_notes enable row level security;
alter table public.hr_documents enable row level security;
alter table public.hr_contact_log enable row level security;
create policy hr_notes_read on public.hr_notes for select using (public.is_hr_or_owner());
create policy hr_notes_write on public.hr_notes for all using (public.is_hr_or_owner());
create policy hr_docs_read on public.hr_documents for select using (public.is_hr_or_owner());
create policy hr_docs_write on public.hr_documents for all using (public.is_hr_or_owner());
create policy hr_contact_read on public.hr_contact_log for select using (public.is_hr_or_owner());
create policy hr_contact_write on public.hr_contact_log for all using (public.is_hr_or_owner());
-- الدالتان بنصّهما السابق: انظر git show 20261027170000^ أو تعريفهما قبل الترحيل (log_app_session بحفظ الشاشات لكل عضو ٩٠ يوماً،
-- app_usage_engagement بقائمة members بالأسماء) — أعد لصقهما من نسخة ما قبل هذا الملف في supabase/migrations.
