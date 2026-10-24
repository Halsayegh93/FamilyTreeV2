// تجربة 20261021130000_registration_and_device_guards على قاعدة محلية معزولة — لا تلمس السيرفر.
// الخلل ١: «السماح بالتسجيل» لا يقرؤه أحد — قبل الترحيل يسجّل الجديد والمفتاح مطفأ؛ بعده يُرفض (registrations_closed) على
//   مسار التسجيل في التطبيقين فقط (السجل المبدئي ← «مسجّل»، إدراج ملف جديد، طلب الانضمام لمسجّل)، ويمر عضو الشجرة والإدارة
//   والمفعّلون والخدمة ومحفّز الدخول. المفتاح مفتوح (الافتراضي) = السلوك نفسه قبل وبعد.
// الخلل ٥: حد الأجهزة — قبل الترحيل لا حد على السيرفر؛ بعده جهاز جديد فوق max_devices_per_user يُرفض (device_limit_reached)،
//   والجهاز المسجّل يحدَّث، والمالك والخدمة مستثنيان. قيد ١..١٠ يُضاف فقط إن كانت القيمة ضمنه.
// ثم التراجع يعيد كل شيء ويُعاد التطبيق.
// التشغيل: cd supabase/tests/family_links && node registration_device_guards.test.mjs
import { makeDb, as, tx as txOn, mig, rb, P, id, counter, val, canExec } from './app_config_env.mjs';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? ''); process.exit(2); });
const t = counter(); const ok = t.ok;
const db = await makeDb();
const tx = fn => txOn(db, fn);
const NOROW = id(30);   // حساب دخول بلا ملف (المحفّز لم ينشئ سجلاً)
await db.exec(`
  alter table public.device_tokens add column device_id text, add column platform text default 'ios', add column updated_at timestamptz default now();
  create unique index idx_device_tokens_member_device_unique on public.device_tokens (member_id, device_id);
  alter table public.device_tokens enable row level security;
  create policy device_tokens_select_self_or_admin on public.device_tokens for select to authenticated
    using (member_id = auth.uid() or public.current_user_role() in ('owner', 'admin'));
  create policy device_tokens_insert_self on public.device_tokens for insert to authenticated with check (member_id = auth.uid());
  create policy device_tokens_update_self on public.device_tokens for update to authenticated
    using (member_id = auth.uid()) with check (member_id = auth.uid());
  create policy device_tokens_delete_self on public.device_tokens for delete to authenticated using (member_id = auth.uid());
  alter table public.admin_requests add column details text;`);

