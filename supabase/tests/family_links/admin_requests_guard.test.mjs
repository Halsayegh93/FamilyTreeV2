// تجربة حارس إدراج طلبات المراجعة على قاعدة محلية معزولة (لا تلمس السيرفر).
// كل طلب يُرسل بدور authenticated وسياسات الجدول الحية، قبل الحارس وبعده:
// طلبات التطبيقات (آيفون بحروف كبيرة وشرطات مهرّبة، أندرويد، النسخ القديمة، الإدارة) تمر،
// والطلبات المفبركة تُرفض أو تُصحَّح.
// التشغيل: cd supabase/tests/family_links && node admin_requests_guard.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, (e.query ?? '').slice(0, 200)); process.exit(2); });
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody, rest] = base.split('-- ─── المشغّلات');
const baseTriggers = rest.slice(rest.indexOf('\n') + 1);
const grab = (src, name) => { const i = src.indexOf(`create or replace function public.${name}(`); return src.slice(i, src.indexOf('$function$;', i) + '$function$;'.length); };
const preFns = ['adopt_tree_profile', 'merge_member_into_tree', 'women_auto_merge_wife']
  .map(n => grab(readFileSync(`${REPO}/rollback/20261001150000_protect_family_links_rollback.sql`, 'utf8'), n)).join('\n\n');
const guard = readFileSync(`${REPO}/migrations/20261004200000_admin_requests_insert_guard.sql`, 'utf8');
const rollback = readFileSync(`${REPO}/rollback/20261004200000_admin_requests_insert_guard_rollback.sql`, 'utf8');

// أعمدة الجدول وسياساته ودواله كما في السيرفر الحي (٢٠٢٦-١٠-٠٤).
const liveTable = `
alter table public.admin_requests
  add column details text, add column new_value text, add column created_at timestamptz default now(),
  add column admin_reply text, add column replied_at timestamptz,
  add column replied_by uuid references public.profiles(id);
alter table public.admin_requests alter column request_type set default 'deceased_report',
  alter column status set default 'pending';
create table public.news (id uuid primary key default gen_random_uuid(), content text);
create or replace function public.is_approved_member() returns boolean language sql stable security definer
  set search_path to 'public' as $$
  select coalesce(public.current_user_role() = any(array['member','supervisor','monitor','admin','owner']), false); $$;
create or replace function public.can_handle_admin_request(p_type text) returns boolean language sql stable
  security definer set search_path to 'public' as $$
  select case public.current_user_role()
    when 'owner' then true when 'admin' then true
    when 'monitor' then coalesce(p_type, '') not in ('news_report', 'content_report')
    when 'supervisor' then coalesce(p_type, '') in ('news_report', 'content_report', 'contact_message')
    else false end; $$;
alter table public.admin_requests enable row level security;
create policy admin_requests_insert_self_or_moderator on public.admin_requests for insert
  with check ((auth.uid() is not null) and ((requester_id = auth.uid())
    or (public.current_user_role() = any (array['supervisor','admin','owner','monitor']))));
create policy admin_requests_select_moderator_or_owner on public.admin_requests for select
  using ((requester_id = auth.uid()) or (member_id = auth.uid())
    or (public.current_user_role() = any (array['supervisor','monitor','admin','owner'])));
create policy admin_requests_update_by_scope on public.admin_requests for update to authenticated
  using (public.can_handle_admin_request(request_type) and ((public.current_user_role() = 'owner')
    or ((requester_id is distinct from auth.uid()) and (member_id is distinct from auth.uid()))))
  with check (public.can_handle_admin_request(request_type));
create policy admin_requests_delete_by_scope on public.admin_requests for delete to authenticated
  using (public.can_handle_admin_request(request_type));
create policy require_authenticated_admin_requests on public.admin_requests as restrictive for all
  using (auth.uid() is not null) with check (auth.uid() is not null);
grant usage on schema auth to authenticated, anon;
grant select, insert, update, delete on public.admin_requests to authenticated, anon;`;

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const U = s => s.toUpperCase();
const P = { O: id(1), A: id(2), S: id(3), M: id(4), M2: id(5), PEND: id(6), FROZ: id(7), T: id(8),
  OLDCH: id(9), CH: id(10), CH2: id(11), N1: 'aaaaaaaa-0000-4000-8000-000000000001', CMT: 'bbbbbbbb-0000-4000-8000-000000000002' };
