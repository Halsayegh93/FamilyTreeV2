// تجربة 20261021110000_app_config (إعدادات التطبيق من السيرفر) على قاعدة محلية معزولة — لا تلمس السيرفر.
// ١) لا شيء قائم يتغيّر (نصوص كل الدوال الموجودة قبله كما هي)، وصلاحيات Supabase الافتراضية مفعّلة قبل الترحيل.
// ٢) الصلاحيات: الجدولان بلا وصول مباشر (السجل للمالك والمدير فقط)، config_* والدوال الداخلية بلا تنفيذ لأحد،
//    app_config للمسجّل، app_config_public لـ anon أيضاً، set_app_config للمالك وحده (حتى الحساب المنقول).
// ٣) النطاق: المفعّل يأخذ كل المفاتيح، المعلّق/المجمّد/بلا ملف العامة فقط، والوصف (meta) للمالك والمدير.
// ٤) البذور = القيم الحالية في التطبيقين، والفحص يرفض كل قيمة خارج القواعد (حتى من صيانة SQL)، والسجل يحفظ كل تغيير.
// ٥) الخلل ٢ (iOS يتجاهل news_requires_approval): محفّز السيرفر يقبل نشر العضو مباشرة إذا أُطفئت المراجعة — لا تغيير لازم.
// ٦) التراجع يحذف كل شيء، ويرفض لو بقيت دالة تقرأ config_*، ويُعاد التطبيق بعده.
// التشغيل: cd supabase/tests/family_links && node app_config.test.mjs
import { makeDb, as, mig, rb, read, P, id, counter, one, val, canExec } from './app_config_env.mjs';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? ''); process.exit(2); });
const t = counter(); const ok = t.ok;
const db = await makeDb();
await db.exec(`insert into auth.users (id, raw_app_meta_data) values ('${P.GHOST}', '{"profile_id": "${P.O}"}')`);
const MOVED_OWNER = { sub: P.GHOST, pid: P.O };

const fnSnapshot = async () => (await db.query(`select p.oid::regprocedure::text sig, md5(pg_get_functiondef(p.oid)) m,
  coalesce(p.proacl::text, '') a from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'auth') order by 1`)).rows;
const BEFORE = await fnSnapshot();
const TABLES_BEFORE = await val(db, `select string_agg(table_schema || '.' || table_name, ',' order by 1) from information_schema.tables
  where table_schema in ('public', 'private', 'auth')`);

// ══════════ الترحيل ══════════
await db.exec(mig('config'));
const after = new Map((await fnSnapshot()).map(r => [r.sig, r]));
ok(BEFORE.every(b => after.get(b.sig)?.m === b.m && after.get(b.sig)?.a === b.a), 'لا دالة قائمة تغيّرت (النص والصلاحيات)');

const KEYS = (await db.query(`select key, kind, value, default_value, is_public, category from public.app_config order by key`)).rows;
const PUBLIC = KEYS.filter(k => k.is_public).map(k => k.key).sort();
ok(KEYS.length === 37, 'البذور: ٣٧ مفتاحاً', KEYS.length);
ok(KEYS.every(k => JSON.stringify(k.value) === JSON.stringify(k.default_value)), 'كل قيمة = افتراضيها');
ok(JSON.stringify(PUBLIC) === JSON.stringify(['privacy_url', 'privacy_url_en', 'site_url', 'support_email', 'terms_url',
  'terms_url_en', 'terms_version']), 'العامة: الروابط ونسخة الشروط فقط', PUBLIC.join(','));
