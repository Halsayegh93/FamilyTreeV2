/// CORS headers — مشترك بين كل الـ Edge Functions
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/// JSON response helper
export function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

/// Handle CORS preflight
export function handleCors(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return null;
}

/// Validate POST method
export function validatePost(req: Request): Response | null {
  if (req.method !== "POST") {
    return json(405, { ok: false, message: "Method not allowed" });
  }
  return null;
}
