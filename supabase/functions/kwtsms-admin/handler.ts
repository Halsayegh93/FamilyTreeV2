// kwtsms-admin — إجراءات صفحة «رسائل الدخول · KWT SMS» للمالك والمدير (مُعدّة ٢٠٢٦-١٠-٢٠، لم تُنشر).
// بيانات دخول KWT تبقى على السيرفر (Edge Secrets) ولا تخرج في أي رد أو سجل. روابط KWT ثابتة، POST JSON،
// مهلة لكل طلب، بلا إعادة محاولة (الإرسال الغامض قد يكون خُصم). الأرقام لا تُسجَّل ولا تُرجع.
//   balance  — الرصيد الحي (+ يُحفظ في السجل اليومي)       senderid — المرسلون المعتمدون في الحساب
//   coverage — الدول المفعّلة                               status   — حالة رسالة برقمها (+ تُحفظ على الإرسال)
//   validate — فحص رقم كويتي واحد                           test_send — المالك فقط، لرقم ملفه، مرة كل ١٠ دقائق
//   set_sender — المالك فقط: اسم المرسل من قائمة KWT المعتمدة حرفياً (null = الافتراضي) ← app_settings.sms_sender
//   unlock — المالك فقط: يفك قفل «الطلبات المتكررة» عن رقم ويمسح سجل طلباته (20261023120000)
//   (20261020170000). المرسل «المستخدم» في balance/senderid/test_send = المحفوظ، وإلا الافتراضي — نفس قاعدة send-sms-kwtsms.
import { profileAllowed, trustedProfileId } from "../_shared/auth-policy.ts";
// عميل KWT (القراءة المحدودة، الأرقام، رمز الخطأ، النداء) مشترك مع kwtsms-cron — نُقل حرفياً بلا تغيير سلوك
import { kwtCall, num, providerCode, readBounded, readJson } from "../_shared/kwtsms-client.ts";

export type Config = {
  username: string;
  password: string;
  sender: string;
  test: boolean;
  hashKey: string;
  supabaseURL: string;
  serviceKey: string;
};
export const ACTIONS = [
  "balance",
  "senderid",
  "coverage",
  "status",
  "validate",
  "test_send",
  "set_sender",
  "unlock",
] as const;
type Action = typeof ACTIONS[number];
// ٣٧ حرفاً — رسالة عربية واحدة (≤ ٧٠ حرف = نقطة واحدة)، وليست رمز دخول
export const TEST_MESSAGE = "رسالة اختبار من تطبيق عائلة المحمدعلي";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MSGID = /^[A-Za-z0-9-]{1,64}$/;
const STATUS = /^[A-Za-z0-9 _.:-]{1,40}$/;
// نفس قيد app_settings.sms_sender ونفس فحص send-sms-kwtsms
const SENDER = /^[A-Za-z0-9 -]{1,11}$/;

const reply = (status: number, body: Record<string, unknown>) =>
  Response.json(body, { status });
const fail = (status: number, code: string, extra: Record<string, unknown> = {}) =>
  reply(status, { ok: false, error: { code, ...extra } });