const V = Object.fromEntries(KEYS.map(k => [k.key, k.value]));
const expect = {
  news_max_photos: 5, report_review_hours: 24, profile_free_edits: 3, profile_edit_limit_enabled: true, terms_version: 1,
  living_check_old_birth_year: 1940, living_check_median_year: 1960, living_check_min_births: 3, approvals_info_hours: 48,
  death_announce_window_days: 30, sms_suspicious_per_hour: 5, activity_heartbeat_seconds: 60, greeting_morning_start_hour: 4,
  greeting_afternoon_start_hour: 12, greeting_evening_start_hour: 17, age_bands: [18, 30, 50, 70], branch_root_id: '',
  site_url: 'https://almohali.com', privacy_url: 'https://almohali.com/privacy', privacy_url_en: 'https://almohali.com/privacy/en',
  terms_url: 'https://almohali.com/terms', terms_url_en: 'https://almohali.com/terms/en', support_email: 'info@almohali.com',
  sms_otp_template: 'عائلة المحمدعلي: رمز الدخول {code}. لا تشاركه مع أحد.',
  sms_otp_template_en: 'Your Al-Mohammadali Family app login code is {code}. Do not share this code.',
  announce_preset_titles: ['عائلة المحمدعلي', 'إعلان من الإدارة', 'تذكير', 'دعوة', 'تهنئة', 'تنبيه مهم'],
  notify_join_approved_title: 'تم قبول طلبك', notify_join_approved_body: 'وافقت الإدارة على انضمامك — مرحباً في عائلة المحمدعلي',
  notify_news_like_body: '{name} أعجب بمنشورك', notify_news_comment_body: '{name} علّق على منشورك',
  death_announce_template_male: 'انتقل إلى رحمة الله تعالى {name}\nتغمّده الله بواسع رحمته وأسكنه فسيح جناته\nإنا لله وإنا إليه راجعون',
  death_announce_template_female: 'انتقلت إلى رحمة الله تعالى {name}\nتغمّدها الله بواسع رحمته وأسكنها فسيح جناته\nإنا لله وإنا إليه راجعون',
};
for (const [k, v] of Object.entries(expect)) ok(JSON.stringify(V[k]) === JSON.stringify(v), `افتراضي ${k} = القيمة الحالية`, JSON.stringify(V[k]));
ok(V.branch_extra_heads.length === 4 && V.branch_extra_heads.every(h => h.id === null) && V.branch_extra_heads[3].name === 'ابراهيم(العطار) المحمدعلي',
  'الفروع الإضافية الأربعة بأسمائها وبلا معرّف (المطابقة بالاسم كما اليوم)');
// النص الجاهز للإعلان = نص التطبيقين بعد استبدال الاسم
const ios = 'انتقل إلى رحمة الله تعالى زيد\nتغمّده الله بواسع رحمته وأسكنه فسيح جناته\nإنا لله وإنا إليه راجعون';
ok(V.death_announce_template_male.replace('{name}', 'زيد') === ios, 'قالب الوفاة = نص iOS/Android حرفياً');
ok(V.sms_otp_template.replace('{code}', '123456') === 'عائلة المحمدعلي: رمز الدخول 123456. لا تشاركه مع أحد.', 'قالب الرمز = نص الدالة الطرفية حرفياً');

// ── الصلاحيات ──
for (const who of ['anon', 'authenticated', 'service_role']) {
  for (const tb of ['public.app_config', 'public.app_config_history'])
    ok(!(await val(db, `select has_table_privilege('${who}', '${tb}', 'insert') or has_table_privilege('${who}', '${tb}', 'update')
      or has_table_privilege('${who}', '${tb}', 'delete')`)), `${tb}: لا كتابة لـ ${who}`);
  ok(!(await val(db, `select has_table_privilege('${who}', 'public.app_config', 'select')`)), `app_config: لا قراءة مباشرة لـ ${who}`);
  for (const f of ['public.config_int(text,integer)', 'public.config_text(text,text)', 'public.config_bool(text,boolean)',
    'public.config_json(text,jsonb)', 'private.app_config_problem(text,jsonb,numeric,numeric,integer,jsonb)',
    'private.app_config_text_problem(text,boolean,integer,jsonb)', 'private.app_config_guard()', 'private.app_config_log()'])
    ok(!(await canExec(db, who, f)), `${f.split('(')[0]}: لا تنفيذ لـ ${who}`);
}
ok(!(await canExec(db, 'anon', 'public.app_config()')) && await canExec(db, 'authenticated', 'public.app_config()')
  && !(await canExec(db, 'service_role', 'public.app_config()')), 'app_config(): للمسجّل فقط');
ok(await canExec(db, 'anon', 'public.app_config_public()') && await canExec(db, 'authenticated', 'public.app_config_public()'),
  'app_config_public(): anon والمسجّل');
ok(!(await canExec(db, 'anon', 'public.set_app_config(text,jsonb)')) && await canExec(db, 'authenticated', 'public.set_app_config(text,jsonb)'),
  'set_app_config: للمسجّل (والدالة تفحص المالك)');
