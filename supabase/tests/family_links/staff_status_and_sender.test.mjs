// تجربة سياسات شجرة النساء/الأزواج (حالة الحساب، المشرف يقرأ فقط) وحارس مرسل الإشعار
// على قاعدة محلية معزولة (لا تلمس السيرفر) — قبل التعديل وبعده وبعد التراجع.
// التشغيل: cd supabase/tests/family_links && node staff_status_and_sender.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? '', (e.query ?? '').slice(0, 300)); process.exit(2); });
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody, rest] = base.split('-- ─── المشغّلات');
const baseTriggers = rest.slice(rest.indexOf('\n') + 1);
const grab = (src, name) => { const i = src.indexOf(`create or replace function public.${name}(`); return src.slice(i, src.indexOf('$function$;', i) + '$function$;'.length); };
const preFns = ['adopt_tree_profile', 'merge_member_into_tree', 'women_auto_merge_wife']
  .map(n => grab(readFileSync(`${REPO}/rollback/20261001150000_protect_family_links_rollback.sql`, 'utf8'), n)).join('\n\n');
const mig = n => readFileSync(`${REPO}/migrations/${n}.sql`, 'utf8');
const chain = ['20261001150000_protect_family_links', '20261001190000_carry_own_women_node_links'].map(mig);
const fanoutLive = grab(mig('20260725151900_notifications_subject_member_id'), 'fanout_broadcast_notification');
const fanoutNow = [mig('20261004150000_notifications_start_at_login'), mig('20261004170000_broadcast_only_registered_devices')];
const fix = mig('20261004220000_staff_status_and_notification_sender');
const rollback = readFileSync(`${REPO}/rollback/20261004220000_staff_status_and_notification_sender_rollback.sql`, 'utf8');

