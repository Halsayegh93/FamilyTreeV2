begin;
create index if not exists news_feed_cursor_idx on public.news(created_at desc,id desc);

create or replace function public.news_feed_page(p_before_time timestamptz default null,p_before_id uuid default null,p_search text default '',p_type text default null,p_limit int default 25)
returns setof public.news language sql stable security invoker set search_path=public as $$
  select n.* from public.news n
  where public.is_approved_member()
    and (public.current_user_role() in ('owner','admin','monitor','supervisor') or coalesce(n.approval_status,'approved')='approved' or coalesce(n.author_id,n.posted_by)=public.current_profile_id())
    and (p_before_time is null or (n.created_at,n.id)<(p_before_time,p_before_id))
    and (p_type is null or n.type=p_type)
    and (coalesce(p_search,'')='' or strpos(lower(n.content),lower(p_search))>0 or strpos(lower(n.author_name),lower(p_search))>0)
  order by n.created_at desc,n.id desc limit greatest(1,least(coalesce(p_limit,25),50));
$$;
revoke all on function public.news_feed_page(timestamptz,uuid,text,text,int) from public,anon;
grant execute on function public.news_feed_page(timestamptz,uuid,text,text,int) to authenticated;

create or replace function public.news_page_stats(p_ids uuid[])
returns table(news_id uuid,likes_count bigint,comments_count bigint,is_liked boolean,poll_counts jsonb,my_vote int)
language sql stable security invoker set search_path=public as $$
  select n.id,
    (select count(*) from news_likes l where l.news_id=n.id),
    (select count(*) from news_comments c where c.news_id=n.id),
    exists(select 1 from news_likes l where l.news_id=n.id and l.member_id in (auth.uid(),public.current_profile_id())),
    coalesce((select jsonb_object_agg(v.option_index,v.total) from (select option_index,count(*) total from news_poll_votes where news_poll_votes.news_id=n.id group by option_index) v),'{}'::jsonb),
    (select v.option_index from news_poll_votes v where v.news_id=n.id and v.member_id in (auth.uid(),public.current_profile_id()) limit 1)
  from news n where n.id=any(p_ids[1:50]) and public.is_approved_member();
$$;
revoke all on function public.news_page_stats(uuid[]) from public,anon;
grant execute on function public.news_page_stats(uuid[]) to authenticated;
commit;