let r = await as(db, 'O', `select * from public.app_config`);
ok(!r.ok && /permission denied/.test(r.err), 'حتى المالك لا يقرأ الجدول مباشرة', r.err);
r = await as(db, 'O', `update public.app_config set value = '7' where key = 'news_max_photos'`);
ok(!r.ok && /permission denied/.test(r.err), 'ولا يكتب فيه مباشرة', r.err);
r = await as(db, 'M', `select public.config_int('news_max_photos', 1)`);
ok(!r.ok && /permission denied/.test(r.err), 'العضو لا ينادي config_int', r.err);

// ── النطاق ──
const cfg = async who => { const x = await as(db, who, `select public.app_config() j`); if (!x.ok) throw Error(x.err); return x.rows[0].j; };
for (const k of ['O', 'A', 'MON', 'S', 'M']) {
  const j = await cfg(k);
  ok(j.scope === 'member' && Object.keys(j.values).length === KEYS.length + 2, `${k}: كل المفاتيح + الإعدادين`, Object.keys(j.values).length);
}
for (const k of ['FA', 'FM', 'PEND', 'NEW', 'TREE', id(99)]) {
  const j = await cfg(k);
  const keys = Object.keys(j.values).sort();
  ok(j.scope === 'public' && JSON.stringify(keys) === JSON.stringify([...PUBLIC, 'allow_new_registrations', 'sms_wait_seconds'].sort())
    && !('meta' in j), `${k}: العامة فقط وبلا وصف`, keys.join(','));
}
let j = await cfg('O');
ok(j.can_edit === true && Object.keys(j.meta).length === KEYS.length && j.categories.length === 9, 'المالك: الوصف كاملاً + يعدّل');
ok(j.meta.news_max_photos.label_ar === 'أقصى عدد صور في الخبر' && j.meta.news_max_photos.min === 1 && j.meta.news_max_photos.max === 10
  && j.meta.news_max_photos.default === 5 && j.meta.news_max_photos.is_default === true && j.meta.sms_otp_template.rules.placeholders[0] === '{code}',
  'الوصف: العنوان والمدى والافتراضي والقواعد');
j = await cfg('A');
ok(j.can_edit === false && Object.keys(j.meta).length === KEYS.length, 'المدير: الوصف للقراءة');
for (const k of ['MON', 'S', 'M']) ok(!('meta' in (await cfg(k))), `${k}: بلا وصف`);
j = await cfg(MOVED_OWNER);
ok(j.can_edit === true, 'الحساب المنقول للمالك (app_metadata.profile_id) = المالك');
r = await as(db, 'anon', `select public.app_config()`);
ok(!r.ok && /permission denied/.test(r.err), 'anon لا يقرأ app_config()', r.err);

// ── العامة قبل الدخول ──
const pub = async () => (await as(db, 'anon', `select public.app_config_public() j`)).rows[0].j;
j = await pub();
ok(Object.keys(j.values).length === PUBLIC.length + 2 && j.values.sms_wait_seconds === 60 && j.values.allow_new_registrations === true
  && j.values.terms_version === 1 && j.values.privacy_url === 'https://almohali.com/privacy', 'anon: الروابط والشروط + الانتظار ٦٠ + التسجيل مفتوح');
await db.exec(`update public.app_settings set sms_wait_seconds = 45, allow_new_registrations = false`);
j = await pub();
ok(j.values.sms_wait_seconds === 45 && j.values.allow_new_registrations === false, 'يتبع app_settings (الانتظار ٤٥، التسجيل مغلق) — الخللان ١ و٣');
ok((await cfg('M')).values.sms_wait_seconds === 45, 'وapp_config() للعضو أيضاً');
await db.exec(`update public.app_settings set sms_wait_seconds = 60, allow_new_registrations = true`);