const NAME = { T: 'طاهر صلاح المحمدعلي', A: 'بدر المدير', M: 'حسن صلاح' };
const PHOTO = (uid, u = 'c0ffee00-1234-4abc-8def-0123456789ab') =>
  `https://poxyxsgvzwmnmewytsiw.supabase.co/storage/v1/object/public/avatars/photo_suggestion_${uid}_${u}.jpg`;
const iosJSON = o => JSON.stringify(o).replaceAll('/', '\\/'); // JSONEncoder في الآيفون يهرّب «/»

let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

async function setup(withGuard) {
  const db = new PGlite();
  await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers); await db.exec(liveTable);
  if (withGuard) await db.exec(guard);
  await db.exec(`
    insert into profiles(id, first_name, full_name, gender, role, status) values
      ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active'),
      ('${P.A}', 'بدر', '${NAME.A}', 'male', 'admin', 'active'),
      ('${P.S}', 'سعد', 'سعد المشرف', 'male', 'supervisor', 'active'),
      ('${P.M}', 'حسن', '${NAME.M}', 'male', 'member', 'active'),
      ('${P.M2}', 'علي', 'علي صلاح', 'male', 'member', 'active'),
      ('${P.PEND}', 'جديد', 'مسجّل جديد', 'male', 'pending', 'pending'),
      ('${P.FROZ}', 'مجمد', 'عضو مجمّد', 'male', 'member', 'frozen'),
      ('${P.T}', 'طاهر', '${NAME.T}', 'male', 'member', 'active');
    insert into women_members(id, first_name, full_name, gender) values ('${P.M}', 'حسن', '${NAME.M}', 'male');
    insert into profiles(id, first_name, full_name, gender, role, status, father_id, created_at) values
      ('${P.OLDCH}', 'قديم', 'ابن قديم', 'male', 'member', 'active', '${P.M}', now() - interval '2 days'),
      ('${P.CH}', 'جديد', 'ابن جديد', 'male', 'member', 'pending', '${P.M}', now()),
      ('${P.CH2}', 'ثاني', 'ابن ثاني', 'male', 'member', 'pending', '${P.M}', now());
    insert into auth.users(id) values ('${P.O}'), ('${P.A}'), ('${P.S}'), ('${P.M}'), ('${P.M2}'), ('${P.PEND}'), ('${P.FROZ}');
    insert into news(id, content) values ('${P.N1}', 'خبر');`);
  return db;
}

// إدراج كما يفعله PostgREST: دور authenticated + JWT المتصل (أو بلا JWT = صيانة SQL).
async function ins(db, who, r) {
  const claims = who === 'maint' ? '' : JSON.stringify(who === 'service' ? { role: 'service_role' } : { sub: who, role: 'authenticated' });
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [claims]);
  const asUser = who !== 'maint' && who !== 'service';
  if (asUser) await db.exec('set role authenticated');
  try {
    const row = (await db.query(
      `insert into public.admin_requests (member_id, requester_id, request_type, status, new_value, details, admin_reply)
       values ($1::uuid, $2::uuid, $3, $4, $5, $6, $7)
       returning id, member_id, requester_id, status, new_value, details, admin_reply`,
      [r.member, r.requester ?? (asUser ? who : P.O), r.type, r.status ?? 'pending', r.nv ?? null, r.details ?? null, r.reply ?? null])).rows[0];
    return { ok: true, row };
  } catch (e) {
    return { ok: false, err: e.message };
  } finally {
    if (asUser) await db.exec('reset role');
  }
}