// السيرفر الحي (٢٠٢٦-١٠-٠٤): مشغّلات الإشعارات وسياساتها، وسياسات شجرة النساء والأزواج
const live = `
alter table public.notifications add column if not exists request_id uuid,
  add column if not exists request_type text, add column if not exists details jsonb,
  add column if not exists subject_member_id uuid;
${fanoutLive}
create trigger trg_fanout_broadcast_notification before insert on public.notifications
  for each row execute function public.fanout_broadcast_notification();
create or replace function public.admin_sender_as_administration() returns trigger language plpgsql
  security definer set search_path to 'public' as $f$
begin
  if new.kind in ('news_like', 'news_comment')
     and new.created_by is not null
     and new.target_member_id is not null
     and exists (select 1 from public.profiles p
                 where p.id = new.created_by
                   and p.role in ('owner', 'admin', 'monitor', 'supervisor'))
     and exists (select 1 from public.profiles p
                 where p.id = new.target_member_id
                   and p.role in ('member', 'pending')) then
    new.body := case new.kind
                  when 'news_like' then 'الإدارة أعجبت بخبرك'
                  else 'الإدارة علّقت على خبرك'
                end;
  end if;
  return new;
end; $f$;
create trigger trg_admin_sender_as_administration before insert on public.notifications
  for each row execute function public.admin_sender_as_administration();
create or replace function public.is_descendant_of_caller(target uuid) returns boolean language sql stable
  security definer set search_path to 'public' as $f$
  with recursive ancestors as (
    select father_id as ancestor_id from public.profiles where id = target
    union all
    select p.father_id from public.profiles p join ancestors a on p.id = a.ancestor_id where p.father_id is not null)
  select coalesce((select status = 'active' from public.profiles where id = auth.uid()), false)
     and coalesce((select exists (select 1 from ancestors where ancestor_id = auth.uid())), false); $f$;
create or replace function public.is_approved_member() returns boolean language sql stable security definer
  set search_path to 'public' as $f$
  select coalesce(public.current_user_role() = any(array['member','supervisor','monitor','admin','owner']), false); $f$;
alter table public.notifications enable row level security;
create policy notifications_insert_moderator_or_self_scope on public.notifications for insert to authenticated
  with check ((public.current_user_role() = any (array['owner','admin']))
    or ((public.current_user_role() = any (array['monitor','supervisor'])) and (coalesce(kind, '') <> all (array['admin_broadcast','app_update'])))
    or ((target_member_id is not null) and ((target_member_id = auth.uid()) or public.is_descendant_of_caller(target_member_id))));
create policy notifications_select_target_or_all_or_moderator on public.notifications for select
  using ((target_member_id = auth.uid()) or ((target_member_id is null)
    and (public.current_user_role() = any (array['owner','admin','monitor','supervisor']))));
create policy require_authenticated_notifications on public.notifications as restrictive for all
  using (auth.uid() is not null) with check (auth.uid() is not null);
alter table public.women_members enable row level security;
create policy women_members_select on public.women_members for select to authenticated
  using (((is_hidden_from_tree = false) or (id = (select public.my_women_node())) or (husband_id = (select public.my_women_node()))
          or (parent_id = (select public.my_women_node())) or (mother_id = (select public.my_women_node())))
         and ((select public.is_approved_member()) or (id = (select public.my_women_node()))));
create policy women_members_write on public.women_members for all to authenticated
  using (exists (select 1 from public.profiles p
                 where (p.id = auth.uid() or p.id = (nullif((auth.jwt() -> 'app_metadata') ->> 'profile_id', ''))::uuid)
                   and p.role = any (array['owner','admin','monitor'])))
  with check (exists (select 1 from public.profiles p
                      where (p.id = auth.uid() or p.id = (nullif((auth.jwt() -> 'app_metadata') ->> 'profile_id', ''))::uuid)
                        and p.role = any (array['owner','admin','monitor'])));
alter table public.external_spouses enable row level security;
create policy external_spouses_select_mods on public.external_spouses for select to authenticated
  using (exists (select 1 from public.profiles p
                 where (p.id = auth.uid() or p.id = (nullif((auth.jwt() -> 'app_metadata') ->> 'profile_id', ''))::uuid)
                   and p.role = any (array['owner','admin','monitor','supervisor'])));
create policy external_spouses_write_mods on public.external_spouses for all to authenticated
  using (exists (select 1 from public.profiles p
                 where (p.id = auth.uid() or p.id = (nullif((auth.jwt() -> 'app_metadata') ->> 'profile_id', ''))::uuid)
                   and p.role = any (array['owner','admin','monitor','supervisor'])))
  with check (exists (select 1 from public.profiles p
                      where (p.id = auth.uid() or p.id = (nullif((auth.jwt() -> 'app_metadata') ->> 'profile_id', ''))::uuid)
                        and p.role = any (array['owner','admin','monitor','supervisor'])));
grant usage on schema auth to authenticated;
grant select, insert, update, delete on public.notifications, public.women_members, public.external_spouses to authenticated;
grant select on public.profiles to authenticated;`;

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const P = { O: id(1), A: id(2), AF: id(3), MON: id(4), S: id(5), M: id(6), K: id(7), PEND: id(8), G: id(9),
  W1: id(30), E1: id(31) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

async function setup(stage) {
  const db = new PGlite();
  await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers);
  for (const m of chain) await db.exec(m);
  await db.exec(live);
  for (const m of fanoutNow) await db.exec(m);
  if (stage !== 'before') await db.exec(fix);
  if (stage === 'rolledback') await db.exec(rollback);
  await db.exec(`
    insert into profiles(id, first_name, full_name, gender, role, status) values
      ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active'),
      ('${P.A}', 'بدر', 'مدير', 'male', 'admin', 'active'),
      ('${P.AF}', 'مجمد', 'مدير مجمّد', 'male', 'admin', 'frozen'),
      ('${P.MON}', 'علي', 'مراقب', 'male', 'monitor', 'active'),
      ('${P.S}', 'سعد', 'مشرف', 'male', 'supervisor', 'active'),
      ('${P.G}', 'صلاح', 'الجد', 'male', 'member', 'active'),
      ('${P.PEND}', 'جديد', 'مسجّل معلّق', 'male', 'pending', 'pending');
    insert into women_members(id, first_name, full_name, gender) values ('${P.G}', 'صلاح', 'الجد', 'male');
    insert into profiles(id, first_name, full_name, gender, role, status, father_id) values
      ('${P.M}', 'حسن', 'عضو أب', 'male', 'member', 'active', '${P.G}');
    insert into women_members(id, first_name, full_name, gender) values ('${P.M}', 'حسن', 'عضو أب', 'male')
      on conflict (id) do nothing;
    insert into profiles(id, first_name, full_name, gender, role, status, father_id) values
      ('${P.K}', 'كريم', 'ابن العضو', 'male', 'member', 'active', '${P.M}');
    insert into auth.users(id) values ('${P.O}'), ('${P.A}'), ('${P.AF}'), ('${P.MON}'), ('${P.S}'), ('${P.M}'), ('${P.K}'), ('${P.PEND}');
    insert into device_tokens(member_id, token) values ('${P.O}', 'tok-o-000000000000'), ('${P.K}', 'tok-k-000000000000');
    insert into women_members(id, first_name, full_name, gender) values ('${P.W1}', 'نورة', 'نورة', 'female');
    insert into external_spouses(id, woman_id, full_name) values ('${P.E1}', '${P.W1}', 'زوج من خارج العائلة');`);
  return db;
}