// ── التعديل ──
const set = async (key, value, who = 'O') => as(db, who, `select public.set_app_config($1, $2::jsonb) j`, [key, value === null ? null : JSON.stringify(value)]);
for (const k of ['A', 'MON', 'S', 'M', 'FA', 'FM', 'PEND', 'NEW']) {
  r = await set('news_max_photos', 7, k);
  ok(!r.ok && r.code === '42501' && r.hint === 'not_allowed', `set_app_config ممنوع على ${k}`, r.err);
}
r = await as(db, 'anon', `select public.set_app_config('news_max_photos', '7')`);
ok(!r.ok && /permission denied/.test(r.err), 'وعلى anon', r.err);
ok(await val(db, `select count(*)::int from public.app_config_history`) === 0, 'المرفوض لا يُسجَّل');
r = await set('news_max_photos', 7);
ok(r.ok && r.rows[0].j.value === 7 && r.rows[0].j.is_default === false && r.rows[0].j.updated_by === P.O, 'المالك يحفظ ٧', JSON.stringify(r.rows?.[0]));
let h = await one(db, `select key, old_value, new_value, changed_by from public.app_config_history order by id desc limit 1`);
ok(h.key === 'news_max_photos' && h.old_value === 5 && h.new_value === 7 && h.changed_by === P.O, 'السجل: القديم والجديد ومن', JSON.stringify(h));
ok((await cfg('M')).values.news_max_photos === 7, 'العضو يرى ٧ فوراً');
r = await set('news_max_photos', 8, MOVED_OWNER);
ok(r.ok && r.rows[0].j.value === 8, 'الحساب المنقول للمالك يحفظ');
r = await set('news_max_photos', null);
ok(r.ok && r.rows[0].j.value === 5 && r.rows[0].j.is_default, 'null ← الافتراضي');
r = await as(db, 'O', `select public.set_app_config('news_max_photos', 'null'::jsonb) j`);
ok(r.ok && r.rows[0].j.value === 5, 'JSON null ← الافتراضي أيضاً');
ok(await val(db, `select count(*)::int from public.app_config_history where key = 'news_max_photos'`) === 3, 'كل تغيير سُجّل (٧، ٨، ٥) — إعادة نفس القيمة لا تُسجَّل');
r = await set('no_such_key', 1);
ok(!r.ok && r.code === 'P0002' && r.hint === 'unknown_key', 'مفتاح مجهول ← unknown_key', r.err);

const bad = [
  ['news_max_photos', 11, 'فوق المدى'], ['news_max_photos', 0, 'تحت المدى'], ['news_max_photos', 2.5, 'كسر'], ['news_max_photos', '5', 'نص بدل رقم'],
  ['profile_edit_limit_enabled', 1, 'رقم بدل تشغيل/إيقاف'], ['approvals_info_hours', 169, 'مهلة فوق ١٦٨'],
  ['sms_otp_template', 'عائلة المحمدعلي: رمز الدخول. لا تشاركه.', 'رسالة بلا {code}'],
  ['sms_otp_template', 'عائلة المحمدعلي {code} '.repeat(4), '{code} مكرر'],
  ['sms_otp_template', 'عائلة المحمدعلي: رمز الدخول {code}. لا تشاركه مع أحد أبداً أبداً أبداً أبداً.', 'أطول من ٧٠'],
  ['sms_otp_template', 'عائلة المحمدعلي 🌿 رمز {code}', 'وجه تعبيري (خارج BMP)'],
  ['sms_otp_template', 'عائلة المحمدعلي\nرمز {code}', 'سطر جديد في نص قصير'],
  ['sms_otp_template_en', 'Your code is {code} [family]', 'إنجليزي برمز امتداد'],
  ['sms_otp_template_en', 'رمزك {code}', 'إنجليزي بحروف عربية'],
  ['death_announce_template_male', 'انتقل إلى رحمة الله', 'إعلان بلا {name}'],
  ['notify_news_like_body', 'أعجب بمنشورك', 'إعجاب بلا {name}'],
  ['notify_join_approved_title', '', 'عنوان فارغ'],
  ['privacy_url', 'http://almohali.com/privacy', 'رابط بلا https'],
  ['support_email', 'info-almohali.com', 'بريد غير صحيح'],
  ['announce_preset_titles', [], 'قائمة فارغة'], ['announce_preset_titles', ['أ', 'أ'], 'عناوين مكررة'],
  ['announce_preset_titles', ['أ', 5], 'عنصر ليس نصاً'], ['announce_preset_titles', Array.from({ length: 13 }, (_, i) => 'ع' + i), '١٣ عنواناً'],
  ['announce_preset_titles', 'عائلة', 'نص بدل قائمة'],
  ['age_bands', [18, 50, 30], 'فئات غير تصاعدية'], ['age_bands', [0, 18], 'فئة صفر'], ['age_bands', [18, 18.5], 'كسر في الفئات'],
  ['branch_root_id', 'abc', 'معرّف غير صالح'],
  ['branch_extra_heads', [{ name: 'فرع', id: 'x' }], 'معرّف فرع غير صالح'], ['branch_extra_heads', [{ name: 'فرع', extra: 1 }], 'مفتاح زائد'],
  ['branch_extra_heads', [{ id: null }], 'فرع بلا اسم'],
  ['greeting_morning_start_hour', 12, 'الصباح يتداخل مع العصر'],
];
for (const [k, v, why] of bad) {
  r = await set(k, v);
  ok(!r.ok && r.code === '22023' && r.hint === 'bad_value' && /[؀-ۿ]/.test(r.err), `يرفض ${k}: ${why}`, r.err);
}
ok(await val(db, `select count(*)::int from public.app_config where value <> default_value`) === 0, 'المرفوض لم يغيّر شيئاً');
const good = [
  ['sms_otp_template', 'عائلة المحمدعلي: رمزك {code}'], ['sms_otp_template_en', 'Al-Mohammadali Family code: {code}'],
  ['death_announce_template_female', 'انتقلت إلى رحمة الله {name}\nإنا لله وإنا إليه راجعون'],
  ['announce_preset_titles', ['عائلة المحمدعلي 🌿', 'تذكير']], ['age_bands', [18, 31, 51, 71]],
  ['branch_root_id', '6ea5f129-03c1-4171-8430-87d708f6cd9c'], ['branch_root_id', ''],
  ['branch_extra_heads', [{ id: '6ea5f129-03c1-4171-8430-87d708f6cd9c', name: 'فرع' }, { id: null, name: 'آخر' }]],
  ['profile_free_edits', 0], ['profile_edit_limit_enabled', false], ['terms_version', 2], ['privacy_url', 'https://example.org/p'],
];
for (const [k, v] of good) { r = await set(k, v); ok(r.ok, `يقبل ${k} = ${JSON.stringify(v).slice(0, 40)}`, r.err); }
for (const [k] of good) await set(k, null);
ok(await val(db, `select count(*)::int from public.app_config where value <> default_value`) === 0, 'كل شيء رجع للافتراضي');

