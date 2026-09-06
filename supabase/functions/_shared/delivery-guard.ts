import { createServiceClient } from "./auth.ts";
import { json } from "./cors.ts";

// A database reservation is shared by all Edge isolates, including cold starts.
// It records an attempt, not proof of provider delivery. Unknown outcomes aren't resent.
export async function deliveryGuard(scope: string, actor: string, key: unknown, limit = 10, dedupeSeconds = 300): Promise<Response | null> {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(key)));
  const digest = Array.from(new Uint8Array(hash), b => b.toString(16).padStart(2, "0")).join("");
  const { data, error } = await createServiceClient().rpc("reserve_delivery_attempt", {
    p_scope: scope, p_actor: actor, p_key: digest, p_limit: limit, p_dedupe_seconds: dedupeSeconds,
  });
  if (error) {
    console.error(JSON.stringify({ event: "delivery_guard_unavailable", scope }));
    return json(503, { ok: false, message: "Delivery temporarily unavailable" });
  }
  if (data === "duplicate") return json(202, { ok: true, duplicate: true, delivery: "previous_attempt_not_retried" });
  if (data !== "allowed") return json(429, { ok: false, message: "Too many requests. Please try again later." });
  return null;
}
