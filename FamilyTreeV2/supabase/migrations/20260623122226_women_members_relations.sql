-- علاقات شجرة النساء (مثل profiles): أم + زوج.
alter table public.women_members
  add column if not exists mother_id uuid references public.women_members(id) on delete set null,
  add column if not exists husband_id uuid references public.women_members(id) on delete set null;

create index if not exists women_members_mother_id_idx on public.women_members(mother_id);
create index if not exists women_members_husband_id_idx on public.women_members(husband_id);;