const setReg = open => db.query(`update public.app_settings set allow_new_registrations = $1`, [open]);
const code = r => r.ok ? 'ok' : (r.hint || r.code || r.err);
// مسارات التسجيل كما تكتبها التطبيقات (registerNewUser / registration_screen._submit / ensurePendingLinkRequest)
const scenarios = async () => tx(async () => {
  const o = {};
  o.new_register = code(await as(db, 'NEW', `update public.profiles set full_name = 'جديد المحمدعلي', first_name = 'جديد', role = 'pending',
    status = 'pending', is_hidden_from_tree = true where id = '${P.NEW}' and status = 'pending'`));
  o.new_join = code(await as(db, 'NEW', `insert into public.admin_requests (member_id, requester_id, request_type, status, details)
    values ('${P.NEW}', '${P.NEW}', 'join_request', 'pending', 'طلب انضمام جديد')`));
  o.norow_insert = code(await as(db, NOROW, `insert into public.profiles (id, full_name, first_name, role, status)
    values ('${NOROW}', 'بلا سجل', 'بلا', 'pending', 'pending')`));
  o.pend_edit = code(await as(db, 'PEND', `update public.profiles set full_name = 'مسجّل معلّق معدّل', role = 'pending', status = 'pending'
    where id = '${P.PEND}' and status = 'pending'`));
  o.pend_link = code(await as(db, 'PEND', `insert into public.admin_requests (member_id, requester_id, request_type, status)
    values ('${P.PEND}', '${P.PEND}', 'link_request', 'pending')`));
  o.tree_join = code(await as(db, 'TREE', `insert into public.admin_requests (member_id, requester_id, request_type, status, details)
    values ('${P.TREE}', '${P.TREE}', 'join_request', 'pending', 'طلب انضمام — العضو موجود في الشجرة')`));
  o.member_edit = code(await as(db, 'M', `update public.profiles set birth_date = '1990-01-01' where id = '${P.M}'`));
  o.member_contact = code(await as(db, 'M', `insert into public.admin_requests (member_id, requester_id, request_type, status)
    values ('${P.M}', '${P.M}', 'contact_message', 'pending')`));
  o.admin_add = code(await as(db, 'A', `insert into public.profiles (id, full_name, first_name, role, status) values ('${id(31)}', 'ابن مضاف', 'ابن', 'member', 'active')`));
  o.monitor_add = code(await as(db, 'MON', `insert into public.profiles (id, full_name, first_name, role, status) values ('${id(32)}', 'ابن آخر', 'ابن', 'member', 'pending')`));
  o.admin_join = code(await as(db, 'A', `insert into public.admin_requests (member_id, requester_id, request_type, status) values ('${P.NEW}', '${P.A}', 'join_request', 'pending')`));
  o.service = code(await as(db, 'service', `insert into public.profiles (id, full_name, role, status) values ('${id(33)}', '', 'pending', 'pending')`));
  o.auth_trigger = await db.query(`insert into public.profiles (id, phone_number, full_name, first_name, role, status) values ('${id(34)}', '+96599999999', '', '', 'member', 'pending')`)
    .then(() => 'ok', e => e.hint || e.code);
  return o;
});
const OPEN_ALL_OK = { new_register: 'ok', new_join: 'ok', norow_insert: 'ok', pend_edit: 'ok', pend_link: 'ok', tree_join: 'ok', member_edit: 'ok',
  member_contact: 'ok', admin_add: 'ok', admin_join: 'ok', monitor_add: 'ok', service: 'ok', auth_trigger: 'ok' };

// الأجهزة
const dev = (who, member, device) => as(db, who, `insert into public.device_tokens (member_id, device_id, token) values ($1, $2, 'tok')
  on conflict (member_id, device_id) do update set token = excluded.token, updated_at = now()`, [member, device]);
const devScenario = async () => tx(async () => {
  const o = {};
  await db.exec(`insert into public.device_tokens (member_id, device_id) values ('${P.M}', 'm-1'), ('${P.M}', 'm-2'),
    ('${P.O}', 'o-1'), ('${P.O}', 'o-2'), ('${P.O}', 'o-3'), ('${P.S}', null), ('${P.S}', null), ('${P.S}', 's-1')`);
  o.m_third = code(await dev('M', P.M, 'm-3'));
  o.m_fourth = code(await dev('M', P.M, 'm-4'));
  o.m_refresh = code(await dev('M', P.M, 'm-2'));
  o.owner_fourth = code(await dev('O', P.O, 'o-4'));
  o.s_legacy = code(await dev('S', P.S, 's-2'));
  o.s_refresh = code(await dev('S', P.S, 's-1'));
  o.service = code(await as(db, 'service', `insert into public.device_tokens (member_id, device_id) values ('${P.M}', 'm-svc')`));
  o.count_m = await val(db, `select count(*)::int from public.device_tokens where member_id = '${P.M}'`);
  return o;
});

// ── «قبل»: الخللان ظاهران ──
await setReg(false);
const CLOSED_BEFORE = await scenarios();
const same = (x, y) => JSON.stringify(Object.entries(x).sort()) === JSON.stringify(Object.entries(y).sort());
ok(same(CLOSED_BEFORE, OPEN_ALL_OK), 'قبل: التسجيل «مغلق» ولا شيء يُرفض (الخلل ١)', JSON.stringify(CLOSED_BEFORE));
await setReg(true);
const OPEN_BEFORE = await scenarios();
const DEV_BEFORE = await devScenario();
ok(DEV_BEFORE.m_fourth === 'ok' && DEV_BEFORE.count_m === 5, 'قبل: الجهاز الرابع والخامس يُسجَّلان (الخلل ٥)', JSON.stringify(DEV_BEFORE));