async function as(db, who, sql, params = []) {
  const claims = who ? JSON.stringify({ sub: who, role: 'authenticated' }) : '';
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [claims]);
  if (who) await db.exec('set role authenticated');
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message }; }
  finally { if (who) await db.exec('reset role'); }
}
const updWoman = (db, who, name) => as(db, who, `update women_members set full_name = $1 where id = $2 returning id`, [name, P.W1]);
const readExt = (db, who) => as(db, who, `select id from external_spouses where id = $1`, [P.E1]);
const updExt = (db, who, name) => as(db, who, `update external_spouses set full_name = $1 where id = $2 returning id`, [name, P.E1]);
// إدراج بلا returning كما تفعل التطبيقات (المرسل لا يقرأ إشعار غيره)، ثم القراءة بصلاحية القاعدة
const notify = async (db, who, row) => {
  const r = await as(db, who,
    `insert into notifications(target_member_id, title, body, kind, created_by) values ($1, $2, $3, $4, $5)`,
    [row.target ?? null, row.title, row.body ?? 'نص', row.kind, row.by ?? null]);
  if (!r.ok) return r;
  const rows = (await db.query(`select created_by, body from notifications
    where title = $1 and target_member_id is not distinct from $2 order by created_at desc limit 1`,
    [row.title, row.target ?? null])).rows;
  return { ok: true, rows };
};
const copies = async (db, title) => (await db.query(`select target_member_id, created_by from notifications where title = $1 and target_member_id is not null`, [title])).rows;

