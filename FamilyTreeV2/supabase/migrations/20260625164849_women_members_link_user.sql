-- ربط اسم المرأة في شجرة النساء بحساب مستخدم (profiles) — مرجع إداري + زر "موقعي".
alter table public.women_members
  add column if not exists linked_user_id uuid references public.profiles(id) on delete set null;

create index if not exists idx_women_members_linked_user
  on public.women_members(linked_user_id);

comment on column public.women_members.linked_user_id is
  'حساب التطبيق المرتبط بهذا الاسم (للإناث المسجّلات) — يستخدمه زر موقعي. يُضبط من الإدارة فقط.';;
