-- تراجع 20261028130000_comment_filter_terms
drop trigger if exists trg_news_comments_filter on public.news_comments;
drop function if exists public.trg_news_comments_filter();
drop function if exists public.contains_blocked_word(text);
drop function if exists public.normalize_filter_text(text);
drop function if exists public.accept_terms(int);
drop function if exists public.my_terms_status();
drop table if exists public.terms_acceptances;
delete from public.app_config where key in ('blocked_words', 'blocked_words_message', 'terms_version');
