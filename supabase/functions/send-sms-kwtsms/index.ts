import { createHandler } from "./handler.ts";

Deno.serve(createHandler(() => ({
  hookSecret: Deno.env.get("SEND_SMS_HOOK_SECRET") ?? "",
  username: Deno.env.get("KWTSMS_USERNAME") ?? "",
  password: Deno.env.get("KWTSMS_PASSWORD") ?? "",
  // بدون Sender ID خاص (قرار المالك ٢٠٢٦-١٠-١٩) ← المرسل المشترك KWT-SMS
  sender: Deno.env.get("KWTSMS_SENDER") || "KWT-SMS",
  test: Deno.env.get("KWTSMS_TEST_MODE") !== "false",
  language: Deno.env.get("KWTSMS_LANGUAGE") === "en" ? "en" : "ar",
  hashKey: Deno.env.get("KWTSMS_HASH_KEY") ?? "",
  supabaseURL: Deno.env.get("SUPABASE_URL") ?? "",
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
})));