// ── قراءة السجل ──
const hist = async who => { const x = await as(db, who, `select count(*)::int n from public.app_config_history`); return x.ok ? x.rows[0].n : x.err; };
const nh = await val(db, `select count(*)::int from public.app_config_history`);
ok(await hist('O') === nh && await hist('A') === nh, 'السجل: المالك والمدير يقرآنه', `${await hist('O')}/${nh}`);
for (const k of ['MON', 'S', 'M', 'FA', 'PEND']) ok(await hist(k) === 0, `السجل: ${k} لا يرى شيئاً`);
r = await as(db, 'O', `insert into public.app_config_history (key) values ('x')`);
ok(!r.ok && /permission denied/.test(r.err), 'ولا يكتب فيه أحد', r.err);

// ── صيانة SQL (بلا مستخدم): الفحص نفسه، والسجل بلا «من» ──
r = await db.query(`update public.app_config set value = '99' where key = 'news_max_photos'`).then(() => ({ ok: true }), e => ({ ok: false, err: e.message, code: e.code }));
ok(!r.ok && r.code === '22023', 'صيانة SQL بقيمة خارج المدى تُرفض أيضاً', r.err);
r = await db.query(`insert into public.app_config (key, kind, value, default_value, category, label_ar) values ('x_test', 'int', '"a"', '1', 'general', 'س')`)
  .then(() => ({ ok: true }), e => ({ ok: false, code: e.code }));
ok(!r.ok && r.code === '22023', 'ومفتاح جديد بقيمة لا تطابق نوعه');
await db.exec(`update public.app_config set value = '6' where key = 'news_max_photos'`);
h = await one(db, `select new_value, changed_by from public.app_config_history order by id desc limit 1`);
ok(h.new_value === 6 && h.changed_by === null, 'تعديل الصيانة مسجَّل بلا «من»');

