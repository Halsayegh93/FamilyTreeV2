-- 🔴 ثغرة حرجة: أي شخص ينهي OTP يقرأ كل شيء — حتى بلا صفّ في profiles.
-- مُثبَت: غريب بجلسة مصادقة فقط قرأ 2712 ملفاً و49 رقم هاتف و2947 صفاً نسائياً.
--
-- السبب: على profiles ثلاث سياسات قراءة تُجمع بـ«أو»، إحداها
-- profiles_select_authenticated = auth.uid() IS NOT NULL — تبتلع السياستين
-- المدقّقتين وتُلغيهما. والواجهة تُخفي ذلك بشاشة «بانتظار الموافقة»، فالبوّابة
-- كانت في التطبيق لا في القاعدة.
-- وزيادةً: 1649 حساباً «قيد الموافقة» دورها member، فحذف الواسعة وحدها لا يكفي
-- — لا بدّ من اشتراط status = 'active' صراحةً.

-- عضو معتمَد فعلاً: له ملف، حالته active، ودوره من الأدوار المعروفة.
create or replace function public.is_approved_member()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = coalesce(
            nullif(auth.jwt() -> 'app_metadata' ->> 'profile_id','')::uuid,
            nullif(auth.jwt() -> 'user_metadata' ->> 'profile_id','')::uuid,
            auth.uid())
      and p.status = 'active'
      and p.role = any (array['member','supervisor','monitor','admin','owner'])
  );
$$;
revoke all on function public.is_approved_member() from public, anon;
grant execute on function public.is_approved_member() to authenticated;

-- ── profiles: سياسة قراءة واحدة واضحة بدل ثلاث تتنازع ──
drop policy if exists profiles_select_authenticated on public.profiles;
drop policy if exists profiles_select_active_only   on public.profiles;
drop policy if exists profiles_select_self_or_active on public.profiles;
create policy profiles_select_self_or_approved on public.profiles
for select to authenticated
using (
  id = auth.uid()                       -- كلٌّ يقرأ ملفّه (شاشة الانتظار تحتاجه)
  or (select public.is_approved_member())
);

-- ── women_members: الفرع الأول كان يسمح لأي مصادَق بقراءة غير المخفيّ ──
drop policy if exists women_members_select on public.women_members;
create policy women_members_select on public.women_members
for select to authenticated
using (
  (
    is_hidden_from_tree = false
    or id         = (select public.my_women_node())
    or husband_id = (select public.my_women_node())
    or parent_id  = (select public.my_women_node())
    or mother_id  = (select public.my_women_node())
  )
  and (
    (select public.is_approved_member())
    or id = (select public.my_women_node())   -- عقدة القارئ نفسه
  )
);