// ══════════ الترحيل ══════════
await db.exec(mig('guards'));
for (const who of ['anon', 'authenticated', 'service_role'])
  for (const f of ['public.trg_profiles_registration_gate()', 'public.trg_admin_requests_registration_gate()', 'public.trg_device_tokens_limit()'])
    ok(!(await canExec(db, who, f)), `${f.split('(')[0]}: لا تنفيذ لـ ${who}`);
ok(await val(db, `select count(*)::int from pg_constraint where conname = 'app_settings_max_devices_per_user_check'`) === 1, 'قيد ١..١٠ أُضيف (القيمة ٣ ضمنه)');

// ── مفتوح (الافتراضي): لا تغيير ──
ok(JSON.stringify(await scenarios()) === JSON.stringify(OPEN_BEFORE), 'التسجيل مفتوح: كل المسارات كما قبل الترحيل');

// ── مغلق ──
await setReg(false);
const closed = await scenarios();
const want = { ...OPEN_ALL_OK, new_register: 'registrations_closed', new_join: 'registrations_closed', norow_insert: 'registrations_closed',
  pend_link: 'registrations_closed' };
for (const [k, v] of Object.entries(want)) ok(closed[k] === v, `مغلق: ${k} ← ${v}`, closed[k]);
let r = await tx(() => as(db, 'NEW', `update public.profiles set full_name = 'اسم فقط' where id = '${P.NEW}'`));
ok(r.hint === 'registrations_closed' && /مغلق/.test(r.err), 'مغلق: كتابة اسم على السجل المبدئي وحدها تُرفض برسالة عربية', r.err);
r = await tx(() => as(db, 'NEW', `update public.profiles set gender = 'male' where id = '${P.NEW}'`));
ok(r.ok, 'مغلق: تعديل لا يمس الدور/الحالة/الاسم يمر (مثل الجنس)');
r = await tx(() => as(db, { sub: id(35), pid: P.NEW }, `update public.profiles set full_name = 'عبر حساب منقول', role = 'pending' where id = '${P.NEW}'`));
ok(r.hint === 'registrations_closed', 'مغلق: الحساب المنقول (current_profile_id) يُرفض أيضاً');
r = await tx(() => as(db, 'FM', `insert into public.admin_requests (member_id, requester_id, request_type, status) values ('${P.FM}', '${P.FM}', 'join_request', 'pending')`));
ok(r.ok, 'مغلق: طلب انضمام لملف شجرة مسمّى (ولو مجمّداً) لا يمسّه هذا الحارس');
await setReg(true);

