-- Migration for configuring News Likes and Comments

create table if not exists public.news_likes (
  id uuid primary key default gen_random_uuid(),
  news_id uuid references public.news(id) on delete cascade not null,
  member_id uuid references auth.users(id) on delete cascade not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  unique (news_id, member_id)
);

create table if not exists public.news_comments (
  id uuid primary key default gen_random_uuid(),
  news_id uuid references public.news(id) on delete cascade not null,
  author_id uuid references auth.users(id) on delete set null,
  author_name text not null,
  content text not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Indexes for performance
create index if not exists idx_news_likes_news_id on public.news_likes(news_id);
create index if not exists idx_news_comments_news_id on public.news_comments(news_id);

-- RLS for news_likes
alter table public.news_likes enable row level security;

drop policy if exists "Anyone can select likes" on public.news_likes;
create policy "Anyone can select likes" on public.news_likes
for select using (true);

drop policy if exists "Users can like posts" on public.news_likes;
create policy "Users can like posts" on public.news_likes
for insert with check (auth.uid() = member_id);

drop policy if exists "Users can unlike posts" on public.news_likes;
create policy "Users can unlike posts" on public.news_likes
for delete using (auth.uid() = member_id);

-- RLS for news_comments
alter table public.news_comments enable row level security;

drop policy if exists "Anyone can select comments" on public.news_comments;
create policy "Anyone can select comments" on public.news_comments
for select using (true);

drop policy if exists "Users can insert comments" on public.news_comments;
create policy "Users can insert comments" on public.news_comments
for insert with check (auth.uid() = author_id);

drop policy if exists "Users can delete their own comments or admins can delete any" on public.news_comments;
create policy "Users can delete their own comments or admins can delete any" on public.news_comments
for delete using (auth.uid() = author_id or public.current_user_role() in ('supervisor', 'admin'));
