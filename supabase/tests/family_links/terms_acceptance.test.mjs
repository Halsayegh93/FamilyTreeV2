// تجربة 20261021150000_terms_acceptance (الموافقة على الشروط على السيرفر — التوصية ١٥) على قاعدة محلية معزولة.
// accept_terms / my_terms_status بالصلاحيات (anon، العضو، المعلّق، المجمّد، الإدارة)، النسخة من app_config.terms_version،
// لا نزول للنسخة، لا أثر على حراس profiles ولا حد التعديل، ثم التراجع (يحذف العمود ويفرّغ ما كُتب) وإعادة التطبيق.
// التشغيل: cd supabase/tests/family_links && node terms_acceptance.test.mjs
import { makeDb, as, mig, rb, P, id, counter, val, canExec } from './app_config_env.mjs';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? ''); process.exit(2); });
const t = counter(); const ok = t.ok;
const db = await makeDb();
await db.exec(mig('config'));
await db.exec(mig('edits'));    // حد التعديل مطبّق: الموافقة لا تُحسب تعديلاً
await db.exec(mig('guards'));   // وحارس التسجيل (مغلق أدناه): الموافقة ليست تسجيلاً
const COLS_BEFORE = await val(db, `select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns
  where table_schema = 'public' and table_name = 'profiles'`);
await db.exec(`update public.profiles set terms_accepted_at = '2026-01-01' where id = '${P.M2}'`);   // قيمة قديمة يجب أن تبقى

// ══════════ الترحيل ══════════
await db.exec(mig('terms'));
for (const f of ['public.accept_terms(integer)', 'public.my_terms_status()']) {
  ok(!(await canExec(db, 'anon', f)) && !(await canExec(db, 'service_role', f)) && await canExec(db, 'authenticated', f), `${f.split('(')[0]}: للمسجّل فقط`);
}
const st = async who => { const x = await as(db, who, `select public.my_terms_status() j`); return x.ok ? x.rows[0].j : x.hint; };
const acc = async (who, v) => { const x = await as(db, who, `select public.accept_terms($1) j`, [v]); return x.ok ? x.rows[0].j : (x.hint || x.err); };
let j = await st('M');
ok(j.current_version === 1 && j.accepted_version === null && j.accepted_at === null && j.needs_accept === true, 'جديد: لم يوافق بعد (النسخة ١)', JSON.stringify(j));
await db.exec(`update public.app_settings set allow_new_registrations = false`);
for (const k of ['M', 'S', 'A', 'O', 'PEND', 'NEW']) {
  j = await acc(k, 1);
  ok(j.accepted_version === 1 && j.needs_accept === false && j.accepted_at, `${k} يوافق على ١`, JSON.stringify(j));
}
await db.exec(`update public.app_settings set allow_new_registrations = true`);
ok(await val(db, `select count(*)::int from public.profile_edit_counts`) === 0, 'الموافقة لا تُحسب تعديلاً');
ok(await val(db, `select role || '/' || status || '/' || full_name from public.profiles where id = '${P.NEW}'`) === 'member/pending/', 'السجل المبدئي لم يتغيّر غير الموافقة');
for (const k of ['FA', 'FM']) ok((await acc(k, 1)) === 'account_inactive', `${k} (مجمّد) لا يوافق`);
ok((await acc(id(77), 1)) === 'no_profile', 'حساب بلا ملف ← no_profile');
for (const v of [0, 2, null]) ok((await acc('M', v)) === 'bad_value', `نسخة ${v} ← bad_value (الحالية ١)`);
let x = await as(db, 'anon', `select public.accept_terms(1)`);
ok(!x.ok && /permission denied/.test(x.err), 'anon لا يوافق');
x = await as(db, 'anon', `select public.my_terms_status()`);
ok(!x.ok, 'ولا يقرأ الحالة');

// المالك يرفع النسخة ← الكل يحتاج موافقة جديدة
const r = await as(db, 'O', `select public.set_app_config('terms_version', '2')`);
ok(r.ok, 'المالك يرفع النسخة إلى ٢');
ok((await st('M')).needs_accept === true && (await st('M')).accepted_version === 1, 'العضو: يحتاج الموافقة على ٢');
j = await acc('M', 2);
ok(j.accepted_version === 2 && j.needs_accept === false, 'يوافق على ٢');
j = await acc('M', 1);
ok(j.accepted_version === 2, 'موافقة قديمة لا تنزل النسخة');
ok((await st('S')).needs_accept === true, 'المشرف ما زال يحتاج');

// ══════════ التراجع ══════════
await db.exec(rb('terms'));
ok(await val(db, `select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns
  where table_schema = 'public' and table_name = 'profiles'`) === COLS_BEFORE, 'التراجع: أعمدة profiles كما كانت');
ok(await val(db, `select count(*)::int from public.profiles where terms_accepted_at is not null`) === 1
  && await val(db, `select terms_accepted_at::date::text from public.profiles where id = '${P.M2}'`) === '2026-01-01', 'التراجع: ما كتبته accept_terms فُرّغ، والقيمة القديمة باقية');
ok(await val(db, `select count(*)::int from pg_proc where proname in ('accept_terms', 'my_terms_status')`) === 0, 'التراجع: الدالتان حُذفتا');
x = await db.exec(rb('terms')).then(() => ({ ok: true }), e => ({ ok: false, err: e.message }));
ok(x.ok, 'التراجع مرتين بلا خطأ', x.err);
await db.exec(mig('terms'));
ok((await acc('M', 2)).accepted_version === 2, 'إعادة التطبيق بعد التراجع تعمل');
x = await db.exec(rb('config')).then(() => ({ ok: true }), e => ({ ok: false, err: e.message }));
ok(!x.ok && /accept_terms|my_terms_status/.test(x.err), 'تراجع app_config قبل هذا يُرفض', x.err);
t.done();
