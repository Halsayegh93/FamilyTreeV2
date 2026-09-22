import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { handleCors, validatePost, json } from "../_shared/cors.ts";
import { authenticateRequest, createServiceClient, parseBody } from "../_shared/auth.ts";

serve(async (req) => {
  const cors = handleCors(req); if (cors) return cors;
  const method = validatePost(req); if (method) return method;
  try {
    const auth = await authenticateRequest(req, ["owner", "admin"]);
    if (auth instanceof Response) return auth;
    const body = await parseBody<{ memberId?: string }>(req);
    if (body instanceof Response) return body;
    if (!body || typeof body.memberId !== "string" || !/^[0-9a-f-]{36}$/i.test(body.memberId)) {
      return json(400, { ok: false, message: "memberId required" });
    }
    const client = createServiceClient();
    const { data: profile, error: lookupError } = await client.from("profiles")
      .select("id,role").eq("id", body.memberId).maybeSingle();
    if (lookupError) throw lookupError;
    if (!profile) return json(404, { ok: false, message: "Member not found" });
    if (profile.role === "owner" || profile.id === auth.profileId) {
      return json(403, { ok: false, message: "Protected account" });
    }
    // Freeze/clear in one transaction first; an auth error is retryable, never success.
    const { data: authIds, error: unlinkError } = await client.rpc("prepare_phone_unlink", { p_profile_id: profile.id });
    if (unlinkError) throw unlinkError;
    for (const id of authIds ?? []) {
      const { error } = await client.auth.admin.deleteUser(id);
      if (error && error.code !== "user_not_found") throw error;
    }
    return json(200, { ok: true, message: "Phone unlinked" });
  } catch {
    return json(500, { ok: false, message: "Phone unlink incomplete. Please retry." });
  }
});
