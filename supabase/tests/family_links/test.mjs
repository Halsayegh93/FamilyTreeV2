// تجربة حماية روابط العائلة على قاعدة محلية معزولة (لا تلمس السيرفر).
// التشغيل: cd supabase/tests/family_links && npm install && node test.mjs
// base.sql = نسخة من السيرفر الحي قبل 20261001150000 (الجداول والدوال والمشغّلات المعنية).
// تُشغَّل كل السيناريوهات مرتين: قبل الحماية (يتكرر الخلل) وبعدها (يجب أن تنجح كلها).
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? '', (e.query ?? '').slice(0, 300)); process.exit(2); });

const REPO = fileURLToPath(new URL('../../', import.meta.url));
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody, rest] = base.split('-- ─── المشغّلات');
const baseTriggers = rest.slice(rest.indexOf('\n') + 1);
const rollback = readFileSync(`${REPO}/rollback/20261001150000_protect_family_links_rollback.sql`, 'utf8');
const migrations = ['20261001150000_protect_family_links', '20261001190000_carry_own_women_node_links']
  .map(n => readFileSync(`${REPO}/migrations/${n}.sql`, 'utf8'));
const grab = (src, name) => {
  const i = src.indexOf(`create or replace function public.${name}(`);
  return src.slice(i, src.indexOf('$function$;', i) + '$function$;'.length);
};
const liveFns = ['adopt_tree_profile', 'merge_member_into_tree', 'women_auto_merge_wife'].map(n => grab(rollback, n)).join('\n\n');

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const P = { O: id(1), G: id(2), H: id(3), S: id(4), T: id(5), ST: id(6), N: id(7), A: id(8), M2: id(9), M3: id(10), M4: id(11), X: id(12), SS: id(13) };
const W = { HM: id(111), TM: id(112), W: id(101), D1: id(102), D2: id(103), WT: id(104), DT: id(105), W2: id(106), DM: id(107), C1: id(108), C2: id(109), NW: id(110) };
const name = Object.fromEntries([...Object.entries(P), ...Object.entries(W)].map(([k, v]) => [v, k]));
const nm = v => (v == null ? 'NULL' : name[v] ?? v.slice(-4));

