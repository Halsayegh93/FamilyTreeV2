-- مطبَّق على الحي ٢٠٢٦-١١-٢٧ بعد تجربة begin…rollback (حسين المتوفى في الحي: مرفوض · بدر وجمانة: معاينة سليمة)
-- لم يُطبَّق على الحي بعد (بانتظار تجربة المدير) — يحلّ محلّ دالة 20261127240000 (المطبّقة ٢٠٢٦-١١-٢٧).
-- حراس «دمج» المكرّرين بعد مراجعة المنتقد (٢٠٢٦-١١-٢٧) — merge_duplicate_members(p_keep, p_remove, p_dry_run):
--
-- ١) رفض جديد (P0001 + hint):
--    • deceased_mismatch — أحدهما متوفى والآخر حيّ: «لا يمكن دمج متوفى في حيّ — قد يكونان أخوين بنفس الاسم.»
--    • birth_mismatch — لكليهما ميلاد وسنتاهما متباعدتان أكثر من سنتين.
--    التطبيق يخفي «دمجه في الآخر» حيث يرفض السيرفر (AdminMergeRules.compatible، القاعدة نفسها).
-- ٢) شجرة النساء: moved_children = الأبناء (عقد ذكور تحت الأم)، moved_daughters = البنات، moved_husbands = من يشير لها
--    زوجاً — منفصلة ليعرض التطبيق «ينتقل: ابنان، بنت واحدة، …». moved_women = moved_daughters + moved_husbands.
--    (شجرة الرجال كما هي، و moved_husbands = 0.)
-- ٣) النقل صفّاً صفّاً: كانت مخالفة فريد واحدة تتخطّى نقل الجدول كله بصمت. الآن: محاولة الجدول كله، وعند التعارض كل صفّ
--    وحده — ينتقل كل صفّ يمكن نقله، والمتعارض وحده (للمُبقى صفّ مثله: تصويت، قراءة…) يبقى فيذهب مع المحذوف (مفاتيحه
--    on delete cascade)، وفي الأعمدة بلا مفتاح أجنبي يُحذف. يُذكر في not_moved كـ {"table": …, "count": n} بجانب
--    الحقول النصية ("phone_number") — النسخ القديمة من التطبيق تتجاهل الكائنات.
-- الباقي كما في 20261127240000 (الصلاحية، الأب نفسه، الحسابات، الإدارة، الملء، family.merging، المعاينة).
-- الأخطاء: same_member · not_found · not_same_tree · different_father · staff_member · remove_has_login · both_have_login ·
--          deceased_mismatch · birth_mismatch — والصلاحية 42501 hint not_allowed.
-- التراجع: supabase/rollback/20261127270000_merge_duplicate_guards_rollback.sql (يعيد دالة 20261127240000 حرفياً)
-- تجربة: cd supabase/tests/family_links && node merge_duplicate_members.test.mjs

