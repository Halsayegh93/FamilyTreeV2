// بيئة مشتركة لتجارب إعدادات السيرفر (20261021110000…150000) — قاعدة PGlite معزولة، لا تلمس السيرفر.
// base.sql (الهوية والملفات والمحفّزات كما في الحي) + app_settings بأعمدة الحي التي تقرؤها الترحيلات + مخطط private +
// صلاحيات Supabase الافتراضية (كل جدول/دالة جديدة تُمنح لـ anon/authenticated/service_role) حتى يُثبت أن السحب يعمل.
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const REPO = fileURLToPath(new URL('../../', import.meta.url));
export const read = f => readFileSync(`${REPO}/${f}`, 'utf8');
export const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
// المالك، مدير، مراقب، مشرف، عضوان، مدير مجمّد، عضو مجمّد، مسجّل معلّق، سجل مبدئي بلا اسم (أول دخول)، عضو شجرة لم يُفعَّل
export const P = { O: id(1), A: id(2), MON: id(3), S: id(4), M: id(5), M2: id(6), FA: id(7), FM: id(8), PEND: id(9),
  NEW: id(10), TREE: id(11), GHOST: id(12) };
export const ROLES = { O: 'owner', A: 'admin', MON: 'monitor', S: 'supervisor', M: 'member', M2: 'member', FA: 'frozen',
  FM: 'frozen', PEND: 'pending', NEW: 'pending', TREE: 'pending' };

export const MIGS = {
  config: '20261021110000_app_config',
  reads: '20261021120000_app_config_server_reads',
  guards: '20261021130000_registration_and_device_guards',
  edits: '20261021140000_profile_edit_limit',
  terms: '20261021150000_terms_acceptance',
};
export const mig = k => read(`migrations/${MIGS[k]}.sql`);
export const rb = k => read(`rollback/${MIGS[k]}_rollback.sql`);

export function counter() {
  const s = { pass: 0, fail: 0 };
  s.ok = (c, m, x = '') => { c ? s.pass++ : s.fail++; console.log(`${c ? '✅' : '❌'} ${m}${!c && x !== '' ? ' — ' + x : ''}`); };
  s.done = () => { console.log(`\nالنتيجة: ${s.pass} نجحت، ${s.fail} فشلت`); process.exit(s.fail ? 1 : 0); };
  return s;
}