// ── الأجهزة ──
const after = await devScenario();
ok(after.m_third === 'ok' && after.m_fourth === 'device_limit_reached', 'الحد ٣: الثالث يُسجَّل والرابع يُرفض', JSON.stringify(after));
ok(after.m_refresh === 'ok' && after.s_refresh === 'ok', 'تحديث جهاز مسجّل (upsert) يمر دائماً');
ok(after.owner_fourth === 'ok', 'المالك مستثنى');
ok(after.s_legacy === 'device_limit_reached', 'صفوف قديمة بلا device_id تُعدّ (مثل التطبيقين)');
ok(after.service === 'ok' && after.count_m === 4, 'الخدمة تمر (٤ = ٣ + الخدمة)');
const twoDevices = () => db.exec(`insert into public.device_tokens (member_id, device_id) values ('${P.M}', 'm-1'), ('${P.M}', 'm-2')`);
r = await tx(async () => { await twoDevices(); await dev('M', P.M, 'm-3'); return dev('M', P.M, 'm-4'); });
ok(r.hint === 'device_limit_reached' && /الأقصى من الأجهزة \(3\)/.test(r.err), 'الرسالة عربية بالحد', r.err);
await db.exec(`update public.app_settings set max_devices_per_user = 5`);
r = await tx(async () => [await twoDevices() && '', code(await dev('M', P.M, 'a')), code(await dev('M', P.M, 'b')), code(await dev('M', P.M, 'c')), code(await dev('M', P.M, 'd'))]);
ok(JSON.stringify(r.slice(1)) === JSON.stringify(['ok', 'ok', 'ok', 'device_limit_reached']), 'الحد ٥ من الإعدادات: ٢ موجودان + ٣ ثم رفض', JSON.stringify(r));
await db.exec(`update public.app_settings set max_devices_per_user = 1`);
r = await tx(async () => code(await dev('M2', P.M2, 'x')) + ',' + code(await dev('M2', P.M2, 'y')));
ok(r === 'ok,device_limit_reached', 'الحد ١', r);
await db.exec(`update public.app_settings set max_devices_per_user = 3`);
for (const v of [0, 11, -1]) {
  r = await as(db, 'O', `update public.app_settings set max_devices_per_user = ${v}`);
  ok(!r.ok && r.code === '23514', `قيد: ${v} مرفوض`, r.err);
}
r = await as(db, 'O', `update public.app_settings set max_devices_per_user = 10`);
ok(r.ok, 'قيد: ١٠ مقبول');
await db.exec(`update public.app_settings set max_devices_per_user = 3`);

// ══════════ التراجع ══════════
await db.exec(rb('guards'));
ok(await val(db, `select count(*)::int from pg_trigger where tgname in ('trg_profiles_registration_gate', 'trg_admin_requests_registration_gate', 'trg_device_tokens_limit')`) === 0
  && await val(db, `select count(*)::int from pg_proc where proname in ('trg_profiles_registration_gate', 'trg_admin_requests_registration_gate', 'trg_device_tokens_limit')`) === 0,
  'التراجع: المحفّزات والدوال حُذفت');
ok(await val(db, `select count(*)::int from pg_constraint where conname = 'app_settings_max_devices_per_user_check'`) === 0, 'التراجع: القيد حُذف');
await setReg(false);
ok(JSON.stringify(await scenarios()) === JSON.stringify(CLOSED_BEFORE), 'التراجع: السلوك القديم (مغلق لا يُرفض)');
await setReg(true);
ok(JSON.stringify(await devScenario()) === JSON.stringify(DEV_BEFORE), 'التراجع: الأجهزة بلا حد كما كانت');
r = await db.exec(rb('guards')).then(() => ({ ok: true }), e => ({ ok: false, err: e.message }));
ok(r.ok, 'التراجع مرتين بلا خطأ', r.err);

// قيمة حية خارج ١..١٠ ← لا قيد، والتراجع لا يحذف قيداً لم يضفه
await db.exec(`update public.app_settings set max_devices_per_user = 15`);
await db.exec(mig('guards'));
ok(await val(db, `select count(*)::int from pg_constraint where conname = 'app_settings_max_devices_per_user_check'`) === 0, 'القيمة ١٥: القيد لا يُضاف (لا تغيير بيانات)');
await db.exec(rb('guards'));
await db.exec(`update public.app_settings set max_devices_per_user = 3;
  alter table public.app_settings add constraint app_settings_max_devices_per_user_check check (max_devices_per_user between 1 and 20)`);
await db.exec(mig('guards'));
await db.exec(rb('guards'));
ok(await val(db, `select count(*)::int from pg_constraint where conname = 'app_settings_max_devices_per_user_check'`) === 1, 'قيد موجود قبله لا يُمسّ ولا يحذفه التراجع');
await db.exec(`alter table public.app_settings drop constraint app_settings_max_devices_per_user_check`);

await db.exec(mig('guards'));
await setReg(false);
ok((await scenarios()).new_register === 'registrations_closed' && (await devScenario()).m_fourth === 'device_limit_reached', 'إعادة التطبيق بعد التراجع تعمل');
await setReg(true);
t.done();