create or replace function public.merge_duplicate_members(p_keep uuid, p_remove uuid, p_dry_run boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_role     text := public.current_user_role();
  v_tree     text;
  kp         public.profiles%rowtype;
  rp         public.profiles%rowtype;
  kw         public.women_members%rowtype;
  rw         public.women_members%rowtype;
  kmw        public.women_members%rowtype;   -- عقدة المُبقى في شجرة النساء (للرجال)
  rmw        public.women_members%rowtype;   -- عقدة المحذوف في شجرة النساء (للرجال)
  k_login    boolean;
  r_login    boolean;
  v_filled   text[] := '{}';
  v_conf     jsonb := '[]'::jsonb;
  v_lost     text[] := '{}';
  n_children int := 0;
  n_daughters int := 0;
  n_wives    int := 0;
  n_women    int := 0;
  n_husbands int := 0;
  v_rows     jsonb := '[]'::jsonb;    -- صفوف لم تنتقل لتعارض فريد: [{table, count}]
  n_left     int;
  v_tid      tid;
  v_prev     text := coalesce(current_setting('family.merging', true), '');
  c          record;
begin
  if coalesce(v_role, '') not in ('owner', 'admin') then
    raise exception 'الدمج للمالك والمدير فقط' using errcode = '42501', hint = 'not_allowed';
  end if;
  if p_keep is null or p_remove is null or p_keep = p_remove then
    raise exception 'اختر شخصين مختلفين' using errcode = 'P0001', hint = 'same_member';
  end if;

  -- ─── أين يعيش الاثنان ───
  select * into kp from public.profiles where id = p_keep for update;
  select * into rp from public.profiles where id = p_remove for update;
  select * into kw from public.women_members where id = p_keep for update;
  select * into rw from public.women_members where id = p_remove for update;
  if (kp.id is null and kw.id is null) or (rp.id is null and rw.id is null) then
    raise exception 'أحد الاسمين غير موجود' using errcode = 'P0001', hint = 'not_found';
  end if;

  if kp.id is not null and rp.id is not null
     and lower(coalesce(kp.gender, 'male')) <> 'female' and lower(coalesce(rp.gender, 'male')) <> 'female' then
    v_tree := 'men';
  elsif kw.id is not null and rw.id is not null
     and lower(coalesce(kw.gender, 'female')) = 'female' and lower(coalesce(rw.gender, 'female')) = 'female' then
    v_tree := 'women';
  else
    raise exception 'الاسمان ليسا في الشجرة نفسها' using errcode = 'P0001', hint = 'not_same_tree';
  end if;

  if v_tree = 'men' then
    if kp.father_id is null or kp.father_id is distinct from rp.father_id then
      raise exception 'الاسمان ليسا تحت الأب نفسه' using errcode = 'P0001', hint = 'different_father';
    end if;
    if kp.role in ('owner', 'admin', 'monitor', 'supervisor') or rp.role in ('owner', 'admin', 'monitor', 'supervisor') then
      raise exception 'لا يُدمج ملف أحد أعضاء الإدارة' using errcode = 'P0001', hint = 'staff_member';
    end if;
    k_login := public.profile_has_login(p_keep);
    r_login := public.profile_has_login(p_remove);
  else
    if kw.parent_id is null or kw.parent_id is distinct from rw.parent_id then
      raise exception 'الاسمان ليسا تحت الأب نفسه' using errcode = 'P0001', hint = 'different_father';
    end if;
    k_login := kw.linked_user_id is not null or kp.id is not null;
    r_login := rw.linked_user_id is not null or rp.id is not null;
  end if;
  if k_login and r_login then
    raise exception 'لكلٍّ منهما حساب دخول — لا يُدمجان' using errcode = 'P0001', hint = 'both_have_login';
  end if;
  if r_login then
    raise exception 'الاسم الذي سيُحذف له حساب دخول — احذف الآخر بدلاً منه' using errcode = 'P0001', hint = 'remove_has_login';
  end if;

  -- ─── متوفى وحيّ، أو ميلادان متباعدان: غالباً أخوان بالاسم نفسه — لا دمج ───
  if v_tree = 'men' then
    if coalesce(kp.is_deceased, false) <> coalesce(rp.is_deceased, false) then
      raise exception 'لا يمكن دمج متوفى في حيّ — قد يكونان أخوين بنفس الاسم.' using errcode = 'P0001', hint = 'deceased_mismatch';
    end if;
    if kp.birth_date is not null and rp.birth_date is not null
       and abs(extract(year from kp.birth_date) - extract(year from rp.birth_date)) > 2 then
      raise exception 'لا يمكن الدمج — سنتا الميلاد متباعدتان، وقد يكونان أخوين بنفس الاسم.' using errcode = 'P0001', hint = 'birth_mismatch';
    end if;
  else
    if coalesce(kw.is_deceased, false) <> coalesce(rw.is_deceased, false) then
      raise exception 'لا يمكن دمج متوفى في حيّ — قد يكونان أختين بنفس الاسم.' using errcode = 'P0001', hint = 'deceased_mismatch';
    end if;
    if kw.birth_date is not null and rw.birth_date is not null
       and abs(extract(year from kw.birth_date) - extract(year from rw.birth_date)) > 2 then
      raise exception 'لا يمكن الدمج — سنتا الميلاد متباعدتان، وقد يكونان أختين بنفس الاسم.' using errcode = 'P0001', hint = 'birth_mismatch';
    end if;
  end if;

  begin
    perform set_config('family.merging', 'on', true);

    if v_tree = 'men' then
      select * into kmw from public.women_members where id = p_keep;
      select * into rmw from public.women_members where id = p_remove;

      -- ─── ما سينتقل (قبل النقل) ───
      select count(*) into n_children from public.profiles where father_id = p_remove;
      select count(*) into n_daughters from public.women_members w
       where w.parent_id = p_remove and not exists (select 1 from public.profiles p where p.id = w.id);
      select count(*) into n_wives from (
        select w.id from public.women_members w where w.husband_id = p_remove
        union select p.id from public.profiles p where p.husband_id = p_remove) x;
      n_women := n_daughters + n_wives;

      -- ─── الملء والتعارض ───
      if kp.birth_date is null and rp.birth_date is not null then
        kp.birth_date := rp.birth_date; v_filled := array_append(v_filled, 'birth_date');
      elsif kp.birth_date is distinct from rp.birth_date and rp.birth_date is not null then
        v_conf := v_conf || jsonb_build_object('field', 'birth_date', 'kept', kp.birth_date, 'removed', rp.birth_date);
      end if;
      if coalesce(rp.is_deceased, false) and not coalesce(kp.is_deceased, false) then
        v_conf := v_conf || jsonb_build_object('field', 'is_deceased', 'kept', false, 'removed', true);
      elsif coalesce(kp.is_deceased, false) and kp.death_date is null and rp.death_date is not null then
        kp.death_date := rp.death_date; v_filled := array_append(v_filled, 'death_date');
      elsif kp.death_date is distinct from rp.death_date and kp.death_date is not null and rp.death_date is not null then
        v_conf := v_conf || jsonb_build_object('field', 'death_date', 'kept', kp.death_date, 'removed', rp.death_date);
      end if;
      -- الأم: في ملفه (profiles.mother_id) أو في عقدته (women_members.mother_id — repoint_women_node يحملها)
      if kp.mother_id is null and rp.mother_id is not null then
        kp.mother_id := rp.mother_id; v_filled := array_append(v_filled, 'mother_id');
      elsif kp.mother_id is distinct from rp.mother_id and rp.mother_id is not null then
        v_conf := v_conf || jsonb_build_object('field', 'mother_id', 'kept', kp.mother_id, 'removed', rp.mother_id);
      end if;
      if kmw.id is not null and rmw.mother_id is not null then
        if kmw.mother_id is null then
          if not ('mother_id' = any (v_filled)) then v_filled := array_append(v_filled, 'mother_id'); end if;
        elsif kmw.mother_id <> rmw.mother_id then
          v_conf := v_conf || jsonb_build_object('field', 'mother_id', 'kept', kmw.mother_id, 'removed', rmw.mother_id);
        end if;
      end if;
      if nullif(btrim(coalesce(kp.family_name, '')), '') is null and nullif(btrim(coalesce(rp.family_name, '')), '') is not null then
        kp.family_name := rp.family_name; v_filled := array_append(v_filled, 'family_name');
      end if;
      if nullif(kp.avatar_url, '') is null and nullif(rp.avatar_url, '') is not null then
        kp.avatar_url := rp.avatar_url; kp.photo_url := coalesce(nullif(kp.photo_url, ''), rp.photo_url);
        v_filled := array_append(v_filled, 'avatar_url');
      end if;
      if not coalesce(kp.is_married, false) and coalesce(rp.is_married, false) then
        kp.is_married := true; v_filled := array_append(v_filled, 'is_married');
      end if;
      -- الرقم لا ينتقل (مشغّلات الرقم تربط حسابات) — يُذكر فقط
      if nullif(btrim(coalesce(rp.phone_number, '')), '') is not null
         and rp.phone_number is distinct from kp.phone_number then
        v_lost := array_append(v_lost, 'phone_number');
      end if;

      update public.profiles set
        birth_date = kp.birth_date, death_date = kp.death_date, mother_id = kp.mother_id,
        family_name = kp.family_name, avatar_url = kp.avatar_url, photo_url = kp.photo_url, is_married = kp.is_married
      where id = p_keep
        and (birth_date, death_date, mother_id, family_name, avatar_url, photo_url, is_married)
            is distinct from (kp.birth_date, kp.death_date, kp.mother_id, kp.family_name, kp.avatar_url, kp.photo_url, kp.is_married);

      -- ─── إشعارات المحذوف نفسه لا تنتقل ───
      delete from public.notifications where target_member_id = p_remove;

      -- ─── عقدة شجرة النساء ومن يشير لها (البنات، الزوجات، أم عقدته) ───
      perform public.repoint_women_node(p_remove, p_keep);

      -- ─── كل مفتاح أجنبي على profiles(id) ───
      for c in
        select con.conrelid::regclass as tbl, att.attname as col
          from pg_constraint con
          join pg_attribute att on att.attrelid = con.conrelid and att.attnum = con.conkey[1]
         where con.contype = 'f' and con.confrelid = 'public.profiles'::regclass and array_length(con.conkey, 1) = 1
      loop
        begin
          execute format('update %s set %I = $1 where %I = $2', c.tbl, c.col, c.col) using p_keep, p_remove;
        exception when unique_violation then
          -- للمُبقى صفّ مثله أصلاً (تصويت، قراءة…): يُنقل صفّاً صفّاً، ويبقى المتعارض وحده فيذهب مع المحذوف
          -- (كل هذه المفاتيح on delete cascade) ويُذكر في not_moved
          n_left := 0;
          for v_tid in execute format('select ctid from %s where %I = $1', c.tbl, c.col) using p_remove loop
            begin
              execute format('update %s set %I = $1 where ctid = $2', c.tbl, c.col) using p_keep, v_tid;
            exception when unique_violation then
              n_left := n_left + 1;
            end;
          end loop;
          if n_left > 0 then
            v_rows := v_rows || jsonb_build_object('table', regexp_replace(c.tbl::text, '^public\.', ''), 'count', n_left);
          end if;
        end;
      end loop;

      update public.profiles
         set sons_ids = case when p_keep = any (sons_ids) then array_remove(sons_ids, p_remove)
                             else array_replace(sons_ids, p_remove, p_keep) end
       where p_remove = any (sons_ids);
    else
      -- ─── شجرة النساء ───
      -- أبناؤها وبناتها كلٌّ على حدة (عقد الأبناء في شجرة النساء ذكور)، ومن يشير لها زوجاً
      select count(*) filter (where lower(coalesce(gender, 'female')) <> 'female'),
             count(*) filter (where lower(coalesce(gender, 'female')) = 'female')
        into n_children, n_daughters
        from public.women_members where mother_id = p_remove or parent_id = p_remove;
      select count(*) into n_husbands from public.women_members where husband_id = p_remove;
      n_women := n_daughters + n_husbands;

      if kw.birth_date is null and rw.birth_date is not null then
        kw.birth_date := rw.birth_date; v_filled := array_append(v_filled, 'birth_date');
      elsif kw.birth_date is distinct from rw.birth_date and rw.birth_date is not null then
        v_conf := v_conf || jsonb_build_object('field', 'birth_date', 'kept', kw.birth_date, 'removed', rw.birth_date);
      end if;
      if coalesce(rw.is_deceased, false) and not coalesce(kw.is_deceased, false) then
        v_conf := v_conf || jsonb_build_object('field', 'is_deceased', 'kept', false, 'removed', true);
      elsif coalesce(kw.is_deceased, false) and kw.death_date is null and rw.death_date is not null then
        kw.death_date := rw.death_date; v_filled := array_append(v_filled, 'death_date');
      elsif kw.death_date is distinct from rw.death_date and kw.death_date is not null and rw.death_date is not null then
        v_conf := v_conf || jsonb_build_object('field', 'death_date', 'kept', kw.death_date, 'removed', rw.death_date);
      end if;
      if kw.mother_id is null and rw.mother_id is not null then
        v_filled := array_append(v_filled, 'mother_id');
      elsif kw.mother_id is distinct from rw.mother_id and rw.mother_id is not null then
        v_conf := v_conf || jsonb_build_object('field', 'mother_id', 'kept', kw.mother_id, 'removed', rw.mother_id);
      end if;
      if kw.husband_id is null and rw.husband_id is not null then
        v_filled := array_append(v_filled, 'husband_id');
      elsif kw.husband_id is distinct from rw.husband_id and rw.husband_id is not null then
        v_conf := v_conf || jsonb_build_object('field', 'husband_id', 'kept', kw.husband_id, 'removed', rw.husband_id);
      end if;
      if kw.is_married is null and rw.is_married is not null then v_filled := array_append(v_filled, 'is_married'); end if;

      update public.women_members set birth_date = kw.birth_date, death_date = kw.death_date
       where id = p_keep and (birth_date, death_date) is distinct from (kw.birth_date, kw.death_date);

      -- الأم والزوج و«متزوجة» الفارغة تُحمل هنا، وكل من يشير للمحذوفة ينتقل
      perform public.repoint_women_node(p_remove, p_keep);
    end if;

    -- ─── أعمدة بلا مفتاح أجنبي (الموجودة فقط) ───
    for c in
      select x.t, x.col from (values
        ('death_announcements', 'member_id'), ('death_marks', 'member_id'),
        ('guardian_consents', 'tree_member_id'), ('guardian_consents', 'minor_id'),
        ('join_requests', 'suggested_father_id'), ('admin_request_events', 'subject_id'),
        ('admin_request_steps', 'subject_id'), ('daughter_son_lineage', 'women_node_id')) as x(t, col)
      where exists (select 1 from information_schema.columns ic
                    where ic.table_schema = 'public' and ic.table_name = x.t and ic.column_name = x.col)
    loop
      begin
        execute format('update public.%I set %I = $1 where %I = $2', c.t, c.col, c.col) using p_keep, p_remove;
      exception when unique_violation then
        -- صفّاً صفّاً؛ المتعارض وحده يُحذف (لا مفتاح أجنبي يحذفه مع المحذوف) ويُذكر في not_moved
        n_left := 0;
        for v_tid in execute format('select ctid from public.%I where %I = $1', c.t, c.col) using p_remove loop
          begin
            execute format('update public.%I set %I = $1 where ctid = $2', c.t, c.col) using p_keep, v_tid;
          exception when unique_violation then
            execute format('delete from public.%I where ctid = $1', c.t) using v_tid;
            n_left := n_left + 1;
          end;
        end loop;
        if n_left > 0 then
          v_rows := v_rows || jsonb_build_object('table', c.t, 'count', n_left);
        end if;
      end;
    end loop;
    if exists (select 1 from information_schema.columns ic
               where ic.table_schema = 'public' and ic.table_name = 'women_members' and ic.column_name = 'hidden_children') then
      update public.women_members
         set hidden_children = case when p_keep = any (hidden_children) then array_remove(hidden_children, p_remove)
                                    else array_replace(hidden_children, p_remove, p_keep) end
       where p_remove = any (hidden_children);
    end if;

    -- ─── الحذف (الحارس يرفض إن بقي أحد من العائلة مربوطاً) ───
    if v_tree = 'men' then
      delete from public.profiles where id = p_remove;
    else
      delete from public.women_members where id = p_remove;
    end if;

    perform set_config('family.merging', v_prev, true);
    if p_dry_run then
      raise exception 'dry run' using errcode = 'MD001';
    end if;
  exception when sqlstate 'MD001' then
    -- المعاينة: كل ما سبق تراجع، والنتيجة محسوبة
    null;
  end;

  return jsonb_build_object(
    'kept', p_keep, 'removed', p_remove, 'tree', v_tree,
    'moved_children', n_children, 'moved_daughters', n_daughters, 'moved_wives', n_wives, 'moved_husbands', n_husbands,
    'moved_women', n_women,
    'filled', to_jsonb(v_filled), 'conflicts', v_conf, 'not_moved', to_jsonb(v_lost) || v_rows, 'dry_run', coalesce(p_dry_run, false));
end;
$function$;

revoke all on function public.merge_duplicate_members(uuid, uuid, boolean) from public, anon;
grant execute on function public.merge_duplicate_members(uuid, uuid, boolean) to authenticated;

comment on function public.merge_duplicate_members(uuid, uuid, boolean) is
  'دمج اسمين مكرّرين تحت الأب نفسه (المالك والمدير): ينقل كل ما يشير للمحذوف إلى المُبقى، يملأ الفارغ، ثم يحذفه. p_dry_run = معاينة. hint: not_allowed | same_member | not_found | not_same_tree | different_father | staff_member | remove_has_login | both_have_login | deceased_mismatch | birth_mismatch';
