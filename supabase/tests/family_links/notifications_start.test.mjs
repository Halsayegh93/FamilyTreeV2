// تجربة «الإشعارات تبدأ مع العضو من دخوله» على قاعدة محلية معزولة (لا تلمس السيرفر).
// التشغيل: cd supabase/tests/family_links && npm install && node notifications_start.test.mjs
// القاعدة = base.sql + ترحيلات ١ أكتوبر (نفس السيرفر الحي)، ثم يُطبَّق 20261004150000.
// كل سيناريو يُشغَّل مرتين: قبل التعديل (يتكرر الخلل) وبعده (يجب أن ينجح).
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? '', (e.query ?? '').slice(0, 300)); process.exit(2); });

const REPO = fileURLToPath(new URL('../../', import.meta.url));
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody, rest] = base.split('-- ─── المشغّلات');
const baseTriggers = rest.slice(rest.indexOf('\n') + 1);
const live = ['20261001150000_protect_family_links', '20261001190000_carry_own_women_node_links']
  .map(n => readFileSync(`${REPO}/migrations/${n}.sql`, 'utf8'));
const grab = (src, name) => {
  const i = src.indexOf(`create or replace function public.${name}(`);
  return src.slice(i, src.indexOf('$function$;', i) + '$function$;'.length);
};
// دوال ما قبل الحماية (كالاختبار الأصلي) — المشغّلات الأساسية تعتمد عليها، ثم تستبدلها ترحيلات ١ أكتوبر
const preFns = ['adopt_tree_profile', 'merge_member_into_tree', 'women_auto_merge_wife']
  .map(n => grab(readFileSync(`${REPO}/rollback/20261001150000_protect_family_links_rollback.sql`, 'utf8'), n)).join('\n\n');
const fanoutLive = grab(readFileSync(`${REPO}/migrations/20260725151900_notifications_subject_member_id.sql`, 'utf8'),
  'fanout_broadcast_notification');
const fix = readFileSync(`${REPO}/migrations/20261004150000_notifications_start_at_login.sql`, 'utf8');
const rollback = readFileSync(`${REPO}/rollback/20261004150000_notifications_start_at_login_rollback.sql`, 'utf8');
// معيار أشد (نفس اليوم): الإعلانات لمن له جهاز مسجّل فقط
const devicesFix = readFileSync(`${REPO}/migrations/20261004170000_broadcast_only_registered_devices.sql`, 'utf8');

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const P = { O: id(1), G: id(2), H: id(3), T: id(5), N: id(7), X: id(20), R: id(21) };

