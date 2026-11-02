-- بطاقة حساب مراجعة Apple في «حسابي» (اختيار المالك «ب» ٢٠٢٦-١٠-٣٠): النصوص على السيرفر،
-- و my_review_card() ترجعها لحسابات review_account_ids فقط (غيرهم null).

insert into public.app_config(key, value, default_value, kind, category, sort, label_ar, help_ar, is_public)
values ('review_card', $j${"badge_ar":"بطاقة زائر رسمي","badge_en":"Official visitor pass","tag":"APP REVIEW","title_ar":"فريق مراجعة Apple","title_en":"Apple Review Team","subtitle_ar":"ضيف — غير مرتبط بالشجرة","subtitle_en":"Guest — not linked to the tree","access_ar":"تصفح وتجربة","access_en":"Browse and try","about_ar":"مخصص لمراجعة التطبيق في متجر App Store. ما تكتبه من تعليقات أو بلاغات يصل للإدارة فقط ولا يظهر لأفراد العائلة.","about_en":"Reserved for App Store review. Comments and reports you write reach the administration only and are not shown to family members."}$j$::jsonb,
        '{}'::jsonb, 'json', 'members', 98, 'بطاقة حساب المراجعة', 'نصوص البطاقة التي تظهر في «حسابي» لحسابات مراجعة Apple.', false)
on conflict (key) do nothing;

create or replace function public.my_review_card()
returns jsonb language sql stable security definer set search_path = '' as $$
  select case when auth.uid() = any(public.review_account_ids())
              then coalesce((select c.value from public.app_config c where c.key = 'review_card'), '{}'::jsonb) end;
$$;

revoke all on function public.my_review_card() from public, anon;
grant execute on function public.my_review_card() to authenticated;

-- شارة «معتمد» على كل ما يفعله حساب المراجعة: التطبيق يحتاج قائمة المعرّفات (للمسجّلين فقط)
create or replace function public.review_account_list()
returns uuid[] language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is not null then public.review_account_ids() else '{}'::uuid[] end;
$$;
revoke all on function public.review_account_list() from public, anon;
grant execute on function public.review_account_list() to authenticated;

-- ثم: الشارة للمالك وحده (طلب المالك «بس يبين الاعتماد عندي») — غيره يستلم قائمة فاضية
create or replace function public.review_account_list()
returns uuid[] language sql stable security definer set search_path = '' as $$
  select case when coalesce(public.current_user_role(), '') = 'owner' then public.review_account_ids() else '{}'::uuid[] end;
$$;