// نفس قاعدة send-sms-kwtsms (الكويت فقط: 965 + ٨ أرقام تبدأ بـ 4/5/6/9) — handler_test يتأكد أنهما متطابقتان
export function normalizePhone(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const phone = value.replace(/^\+|^00/, "");
  return /^965[4569][0-9]{7}$/.test(phone) ? phone : null;
}
// نفس بصمة send-sms-kwtsms (HMAC بمفتاح KWTSMS_HASH_KEY) حتى تنطبق مهلة الرقم بين الدالتين
export async function digest(key: string, text: string): Promise<string> {
  const encoder = new TextEncoder();
  const imported = await crypto.subtle.importKey(
    "raw",
    encoder.encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return Array.from(
    new Uint8Array(
      await crypto.subtle.sign("HMAC", imported, encoder.encode(text)),
    ),
  ).map((b) => b.toString(16).padStart(2, "0")).join("");
}

const strings = (v: unknown, pattern: RegExp, max: number): string[] =>
  Array.isArray(v)
    ? [...new Set(v.filter((x): x is string => typeof x === "string" && pattern.test(x)))].slice(0, max)
    : [];

export function createHandler(
  config: () => Config,
  send: typeof fetch = fetch,
  now: () => number = Date.now,
) {
  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") return fail(405, "method_not_allowed");
    const c = config();
    if (
      !c.username || c.username.length > 15 || !c.password || c.password.length > 30 ||
      c.hashKey.length < 32 || !c.serviceKey ||
      !/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(c.supabaseURL) ||
      !/^[a-zA-Z0-9 -]{1,11}$/.test(c.sender)
    ) {
      return fail(503, "not_configured");
    }
    const jwt = (req.headers.get("authorization") ?? "").match(
      /^Bearer ([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)$/,
    )?.[1];
    if (!jwt || jwt.length > 8192) return fail(401, "unauthorized");
    // deno-lint-ignore no-explicit-any
    let body: any;
    try {
      body = JSON.parse(await readBounded(req.body, 4096));
    } catch {
      return fail(400, "bad_request");
    }
    const service = {
      "Content-Type": "application/json",
      Accept: "application/json",
      apikey: c.serviceKey,
      Authorization: `Bearer ${c.serviceKey}`,
    };

    // ١) الهوية: Supabase Auth يتحقق من الـ JWT (لا نثق بمحتواه بدونه)
    // deno-lint-ignore no-explicit-any
    let user: any;
    try {
      const response = await send(`${c.supabaseURL}/auth/v1/user`, {
        method: "GET",
        signal: AbortSignal.timeout(3000),
        headers: { apikey: c.serviceKey, Authorization: `Bearer ${jwt}` },
      });
      if (response.status === 401 || response.status === 403) {
        return fail(401, "unauthorized");
      }
      if (!response.ok) return fail(503, "auth_unavailable");
      user = await readJson(response, 32768);
    } catch {
      return fail(503, "auth_unavailable");
    }
    if (typeof user?.id !== "string" || !UUID.test(user.id)) {
      return fail(401, "unauthorized");
    }
    // ٢) الدور من قاعدة البيانات بنفس منطق current_profile_id()/current_user_role() (app_metadata، لا user_metadata)
    let profileId: string;
    try {
      profileId = trustedProfileId(user);
    } catch {
      return fail(403, "forbidden");
    }
    const action = body?.action as Action;
    // deno-lint-ignore no-explicit-any
    let profile: any;
    try {
      const columns = action === "test_send" ? "id,role,status,phone_number" : "id,role,status";
      const response = await send(
        `${c.supabaseURL}/rest/v1/profiles?id=eq.${profileId}&select=${columns}&limit=1`,
        { method: "GET", signal: AbortSignal.timeout(3000), headers: service },
      );
      if (!response.ok) throw Error("profile lookup");
      const rows = await readJson(response, 32768);
      profile = Array.isArray(rows) ? rows[0] ?? null : null;
    } catch {
      return fail(503, "storage_unavailable");
    }
    if (!profileAllowed(profile, ["owner", "admin"])) return fail(403, "forbidden");
    if (!ACTIONS.includes(action)) return fail(400, "bad_action");

    const rpc = async (name: string, args: Record<string, unknown>) => {
      const response = await send(`${c.supabaseURL}/rest/v1/rpc/${name}`, {
        method: "POST",
        signal: AbortSignal.timeout(3000),
        headers: service,
        body: JSON.stringify(args),
      });
      if (!response.ok) throw Error("storage unavailable");
      return await readJson(response);
    };
    // نداء KWT واحد: رابط ثابت، بلا إعادة محاولة. يرمي عند انقطاع/مهلة فقط (../_shared/kwtsms-client.ts).
    const kwt = (endpoint: string, extra: Record<string, string> = {}) => kwtCall(send, c, endpoint, extra, 8000);
    // المرسل المستخدم: المحفوظ في app_settings، وإلا (لا قيمة، قيمة غريبة، تعذّر القراءة، قاعدة قبل الترحيل) الافتراضي
    const inUseSender = async (): Promise<string> => {
      try {
        const response = await send(
          `${c.supabaseURL}/rest/v1/app_settings?select=sms_sender&order=updated_at.desc&limit=1`,
          { method: "GET", signal: AbortSignal.timeout(3000), headers: service },
        );
        if (!response.ok) {
          await response.body?.cancel();
          return c.sender;
        }
        const rows = await readJson(response, 4096);
        const value = Array.isArray(rows) ? rows[0]?.sms_sender : null;
        return typeof value === "string" && SENDER.test(value) ? value : c.sender;
      } catch {
        return c.sender;
      }
    };
    const providerFail = (code: string) => {
      console.error(`[kwtsms-admin] ${action} provider ${code}`);
      return fail(502, "provider_error", { provider_code: code });
    };

    try {
      if (action === "balance") {
        const r = await kwt("balance");
        const available = num(r.data?.available);
        if (!r.ok || available === null) return providerFail(providerCode(r.data));
        let stored = true;
        try {
          await rpc("record_kwtsms_balance", { p_balance: available });
        } catch {
          stored = false;
        }
        return reply(200, {
          ok: true,
          balance: available,
          purchased: num(r.data?.purchased),
          test_mode: c.test,
          sender: await inUseSender(),
          stored,
        });
      }
      if (action === "senderid") {
        const r = await kwt("senderid");
        if (!r.ok) return providerFail(providerCode(r.data));
        const senders = strings(r.data?.senderid, /^[A-Za-z0-9 ._-]{1,11}$/, 50);
        const inUse = await inUseSender();
        return reply(200, { ok: true, senders, in_use: inUse, in_use_listed: senders.includes(inUse) });
      }
      if (action === "coverage") {
        const r = await kwt("coverage");
        if (!r.ok) return providerFail(providerCode(r.data));
        const prefixes = strings(r.data?.prefixes, /^[0-9]{1,4}$/, 300);
        return reply(200, { ok: true, prefixes, kuwait: prefixes.includes("965") });
      }
      if (action === "status") {
        const msgid = body?.msgid;
        if (typeof msgid !== "string" || !MSGID.test(msgid)) return fail(400, "bad_msgid");
        const r = await kwt("status", { msgid });
        let status: string;
        if (r.ok) {
          status = typeof r.data?.status === "string" && STATUS.test(r.data.status)
            ? r.data.status
            : "unknown";
        } else if (["ERR029", "ERR030"].includes(providerCode(r.data))) {
          // ٢٩: الرسالة غير موجودة · ٣٠: عالقة في الطابور بخطأ — حالتان للرسالة نفسها، تنحفظان
          status = providerCode(r.data);
        } else {
          return providerFail(providerCode(r.data));
        }
        let stored = false;
        try {
          stored = (await rpc("record_kwtsms_delivery_status", { p_msgid: msgid, p_status: status })) === true;
        } catch {
          stored = false;
        }
        return reply(200, { ok: true, msgid, status, stored });
      }
      if (action === "validate") {
        const phone = normalizePhone(body?.phone);
        if (!phone) return fail(400, "kuwait_only");
        const r = await kwt("validate", { mobile: phone });
        if (!r.ok) return providerFail(providerCode(r.data));
        const has = (k: string) => Array.isArray(r.data?.mobile?.[k]) && r.data.mobile[k].includes(phone);
        const verdict = has("OK") ? "valid" : has("NR") ? "no_route" : has("ER") ? "invalid" : "unknown";
        return reply(200, { ok: true, verdict });
      }

      if (action === "set_sender") {
        // المالك فقط. مرسل غير معتمد في KWT يوقف كل رسائل الدخول، فلا يُحفظ إلا ما في قائمة الحساب حرفياً.
        // الرجوع للافتراضي (null) لا ينتظر KWT: لو تعذّرت القائمة يُحفظ ويرجع senders = null.
        if (profile.role !== "owner") return fail(403, "owner_only");
        if (!Object.hasOwn(body, "sender")) return fail(400, "bad_sender");
        const wanted = body.sender;
        if (wanted !== null && (typeof wanted !== "string" || !SENDER.test(wanted))) {
          return fail(400, "bad_sender");
        }
        let senders: string[] | null = null;
        try {
          const r = await kwt("senderid");
          if (r.ok) senders = strings(r.data?.senderid, /^[A-Za-z0-9 ._-]{1,11}$/, 50);
          else if (wanted !== null) return providerFail(providerCode(r.data));
        } catch (e) {
          if (wanted !== null) throw e; // ← 504 بلا حفظ
        }
        if (wanted !== null && !(senders ?? []).includes(wanted)) {
          return fail(409, "sender_not_approved", { senders });
        }
        let stored: unknown;
        try {
          stored = await rpc("set_kwtsms_sender", { p_sender: wanted, p_by: profileId });
        } catch {
          return fail(503, "storage_unavailable");
        }
        const current = typeof stored === "string" && SENDER.test(stored) ? stored : null;
        return reply(200, {
          ok: true,
          sender: current,
          in_use: current ?? c.sender,
          default: c.sender,
          source: current === null ? "default" : "settings",
          senders,
        });
      }

      if (action === "unlock") {
        // المالك فقط — البصمة نفسها التي يقفل بها send-sms-kwtsms (HMAC «phone:<الرقم>»)
        if (profile.role !== "owner") return fail(403, "owner_only");
        const target = normalizePhone(body?.phone);
        if (!target) return fail(400, "kuwait_only");
        if (c.hashKey.length < 32) return fail(503, "not_configured");
        try {
          const result = await rpc("kwtsms_unlock_number", { p_phone_hash: await digest(c.hashKey, `phone:${target}`) });
          return reply(200, {
            ok: true,
            was_locked: result?.was_locked === true,
            cleared_requests: typeof result?.cleared_requests === "number" ? result.cleared_requests : 0,
          });
        } catch {
          return fail(503, "storage_unavailable");
        }
      }

      // test_send — المالك فقط، لرقم ملفه هو فقط
      if (profile.role !== "owner") return fail(403, "owner_only");
      const mobile = normalizePhone(profile.phone_number);
      if (!mobile) return fail(400, "no_phone");
      const event = await digest(c.hashKey, `admin_test:${profileId}:${now()}:${crypto.randomUUID()}`);
      const phone = await digest(c.hashKey, `phone:${mobile}`);
      // نفس المرسل اللي ترسل به رموز الدخول — «اختبار إرسال لرقمي» بعد تغييره يثبت أنه يوصل
      const sender = await inUseSender();
      let reservation: unknown;
      try {
        reservation = await rpc("reserve_kwtsms_admin_test", { p_event: event, p_phone: phone, p_test: c.test });
      } catch {
        return fail(503, "storage_unavailable");
      }
      if (reservation === "wait") return fail(429, "wait_10_minutes");
      if (reservation !== "send") return fail(429, "rate_limited");
      const finish = async (
        outcome: string,
        msgid: string | null = null,
        charged: number | null = null,
        balance: number | null = null,
        errorCode: string | null = null,
      ) => {
        try {
          await rpc("finish_kwtsms_send", {
            p_event: event,
            p_outcome: outcome,
            p_msgid: msgid,
            p_charged: charged,
            p_balance: balance,
            ...(errorCode ? { p_error_code: errorCode } : {}),
          });
        } catch {
          console.error("[kwtsms-admin] outcome persistence failed");
        }
      };
      let r: Awaited<ReturnType<typeof kwt>>;
      try {
        r = await kwt("send", {
          sender,
          mobile,
          message: TEST_MESSAGE,
          test: c.test ? "1" : "0",
        });
      } catch (e) {
        await finish("unknown", null, null, null, (e as Error)?.name === "TimeoutError" ? "TIMEOUT" : "NETWORK");
        return fail(504, "provider_unavailable");
      }
      const msgid = r.data?.["msg-id"];
      if (!r.ok || r.data?.numbers !== 1 || typeof msgid !== "string" || !MSGID.test(msgid)) {
        const code = providerCode(r.data) !== "UNKNOWN"
          ? providerCode(r.data)
          : r.status >= 400 ? `HTTP_${r.status}` : "BAD_RESPONSE";
        await finish("failed", null, null, null, code);
        return providerFail(code);
      }
      const points = num(r.data["points-charged"]);
      const balance = num(r.data["balance-after"]);
      await finish("accepted", msgid, points, balance);
      return reply(200, { ok: true, test_mode: c.test, msgid, points, balance });
    } catch {
      // انقطاع أو مهلة مع KWT (غير test_send): لا إعادة محاولة
      console.error(`[kwtsms-admin] ${action} transport failure`);
      return fail(504, "provider_unavailable");
    }
  };
}