export async function makeDb() {
  const db = new PGlite();
  await db.exec(`
    create or replace function public.women_auto_merge_wife() returns trigger language plpgsql as $f$ begin return new; end $f$;`);
  await db.exec(readFileSync(new URL('./base.sql', import.meta.url), 'utf8'));
  await db.exec(`
    do $$ begin
      if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if;
    end $$;
    grant usage on schema public to anon, authenticated, service_role;
    grant usage on schema auth to anon, authenticated, service_role;
    grant execute on all functions in schema auth to anon, authenticated, service_role;
    grant select, insert, update, delete on public.profiles, public.admin_requests, public.device_tokens to authenticated, service_role;
    alter role service_role bypassrls;   -- كما في Supabase
    create schema private;
    -- app_settings: أعمدة الحي التي تقرؤها الترحيلات (20260309100000، 20261020170000، 20261020180000، 20261021100000)
    create table public.app_settings (
      id uuid primary key default gen_random_uuid(),
      news_requires_approval boolean not null default true,
      allow_new_registrations boolean not null default true,
      max_devices_per_user integer not null default 3,
      sms_wait_seconds integer not null default 60 check (sms_wait_seconds between 30 and 600),
      death_alert_days integer not null default 7 check (death_alert_days between 1 and 30),
      updated_at timestamptz not null default now(),
      updated_by uuid references public.profiles(id));
    insert into public.app_settings (id) values ('00000000-0000-0000-0000-000000000001');
    alter table public.app_settings enable row level security;
    create policy "Authenticated users can read app_settings" on public.app_settings for select to authenticated using (true);
    create policy "Owner can update app_settings" on public.app_settings for update to authenticated
      using (public.current_user_role() = 'owner') with check (public.current_user_role() = 'owner');
    grant select, update on public.app_settings to authenticated;
    insert into public.profiles (id, first_name, full_name, role, status, phone_number) values
      ('${P.O}', 'حسن', 'المالك', 'owner', 'active', '+96590000001'),
      ('${P.A}', 'بدر', 'المدير', 'admin', 'active', '+96590000002'),
      ('${P.MON}', 'علي', 'المراقب', 'monitor', 'active', '+96590000003'),
      ('${P.S}', 'سعد', 'المشرف', 'supervisor', 'active', '+96590000004'),
      ('${P.M}', 'أحمد', 'عضو', 'member', 'active', '+96590000005'),
      ('${P.M2}', 'خالد', 'عضو ثان', 'member', 'active', '+96590000006'),
      ('${P.FA}', 'مجمد', 'مدير مجمّد', 'admin', 'frozen', '+96590000007'),
      ('${P.FM}', 'مجمد', 'عضو مجمّد', 'member', 'frozen', '+96590000008'),
      ('${P.PEND}', 'جديد', 'مسجّل معلّق', 'pending', 'pending', '+96590000009'),
      ('${P.NEW}', '', '', 'member', 'pending', '+96590000010'),
      ('${P.TREE}', 'شجرة', 'عضو شجرة لم يُفعَّل', 'member', 'pending', '+96590000011');
    -- صلاحيات Supabase الافتراضية: كل جديد يُمنح للتطبيقات — الترحيل يجب أن يسحبها بنفسه
    alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
    alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
    alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;`);
  return db;
}

// who: مفتاح من P (جلسة authenticated بمعرّفه)، أو 'anon'، أو 'service'، أو {sub, pid} (حساب منقول)
export async function as(db, who, sql, params = []) {
  let role = 'authenticated', claims;
  if (who === 'anon') { role = 'anon'; claims = { role: 'anon' }; }
  else if (who === 'service') { role = 'service_role'; claims = { role: 'service_role' }; }
  else if (typeof who === 'string') claims = { sub: P[who] ?? who, role: 'authenticated' };
  else claims = { sub: who.sub, role: 'authenticated', app_metadata: { profile_id: who.pid } };
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify(claims)]);
  // داخل معاملة (tx): نقطة حفظ حتى لا يُفسد خطأ متوقَّع بقية المعاملة
  if (db.__inTx) await db.exec('savepoint s_as');
  await db.exec(`set role ${role}`);
  try { const r = await db.query(sql, params); return { ok: true, rows: r.rows, n: r.affectedRows ?? r.rows.length }; }
  catch (e) {
    if (db.__inTx) await db.exec('rollback to savepoint s_as');
    return { ok: false, err: e.message, code: e.code, hint: e.hint, detail: e.detail };
  }
  finally { await db.exec('reset role'); await db.query(`select set_config('request.jwt.claims', '', false)`); }
}

// تشغيل داخل معاملة تُلغى في الآخر: نفس البيانات لكل مقارنة
export async function tx(db, fn) {
  await db.exec('begin'); db.__inTx = true;
  try { return await fn(); } finally { db.__inTx = false; await db.exec('rollback'); }
}

export const one = async (db, q, p = []) => (await db.query(q, p)).rows[0];
export const val = async (db, q, p = []) => Object.values((await db.query(q, p)).rows[0] ?? {})[0];
export const md5fn = async (db, sig) => val(db, `select md5(pg_get_functiondef('${sig}'::regprocedure))`);
export const acl = async (db, sig) => val(db, `select coalesce(proacl::text, '') from pg_proc where oid = '${sig}'::regprocedure`);
export const canExec = async (db, who, sig) => val(db, `select has_function_privilege('${who}', '${sig}', 'execute')`);
