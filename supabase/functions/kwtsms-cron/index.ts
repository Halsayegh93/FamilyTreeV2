// kwtsms-cron — فحص الرصيد اليومي، تستدعيه قاعدة البيانات فقط (يُنشر بـ --no-verify-jwt؛ السرّ يُفحص داخل الدالة)
import { createHandler } from "./handler.ts";

Deno.serve(createHandler(() => ({
  // نفس سرّ push-on-notification (private.app_secrets «push_webhook_secret» في قاعدة البيانات)
  webhookSecret: Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "",
  username: Deno.env.get("KWTSMS_USERNAME") ?? "",
  password: Deno.env.get("KWTSMS_PASSWORD") ?? "",
  supabaseURL: Deno.env.get("SUPABASE_URL") ?? "",
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
})));
