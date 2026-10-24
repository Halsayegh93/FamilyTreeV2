// kwtsms-admin — للمالك والمدير (يُنشر بـ verify_jwt الافتراضي = true؛ الدالة تتحقق من المستخدم ودوره بنفسها أيضاً)
import { createHandler } from "./handler.ts";

Deno.serve(createHandler(() => ({
  username: Deno.env.get("KWTSMS_USERNAME") ?? "",
  password: Deno.env.get("KWTSMS_PASSWORD") ?? "",
  // نفس المرسل والوضع اللي تستخدمهما send-sms-kwtsms
  sender: Deno.env.get("KWTSMS_SENDER") || "KWT-SMS",
  test: Deno.env.get("KWTSMS_TEST_MODE") !== "false",
  hashKey: Deno.env.get("KWTSMS_HASH_KEY") ?? "",
  supabaseURL: Deno.env.get("SUPABASE_URL") ?? "",
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
})));