// ── دوال السيرفر تقرأ بالاحتياطي ──
ok(await val(db, `select public.config_int('news_max_photos', 1)`) === 6, 'config_int يقرأ القيمة');
ok(await val(db, `select public.config_int('no_key', 42)`) === 42, 'مفتاح غائب ← الاحتياطي');
ok(await val(db, `select public.config_int('sms_otp_template', 42)`) === 42, 'نوع مختلف ← الاحتياطي');
ok(await val(db, `select public.config_text('support_email', 'x')`) === 'info@almohali.com', 'config_text');
ok(await val(db, `select public.config_text('news_max_photos', 'x')`) === 'x', 'config_text على رقم ← الاحتياطي');
ok(await val(db, `select public.config_bool('profile_edit_limit_enabled', false)`) === true, 'config_bool');
ok(JSON.stringify(await val(db, `select public.config_json('age_bands', '[]')`)) === '[18,30,50,70]', 'config_json');
ok(JSON.stringify(await val(db, `select public.config_json('no_key', '[1]')`)) === '[1]', 'config_json غائب ← الاحتياطي');
await db.exec(`update public.app_config set value = default_value where key = 'news_max_photos'`);

// ══════════ الخلل ٢: محفّز الأخبار (السيرفر الحي، 20260922230000) ══════════
await db.exec(`create table public.news (id uuid primary key default gen_random_uuid(), author_id uuid, posted_by uuid, content text,
    approval_status text default 'pending', approved_by uuid, approved_at timestamptz);
  grant select, insert on public.news to authenticated;`);
await db.exec(read('migrations/20260922230000_diwaniya_approval_admin_only.sql'));
await db.exec(`create trigger trg_content_force_pending before insert or update of approval_status on public.news
  for each row execute function public.trg_content_force_pending()`);
const post = async (who, status) => { const x = await as(db, who, `insert into public.news (author_id, posted_by, content, approval_status, approved_by)
  values ($1, $1, 'خبر', $2, case when $2 = 'approved' then $1::uuid end) returning approval_status, approved_by`, [P[who], status]); return x.rows?.[0] ?? x; };
let n = await post('M', 'approved');
ok(n.approval_status === 'pending' && n.approved_by === null, 'المراجعة مفعّلة: خبر العضو «معتمد» يُحفظ معلّقاً');
await db.exec(`update public.app_settings set news_requires_approval = false`);
n = await post('M', 'approved');
ok(n.approval_status === 'approved' && n.approved_by === P.M, 'المراجعة مطفأة: العضو يرسل approved فيُنشر مباشرة (ما يرسله Android)');
n = await post('M', 'pending');
ok(n.approval_status === 'pending', 'المراجعة مطفأة والتطبيق أرسل pending (iOS اليوم) ← يبقى معلّقاً: الخلل في iOS لا في السيرفر');
await db.exec(`update public.app_settings set news_requires_approval = true`);

// ══════════ التراجع ══════════
await db.exec(`create function public.x_reader() returns int language sql security definer as $$ select public.config_int('news_max_photos', 5) $$`);
r = await db.exec(rb('config')).then(() => ({ ok: true }), e => ({ ok: false, err: e.message }));
ok(!r.ok && /x_reader/.test(r.err), 'التراجع يرفض ما دامت دالة تقرأ config_*', r.err);
await db.exec(`drop function public.x_reader()`);
await db.exec(rb('config'));
ok(await val(db, `select count(*)::int from pg_proc where proname in ('app_config', 'app_config_public', 'set_app_config', 'config_int',
  'config_text', 'config_bool', 'config_json', 'app_config_problem', 'app_config_text_problem', 'app_config_guard', 'app_config_log')`) === 0, 'التراجع: الدوال حُذفت');
await db.exec(`drop table public.news; drop function public.trg_content_force_pending();`);
ok(await val(db, `select string_agg(table_schema || '.' || table_name, ',' order by 1) from information_schema.tables
  where table_schema in ('public', 'private', 'auth')`) === TABLES_BEFORE, 'التراجع: الجداول كما قبل الترحيل');
const back = new Map((await fnSnapshot()).map(x => [x.sig, x]));
ok(BEFORE.length === back.size && BEFORE.every(b => back.get(b.sig)?.m === b.m && back.get(b.sig)?.a === b.a), 'التراجع: الدوال كما قبل الترحيل حرفياً');
r = await db.exec(rb('config')).then(() => ({ ok: true }), e => ({ ok: false, err: e.message }));
ok(r.ok, 'التراجع مرتين بلا خطأ', r.err);
await db.exec(mig('config'));
r = await set('news_max_photos', 9);
ok(r.ok && (await cfg('M')).values.news_max_photos === 9, 'إعادة التطبيق بعد التراجع تعمل');
t.done();
