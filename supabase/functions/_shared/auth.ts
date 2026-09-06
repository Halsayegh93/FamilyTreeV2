import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";
import { json } from "./cors.ts";
import { trustedProfileId, profileAllowed, type AuthOptions } from "./auth-policy.ts";

export function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !key) throw new Error("Missing Supabase env");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

export async function authenticateRequest(req: Request, allowedRoles?: string[], options: AuthOptions = {}) {
  const match = (req.headers.get("authorization") ?? "").match(/^Bearer\s+(\S+)$/i);
  if (!match) return json(401, { ok: false, message: "Missing authorization" });
  const client = createServiceClient();
  const { data: { user }, error } = await client.auth.getUser(match[1]);
  if (error || !user) return json(401, { ok: false, message: "Invalid token" });
  let profileId: string;
  try { profileId = trustedProfileId(user); }
  catch { return json(403, { ok: false, message: "Invalid profile binding" }); }
  const { data: profile, error: profileError } = await client.from("profiles")
    .select("id,role,status").eq("id", profileId).maybeSingle();
  if (profileError) return json(503, { ok: false, message: "Unable to verify account" });
  if (!profileAllowed(profile, allowedRoles, options)) return json(403, { ok: false, message: "Account not authorized" });
  return { user: { id: user.id }, profileId, role: profile?.role ?? null, status: profile?.status ?? null };
}

export async function parseBody<T>(req: Request): Promise<T | Response> {
  try { return (await req.json()) as T; }
  catch { return json(400, { ok: false, message: "Invalid JSON body" }); }
}