let pass = 0, fail = 0;
const check = (label, ok, extra = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${label}${extra ? ' — ' + extra : ''}`); };

async function fresh(stage) {
  const db = new PGlite();
  await db.exec(baseBody);
  await db.exec(preFns);
  await db.exec(baseTriggers);
  for (const m of live) await db.exec(m);
  // أعمدة الإشعارات الحية التي يستعملها التفريخ + مشغّله (كالسيرفر)
  await db.exec(`
    alter table public.notifications add column if not exists request_id uuid,
      add column if not exists request_type text, add column if not exists details jsonb,
      add column if not exists subject_member_id uuid;
    ${fanoutLive}
    create trigger trg_fanout_broadcast_notification before insert on public.notifications
      for each row execute function public.fanout_broadcast_notification();`);
  if (stage === 'fixed') await db.exec(fix);
  if (stage === 'rolledback') { await db.exec(fix); await db.exec(rollback); }
  if (stage === 'devices') { await db.exec(fix); await db.exec(devicesFix); }
  const q = async (sql, params) => (await db.query(sql, params)).rows;
  const as = async (uid, fn) => {
    await db.query(`select set_config('request.jwt.claims', $1, false)`, [uid ? JSON.stringify({ sub: uid, role: 'authenticated' }) : '']);
    try { return await fn(); } finally { await db.query(`select set_config('request.jwt.claims', '', false)`); }
  };
  // المالك O وحسن H لهما حساب دخول؛ الجد G وطاهر T وX أسماء في الشجرة بلا دخول؛ N مسجّل جديد معلّق
  await db.exec(`
    insert into profiles(id, first_name, full_name, gender, role, status) values
      ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active'),
      ('${P.G}', 'صلاح', 'صلاح الجد', 'male', 'member', 'active');
    insert into women_members(id, first_name, full_name, gender) values ('${P.G}', 'صلاح', 'صلاح الجد', 'male');
    insert into profiles(id, first_name, full_name, gender, role, status, father_id) values
      ('${P.H}', 'حسن', 'حسن صلاح', 'male', 'member', 'active', '${P.G}'),
      ('${P.T}', 'طاهر', 'طاهر صلاح', 'male', 'member', 'active', '${P.G}'),
      ('${P.X}', 'خالد', 'خالد صلاح', 'male', 'member', 'active', '${P.G}');
    insert into profiles(id, first_name, full_name, gender, role, status) values
      ('${P.N}', 'طاهر', 'طاهر (تسجيل جديد)', 'male', 'pending', 'pending');
    insert into auth.users(id) values ('${P.O}'), ('${P.H}'), ('${P.N}'), ('${P.R}');
    -- المالك له جهاز مسجّل؛ حسن له حساب دخول بلا جهاز
    insert into device_tokens(member_id, token) values ('${P.O}', 'tok-owner-0000000000000000');`);
  return { db, q, as };
}

for (const stage of ['before', 'fixed', 'rolledback', 'devices']) {
  const devicesOnly = stage === 'devices';
  const fixed = stage === 'fixed' || devicesOnly;
  console.log(`\n══════ ${stage === 'before' ? 'قبل التعديل (السيرفر الحالي)' : stage === 'fixed' ? 'بعد التعديل' : devicesOnly ? 'معيار أشد: جهاز مسجّل فقط' : 'بعد التراجع'} ══════`);
  const { q, as } = await fresh(stage);

  // ١) إعلان «للجميع»: نسخ لمن له حساب دخول فقط
  await q(`insert into notifications(target_member_id, title, body, kind) values (null, 'إعلان', 'نص', 'admin_broadcast')`);
  const copies = (await q(`select target_member_id t from notifications where title = 'إعلان' and target_member_id is not null`)).map(r => r.t);
  const toNoLogin = copies.filter(t => [P.G, P.T, P.X].includes(t)).length;
  check(`إعلان للجميع: ${fixed ? 'لا نسخ لمن لم يدخل' : 'نسخ لمن لم يدخل (الخلل)'}`, fixed ? toNoLogin === 0 : toNoLogin > 0, `نسخ=${copies.length}، لغير الداخلين=${toNoLogin}`);
  check('إعلان للجميع: المالك (له جهاز) وصله', copies.includes(P.O));
  check(`إعلان للجميع: حسن (دخول بلا جهاز) ${devicesOnly ? 'لا يصله' : 'يصله'}`, devicesOnly ? !copies.includes(P.H) : copies.includes(P.H));
  check('إعلان للجميع: المعلّق لا يصله', !copies.includes(P.N));

  // ٢) «ربط بالشجرة» من الإدارة: N يُدمج في سجل الشجرة T
  await q(`insert into notifications(target_member_id, title, body, kind) values
    ('${P.T}', 'قديم-T', 'x', 'test'), ('${P.N}', 'خاص-N', 'x', 'test')`);
  const res = await as(P.O, () => q(`select public.merge_member_into_tree($1, $2) r`, [P.N, P.T]));
  check('الدمج نجح', res[0].r.success === true, res[0].r.message);
  const nNotes = (await q(`select title from notifications where target_member_id = $1`, [P.N])).map(r => r.title);
  check(`الدمج: ${fixed ? 'إشعارات T القديمة لا تنتقل' : 'إشعارات T القديمة تنتقل (الخلل)'}`, fixed ? !nNotes.includes('قديم-T') : nNotes.includes('قديم-T'), nNotes.join('، '));
  check('الدمج: إشعارات N نفسه باقية', nNotes.includes('خاص-N'));
  check('الدمج: لا بقايا لإشعار T', fixed ? (await q(`select 1 from notifications where title = 'قديم-T'`)).length === 0 : true);

  // ٣) الربط التلقائي أول دخول: الحساب R يتبنّى ملف الشجرة X
  await q(`insert into notifications(target_member_id, title, body, kind) values ('${P.X}', 'قديم-X', 'x', 'test')`);
  await q(`select public.adopt_tree_profile($1, $2)`, [P.R, P.X]);
  const adopted = (await q(`select full_name from profiles where id = $1`, [P.R]))[0];
  check('الربط التلقائي: الملف انتقل للحساب', adopted?.full_name === 'خالد صلاح', adopted?.full_name ?? 'لا يوجد');
  const rNotes = (await q(`select title from notifications where target_member_id = $1`, [P.R])).map(r => r.title);
  check(`الربط التلقائي: ${fixed ? 'إشعار X القديم لا ينتقل' : 'إشعار X القديم ينتقل (الخلل)'}`, fixed ? !rNotes.includes('قديم-X') : rNotes.includes('قديم-X'), rNotes.join('، ') || 'لا شيء');
  check('الربط التلقائي: X حُذف وروابطه سليمة', (await q(`select 1 from profiles where id = $1`, [P.X])).length === 0);

  // ٤) بعد الربط: الإعلانات الجديدة تصل للحساب الجديد (في معيار الأجهزة: بعد تسجيل جهازه)
  if (devicesOnly) await q(`insert into device_tokens(member_id, token) values ('${P.R}', 'tok-r-00000000000000000000')`);
  await q(`insert into notifications(target_member_id, title, body, kind) values (null, 'إعلان٢', 'نص', 'admin_broadcast')`);
  const newCopies = (await q(`select target_member_id t from notifications where title = 'إعلان٢'`)).map(r => r.t);
  check('بعد الربط: الإعلان الجديد يصل للحساب R', newCopies.includes(P.R));
}

console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
