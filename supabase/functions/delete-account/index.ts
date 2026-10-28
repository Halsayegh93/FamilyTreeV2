import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { handleCors, validatePost, json } from "../_shared/cors.ts";
import { authenticateRequest, createServiceClient } from "../_shared/auth.ts";
import { deleteAccountWorkflow, type DeletionFile } from "../_shared/delete-account-workflow.ts";

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  const method = validatePost(req);
  if (method) return method;
  try {
    // Frozen / already anonymized accounts must be able to retry partial cleanup.
    const auth = await authenticateRequest(req, undefined, { allowInactive: true, allowMissingProfile: true });
    if (auth instanceof Response) return auth;
    const client = createServiceClient();

    // Admin mode (privacy policy art. 9, 2026-10-28): the member files an `account_delete` request
    // in the app; the owner/an admin completes it here with { request_id } within 7 days.
    let body: { request_id?: string } = {};
    try { body = await req.json(); } catch { body = {}; }
    let targetAuthId = auth.user.id;
    let targetProfileId = auth.profileId;
    let requestId: string | null = null;
    if (body.request_id) {
      if (auth.role !== "owner" && auth.role !== "admin") return json(403, { ok: false, message: "not_allowed" });
      const { data: r, error: rErr } = await client.from("admin_requests")
        .select("id,member_id,request_type,status").eq("id", body.request_id).maybeSingle();
      if (rErr) throw rErr;
      if (!r || r.request_type !== "account_delete") return json(404, { ok: false, message: "request_not_found" });
      if (r.status !== "pending") return json(409, { ok: false, message: "already_handled" });
      const { data: target } = await client.from("profiles").select("id,role").eq("id", r.member_id).maybeSingle();
      if (!target) return json(404, { ok: false, message: "member_not_found" });
      if (target.role === "owner") return json(403, { ok: false, message: "Owner account is protected" });
      const { data: authId, error: aErr } = await client.rpc("account_auth_id", { p_profile_id: r.member_id });
      if (aErr) throw aErr;
      if (!authId) return json(404, { ok: false, message: "no_login_account" });
      targetAuthId = authId as string;
      targetProfileId = r.member_id as string;
      requestId = r.id as string;
    } else if (auth.role === "owner") {
      return json(403, { ok: false, message: "Owner account is protected" });
    }

    await deleteAccountWorkflow({
      async prepare() {
        const { data, error } = await client.rpc("prepare_account_deletion", {
          p_auth_id: targetAuthId, p_profile_id: targetProfileId,
        });
        if (error) throw error;
        if (!data || !Array.isArray(data.storage_files)) throw new Error("Invalid cleanup job");
        return data.storage_files as DeletionFile[];
      },
      async remove(bucket, paths) {
        const { error } = await client.storage.from(bucket).remove(paths);
        if (error) throw error;
      },
      async finalize() {
        const { error } = await client.rpc("finalize_account_deletion", { p_auth_id: targetAuthId });
        if (error) throw error;
      },
      async deleteAuth() {
        const { error } = await client.auth.admin.deleteUser(targetAuthId);
        if (error) throw error;
      },
    });
    if (requestId) {
      await client.from("admin_requests").update({
        status: "approved", replied_at: new Date().toISOString(), replied_by: auth.profileId,
      }).eq("id", requestId);
    }
    return json(200, { ok: true, message: "Account deleted" });
  } catch {
    console.error("Account deletion incomplete; retry the retained cleanup job");
    return json(500, { ok: false, message: "Account cleanup incomplete. Please retry." });
  }
});
