-- ═══════════════════════════════════════════════════════════════════════════
-- فرض حظر الهاتف على مستوى السيرفر بالكامل — 2026-06-19
--
-- سابقاً الحظر يُفحص في التطبيق فقط (client-side, fail-open). الآن نفرضه في
-- قاعدة البيانات عبر مُحفِّزين، فلا يعتمد على التطبيق إطلاقاً:
--   1) عند حظر رقم → تجميد أي عضو موجود يملك نفس الرقم (status='frozen').
--      بفضل تحصين status السابق، RLS يحجب المجمّد عن كل شيء → جلسته عديمة الفائدة.
--   2) منع إنشاء ملف (تسجيل) برقم محظور.
--
-- المطابقة: آخر 8 أرقام (يطابق منطق التطبيق KuwaitPhone.localEightDigits)
-- لأن الأرقام تُخزَّن أحياناً محلية (99xxxxxx) وأحياناً E.164 (+96599xxxxxx).
-- المالك (owner) مُستثنى من التجميد التلقائي حمايةً من قفل الحساب الأساسي.
-- ═══════════════════════════════════════════════════════════════════════════

-- مطابقة آخر 8 أرقام بين رقمين (≥8 خانة)
create or replace function public.phones_match_suffix(a text, b text)
returns boolean
language sql
immutable
as $$
  select
    length(regexp_replace(coalesce(a, ''), '[^0-9]', '', 'g')) >= 8
    and length(regexp_replace(coalesce(b, ''), '[^0-9]', '', 'g')) >= 8
    and right(regexp_replace(coalesce(a, ''), '[^0-9]', '', 'g'), 8)
      = right(regexp_replace(coalesce(b, ''), '[^0-9]', '', 'g'), 8);
$$;

-- 1) تجميد العضو عند حظر رقمه
create or replace function public.freeze_member_on_ban()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.is_active is false then
    return NEW;
  end if;
  update public.profiles p
     set status = 'frozen'
   where p.role <> 'owner'
     and public.phones_match_suffix(p.phone_number, NEW.phone_number);
  return NEW;
end;
$$;

drop trigger if exists trg_freeze_member_on_ban on public.banned_phones;
create trigger trg_freeze_member_on_ban
  after insert on public.banned_phones
  for each row execute function public.freeze_member_on_ban();

-- 2) رفض تسجيل/إنشاء ملف برقم محظور
create or replace function public.reject_banned_phone_registration()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.phone_number is not null
     and length(regexp_replace(NEW.phone_number, '[^0-9]', '', 'g')) >= 8
     and exists (
       select 1 from public.banned_phones b
        where b.is_active is not false
          and public.phones_match_suffix(b.phone_number, NEW.phone_number)
     )
  then
    raise exception 'PHONE_BANNED: هذا الرقم محظور ولا يمكن التسجيل به'
      using errcode = 'check_violation';
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_reject_banned_phone_registration on public.profiles;
create trigger trg_reject_banned_phone_registration
  before insert on public.profiles
  for each row execute function public.reject_banned_phone_registration();