for (const stage of ['before', 'after', 'rolledback']) {
  const after = stage === 'after';
  console.log(`\n══════ ${{ before: 'قبل التعديل (السيرفر اليوم)', after: 'بعد التعديل', rolledback: 'بعد التراجع' }[stage]} ══════`);
  const db = await setup(stage);

  console.log('— شجرة النساء والأزواج من خارج العائلة:');
  for (const [who, label] of [[P.O, 'المالك'], [P.A, 'المدير'], [P.MON, 'المراقب']]) {
    const w = await updWoman(db, who, `اسم ${label}`), e = await updExt(db, who, `زوج ${label}`);
    check(`${label} يعدّل شجرة النساء والأزواج`, w.ok && w.rows.length === 1 && e.ok && e.rows.length === 1, w.err ?? e.err ?? '');
  }
  let w = await updWoman(db, P.AF, 'مجمّد'), e = await updExt(db, P.AF, 'مجمّد'), r = await readExt(db, P.AF);
  check(`مدير مجمّد: ${after ? 'لا يعدّل ولا يقرأ الأزواج' : 'يعدّل ويقرأ (الثغرة)'}`,
    after ? w.rows?.length === 0 && e.rows?.length === 0 && r.rows?.length === 0
          : w.rows?.length === 1 && e.rows?.length === 1 && r.rows?.length === 1,
    `نساء ${w.rows?.length} · أزواج ${e.rows?.length} · قراءة ${r.rows?.length}`);
  r = await readExt(db, P.S); e = await updExt(db, P.S, 'مشرف');
  check(`المشرف يقرأ الأزواج${after ? ' ولا يعدّل' : ' ويعدّل (خلاف «المشرف يشوف بلا تعديل»)'}`,
    r.rows?.length === 1 && (after ? e.rows?.length === 0 : e.rows?.length === 1), `قراءة ${r.rows?.length} · تعديل ${e.rows?.length}`);
  w = await updWoman(db, P.S, 'مشرف');
  check('المشرف لا يعدّل شجرة النساء (قبل وبعد)', w.rows?.length === 0);
  w = await updWoman(db, P.M, 'عضو'); e = await updExt(db, P.M, 'عضو');
  check('العضو لا يعدّل (قبل وبعد)', w.rows?.length === 0 && e.rows?.length === 0);

  console.log('— مرسل الإشعار:');
  let n = await notify(db, P.M, { target: P.K, kind: 'profile_update', title: 'تحديث صورة', by: P.O });
  check(`الأب يرسل لابنه «باسم المالك»: ${after ? 'يُكتب باسم الأب' : 'يظهر من المالك (الثغرة)'}`,
    n.ok && n.rows[0].created_by === (after ? P.M : P.O), n.err ?? n.rows?.[0]?.created_by);
  n = await notify(db, P.M, { target: P.K, kind: 'profile_update', title: 'تحديث اسم', by: P.M });
  check('الأب يرسل لابنه باسمه (التطبيق) — كما هو', n.ok && n.rows[0].created_by === P.M, n.err ?? '');
  n = await notify(db, P.M, { target: P.K, kind: 'admin_broadcast', title: 'إعلان مزيّف', by: P.O });
  check(`عضو يرسل «إعلاناً عاماً» لابنه: ${after ? 'مرفوض' : 'يمر (الثغرة)'}`, after ? !n.ok : n.ok, n.err ?? '');
  n = await notify(db, P.M, { kind: 'tree_edit', title: 'طلب تعديل للإدارة', by: P.O });
  let c = await copies(db, 'طلب تعديل للإدارة');
  check(`طلب للإدارة (توزيع على الفريق) «باسم المالك»: ${after ? 'يصلهم باسم العضو' : 'يصلهم من المالك (الثغرة)'}`,
    c.length >= 4 && c.every(x => x.created_by === (after ? P.M : P.O)), `${c.length} نسخة`);
  n = await notify(db, P.PEND, { kind: 'link_request', title: 'طلب انضمام', by: P.PEND });
  c = await copies(db, 'طلب انضمام');
  check('المسجّل المعلّق يبلّغ الإدارة بطلب انضمامه (كما هو)', c.length >= 4 && c.every(x => x.created_by === P.PEND), n.err ?? `${c.length} نسخة`);
  n = await notify(db, P.K, { target: P.K, kind: 'test', title: 'تجربة', by: P.K });
  check('إشعار تجربة لنفسه (الإعدادات) — كما هو', n.ok && n.rows[0].created_by === P.K, n.err ?? '');
  n = await notify(db, P.O, { kind: 'admin_broadcast', title: 'إعلان المالك', by: P.O });
  c = await copies(db, 'إعلان المالك');
  check('إعلان المالك يصل أصحاب الأجهزة باسمه (كما هو)', n.ok && c.length === 2 && c.every(x => x.created_by === P.O), n.err ?? `${c.length} نسخة`);
  n = await notify(db, P.A, { target: P.K, kind: 'news_like', title: 'إعجاب', body: 'بدر أعجب بخبرك', by: P.A });
  check('إعجاب المدير يظهر «الإدارة أعجبت بخبرك» (كما هو)', n.ok && n.rows[0].body === 'الإدارة أعجبت بخبرك', n.err ?? n.rows?.[0]?.body);
  n = await notify(db, null, { target: P.K, kind: 'admin', title: 'صيانة', by: P.O });
  check('صيانة SQL بلا JWT (كما هي)', n.ok && n.rows[0].created_by === P.O, n.err ?? '');
}
console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
