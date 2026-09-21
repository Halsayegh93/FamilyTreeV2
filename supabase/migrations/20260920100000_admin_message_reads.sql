-- رسائل التواصل: حالة «مقروء» على السيرفر بدل كل جهاز على حدة (طلب المالك)
--
-- قبل هذا الجدول كانت المعرّفات المقروءة تُحفظ في UserDefaults/SharedPreferences،
-- فيبقى عدّاد الرسائل مختلفاً بين الآيفون والأندرويد لنفس الشخص.
-- الآن لكل مشرف صفّ واحد لكل رسالة قرأها، ويقرأه أي جهاز يدخل بحسابه.

create table if not exists public.admin_message_reads (
  message_id uuid not null references public.admin_requests(id) on delete cascade,
  member_id  uuid not null references public.profiles(id) on delete cascade,
  read_at    timestamptz not null default now(),
  primary key (message_id, member_id)
);

create index if not exists admin_message_reads_member_idx
  on public.admin_message_reads (member_id);

alter table public.admin_message_reads enable row level security;

-- كل مشرف يرى ويكتب صفوفه هو فقط — لا أحد يقرأ حالة غيره
drop policy if exists admin_message_reads_select_own on public.admin_message_reads;
create policy admin_message_reads_select_own
  on public.admin_message_reads for select
  to authenticated
  using (member_id = auth.uid());

drop policy if exists admin_message_reads_insert_own on public.admin_message_reads;
create policy admin_message_reads_insert_own
  on public.admin_message_reads for insert
  to authenticated
  with check (member_id = auth.uid() and public.is_moderator());

drop policy if exists admin_message_reads_delete_own on public.admin_message_reads;
create policy admin_message_reads_delete_own
  on public.admin_message_reads for delete
  to authenticated
  using (member_id = auth.uid());

grant select, insert, delete on public.admin_message_reads to authenticated;
