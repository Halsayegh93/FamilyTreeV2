// تجربة 20261021140000_profile_edit_limit (حد تعديل الملف من السيرفر — الخلل ٤) على قاعدة محلية معزولة — لا تلمس السيرفر.
// قبل: لا حد على السيرفر (العدّاد في الجهاز فقط). بعد (الافتراضي ٣، مفعّل):
//   أول ٣ تعديلات لكل حقل تمر كما كانت، والرابعة ← edit_limit_reached (detail = الحقل)، الحقول مستقلة، القيمة نفسها لا تُعدّ،
//   حذف الصورة وإخفاء الرقم مجانيان، العضو والمشرف فقط — الإدارة الثلاثة والمعلّق والإدارة على غيرها ودوال السيرفر والخدمة لا.
//   الإعدادان يغيّران العدد ويطفئان العدّ، والقراءة والتصفير بالصلاحيات الصحيحة. ثم التراجع وإعادة التطبيق.
// التشغيل: cd supabase/tests/family_links && node profile_edit_limit.test.mjs
import { makeDb, as, tx as txOn, mig, rb, P, id, counter, val, canExec } from './app_config_env.mjs';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? ''); process.exit(2); });
const t = counter(); const ok = t.ok;
const db = await makeDb();
const tx = fn => txOn(db, fn);
await db.exec(mig('config'));
// دالة سيرفر (SECURITY DEFINER) يناديها العضو وتكتب في ملفه — مثل قرار طلب أو نقل ملف
await db.exec(`create function public.x_server_touch(p uuid, d date) returns void language sql security definer set search_path = '' as $$
  update public.profiles set birth_date = d where id = p $$;
  grant execute on function public.x_server_touch(uuid, date) to authenticated;`);

const code = r => r.ok ? 'ok' : (r.hint || r.code || r.err);
const upd = (who, target, set) => as(db, who, `update public.profiles set ${set} where id = '${P[target] ?? target}'`);
const birth = n => `birth_date = '19${String(80 + n).padStart(2, '0')}-01-01'`;
const series = async (who, target, setter, n) => { const out = []; for (let i = 1; i <= n; i++) out.push(code(await upd(who, target, setter(i)))); return out.join(','); };
const counts = async m => Object.fromEntries((await db.query(`select field, edits from public.profile_edit_counts where member_id = $1`, [P[m] ?? m])).rows.map(x => [x.field, x.edits]));

// ── «قبل»: لا حد ──
ok(await tx(() => series('M', 'M', birth, 6)) === 'ok,ok,ok,ok,ok,ok', 'قبل: العضو يعدّل تاريخ ميلاده ٦ مرات مباشرة (الخلل ٤)');

// ══════════ الترحيل ══════════
await db.exec(mig('edits'));
for (const who of ['anon', 'authenticated', 'service_role'])
  ok(!(await val(db, `select has_table_privilege('${who}', 'public.profile_edit_counts', 'select') or has_table_privilege('${who}', 'public.profile_edit_counts', 'insert')
    or has_table_privilege('${who}', 'public.profile_edit_counts', 'update') or has_table_privilege('${who}', 'public.profile_edit_counts', 'delete')`)), `العدّادات: لا وصول لـ ${who}`);
for (const who of ['anon', 'service_role']) ok(!(await canExec(db, who, 'public.profile_edit_limit_consume(uuid,text[])')), `consume: لا تنفيذ لـ ${who}`);
ok(!(await canExec(db, 'anon', 'public.profile_edit_limits(uuid)')) && !(await canExec(db, 'anon', 'public.reset_profile_edit_counts(uuid,text)')), 'القراءة والتصفير: لا anon');
for (const who of ['anon', 'authenticated', 'service_role']) ok(!(await canExec(db, who, 'public.trg_profiles_self_edit_limit()')), `المحفّز: لا تنفيذ مباشر لـ ${who}`);
let r = await as(db, 'M', `select public.profile_edit_limit_consume('${P.M}', array['birthDate'])`);
ok(!r.ok && r.code === '42501', 'العضو لا ينادي consume مباشرة (خارج المحفّز)', r.err);
r = await as(db, 'M', `select * from public.profile_edit_counts`);
ok(!r.ok && /permission denied/.test(r.err), 'ولا يقرأ العدّادات مباشرة');

