// تجربة 20261114170000_about_credits («أسماء عن التطبيق» في app_config) على قاعدة محلية معزولة — لا تلمس السيرفر.
// جدول app_config بقيود الحي (نفس admin_role_matrix.test.mjs)، والترحيل يضيف حارساً مستقلاً ومفتاحاً واحداً فقط.
// يثبت: البذرة تمرّ وتساوي ما يعرضه التطبيق اليوم، الأشكال الخاطئة تُرفض (hint bad_value)، الافتراضي محروس أيضاً، الحارس لا
// يمسّ المفاتيح الأخرى، إعادة التطبيق لا تمسّ قائمة المالك، والتراجع نظيف.
// التشغيل: cd supabase/tests/family_links && node about_credits.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../../', import.meta.url));
const MIG = readFileSync(`${REPO}/migrations/20261114170000_about_credits.sql`, 'utf8');
const RB = readFileSync(`${REPO}/rollback/20261114170000_about_credits_rollback.sql`, 'utf8');
let pass = 0, fail = 0;
const ok = (c, m, x = '') => { if (c) { pass++; console.log('✓', m); } else { fail++; console.log('✗', m, x); } };

const db = new PGlite();
await db.exec(`
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
end $$;
create schema private;
create table public.app_config (
  key text primary key check (key ~ '^[a-z][a-z0-9_]{1,62}$'),
  value jsonb not null, default_value jsonb not null,
  kind text not null check (kind = any (array['int', 'bool', 'text', 'text_long', 'json'])),
  min_value numeric, max_value numeric,
  max_length integer check (max_length is null or (max_length >= 1 and max_length <= 10000)),
  category text not null check (category = any (array['members', 'news', 'tree', 'notifications', 'approvals', 'deaths', 'sms', 'links', 'general'])),
  label_ar text not null check (btrim(label_ar) <> ''), help_ar text,
  rules jsonb not null default '{}'::jsonb check (jsonb_typeof(rules) = 'object'),
  is_public boolean not null default false, sort integer not null default 0,
  updated_at timestamptz not null default now(), updated_by uuid,
  check (min_value is null or max_value is null or min_value <= max_value));
insert into public.app_config (key, value, default_value, kind, category, label_ar)
values ('other_list', '[{"x": 1}]', '[{"x": 1}]', 'json', 'general', 'مفتاح آخر');
`);

await db.exec(MIG);
const seed = (await db.query(`select value, default_value, kind, is_public from public.app_config where key = 'about_credits'`)).rows[0];
ok(seed && seed.value.length === 1 && seed.value[0].name === 'حسن الصايغ' && seed.value[0].role === 'فكرة وتنفيذ',
   'البذرة = «فكرة وتنفيذ: حسن الصايغ»', JSON.stringify(seed));
ok(seed && seed.kind === 'json' && seed.is_public === false, 'نوعها json وليست عامة قبل الدخول');

const setValue = async v => {
  try { await db.query(`update public.app_config set value = $1::jsonb where key = 'about_credits'`, [JSON.stringify(v)]); return null; }
  catch (e) { return e; }
};
const good = [{ role: 'فكرة وتنفيذ', name: 'حسن الصايغ' }, { name: 'اسم بلا صفة' }, { role: 'التصميم', name: 'فلان', role_en: 'Design', name_en: 'Someone' }];
ok((await setValue(good)) === null, 'قائمة صحيحة (ثلاثة أسماء، أحدها بلا صفة) تُحفظ');
ok((await db.query(`select jsonb_array_length(value) n from public.app_config where key='about_credits'`)).rows[0].n === 3, 'الحفظ وصل');

const bad = [
  [{}, 'ليست قائمة'],
  [[], 'قائمة فارغة'],
  [Array.from({ length: 21 }, (_, i) => ({ name: 'اسم ' + i })), '٢١ اسماً'],
  [['نص'], 'عنصر ليس كائناً'],
  [[{ role: 'صفة' }], 'بلا اسم'],
  [[{ name: '   ' }], 'اسم فراغات'],
  [[{ name: 'فلان', photo: 'x' }], 'مفتاح غير معروف'],
  [[{ name: 5 }], 'اسم ليس نصاً'],
  [[{ name: 'سطر\nثانٍ' }], 'سطر جديد'],
  [[{ name: 'ا'.repeat(61) }], 'اسم أطول من ٦٠'],
  [[{ name: 'فلان', role: 'ص'.repeat(41) }], 'صفة أطول من ٤٠'],
];
for (const [v, m] of bad) {
  const e = await setValue(v);
  ok(e && /bad_value|22023/.test(`${e.code} ${e.hint ?? ''}`), `يُرفض: ${m}`, e?.message);
}
ok((await db.query(`select jsonb_array_length(value) n from public.app_config where key='about_credits'`)).rows[0].n === 3,
   'الرفض لا يغيّر المحفوظ');

let e = null;
try { await db.query(`update public.app_config set default_value = '[]'::jsonb where key = 'about_credits'`); } catch (x) { e = x; }
ok(e, 'الافتراضي محروس أيضاً');

e = null;
try { await db.query(`update public.app_config set value = '[{"anything": true}]'::jsonb where key = 'other_list'`); } catch (x) { e = x; }
ok(!e, 'الحارس لا يمسّ المفاتيح الأخرى', e?.message);

await db.exec(MIG);
ok((await db.query(`select jsonb_array_length(value) n from public.app_config where key='about_credits'`)).rows[0].n === 3,
   'إعادة التطبيق لا تمسّ قائمة المالك');

const priv = (await db.query(`select has_function_privilege('authenticated', 'private.about_credits_problem(jsonb)', 'execute') a`)).rows[0].a;
ok(priv === false, 'دالة الفحص غير متاحة للتطبيقات');

await db.exec(RB);
const left = (await db.query(`select
  (select count(*)::int from public.app_config where key = 'about_credits') k,
  (select count(*)::int from pg_trigger where tgname = 'trg_app_config_about_credits_guard') t,
  (select count(*)::int from pg_proc where proname in ('about_credits_problem', 'app_config_about_credits_guard')) f,
  (select count(*)::int from public.app_config where key = 'other_list') o`)).rows[0];
ok(left.k === 0 && left.t === 0 && left.f === 0 && left.o === 1, 'التراجع نظيف ولا يمسّ غيره', JSON.stringify(left));

console.log(`\n${pass} نجحت، ${fail} فشلت`);
process.exit(fail ? 1 : 0);
