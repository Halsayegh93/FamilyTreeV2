-- «ترتيب الزوجة» (طلب المالك ٢٠٢٦-١١-٠٧): الإدارة ترتّب زوجات الرجل.
-- عمود مستقلّ عن sort_order — sort_order للمرأة هو ترتيبها بين أبناء أبيها (البنت من العائلة)،
-- فاستعماله لترتيب الزوجات يخرّب ترتيب الأبناء.
-- APPLIED 2026-11-07 بموافقة المالك. التطبيق يقرأ العمود اختيارياً (قبل الترحيل = الترتيب القديم).
-- الكتابة: سياسة women_members_update الحالية (owner/admin/monitor) تكفي — لا دوال جديدة.

alter table public.women_members
  add column if not exists wife_order integer;

comment on column public.women_members.wife_order is
  'Order of this woman among her husband''s wives (admin-set). NULL = unordered (falls back to sort_order).';

-- تعبئة أولية: الترتيب الحالي الظاهر (sort_order ثم created_at) لكل زوج
update public.women_members w
set wife_order = s.rn
from (
  select id,
         row_number() over (partition by husband_id order by sort_order, created_at) - 1 as rn
  from public.women_members
  where husband_id is not null
) s
where w.id = s.id
  and w.wife_order is null;

create index if not exists women_members_husband_wife_order_idx
  on public.women_members (husband_id, wife_order)
  where husband_id is not null;