// ── الافتراضي: ٣ لكل حقل ──
await tx(async () => {
  ok(await series('M', 'M', birth, 4) === 'ok,ok,ok,edit_limit_reached', 'تاريخ الميلاد: ٣ تمر والرابعة للإدارة');
  ok(await val(db, `select birth_date::text from public.profiles where id = '${P.M}'`) === '1983-01-01', 'الرابعة لم تُحفظ');
  r = await upd('M', 'M', birth(5));
  ok(r.detail === 'birthDate' && /حد التعديلات/.test(r.err), 'الخطأ: hint + detail بالحقل + رسالة عربية', `${r.detail} ${r.err}`);
  ok(code(await upd('M', 'M', birth(3))) === 'ok', 'نفس القيمة لا تُعدّ تعديلاً');
  ok(await series('M', 'M', i => `is_married = ${i % 2 === 1}`, 4) === 'ok,ok,ok,edit_limit_reached', 'الحالة الاجتماعية مستقلة: ٣ ثم للإدارة');
  ok(await series('M', 'M', i => `bio_json = '[{"title": "محطة ${i}"}]'`, 4) === 'ok,ok,ok,edit_limit_reached', 'السيرة مستقلة');
  ok(await series('M', 'M', i => `avatar_url = 'https://x/a${i}.jpg'`, 4) === 'ok,ok,ok,edit_limit_reached', 'الصورة مستقلة');
  ok(code(await upd('M', 'M', 'avatar_url = null')) === 'ok', 'حذف الصورة مجاني بعد الحد');
  ok(await series('M', 'M', i => `phone_number = '+9655000000${i}'`, 4) === 'ok,ok,ok,edit_limit_reached', 'الرقم مستقل');
  ok(await series('M', 'M', i => `is_phone_hidden = ${i % 2 === 1}`, 6) === 'ok,ok,ok,ok,ok,ok', 'إخفاء الرقم بلا حد (مفتاح الخصوصية)');
  ok((await series('M', 'M', i => `full_name = 'اسم ${i}', gender = 'male'`, 5)).split(',').every(x => x === 'ok'), 'حقول أخرى لا تُعدّ');
  ok(JSON.stringify(await counts('M')) === JSON.stringify({ birthDate: 3, isMarried: 3, bio: 3, avatar: 3, phoneNumber: 3 }), 'العدّاد: ٣ لكل حقل', JSON.stringify(await counts('M')));
});
await tx(async () => {
  await series('M', 'M', birth, 3);
  r = await upd('M', 'M', `${birth(9)}, is_married = true`);
  ok(r.hint === 'edit_limit_reached' && r.detail === 'birthDate', 'تحديث بحقلين أحدهما فوق الحد ← يُرفض كله', r.detail);
  ok((await counts('M')).isMarried === undefined, 'والحقل الآخر لم يُحسب (تراجعت المعاملة)');
  ok(code(await upd('M', 'M', 'is_married = true')) === 'ok' && (await counts('M')).isMarried === 1, 'ثم يُحفظ وحده ويُعدّ مرة');
});
await tx(async () => {
  ok(await series('S', 'S', birth, 4) === 'ok,ok,ok,edit_limit_reached', 'المشرف محدود مثل العضو');
  for (const k of ['O', 'A', 'MON']) ok(await series(k, k, birth, 5) === 'ok,ok,ok,ok,ok', `${k}: ملفه بلا حد`);
  ok(await series('A', 'M2', birth, 5) === 'ok,ok,ok,ok,ok' && JSON.stringify(await counts('M2')) === '{}', 'المدير يعدّل ملف عضو بلا حد ولا يُحسب على العضو');
  ok(await series('MON', 'M2', i => `avatar_url = 'https://x/m${i}.jpg'`, 4) === 'ok,ok,ok,ok', 'والمراقب كذلك');
  ok(await series('PEND', 'PEND', birth, 5) === 'ok,ok,ok,ok,ok', 'المعلّق (التسجيل و«تعديل البيانات») بلا حد');
  r = await upd('FM', 'FM', birth(1));
  ok(r.hint !== 'edit_limit_reached', 'المجمّد: حارسه الحالي هو من يقرر (لا هذا الحد)', code(r));
  let s = ''; for (let i = 1; i <= 5; i++) s += code(await as(db, 'M2', `select public.x_server_touch('${P.M2}', '20${String(10 + i)}-01-01')`)) + ',';
  ok(s === 'ok,ok,ok,ok,ok,' && JSON.stringify(await counts('M2')) === '{}', 'دالة سيرفر (SECURITY DEFINER) يناديها العضو: لا تُعدّ');
  ok(await series('service', 'M2', birth, 5) === 'ok,ok,ok,ok,ok', 'الخدمة بلا حد');
  for (let i = 1; i <= 5; i++) await db.exec(`update public.profiles set ${birth(i + 10)} where id = '${P.M2}'`);
  ok(JSON.stringify(await counts('M2')) === '{}', 'صيانة SQL لا تُعدّ');
  const moved = { sub: id(40), pid: P.M2 };
  ok(await series(moved, 'M2', birth, 4) === 'ok,ok,ok,edit_limit_reached', 'الحساب المنقول يُحسب على ملفه (current_profile_id)');
});

