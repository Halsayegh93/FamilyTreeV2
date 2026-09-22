-- إزالة جهاز من الإدارة تُخرجه فعلاً (طلب المالك)
--
-- كان حذف صف device_tokens وحده لا يكفي: إذا بقي للعضو مكان شاغر في حد الأجهزة،
-- يعيد التطبيق تسجيل الجهاز تلقائياً عند فتحه فيبدو كأن الحذف لم يحدث.
-- الآن تُسجَّل الإزالة هنا، ويقرأها تطبيق العضو عند التحقق من جهازه فيسجّل خروجه
-- ثم يحذف الصف. لا تتأثر بها التنظيفات الآلية (حذف التطبيق/الأجهزة القديمة).

create table if not exists public.device_revocations (
  member_id  uuid not null references public.profiles(id) on delete cascade,
  device_id  text not null,
  revoked_by uuid references public.profiles(id) on delete set null,
  revoked_at timestamptz not null default now(),
  primary key (member_id, device_id)
);

alter table public.device_revocations enable row level security;

drop policy if exists device_revocations_select on public.device_revocations;
create policy device_revocations_select on public.device_revocations
  for select to authenticated
  using (member_id = auth.uid() or public.current_user_role() in ('owner', 'admin'));

drop policy if exists device_revocations_insert_admin on public.device_revocations;
create policy device_revocations_insert_admin on public.device_revocations
  for insert to authenticated
  with check (public.current_user_role() in ('owner', 'admin'));

drop policy if exists device_revocations_update_admin on public.device_revocations;
create policy device_revocations_update_admin on public.device_revocations
  for update to authenticated
  using (public.current_user_role() in ('owner', 'admin'))
  with check (public.current_user_role() in ('owner', 'admin'));

drop policy if exists device_revocations_delete on public.device_revocations;
create policy device_revocations_delete on public.device_revocations
  for delete to authenticated
  using (member_id = auth.uid() or public.current_user_role() in ('owner', 'admin'));

grant select, insert, update, delete on public.device_revocations to authenticated;
