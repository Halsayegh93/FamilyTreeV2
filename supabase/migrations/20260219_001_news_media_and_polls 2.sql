-- News: multi-image support + poll voting

alter table if exists public.news
  add column if not exists image_urls jsonb not null default '[]'::jsonb;

alter table if exists public.news
  add column if not exists poll_question text;

alter table if exists public.news
  add column if not exists poll_options jsonb not null default '[]'::jsonb;

create table if not exists public.news_poll_votes (
  id uuid primary key default gen_random_uuid(),
  news_id uuid not null references public.news(id) on delete cascade,
  member_id uuid not null references public.profiles(id) on delete cascade,
  option_index integer not null check (option_index >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  unique (news_id, member_id)
);

create index if not exists idx_news_poll_votes_news on public.news_poll_votes(news_id);
create index if not exists idx_news_poll_votes_member on public.news_poll_votes(member_id);

alter table public.news_poll_votes enable row level security;

drop policy if exists "news_poll_votes_select_authenticated" on public.news_poll_votes;
create policy "news_poll_votes_select_authenticated" on public.news_poll_votes
for select
using (auth.uid() is not null);

drop policy if exists "news_poll_votes_insert_self" on public.news_poll_votes;
create policy "news_poll_votes_insert_self" on public.news_poll_votes
for insert
with check (member_id = auth.uid());

drop policy if exists "news_poll_votes_update_self" on public.news_poll_votes;
create policy "news_poll_votes_update_self" on public.news_poll_votes
for update
using (member_id = auth.uid())
with check (member_id = auth.uid());
