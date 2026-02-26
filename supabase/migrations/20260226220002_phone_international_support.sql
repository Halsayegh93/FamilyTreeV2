-- Allow storing international phone numbers in E.164 while keeping Kuwaiti 8-digit local format.

create or replace function public.normalize_kuwait_phone(raw text)
returns text
language plpgsql
immutable
as $$
declare
  clean text;
  digits text;
  has_intl_prefix boolean;
begin
  if raw is null then
    return null;
  end if;

  clean := btrim(raw);
  if clean = '' then
    return null;
  end if;

  digits := regexp_replace(clean, '\\D', '', 'g');
  has_intl_prefix := clean like '+%' or clean like '00%';

  -- Kuwaiti local forms (default behavior, stored as 8 digits)
  if not has_intl_prefix then
    if digits like '00965%' and length(digits) > 8 then
      digits := substr(digits, 6);
    elsif digits like '965%' and length(digits) > 8 then
      digits := substr(digits, 4);
    end if;

    if length(digits) > 8 then
      digits := substr(digits, 1, 8);
    end if;

    if length(digits) = 8 then
      return digits;
    end if;

    return null;
  end if;

  -- International input (with + or 00)
  if clean like '00%' then
    digits := regexp_replace(substr(clean, 3), '\\D', '', 'g');
  end if;

  -- Keep Kuwait consistent as local 8 digits.
  if digits like '965%' and length(digits) = 11 then
    return substr(digits, 4);
  end if;

  -- E.164: country code + national number (7..15 digits total)
  if length(digits) between 7 and 15 then
    return '+' || digits;
  end if;

  return null;
end;
$$;

alter table public.profiles
  drop constraint if exists profiles_phone_number_kuwait_ck;

alter table public.profiles
  add constraint profiles_phone_number_kuwait_ck
  check (
    phone_number is null
    or phone_number ~ '^([0-9]{8}|\\+[1-9][0-9]{6,14})$'
  );
