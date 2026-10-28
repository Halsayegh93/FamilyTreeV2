-- مراجعة Apple (٢٠٢٦-١٠-٢٨، «صلّح الكل»):
--  ١) فلتر كلمات مسيئة على التعليقات (Guideline 1.2 «طريقة لفلترة المحتوى المسيء») — القائمة
--     والرسالة على السيرفر في app_config (blocked_words / blocked_words_message) تُعدَّل بلا تحديث.
--  ٢) قبول الشروط صراحةً عند أول دخول (Guideline 1.2 «موافقة المستخدم على الشروط») —
--     app_config.terms_version؛ رفعه يطلب الموافقة من جديد، و0 يوقف الشاشة.
-- التراجع: supabase/rollback/20261028130000_comment_filter_terms_rollback.sql

-- ═══ ١) الفلتر ═══
insert into public.app_config (key, value, default_value, kind, category, label_ar, help_ar, is_public, sort)
values
  ('blocked_words',
   $j$["كلب","حمار","حيوان","خنزير","حقير","وسخ","زبالة","قذر","غبي","تافه","منيوك","منيك","كس","كسمك","زب","شرموطة","شرموط","قحبة","قحبه","عاهرة","عاهره","لوطي","ديوث","معرص","خول","طز","انقلع","fuck","shit","bitch","asshole","bastard","dick","pussy","whore","slut"]$j$::jsonb,
   $j$["كلب","حمار","حيوان","خنزير","حقير","وسخ","زبالة","قذر","غبي","تافه","منيوك","منيك","كس","كسمك","زب","شرموطة","شرموط","قحبة","قحبه","عاهرة","عاهره","لوطي","ديوث","معرص","خول","طز","انقلع","fuck","shit","bitch","asshole","bastard","dick","pussy","whore","slut"]$j$::jsonb,
   'json', 'news', 'كلمات ممنوعة في التعليقات',
   'قائمة كلمات يُرفض التعليق إن احتواها (كلمة كاملة، مع «ال» و«و» قبلها). الهمزات والتشكيل لا تؤثر.',
   false, 40),
  ('blocked_words_message', to_jsonb('التعليق فيه كلمات غير لائقة — عدّله ثم أرسله.'::text),
   to_jsonb('التعليق فيه كلمات غير لائقة — عدّله ثم أرسله.'::text),
   'text', 'news', 'رسالة رفض التعليق', 'تظهر للعضو حين يحتوي تعليقه كلمة ممنوعة.', false, 41)
on conflict (key) do nothing;

-- توحيد الحروف للمقارنة: أ/إ/آ/ٱ ← ا، ى ← ي، ة ← ه، حذف التطويل والتشكيل، أحرف صغيرة
create or replace function public.normalize_filter_text(p_text text)
returns text language sql immutable set search_path = public as $$
  select regexp_replace(translate(lower(coalesce(p_text, '')), 'أإآٱىةـ', 'اااايه'),
                        '[ً-ْٰ]', '', 'g')
$$;

create or replace function public.contains_blocked_word(p_text text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  words jsonb;
  norm text;
  w text;
begin
  select value into words from public.app_config where key = 'blocked_words';
  if words is null or jsonb_typeof(words) <> 'array' then return false; end if;
  norm := ' ' || regexp_replace(public.normalize_filter_text(p_text), '[^[:alnum:]]+', ' ', 'g') || ' ';
  for w in select btrim(regexp_replace(public.normalize_filter_text(x), '[^[:alnum:]]+', ' ', 'g'))
           from jsonb_array_elements_text(words) x loop
    if w <> '' and (position(' ' || w || ' ' in norm) > 0
                    or position(' ال' || w || ' ' in norm) > 0
                    or position(' و' || w || ' ' in norm) > 0
                    or position(' وال' || w || ' ' in norm) > 0) then
      return true;
    end if;
  end loop;
  return false;
end $$;
revoke execute on function public.contains_blocked_word(text) from public, anon;
grant execute on function public.contains_blocked_word(text) to authenticated;

create or replace function public.trg_news_comments_filter()
returns trigger language plpgsql security definer set search_path = public as $$
declare msg text;
begin
  if public.contains_blocked_word(new.content) then
    select value #>> '{}' into msg from public.app_config where key = 'blocked_words_message';
    raise exception '%', coalesce(nullif(msg, ''), 'التعليق فيه كلمات غير لائقة — عدّله ثم أرسله.')
      using errcode = 'P0001', hint = 'objectionable';
  end if;
  return new;
end $$;

drop trigger if exists trg_news_comments_filter on public.news_comments;
create trigger trg_news_comments_filter
  before insert or update of content on public.news_comments
  for each row execute function public.trg_news_comments_filter();

-- ═══ ٢) قبول الشروط ═══
insert into public.app_config (key, value, default_value, kind, category, label_ar, help_ar, min_value, max_value, is_public, sort)
values ('terms_version', to_jsonb(1), to_jsonb(1), 'int', 'links', 'إصدار الشروط',
        'رفع الرقم يطلب من كل عضو الموافقة على «الخصوصية والاستخدام» من جديد عند دخوله. 0 يوقف شاشة الموافقة.',
        0, 1000, true, 92)
on conflict (key) do nothing;

create table if not exists public.terms_acceptances (
  member_id uuid not null,
  version int not null,
  accepted_at timestamptz not null default now(),
  primary key (member_id, version)
);
alter table public.terms_acceptances enable row level security;
drop policy if exists terms_acceptances_select_own on public.terms_acceptances;
create policy terms_acceptances_select_own on public.terms_acceptances
  for select to authenticated
  using (member_id = coalesce(public.current_profile_id(), auth.uid()));
revoke all on public.terms_acceptances from anon;

-- {required, accepted, needs}: needs = true حين تلزم الموافقة على الإصدار الحالي
create or replace function public.my_terms_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := coalesce(public.current_profile_id(), auth.uid());
  req int;
  acc int;
begin
  if me is null then raise exception 'not_authenticated' using hint = 'not_authenticated'; end if;
  select coalesce((value #>> '{}')::int, 0) into req from public.app_config where key = 'terms_version';
  req := coalesce(req, 0);
  select max(version) into acc from public.terms_acceptances where member_id = me;
  return jsonb_build_object('required', req, 'accepted', coalesce(acc, 0),
                            'needs', req > 0 and coalesce(acc, 0) < req);
end $$;

create or replace function public.accept_terms(p_version int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := coalesce(public.current_profile_id(), auth.uid());
  req int;
begin
  if me is null then raise exception 'not_authenticated' using hint = 'not_authenticated'; end if;
  select coalesce((value #>> '{}')::int, 0) into req from public.app_config where key = 'terms_version';
  if p_version is null or p_version < 1 or p_version > coalesce(req, 0) then
    raise exception 'invalid_version' using hint = 'invalid_version';
  end if;
  insert into public.terms_acceptances (member_id, version) values (me, p_version)
  on conflict do nothing;
  return public.my_terms_status();
end $$;

revoke execute on function public.my_terms_status() from public, anon;
revoke execute on function public.accept_terms(int) from public, anon;
grant execute on function public.my_terms_status() to authenticated;
grant execute on function public.accept_terms(int) to authenticated;