const te = (o) => ({ v: 3, ...o });
// [الوصف، المتصل، الطلب، الحكم بعد الحارس: 'ok' | 'reject' | دالة تفحص الصف]
const legit = [
  ['آيفون: طلب انضمام من مسجّل معلّق (معرّفات المطابقة بحروف كبيرة)', P.PEND,
    { member: U(P.PEND), requester: U(P.PEND), type: 'link_request', details: `طلب ربط — وُجدت 1 مطابقة محتملة|matched_ids:${U(P.T)}` }],
  ['أندرويد: طلب انضمام بلا مطابقات', P.PEND, { member: P.PEND, type: 'link_request', details: 'طلب انضمام جديد — لا توجد مطابقات' }],
  ['رسالة تواصل من معلّق', P.PEND, { member: P.PEND, type: 'contact_message', nv: 'استفسار', details: 'التصنيف: استفسار\nالرسالة: متى الموافقة؟' }],
  ['رسالة تواصل من مجمّد', P.FROZ, { member: P.FROZ, type: 'contact_message', nv: 'شكوى', details: 'التصنيف: شكوى\nالرسالة: …' }],
  ['رسالة تواصل من عضو', P.M, { member: U(P.M), requester: U(P.M), type: 'contact_message', nv: 'اقتراح', details: 'التصنيف: اقتراح\nالرسالة: …' }],
  ['تغيير الاسم (نفسه)', P.M, { member: U(P.M), requester: U(P.M), type: 'name_change', nv: 'حسن صلاح الجديد', details: 'طلب تغيير الاسم' }],
  ['تغيير اسم العائلة (نفسه)', P.M, { member: P.M, type: 'family_change', nv: 'المحمدعلي', details: 'طلب تغيير اسم العائلة' }],
  ['تغيير الرقم (نفسه، رقم مستخدم يروح للإدارة)', P.M, { member: P.M, type: 'phone_change', nv: '99998888', details: 'طلب تغيير رقم' }],
  ['بلاغ عن خبر', P.M, { member: U(P.M), requester: U(P.M), type: 'news_report', nv: U(P.N1), details: 'بلاغ على محتوى خبر' }],
  ['بلاغ عن تعليق', P.M, { member: P.M, type: 'content_report', nv: P.CMT, details: '[comment] تعليق — السبب: إساءة' }],
  ['بلاغ عن محتوى بلا معرّف', P.M, { member: P.M, type: 'content_report', details: '[member] — السبب: …' }],
  ['آيفون: إضافة ابن أضافه للتو (معرّف بحروف كبيرة)', P.M, { member: U(P.M), requester: U(P.M), type: 'child_add', nv: U(P.CH), details: 'تمت إضافة ابن جديد: جديد (حي).' }],
  ['آيفون: تعديل اسم عضو آخر (الاسم الحقيقي يُكتب من السيرفر)', P.M,
    { member: U(P.T), requester: U(P.M), type: 'tree_edit', nv: 'edit_name', details: iosJSON(te({ action: 'edit_name', targetMemberId: U(P.T), targetMemberName: NAME.T, newName: 'طاهر صلاح' })) },
    r => JSON.parse(r.details).targetMemberName === NAME.T && r.new_value === 'edit_name'],
  ['آيفون: إضافة ابن لعضو آخر (الأب = المستهدف)', P.M,
    { member: U(P.T), requester: U(P.M), type: 'tree_edit', nv: 'add', details: iosJSON(te({ action: 'add', targetMemberId: U(P.T), targetMemberName: NAME.T, parentMemberId: U(P.T), parentMemberName: NAME.T, newMemberName: 'محمد' })) },
    r => { const d = JSON.parse(r.details); return d.parentMemberName === NAME.T && d.newMemberName === 'محمد'; }],
  ['آيفون: اقتراح صورة (الرابط بشرطات مهرّبة)', P.M,
    { member: U(P.T), requester: U(P.M), type: 'tree_edit', nv: 'add_photo', details: iosJSON(te({ action: 'add_photo', targetMemberId: U(P.T), targetMemberName: NAME.T, newPhotoUrl: PHOTO(P.M) })) },
    r => JSON.parse(r.details).newPhotoUrl === PHOTO(P.M)],
  ['آيفون: تسجيل وفاة عضو آخر', P.M, { member: U(P.T), requester: U(P.M), type: 'tree_edit', nv: 'deceased', details: iosJSON(te({ action: 'deceased', targetMemberId: U(P.T), targetMemberName: NAME.T, deathDate: '2026-10-01' })) }],
  ['آيفون: تعديل رقم عضو آخر', P.M, { member: U(P.T), requester: U(P.M), type: 'tree_edit', nv: 'edit_phone', details: iosJSON(te({ action: 'edit_phone', targetMemberId: U(P.T), targetMemberName: NAME.T, newPhone: '+96599998888' })) }],
  ['آيفون: حذف من الشجرة مع السبب', P.M, { member: U(P.T), requester: U(P.M), type: 'tree_edit', nv: 'delete', details: iosJSON(te({ action: 'delete', targetMemberId: U(P.T), targetMemberName: NAME.T, reason: 'مكرر' })) }],
  ['آيفون: النبذة بعد تجاوز الحد (طلب آخر عن نفسه)', P.M,
    { member: U(P.M), requester: U(P.M), type: 'tree_edit', nv: 'other', details: iosJSON(te({ action: 'other', targetMemberId: U(P.M), targetMemberName: NAME.M, newName: '[{"title":"عمل","details":"x/y"}]', reason: 'profile_bio', notes: 'طلب تعديل النبذة' })) }],
  ['آيفون: الميلاد بعد تجاوز الحد (نفسه)', P.M, { member: U(P.M), requester: U(P.M), type: 'tree_edit', nv: 'edit_birth', details: iosJSON(te({ action: 'edit_birth', targetMemberId: U(P.M), targetMemberName: NAME.M, newBirthDate: '1990-01-01' })) }],
  ['أندرويد: تعديل اسم عضو آخر', P.M, { member: P.T, type: 'tree_edit', nv: 'edit_name', details: JSON.stringify(te({ action: 'edit_name', targetMemberId: P.T, targetMemberName: NAME.T, newName: 'طاهر' })) }],
  ['أندرويد: إخفاء الرقم بعد تجاوز الحد', P.M, { member: P.M, type: 'tree_edit', nv: 'other', details: JSON.stringify(te({ action: 'other', targetMemberId: P.M, targetMemberName: NAME.M, newName: 'true', reason: 'profile_phone_hidden' })) }],
  ['نسخة قديمة (v2): إضافة بالاسم العربي بلا targetMemberId', P.M, { member: P.T, type: 'tree_edit', nv: 'إضافة', details: JSON.stringify({ v: 2, action: 'إضافة', parentMemberId: U(P.T), parentMemberName: NAME.T, newMemberName: 'سالم' }) }],
  ['المالك: سجل «تعديل مباشر» معتمد على عضو آخر', P.O,
    { member: P.T, type: 'tree_edit', status: 'approved', nv: 'edit_name', details: iosJSON(te({ action: 'edit_name', targetMemberId: U(P.T), targetMemberName: 'الاسم القديم', newName: 'طاهر', isAdminDirectEdit: true })) },
    r => r.status === 'approved' && JSON.parse(r.details).isAdminDirectEdit === true && JSON.parse(r.details).targetMemberName === 'الاسم القديم'],
  ['المالك: إضافة ابن لأب آخر (نسخة قديمة)', P.O, { member: P.M2, type: 'child_add', status: 'approved', nv: P.OLDCH, details: 'تمت إضافة ابن' }],
  ['المدير: طلب بنوع قديم (خارج الحارس)', P.A, { member: P.T, type: 'photo_suggestion', nv: 'x' }],
  ['المشرف: بلاغ عن محتوى', P.S, { member: P.S, type: 'content_report', nv: P.CMT, details: '[comment]' }],
  ['صيانة SQL بلا JWT', 'maint', { member: P.T, requester: P.M, type: 'deceased_report', status: 'approved' }],
  ['السيرفر (service_role)', 'service', { member: P.T, requester: P.M, type: 'tree_edit', details: 'نص' }],
];

