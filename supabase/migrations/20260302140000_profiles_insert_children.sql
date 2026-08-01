-- السماح للمستخدمين بإضافة أبناء (ملفات شخصية بمعرّف مختلف عن auth.uid)
-- Allow authenticated users to insert child profiles (where id != auth.uid())
-- This is needed because addChild creates profiles with new UUIDs for children

-- حذف السياسة القديمة
drop policy if exists "profiles_insert_self" on public.profiles;

-- حذف السياسة الجديدة إن وُجدت ثم إعادة إنشائها
drop policy if exists "profiles_insert_authenticated" on public.profiles;

-- سياسة جديدة: السماح بالإدراج لأي مستخدم مسجّل الدخول
-- يمكن للمستخدم إنشاء ملفه الشخصي (id = auth.uid) أو إنشاء ملفات أبناء
create policy "profiles_insert_authenticated" on public.profiles
for insert
with check (auth.uid() is not null);
