// kwtsms-cron — فحص رصيد KWT SMS اليومي (طلب المالك ٢٠٢٦-١٠-٢٠، الميزة ٣). مُعدّة ولم تُنشر.
// تستدعيها قاعدة البيانات فقط: مهمة pg_cron «kwtsms-daily-balance» (٠٦:٠٠ UTC = ٠٩:٠٠ الكويت) ← public.kwtsms_daily_balance_job()
// ← net.http_post بترويسة x-webhook-secret = private.app_secrets «push_webhook_secret» — نفس سرّ ونمط
// trigger_push_on_notification ← push-on-notification (السرّ في الدالة: PUSH_WEBHOOK_SECRET، موجود). verify_jwt = false.
// الخطوات: رصيد KWT الحي (balance) ← RPC kwtsms_balance_check(p_balance) (service_role): يحفظه في السجل اليومي ويطبّق
// نفس قواعد تنبيه الرصيد بعد الإرسال (العتبتان وفواصل التكرار من app_settings، نفس النوع والعنوان والنص، بلا تكرار).
// مهلة لكل طلب، بلا إعادة محاولة، فشل KWT ← لا حفظ ولا تنبيه. لا تُسجَّل بيانات الدخول ولا السرّ أبداً.
import { kwtCall, num, providerCode, readBounded, readJson } from "../_shared/kwtsms-client.ts";

export type Config = {
  webhookSecret: string;
  username: string;
  password: string;
  supabaseURL: string;
  serviceKey: string;
};
export const ACTION = "balance_check";
// فحص وصول رسائل الرمز تلقائياً (طلب المالك ٢٠٢٦-١٠-٢٣ «حط وقت الوصول»): مهمة pg_cron كل دقيقة ← {"action":"status_sweep"}
// ← RPC kwtsms_pending_status_checks (رسائل مقبولة عمرها ١–٣٠ دقيقة بلا حالة نهائية) ← KWT «status» لكل رقم رسالة
// ← record_kwtsms_delivery_status (نفس حفظ «فحص الحالة» اليدوي). مجاني عند KWT، ٢٠ رسالة أقصى بالمرة، بلا إعادة محاولة.
export const SWEEP = "status_sweep";
const MSGID = /^[A-Za-z0-9-]{1,64}$/;
const STATUS = /^[A-Za-z0-9 _.:-]{1,40}$/;

const reply = (status: number, body: Record<string, unknown>) => Response.json(body, { status });
const fail = (status: number, code: string, extra: Record<string, unknown> = {}) =>
  reply(status, { ok: false, error: { code, ...extra } });

// مقارنة بزمن ثابت (لا تكشف طول التطابق)
function sameSecret(given: string | null, expected: string): boolean {
  if (given === null) return false;
  const a = new TextEncoder().encode(given);
  const b = new TextEncoder().encode(expected);
  let diff = a.length ^ b.length;
  for (let i = 0; i < b.length; i++) diff |= (a[i] ?? 0) ^ b[i];
  return diff === 0;
}

export function createHandler(config: () => Config, send: typeof fetch = fetch) {
  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") return fail(405, "method_not_allowed");
    const c = config();
    // ١) الهوية: سرّ النظام فقط (لا JWT ولا مستخدمين)
    if (!c.webhookSecret || c.webhookSecret.length < 16) return fail(503, "not_configured");
    if (!sameSecret(req.headers.get("x-webhook-secret"), c.webhookSecret)) {
      await req.body?.cancel();
      return fail(401, "unauthorized");
    }
    if (
      !c.username || c.username.length > 15 || !c.password || c.password.length > 30 || !c.serviceKey ||
      !/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(c.supabaseURL)
    ) {
      await req.body?.cancel();
      return fail(503, "not_configured");
    }
    // ٢) الطلب: {"action":"balance_check"} فقط
    // deno-lint-ignore no-explicit-any
    let body: any;
    try {
      body = JSON.parse(await readBounded(req.body, 1024));
    } catch {
      return fail(400, "bad_request");
    }
    if (body?.action === SWEEP) return await sweep(c, send);
    if (body?.action !== ACTION) return fail(400, "bad_action");

    // ٣) الرصيد الحي — انقطاع/مهلة/رد غير صالح ← لا حفظ ولا تنبيه
    let available: number | null;
    try {
      const r = await kwtCall(send, c, "balance", {}, 8000);
      available = num(r.data?.available);
      if (!r.ok || available === null) {
        const code = providerCode(r.data);
        console.error(`[kwtsms-cron] balance provider ${code}`);
        return fail(502, "provider_error", { provider_code: code });
      }
    } catch {
      console.error("[kwtsms-cron] balance transport failure");
      return fail(504, "provider_unavailable");
    }

    // ٤) الحفظ + قواعد التنبيه (في قاعدة البيانات)
    try {
      const response = await send(`${c.supabaseURL}/rest/v1/rpc/kwtsms_balance_check`, {
        method: "POST",
        signal: AbortSignal.timeout(3000),
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          apikey: c.serviceKey,
          Authorization: `Bearer ${c.serviceKey}`,
        },
        body: JSON.stringify({ p_balance: available }),
      });
      if (!response.ok) {
        await response.body?.cancel();
        throw Error("storage unavailable");
      }
      const result = await readJson(response, 4096);
      return reply(200, {
        ok: true,
        balance: available,
        state: typeof result?.state === "string" ? result.state : null,
        alerted: result?.alerted === true,
      });
    } catch {
      console.error("[kwtsms-cron] balance check persistence failed");
      return fail(503, "storage_unavailable", { balance: available });
    }
  };
}

async function rpcCall(c: Config, send: typeof fetch, name: string, args: unknown, limit = 65536) {
  const response = await send(`${c.supabaseURL}/rest/v1/rpc/${name}`, {
    method: "POST",
    signal: AbortSignal.timeout(3000),
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      apikey: c.serviceKey,
      Authorization: `Bearer ${c.serviceKey}`,
    },
    body: JSON.stringify(args),
  });
  if (!response.ok) {
    await response.body?.cancel();
    throw Error("storage unavailable");
  }
  return await readJson(response, limit);
}

async function sweep(c: Config, send: typeof fetch): Promise<Response> {
  let ids: string[];
  try {
    const list = await rpcCall(c, send, "kwtsms_pending_status_checks", { p_limit: 20 });
    ids = (Array.isArray(list) ? list : []).filter((x): x is string => typeof x === "string" && MSGID.test(x)).slice(0, 20);
  } catch {
    console.error("[kwtsms-cron] status sweep: pending list unavailable");
    return fail(503, "storage_unavailable");
  }
  let checked = 0, stored = 0;
  for (const msgid of ids) {
    let status: string | null = null;
    try {
      const r = await kwtCall(send, c, "status", { msgid }, 5000);
      if (r.ok) {
        status = typeof r.data?.status === "string" && STATUS.test(r.data.status) ? r.data.status : "unknown";
      } else if (["ERR029", "ERR030"].includes(providerCode(r.data))) {
        status = providerCode(r.data);
      }
    } catch {
      status = null;
    }
    if (status === null) continue;
    checked++;
    try {
      if ((await rpcCall(c, send, "record_kwtsms_delivery_status", { p_msgid: msgid, p_status: status }, 1024)) === true) stored++;
    } catch {
      // التالي — بلا إعادة محاولة
    }
  }
  return reply(200, { ok: true, action: SWEEP, pending: ids.length, checked, stored });
}
