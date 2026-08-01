import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";
import { json } from "./cors.ts";

/// إنشاء Supabase client مع service role
export function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !key) throw new Error("Missing Supabase env");
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/// التحقق من JWT والدور
export async function authenticateRequest(
  req: Request,
  allowedRoles?: string[]
): Promise<
  | { user: { id: string }; role: string }
  | Response
> {
  const authHeader = req.headers.get("authorization") ?? "";
  if (!authHeader) {
    return json(401, { ok: false, message: "Missing authorization" });
  }

  const client = createServiceClient();
  const token = authHeader.replace("Bearer ", "");
  const {
    data: { user },
  } = await client.auth.getUser(token);

  if (!user) {
    return json(401, { ok: false, message: "Invalid token" });
  }

  const { data: profile } = await client
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .single();

  const role = profile?.role ?? "member";

  if (allowedRoles && !allowedRoles.includes(role)) {
    return json(403, {
      ok: false,
      message: `Role '${role}' not allowed`,
    });
  }

  return { user: { id: user.id }, role };
}

/// Parse JSON body بأمان
export async function parseBody<T>(req: Request): Promise<T | Response> {
  try {
    return (await req.json()) as T;
  } catch {
    return json(400, { ok: false, message: "Invalid JSON body" });
  }
}
