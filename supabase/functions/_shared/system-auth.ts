import { json } from "./cors.ts";

export function systemAuthorized(req: Request, serviceKey: string, webhookSecret: string): boolean {
  const bearer = (req.headers.get("authorization") ?? "").match(/^Bearer\s+(\S+)$/i)?.[1];
  return (!!serviceKey && bearer === serviceKey) ||
    (!!webhookSecret && req.headers.get("x-webhook-secret") === webhookSecret);
}

export function requireSystem(req: Request): Response | null {
  if (req.method !== "POST") return json(405, { ok: false, message: "POST required" });
  return systemAuthorized(req, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "", Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "")
    ? null : json(401, { ok: false, message: "System authorization required" });
}