let pass = 0, fail = 0;
const check = (label, ok, extra = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${label}${extra ? ' — ' + extra : ''}`); };

async function fresh(level) {
  const db = new PGlite();
  await db.exec(baseBody);
  await db.exec(liveFns);
  await db.exec(baseTriggers);
  for (const m of migrations.slice(0, level)) await db.exec(m);
  const q = async (sql, params) => (await db.query(sql, params)).rows;
  const as = async (uid, fn) => {
    await db.query(`select set_config('request.jwt.claims', $1, false)`, [uid ? JSON.stringify({ sub: uid, role: 'authenticated' }) : '']);
    try { return await fn(); } finally { await db.query(`select set_config('request.jwt.claims', '', false)`); }
  };
  const err = async fn => { try { await fn(); return null; } catch (e) { return e.message; } };
  const one = async (sql, params) => (await q(sql, params))[0];
  // ─── بيانات أولية: الجد G وفرعه، المالك O ───
  await db.exec(`
    insert into profiles(id, first_name, full_name, gender, role, status) values
      ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active'),
      ('${P.G}', 'صلاح', 'صلاح الجد', 'male', 'member', 'active');
    insert into women_members(id, first_name, full_name, gender) values ('${P.G}', 'صلاح', 'صلاح الجد', 'male');
    insert into profiles(id, first_name, full_name, gender, role, status, father_id, phone_number) values
      ('${P.H}', 'حسن', 'حسن صلاح', 'male', 'member', 'active', '${P.G}', '+96590000001'),
      ('${P.T}', 'طاهر', 'طاهر صلاح', 'male', 'member', 'active', '${P.G}', null);
    insert into profiles(id, first_name, full_name, gender, role, status, father_id) values
      ('${P.S}', 'علي', 'علي حسن', 'male', 'member', 'active', '${P.H}'),
      ('${P.ST}', 'محمد', 'محمد طاهر', 'male', 'member', 'active', '${P.T}');
    insert into women_members(id, first_name, full_name, gender, husband_id) values
      ('${W.W}', 'زينب', 'زينب كمال', 'female', '${P.H}'),
      ('${W.WT}', 'مريم', 'مريم', 'female', '${P.T}');
    insert into women_members(id, first_name, full_name, gender, parent_id, mother_id) values
      ('${W.D1}', 'زهراء', 'زهراء حسن', 'female', '${P.H}', '${W.W}'),
      ('${W.D2}', 'حوراء', 'حوراء حسن', 'female', '${P.H}', '${W.W}'),
      ('${W.DT}', 'سارة', 'سارة طاهر', 'female', '${P.T}', '${W.WT}');
    insert into women_members(id, first_name, full_name, gender, husband_id) values
      ('${W.HM}', 'هدى', 'هدى الصالح', 'female', '${P.G}'),
      ('${W.TM}', 'نورية', 'نورية', 'female', '${P.G}');
    update women_members set mother_id = '${W.HM}' where id = '${P.H}';
    update women_members set mother_id = '${W.TM}' where id = '${P.T}';
    insert into profiles(id, first_name, full_name, gender, role, status, phone_number) values
      ('${P.N}', 'طاهر', 'طاهر (تسجيل جديد)', 'male', 'pending', 'pending', '+96590000002');
    insert into auth.users(id, phone) values ('${P.A}', '96590000001');
  `);
  return { db, q, one, as, err };
}

// ═════════ قبل الحماية: إعادة إنتاج الخلل كما على السيرفر اليوم ═════════
console.log('\n══ قبل الحماية (نسخة السيرفر اليوم) ══');
{
  const { q, one, as } = await fresh(0);
  await q(`select adopt_tree_profile($1, $2)`, [P.A, P.H]);
  const m0 = await one(`select mother_id from women_members where id = $1`, [P.A]);
  console.log(`أول دخول (adopt): أم حسن = ${nm(m0?.mother_id)}`);
  const w = await one(`select husband_id from women_members where id = $1`, [W.W]);
  const d = await q(`select parent_id from women_members where id = any($1)`, [[W.D1, W.D2]]);
  console.log(`أول دخول (adopt): زوج زينب = ${nm(w.husband_id)} · أب البنات = ${d.map(r => nm(r.parent_id)).join('، ')}`);
  const r = await as(P.O, () => one(`select merge_member_into_tree($1, $2) as r`, [P.N, P.T]));
  const wt = await one(`select husband_id from women_members where id = $1`, [W.WT]);
  const dt = await one(`select parent_id from women_members where id = $1`, [W.DT]);
  console.log(`ربط بالشجرة (merge): ${r.r.success} · زوج مريم = ${nm(wt.husband_id)} · أب سارة = ${nm(dt.parent_id)}`);
}

// ═════════ بعد الترحيل الأول فقط (الثغرة التي ضيّعت أم المالك) ═════════
console.log('\n══ بعد 20261001150000 فقط ══');
{
  const { q, one, as } = await fresh(1);
  await q(`select adopt_tree_profile($1, $2)`, [P.A, P.H]);
  const m1 = await one(`select mother_id from women_members where id = $1`, [P.A]);
  const r1 = await as(P.O, () => one(`select merge_member_into_tree($1, $2) as r`, [P.N, P.T]));
  const n1 = await one(`select mother_id from women_members where id = $1`, [P.N]);
  console.log(`أول دخول: أم حسن = ${nm(m1?.mother_id)} · ربط بالشجرة: أم طاهر = ${nm(n1?.mother_id)} (${r1.r.success})`);
}

// ═════════ بعد الحماية ═════════
console.log('\n══ بعد الحماية ══');
{
  const { db, q, one, as, err } = await fresh(2);

  // ١) أول دخول: كل الروابط تنتقل للمعرّف الجديد
  await q(`select adopt_tree_profile($1, $2)`, [P.A, P.H]);
  const w = await one(`select husband_id from women_members where id = $1`, [W.W]);
  const d = await q(`select parent_id from women_members where id = any($1) order by id`, [[W.D1, W.D2]]);
  const s = await one(`select father_id from profiles where id = $1`, [P.S]);
  const sMirror = await one(`select parent_id from women_members where id = $1`, [P.S]);
  const aMirror = await one(`select parent_id from women_members where id = $1`, [P.A]);
  const hGone = (await q(`select 1 from profiles where id = $1 union all select 1 from women_members where id = $1`, [P.H])).length === 0;
  check('أول دخول: الزوجة باقية مع زوجها', w.husband_id === P.A, `زوج زينب = ${nm(w.husband_id)}`);
  check('أول دخول: البنات باقيات مع أبيهن', d.every(r => r.parent_id === P.A), d.map(r => nm(r.parent_id)).join('، '));
  check('أول دخول: الابن باقٍ مع أبيه (وعقدته)', s.father_id === P.A && sMirror.parent_id === P.A);
  check('أول دخول: عقدة الجديد تحت جده، والقديم انحذف', aMirror?.parent_id === P.G && hGone);
  const aMom = await one(`select mother_id from women_members where id = $1`, [P.A]);
  check('أول دخول: الأم باقية (هدى الصالح)', aMom.mother_id === W.HM, `أم حسن = ${nm(aMom.mother_id)}`);

  // ٢) ربط بالشجرة: الزوجة والبنت والابن ينتقلون
  const r = await as(P.O, () => one(`select merge_member_into_tree($1, $2) as r`, [P.N, P.T]));
  const wt = await one(`select husband_id from women_members where id = $1`, [W.WT]);
  const dt = await one(`select parent_id from women_members where id = $1`, [W.DT]);
  const st = await one(`select father_id from profiles where id = $1`, [P.ST]);
  check('ربط بالشجرة: نجح', r.r.success === true, r.r.message);
  const nMom = await one(`select mother_id from women_members where id = $1`, [P.N]);
  check('ربط بالشجرة: الأم باقية', nMom.mother_id === W.TM, `أم طاهر = ${nm(nMom.mother_id)}`);
  check('ربط بالشجرة: الزوجة والبنت والابن انتقلوا', wt.husband_id === P.N && dt.parent_id === P.N && st.father_id === P.N,
    `مريم→${nm(wt.husband_id)} سارة→${nm(dt.parent_id)} محمد→${nm(st.father_id)}`);

  // ٣) حذف شخص له أبناء يُرفض برسالة عربية ولا يتغير شيء
  const e1 = await as(P.O, () => err(() => q(`delete from profiles where id = $1`, [P.G])));
  check('حذف الجد (له أبناء) مرفوض', !!e1 && e1.includes('لا يمكن حذف') && e1.includes('٦'), e1 ?? 'انحذف!');

  // ٤) حذف رجل بلا أبناء لكن له زوجة في شجرة النساء يُرفض (هذا ما فصل عائلة المالك)
  await db.exec(`insert into profiles(id, first_name, full_name, gender, role, status, father_id) values ('${P.M2}', 'جاسم', 'جاسم صلاح', 'male', 'member', 'active', '${P.G}');
                 insert into women_members(id, first_name, full_name, gender, husband_id) values ('${W.W2}', 'نورة', 'نورة', 'female', '${P.M2}');`);
  const e2 = await as(P.O, () => err(() => q(`delete from profiles where id = $1`, [P.M2])));
  const w2 = await one(`select husband_id from women_members where id = $1`, [W.W2]);
  check('حذف رجل له زوجة مرفوض والزوجة باقية معه', !!e2 && w2.husband_id === P.M2, e2 ?? 'انحذف!');

  // ٥) حذف عضو بلا عائلة يعمل كالمعتاد
  await db.exec(`insert into profiles(id, first_name, full_name, gender, role, status, father_id) values ('${P.M3}', 'فهد', 'فهد صلاح', 'male', 'member', 'active', '${P.G}');`);
  const e3 = await as(P.O, () => err(() => q(`delete from profiles where id = $1`, [P.M3])));
  const m3 = await q(`select 1 from profiles where id = $1 union all select 1 from women_members where id = $1`, [P.M3]);
  check('حذف عضو بلا عائلة يعمل', !e3 && m3.length === 0, e3 ?? '');

  // ٦) التفريغ الآلي (بلا مستخدم) ممنوع — القيمة تبقى
  await q(`update women_members set husband_id = null where id = $1`, [W.W]);
  await q(`update profiles set father_id = null where id = $1`, [P.S]);
  const w6 = await one(`select husband_id from women_members where id = $1`, [W.W]);
  const s6 = await one(`select father_id from profiles where id = $1`, [P.S]);
  const blocked = await one(`select count(*)::int n from family_link_history where blocked`);
  check('التفريغ الآلي ممنوع (الزوج والأب باقيان) ومسجّل', w6.husband_id === P.A && s6.father_id === P.A && blocked.n === 2, `محاولات ممنوعة = ${blocked.n}`);

  // ٧) الفصل المقصود من العضو نفسه (إزالة زوجته من «عائلتي») يبقى ممكناً ويُسجَّل
  const e7 = await as(P.A, () => err(() => q(`select remove_self_wife($1)`, [W.W])));
  const w7 = await one(`select husband_id from women_members where id = $1`, [W.W]);
  const h7 = await one(`select actor, blocked from family_link_history where member_id = $1 and col = 'husband_id' order by id desc limit 1`, [W.W]);
  check('العضو يقدر يزيل زوجته بنفسه (مقصود) ويُسجَّل باسمه', !e7 && w7.husband_id === null && h7.actor === P.A && !h7.blocked, e7 ?? '');

  // ٨) الصيانة المقصودة بالمفتاح الصريح فقط
  await db.exec(`begin; select set_config('family.allow_unlink', 'on', true); update women_members set parent_id = null where id = '${W.D2}'; commit;`);
  const d8 = await one(`select parent_id from women_members where id = $1`, [W.D2]);
  check('الفصل اليدوي بالمفتاح الصريح يعمل', d8.parent_id === null);
  await q(`update women_members set parent_id = $1 where id = $2`, [P.A, W.D2]); // رجّعها

  // ٩) دمج الزوجة المكررة لا يحذف أمّاً ما زال لها أبناء من زوج آخر
  await db.exec(`
    insert into profiles(id, first_name, full_name, gender, role, status, father_id) values
      ('${P.M4}', 'يوسف', 'يوسف صلاح', 'male', 'member', 'active', '${P.G}'),
      ('${P.X}', 'خالد', 'خالد صلاح', 'male', 'member', 'active', '${P.G}');
    insert into women_members(id, first_name, full_name, gender) values ('${W.DM}', 'فاطمة', 'فاطمة', 'female');
    insert into women_members(id, first_name, full_name, gender, parent_id, mother_id) values
      ('${W.C1}', 'هدى', 'هدى يوسف', 'female', '${P.M4}', '${W.DM}'),
      ('${W.C2}', 'منى', 'منى خالد', 'female', '${P.X}', '${W.DM}');`);
  const e9 = await err(() => q(`insert into women_members(id, first_name, full_name, gender, husband_id) values ($1, 'فاطمة', 'فاطمة', 'female', $2)`, [W.NW, P.M4]));
  const c1 = await one(`select mother_id from women_members where id = $1`, [W.C1]);
  const c2 = await one(`select mother_id from women_members where id = $1`, [W.C2]);
  check('إضافة زوجة تدمج المكررة دون فصل أبناء الزوج الآخر', !e9 && c1.mother_id === W.NW && c2.mother_id === W.DM,
    e9 ?? `هدى→${nm(c1.mother_id)} منى→${nm(c2.mother_id)}`);

  // ١٠) تحويل جنس ابن له أبناء مرفوض (كان يفصل أبناءه)
  await db.exec(`insert into profiles(id, first_name, full_name, gender, role, status, father_id) values ('${P.SS}', 'حسين', 'حسين علي', 'male', 'member', 'active', '${P.S}');`);
  const e10 = await as(P.O, () => err(() => q(`select move_child_gender($1, 'female')`, [P.S])));
  const s10 = await one(`select father_id from profiles where id = $1`, [P.SS]);
  check('تحويل جنس أبٍ له أبناء مرفوض وأبناؤه باقون', !!e10 && s10.father_id === P.S, e10 ?? 'تم التحويل!');

  // ١١) الحاجز الأخير: حتى لو عُطّل الحارس، قاعدة البيانات ترفض الحذف بدل التفريغ
  await db.exec(`alter table profiles disable trigger trg_family_links_protect_delete;`);
  const e11 = await err(() => q(`delete from profiles where id = $1`, [P.G]));
  await db.exec(`alter table profiles enable trigger trg_family_links_protect_delete;`);
  check('الحاجز الأخير (المفتاح الأجنبي) يرفض الحذف', !!e11 && /foreign key|violates/i.test(e11), e11 ?? 'انحذف!');

  // ١٢) حذف الحساب (إخفاء البيانات) لا يلمس الروابط
  await q(`update profiles set first_name = 'عضو محذوف', full_name = 'عضو محذوف', phone_number = null, status = 'deleted' where id = $1`, [P.A]);
  const a12 = await one(`select father_id from profiles where id = $1`, [P.A]);
  const d12 = await one(`select parent_id from women_members where id = $1`, [W.D1]);
  check('حذف الحساب يُبقي الروابط', a12.father_id === P.G && d12.parent_id === P.A);

  // ١٣) المدير يصحّح أب عضو (مقصود) — مسموح، وعقدته تبقى لأن له بنات
  const e13 = await as(P.O, () => err(() => q(`update profiles set father_id = null where id = $1`, [P.N])));
  const n13 = await one(`select father_id from profiles where id = $1`, [P.N]);
  const nNode = await one(`select count(*)::int n from women_members where id = $1`, [P.N]);
  check('تصحيح يدوي من الإدارة مسموح وعقدة الأب تبقى لبناته', !e13 && n13.father_id === null && nNode.n === 1, e13 ?? '');


  // ١٤) ربط بالشجرة لعضو زوجته لها حساب (زوجة في profiles) — الزوجة تنتقل في الجدولين
  const T2 = id(20), N2 = id(21), WP = id(22), B = id(23), H2 = id(24), WB = id(120), DB = id(121);
  await db.exec(`
    insert into profiles(id, first_name, full_name, gender, role, status, father_id) values ('${T2}', 'بدر', 'بدر صلاح', 'male', 'member', 'active', '${P.G}');
    insert into profiles(id, first_name, full_name, gender, role, status, husband_id) values ('${WP}', 'دانة', 'دانة', 'female', 'member', 'active', '${T2}');
    insert into profiles(id, first_name, full_name, gender, role, status) values ('${N2}', 'بدر', 'بدر (تسجيل)', 'male', 'pending', 'pending');`);
  const r14 = await as(P.O, () => one(`select merge_member_into_tree($1, $2) as r`, [N2, T2]));
  const wp = await one(`select husband_id from profiles where id = $1`, [WP]);
  const wpNode = await one(`select husband_id from women_members where id = $1`, [WP]);
  check('ربط بالشجرة: الزوجة صاحبة الحساب تنتقل (الملف وشجرة النساء)', r14.r.success === true && wp.husband_id === N2 && wpNode.husband_id === N2,
    `${r14.r.message} · ملفها→${nm(wp.husband_id) ?? ''} عقدتها→${nm(wpNode.husband_id) ?? ''}`);

  // ١٥) أول دخول وللحساب سجل مبدئي مسبقاً (مسار ربط الرقم) — الزوجة والبنت تنتقلان
  await db.exec(`
    insert into profiles(id, first_name, full_name, gender, role, status, father_id, phone_number) values ('${H2}', 'سلمان', 'سلمان صلاح', 'male', 'member', 'active', '${P.G}', '+96590000003');
    insert into women_members(id, first_name, full_name, gender, husband_id) values ('${WB}', 'لولوة', 'لولوة', 'female', '${H2}');
    insert into women_members(id, first_name, full_name, gender, parent_id, mother_id) values ('${DB}', 'نور', 'نور سلمان', 'female', '${H2}', '${WB}');
    insert into auth.users(id, phone) values ('${B}', '96590000003');
    insert into profiles(id, first_name, full_name, role, status) values ('${B}', '', '', 'pending', 'pending');`);
  await q(`select adopt_tree_profile($1, $2)`, [B, H2]);
  const wb = await one(`select husband_id from women_members where id = $1`, [WB]);
  const dbb = await one(`select parent_id from women_members where id = $1`, [DB]);
  const bp = await one(`select full_name, father_id from profiles where id = $1`, [B]);
  check('أول دخول بسجل مبدئي: الحساب أخذ ملف الشجرة والعائلة معه', bp.full_name === 'سلمان صلاح' && bp.father_id === P.G && wb.husband_id === B && dbb.parent_id === B,
    `لولوة→${nm(wb.husband_id) ?? wb.husband_id} نور→${nm(dbb.parent_id) ?? dbb.parent_id}`);

  const hist = await one(`select count(*)::int n from family_link_history`);
  console.log(`\nسجلّ التاريخ: ${hist.n} تغييراً مسجّلاً`);
}

console.log(`\nالنتيجة: ${pass} نجح · ${fail} فشل`);
process.exit(fail ? 1 : 0);