const crafted = [
  ['تعديل رقم: المستهدف الحقيقي مدير والاسم المعروض عضو عادي', P.M,
    { member: P.T, type: 'tree_edit', nv: 'edit_phone', details: JSON.stringify(te({ action: 'edit_phone', targetMemberId: P.A, targetMemberName: NAME.T, newPhone: '99998888' })) }],
  ['تعديل اسم باسم معروض مزيّف (يُصحَّح للاسم الحقيقي)', P.M,
    { member: P.A, type: 'tree_edit', nv: 'edit_name', details: JSON.stringify(te({ action: 'edit_name', targetMemberId: P.A, targetMemberName: 'ابن صغير', newName: 'x' })) },
    r => JSON.parse(r.details).targetMemberName === NAME.A],
  ['إضافة ابن: الأب الحقيقي غير المعروض', P.M,
    { member: P.T, type: 'tree_edit', nv: 'add', details: JSON.stringify(te({ action: 'add', targetMemberId: P.T, targetMemberName: NAME.T, parentMemberId: P.A, parentMemberName: NAME.T, newMemberName: 'x' })) }],
  ['«إضافة ابن» تشير لملف مدير (الرفض يحذفه)', P.M, { member: P.M, type: 'child_add', nv: P.A, details: 'تمت إضافة ابن' }],
  ['«إضافة ابن» تشير لابن قديم في الشجرة', P.M, { member: P.M, type: 'child_add', nv: P.OLDCH, details: 'تمت إضافة ابن' }],
  ['«إضافة ابن» مكررة لنفس الملف', P.M, { member: P.M, type: 'child_add', nv: P.CH, details: 'مكرر' }],
  ['«إضافة ابن» باسم أب آخر', P.M, { member: P.M2, type: 'child_add', nv: P.CH2, details: 'تمت إضافة ابن' }],
  ['بلاغ عن محتوى يشير لخبر (القبول يحذف الخبر)', P.M, { member: P.M, type: 'content_report', nv: P.N1, details: '[comment] تعليق' }],
  ['تغيير رقم عضو آخر', P.M, { member: P.T, type: 'phone_change', nv: '99998888', details: 'تغيير رقم' }],
  ['تغيير اسم عضو آخر', P.M, { member: P.M2, type: 'name_change', nv: 'اسم', details: 'تغيير الاسم' }],
  ['طلب انضمام باسم ملف آخر', P.PEND, { member: P.T, type: 'link_request', details: 'طلب' }],
  ['اقتراح صورة بالنوع القديم (الرفض يحذف مساراً)', P.M, { member: P.T, type: 'photo_suggestion', nv: 'avatars/someone.jpg' }],
  ['بلاغ وفاة بالنوع القديم', P.M, { member: P.T, type: 'deceased_report', details: 'وفاة' }],
  ['نوع فارغ (الافتراضي deceased_report)', P.M, { member: P.T, type: null }],
  ['«طلب آخر» يخفي رقم عضو آخر', P.M,
    { member: P.T, type: 'tree_edit', nv: 'other', details: JSON.stringify(te({ action: 'other', targetMemberId: P.T, newName: 'true', reason: 'profile_phone_hidden' })) }],
  ['«طلب آخر» بلا سبب profile_*', P.M,
    { member: P.M, type: 'tree_edit', nv: 'other', details: JSON.stringify(te({ action: 'other', targetMemberId: P.M, notes: 'أي شي' })) }],
  ['صورة من رابط خارجي', P.M,
    { member: P.T, type: 'tree_edit', nv: 'add_photo', details: JSON.stringify(te({ action: 'add_photo', targetMemberId: P.T, newPhotoUrl: 'https://evil.example/x.jpg?/storage/v1/object/public/avatars/' })) }],
  ['صورة من مسار عضو آخر', P.M,
    { member: P.T, type: 'tree_edit', nv: 'add_photo', details: JSON.stringify(te({ action: 'add_photo', targetMemberId: P.T, newPhotoUrl: PHOTO(P.M2) })) }],
  ['تعديل شجرة من مجمّد', P.FROZ, { member: P.T, type: 'tree_edit', nv: 'deceased', details: JSON.stringify(te({ action: 'deceased', targetMemberId: P.T })) }],
  ['تعديل شجرة من مسجّل معلّق', P.PEND, { member: P.T, type: 'tree_edit', nv: 'deceased', details: JSON.stringify(te({ action: 'deceased', targetMemberId: P.T })) }],
  ['تعديل شجرة بنص غير JSON', P.M, { member: P.T, type: 'tree_edit', nv: 'edit_name', details: 'غيّروا اسم طاهر' }],
  ['تعديل شجرة بإجراء غير معروف', P.M, { member: P.T, type: 'tree_edit', nv: 'promote', details: JSON.stringify(te({ action: 'promote', targetMemberId: P.T })) }],
  ['تعديل شجرة بلا مستهدف', P.M, { member: P.T, type: 'tree_edit', nv: 'deceased', details: JSON.stringify(te({ action: 'deceased' })) }],
  ['طلب «معتمد» من عضو (يُصحَّح إلى معلّق)', P.M, { member: P.M, type: 'name_change', status: 'approved', nv: 'اسم', details: 'x' }, r => r.status === 'pending'],
  ['رد إدارة مكتوب مسبقاً (يُمسح)', P.M, { member: P.M, type: 'contact_message', nv: 'أخرى', details: 'x', reply: 'تمت الموافقة' }, r => r.admin_reply === null],
  ['«تعديل مباشر من الإدارة» من عضو (يُحذف الوسم ويبقى معلّقاً)', P.M,
    { member: P.T, type: 'tree_edit', status: 'approved', nv: 'edit_name', details: JSON.stringify(te({ action: 'edit_name', targetMemberId: P.T, newName: 'x', isAdminDirectEdit: true })) },
    r => r.status === 'pending' && JSON.parse(r.details).isAdminDirectEdit === undefined],
  ['new_value يخالف الإجراء الفعلي (يُصحَّح)', P.M,
    { member: P.T, type: 'tree_edit', nv: 'edit_birth', details: JSON.stringify(te({ action: 'edit_phone', targetMemberId: P.T, newPhone: '99998888' })) },
    r => r.new_value === 'edit_phone'],
];

