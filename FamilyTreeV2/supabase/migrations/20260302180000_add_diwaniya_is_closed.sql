-- Add is_closed column to diwaniyas table
alter table public.diwaniyas
  add column if not exists is_closed boolean default false;
