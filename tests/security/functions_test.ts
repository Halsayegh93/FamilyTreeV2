import { profileAllowed, trustedProfileId } from "../../supabase/functions/_shared/auth-policy.ts";
import { canSendEvent, withVerifiedRecipient } from "../../supabase/functions/_shared/event-policy.ts";
import { deleteAccountWorkflow, type DeletionBackend } from "../../supabase/functions/_shared/delete-account-workflow.ts";
import { strict as assert } from "node:assert";

Deno.test("identity ignores editable metadata and fails closed on malformed trusted bindings",()=>{
  const user={id:"10000000-0000-0000-0000-000000000001",user_metadata:{profile_id:"spoof"}};
  assert.equal(trustedProfileId(user),user.id);
  assert.throws(()=>trustedProfileId({...user,app_metadata:{profile_id:"broken"}}));
  assert.equal(trustedProfileId({...user,app_metadata:{profile_id:"20000000-0000-0000-0000-000000000002"}}),"20000000-0000-0000-0000-000000000002");
});
Deno.test("frozen and missing administrators never pass privileged authentication",()=>{
  const p={id:"x",role:"admin",status:"frozen"};
  assert.equal(profileAllowed(p,["admin"]),false);
  assert.equal(profileAllowed(null,["admin"]),false);
  assert.equal(profileAllowed({...p,status:"active"},["admin"]),true);
  assert.equal(profileAllowed(p,undefined,{allowInactive:true}),true);
  assert.equal(profileAllowed(null,undefined,{allowMissingProfile:true,allowInactive:true}),true);
});
Deno.test("members cannot send official mail; addresses always come from verified records",()=>{
  for(const type of ["role_changed","status_changed","contact_reply"]){
    assert.equal(canSendEvent(type,"member","active"),false);
    assert.equal(canSendEvent(type,"owner","frozen"),false);
  }
  assert.equal(canSendEvent("role_changed","admin","active"),false);
  assert.equal(canSendEvent("role_changed","owner","active"),true);
  assert.equal(canSendEvent("join_request","pending","pending"),true);
  assert.equal(canSendEvent("join_request","member","active"),false);
  const p=withVerifiedRecipient({member_email:"attacker@example.invalid",member_name:"spoof"},{email:"verified@example.invalid",full_name:"Verified",phone_number:null});
  assert.equal(p.member_email,"verified@example.invalid"); assert.equal(p.member_name,"Verified");
});
Deno.test("storage failure prevents data/auth deletion and retry completes in order",async()=>{
  const calls:string[]=[];let fail=true;
  const backend:DeletionBackend={
    async prepare(){calls.push("prepare");return [{bucket:"avatars",path:"cover_test.jpg"}]},
    async remove(){calls.push("storage");if(fail)throw Error("unavailable")},
    async finalize(){calls.push("database")}, async deleteAuth(){calls.push("auth")},
  };
  await assert.rejects(()=>deleteAccountWorkflow(backend));
  assert.deepEqual(calls,["prepare","storage"]);
  calls.length=0;fail=false;await deleteAccountWorkflow(backend);
  assert.deepEqual(calls,["prepare","storage","database","auth"]);
});
Deno.test("database failure prevents auth deletion; auth failure is not reported as success",async()=>{
  const backend:DeletionBackend={async prepare(){return []},async remove(){},async finalize(){throw Error("db")},async deleteAuth(){assert.fail("must not delete auth")}};
  await assert.rejects(()=>deleteAccountWorkflow(backend),/db/);
  await assert.rejects(()=>deleteAccountWorkflow({...backend,async finalize(){},async deleteAuth(){throw Error("auth")}}),/auth/);
});

import { systemAuthorized } from "../../supabase/functions/_shared/system-auth.ts";
import { ownsPendingRequest, requestTitle } from "../../supabase/functions/_shared/admin-request-policy.ts";
Deno.test("maintenance rejects anonymous/user JWT and missing system configuration",()=>{
  const req=(headers:Record<string,string>={})=>new Request("https://example.invalid",{method:"POST",headers});
  assert.equal(systemAuthorized(req(),"",""),false);
  assert.equal(systemAuthorized(req({authorization:"Bearer user-jwt"}),"service-secret","hook-secret"),false);
  assert.equal(systemAuthorized(req({authorization:"Bearer service-secret"}),"service-secret","hook-secret"),true);
  assert.equal(systemAuthorized(req({"x-webhook-secret":"hook-secret"}),"service-secret","hook-secret"),true);
});
Deno.test("admin alerts require an owned pending record and use server-defined titles",()=>{
  const row={id:"r",member_id:"target",requester_id:"sender",request_type:"tree_edit",status:"pending"};
  assert.equal(ownsPendingRequest(row,"sender"),true);
  assert.equal(ownsPendingRequest(row,"target"),false);
  assert.equal(ownsPendingRequest({...row,status:"approved"},"sender"),false);
  assert.equal(ownsPendingRequest(null,"sender"),false);
  assert.equal(requestTitle("malicious text"),"طلب جديد للإدارة");
});