for (const stage of ['before', 'after', 'rolledback']) {
  const title = { before: 'قبل الحارس (السيرفر اليوم)', after: 'بعد الحارس', rolledback: 'بعد التراجع' }[stage];
  console.log(`\n══════ ${title} ══════`);
  const db = await setup(stage !== 'before');
  if (stage === 'rolledback') await db.exec(rollback);
  const guarded = stage === 'after';

  console.log('— طلبات التطبيقات الصحيحة (لازم تمر دائماً):');
  for (const [label, who, r, extra] of legit) {
    const res = await ins(db, who, r);
    const ok = res.ok && (!guarded || !extra || extra(res.row));
    check(label, ok, res.ok ? '' : res.err);
  }

  console.log(`— الطلبات المفبركة (${guarded ? 'تُرفض أو تُصحَّح' : 'تمر — الثغرة'}):`);
  for (const [label, who, r, fix] of crafted) {
    const res = await ins(db, who, r);
    if (!guarded) { check(label, res.ok, res.ok ? 'مقبول' : res.err); continue; }
    if (fix) check(label, res.ok && fix(res.row), res.ok ? 'صُحّح' : res.err);
    else check(label, !res.ok, res.ok ? 'قُبل!' : res.err);
  }

  const spoof = await ins(db, P.M, { member: P.M2, requester: P.M2, type: 'name_change', nv: 'x' });
  check('مقدّم طلب باسم غيره: ترفضه سياسة الجدول (قبل وبعد)', !spoof.ok, spoof.err);
}
console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
