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
    if (auth.role === "owner") return json(403, { ok: false, message: "Owner account is protected" });
    const client = createServiceClient();
    await deleteAccountWorkflow({
      async prepare() {
        const { data, error } = await client.rpc("prepare_account_deletion", {
          p_auth_id: auth.user.id, p_profile_id: auth.profileId,
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
        const { error } = await client.rpc("finalize_account_deletion", { p_auth_id: auth.user.id });
        if (error) throw error;
      },
      async deleteAuth() {
        const { error } = await client.auth.admin.deleteUser(auth.user.id);
        if (error) throw error;
      },
    });
    return json(200, { ok: true, message: "Account deleted" });
  } catch {
    console.error("Account deletion incomplete; retry the retained cleanup job");
    return json(500, { ok: false, message: "Account cleanup incomplete. Please retry." });
  }
});