// ── الإعدادان ──
const setc = (k, v) => db.query(`update public.app_config set value = $2::jsonb where key = $1`, [k, JSON.stringify(v)]);
await tx(async () => {
  await series('M', 'M', birth, 3);
  await setc('profile_free_edits', 5);
  ok(await series('M', 'M', i => birth(i + 10), 3) === 'ok,ok,edit_limit_reached', 'الحد ٥: تعديلان إضافيان ثم للإدارة');
  await setc('profile_free_edits', 0);
  ok(code(await upd('M', 'M', 'is_married = true')) === 'edit_limit_reached', 'الحد ٠: كل تعديل للإدارة حتى الأول');
  await setc('profile_edit_limit_enabled', false);
  const before = JSON.stringify(await counts('M'));
  ok(await series('M', 'M', i => birth(i + 20), 5) === 'ok,ok,ok,ok,ok', 'العدّاد مطفأ: كل تعديل يُحفظ');
  ok(JSON.stringify(await counts('M')) === before, 'ولا يُحسب وقت الإيقاف (مثل isDisabled)');
});

// ── القراءة ──
await tx(async () => {
  await series('M', 'M', birth, 2);
  const lim = async (who, m = null) => { const x = await as(db, who, `select public.profile_edit_limits($1) j`, [m]); return x.ok ? x.rows[0].j : x.code; };
  let j = await lim('M');
  ok(j.enabled === true && j.free_edits === 3 && j.exempt === false && j.fields.birthDate.used === 2 && j.fields.birthDate.remaining === 1
    && j.fields.avatar.used === 0 && j.fields.avatar.remaining === 3 && Object.keys(j.fields).length === 5, 'العضو يقرأ عدّاده', JSON.stringify(j));
  ok((await lim('M', P.M2)) === '42501' && (await lim('MON', P.M)) === '42501' && (await lim('S', P.M)) === '42501', 'عدّاد غيره ممنوع على العضو والمراقب والمشرف');
  ok((await lim('A', P.M)).fields.birthDate.used === 2 && (await lim('O', P.M)).member_id === P.M, 'المالك والمدير يقرآن عدّاد أي عضو');
  ok((await lim('O')).exempt === true && (await lim('PEND')).exempt === true && (await lim('S')).exempt === false, 'exempt: المالك والمعلّق مستثنيان، المشرف لا');
  r = await as(db, 'anon', `select public.profile_edit_limits()`);
  ok(!r.ok, 'anon لا يقرأ');
});

// ── التصفير ──
await tx(async () => {
  await series('M', 'M', birth, 3); await series('M2', 'M2', birth, 2); await series('M', 'M', i => `is_married = ${i % 2 === 1}`, 2);
  const reset = async (who, m, f = null) => { const x = await as(db, who, `select public.reset_profile_edit_counts($1, $2) n`, [m, f]); return x.ok ? x.rows[0].n : x.hint; };
  for (const k of ['M', 'MON', 'S', 'FA', 'PEND']) ok((await reset(k, P.M)) === 'not_allowed', `التصفير ممنوع على ${k}`);
  ok((await reset('A', null)) === 'not_allowed', 'المدير لا يصفّر الجميع');
  ok((await reset('A', P.M, 'nope')) === 'bad_value', 'حقل مجهول ← bad_value');
  ok((await reset('A', P.M, 'birthDate')) === 1 && JSON.stringify(await counts('M')) === '{"isMarried":2}', 'المدير يصفّر حقلاً لعضو');
  ok(code(await upd('M', 'M', birth(7))) === 'ok', 'وبعدها يعدّل مباشرة');
  ok((await reset('O', null)) === 3 && await val(db, `select count(*)::int from public.profile_edit_counts`) === 0, 'المالك يصفّر الجميع («تصفير العداد»)');
});

// ══════════ التراجع ══════════
r = await db.exec(rb('config')).then(() => ({ ok: true }), e => ({ ok: false, err: e.message }));
ok(!r.ok && /profile_edit/.test(r.err), 'تراجع app_config قبل هذا يُرفض', r.err);
await db.exec(rb('edits'));
ok(await val(db, `select count(*)::int from pg_proc where proname in ('profile_edit_limit_consume', 'trg_profiles_self_edit_limit', 'profile_edit_limits', 'reset_profile_edit_counts')`) === 0
  && await val(db, `select count(*)::int from pg_class where relname = 'profile_edit_counts'`) === 0, 'التراجع: الدوال والجدول حُذفت');
ok(await tx(() => series('M', 'M', birth, 6)) === 'ok,ok,ok,ok,ok,ok', 'التراجع: بلا حد كما كان');
r = await db.exec(rb('edits')).then(() => ({ ok: true }), e => ({ ok: false, err: e.message }));
ok(r.ok, 'التراجع مرتين بلا خطأ', r.err);
await db.exec(mig('edits'));
ok(await tx(() => series('M', 'M', birth, 4)) === 'ok,ok,ok,edit_limit_reached', 'إعادة التطبيق بعد التراجع تعمل');
t.done();
