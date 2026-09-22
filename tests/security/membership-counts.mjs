import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
const id=n=>'10000000-0000-0000-0000-'+String(n).padStart(12,'0');
await db.exec(`create role anon; create role authenticated; create schema auth;
create table auth.users(id uuid primary key,raw_app_meta_data jsonb,raw_user_meta_data jsonb,last_sign_in_at timestamptz);
create table profiles(id uuid primary key,role text,status text,is_deceased boolean,phone_number text);
create function current_user_role() returns text language sql stable as $$select current_setting('request.app_role',true)$$;`);
for(let n=1;n<=8;n++) await db.query('insert into profiles values($1,$2,$3,$4,$5)',[
 id(n),n===6?'pending':'member',n===3?'frozen':n===4?'deleted':n===5?'pending':'active',n===7,null
]);
// Phone-only approved profile: not proof of sign-in.
await db.query('update profiles set phone_number=$1 where id=$2',['synthetic-phone',id(2)]);
// Direct Auth mapping; blank/hidden phone must still count after a real sign-in.
await db.query('insert into auth.users values($1,null,null,now())',[id(1)]);
// Created Auth account without login is not counted.
await db.query('insert into auth.users values($1,null,null,null)',[id(2)]);
for(let n=3;n<=7;n++) await db.query('insert into auth.users values($1,null,null,now())',[id(n)]);
// Two Auth identities for one server-owned profile mapping count once.
for(let n=9;n<=10;n++) await db.query('insert into auth.users values($1,$2,null,now())',[id(n),JSON.stringify({profile_id:id(8)})]);
// User-editable metadata must not turn phone-only profile into a logged-in member.
await db.query('insert into auth.users values($1,null,$2,now())',[id(11),JSON.stringify({profile_id:id(2)})]);
await db.exec(await fs.readFile('supabase/migrations/20260907180000_membership_counts.sql','utf8'));
await db.exec('set role anon');
await assert.rejects(db.query('select admin_membership_counts()'),/permission denied/);
await db.exec("reset role; set role authenticated; set request.app_role='member'");
await assert.rejects(db.query('select admin_membership_counts()'),/not_authorized/);
await db.exec("set request.app_role='frozen'");
await assert.rejects(db.query('select admin_membership_counts()'),/not_authorized/);
await db.exec("set request.app_role='admin'");
let counts=(await db.query('select admin_membership_counts() as counts')).rows[0].counts;
assert.equal(counts.in_system,2);
assert.equal(counts.total_members,3);
assert.deepEqual(Object.keys(counts).sort(),['checked_at','in_system','total_members']);
await db.exec('reset role');
await db.query('update auth.users set last_sign_in_at=now() where id=$1',[id(2)]);
await db.exec("set role authenticated; set request.app_role='owner'");
counts=(await db.query('select admin_membership_counts() as counts')).rows[0].counts;
assert.equal(counts.in_system,3);
console.log('PASS: actual sign-in, trusted profile binding, hidden phones, unique members, account status/deceased exclusion and admin-only aggregate');
await db.close();
