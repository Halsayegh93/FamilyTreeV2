-- Add optional address column to diwaniyas table.

alter table public.diwaniyas
  add column if not exists address text;
