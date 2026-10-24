import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

type Config = {
  hookSecret: string;
  username: string;
  password: string;
  sender: string;
  test: boolean;
  language: "ar" | "en";
  hashKey: string;
  supabaseURL: string;
  serviceKey: string;
};
const json = (body: unknown, status = 200) => Response.json(body, { status });
const fail = (status: number, message: string) =>
  json({ error: { http_code: status, message } }, status);
// نفس قيد app_settings.sms_sender (20261020170000)
export const SENDER = /^[A-Za-z0-9 -]{1,11}$/;
// «انتظر N ثانية» يصل التطبيق: Supabase Auth يقرأ error من رد 200 ويرد للتطبيق بـ http_code ونص الرسالة.
// أي رد 4xx/5xx من الخطّاف يصل التطبيق «500: Service currently unavailable due to hook» بلا نص (سجل Auth ٢٠٢٦-١٠-١٩).
export const waitMessage = (seconds: number) =>
  `Please wait ${seconds} seconds before requesting another code`;

// Kuwait-only by design: international routes must be separately enabled and reviewed.
export function normalizePhone(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const phone = value.replace(/^\+|^00/, "");
  return /^965[4569][0-9]{7}$/.test(phone) ? phone : null;
}
// نص المالك (٢٠٢٦-١٠-١٩): ٥٣ حرفاً — رسالة عربية وحدة (≤ ٧٠ حرف = نقطة وحدة)، وفيها اسم التطبيق كما تشترط KWT SMS
export function messageFor(otp: string, language: "ar" | "en"): string {
  return language === "ar"
    ? `عائلة المحمدعلي: رمز الدخول ${otp}. لا تشاركه مع أحد.`
    : `Your Al-Mohammadali Family app login code is ${otp}. Do not share this code.`;
}
// نص المالك من app_config (sms_otp_template / sms_otp_template_en، 20261021120000) — يصل مع الحجز (p_format 3).
// يُستعمل فقط إن كان سليماً: نص فيه {code} مرة واحدة، سطر واحد بلا رموز تحكم، ورسالة واحدة بنقطة واحدة
// (العربي ≤ ٧٠ وحدة UCS-2؛ الإنجليزي ≤ ١٦٠ حرف GSM أساسي بلا [ ] { } \ ^ ~ | `). أي شيء آخر ← النص المدمج أعلاه.
// قيود السيرفر نفسها في private.app_config_text_problem، فهذا خط دفاع ثانٍ لا يوقف الدخول أبداً.
export function messageFrom(
  template: unknown,
  otp: string,
  language: "ar" | "en",
): string {
  const builtIn = messageFor(otp, language);
  if (typeof template !== "string" || template.split("{code}").length !== 2) {
    return builtIn;
  }
  const text = template.replace("{code}", otp);
  if (!text.trim() || /[\u0000-\u001f\u007f]/.test(text)) return builtIn;
  if (language === "ar") return text.length <= 70 ? text : builtIn;
  return text.length <= 160 && /^[\x20-\x7E]+$/.test(text) &&
      !/[[\]{}\\^~|`]/.test(text)
    ? text
    : builtIn;
}

async function digest(key: string, text: string): Promise<string> {
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
  )
    .map((b) => b.toString(16).padStart(2, "0")).join("");
}
async function boundedBody(req: Request): Promise<string> {
  const reader = req.body?.getReader();
  if (!reader) throw Error("empty");
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 32768) {
        await reader.cancel();
        throw Error("too large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

export function createHandler(
  config: () => Config,
  send: typeof fetch = fetch,
) {
  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") return fail(405, "Method not allowed");
    const c = config();
    if (
      !c.hookSecret || !c.username || c.username.length > 15 || !c.password ||
      c.password.length > 30 ||
      c.hashKey.length < 32 || !c.serviceKey ||
      !/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(c.supabaseURL) ||
      // المرسل المشترك «KWT-SMS» مسموح (قرار المالك ٢٠٢٦-١٠-١٩: بدون Sender ID خاص حالياً) —
      // أبطأ ولا يوصل لأرقام DND/Virgin؛ يتبدّل بـ KWTSMS_SENDER لما يُعتمد مرسل خاص
      !/^[a-zA-Z0-9 -]{1,11}$/.test(c.sender)
    ) {
      return fail(503, "SMS sender is not configured");
    }
    let raw: string;
    let payload: { user?: { phone?: unknown }; sms?: { otp?: unknown } } | null;
    try {
      raw = await boundedBody(req);
      payload = new Webhook(c.hookSecret.replace(/^v1,whsec_/, ""))
        .verify(raw, Object.fromEntries(req.headers)) as typeof payload;
    } catch {
      return fail(401, "Invalid hook signature");
    }
    const mobile = normalizePhone(payload?.user?.phone);
    const otp = payload?.sms?.otp;
    if (!mobile || typeof otp !== "string" || !/^[0-9]{6}$/.test(otp)) {
      return fail(400, "Invalid SMS recipient or code");
    }
    // Test-mode sends must never be accepted as successful real Auth deliveries.
    // Integration tests call this hook directly using a signed synthetic payload.
    const event = await digest(
      c.hashKey,
      `event:${c.test}:${req.headers.get("webhook-id")}:${raw}`,
    );
    const phone = await digest(c.hashKey, `phone:${mobile}`);
    const post = (name: string, body: unknown) =>
      send(`${c.supabaseURL}/rest/v1/rpc/${name}`, {
        method: "POST",
        signal: AbortSignal.timeout(800),
        headers: {
          "Content-Type": "application/json",
          apikey: c.serviceKey,
          Authorization: `Bearer ${c.serviceKey}`,
        },
        body: JSON.stringify(body),
      });
    const rpc = async (name: string, body: unknown) => {
      const response = await post(name, body);
      if (!response.ok) throw Error("storage unavailable");
      return await response.json();
    };
    // «محاولات الدخول» (20261020160000، طلب المالك ٢٠٢٦-١٠-٢٠): الرقم والنتيجة فقط — الرمز لا يصل هذا السجل.
    // بأفضل جهد: نفس المهلة القصيرة، الأخطاء تُبلع، والرد لا يتغيّر. بعد الإرسال يجري بالتوازي مع finish
    // فلا يطوّل الطريق (مهلة Auth للخطّاف ٥ ثوانٍ). الوضع التجريبي ← «test» (إلا المحجوب فيبقى «blocked»).
    const logAttempt = async (
      outcome: "sent" | "failed" | "unknown" | "blocked",
    ) => {
      try {
        const response = await post("log_login_attempt", {
          p_phone: mobile,
          p_outcome: c.test && outcome !== "blocked" ? "test" : outcome,
        });
        await response.body?.cancel();
        if (!response.ok) throw Error("log unavailable");
      } catch {
        console.error("[kwtsms] login attempt log failed");
      }
    };
    // «اعرض الرمز» للمالك وحده (20261021080000، طلب المالك ٢٠٢٦-١٠-٢١): بعد قبول KWT فقط، ولا في الوضع التجريبي
    // (Supabase ما يحفظ الرمز إذا رد الخطّاف بخطأ). يُحفظ ٥ دقائق في مخطط private، وكل عرض يُسجَّل.
    // بأفضل جهد مثل logAttempt: نفس المهلة، الأخطاء تُبلع، والرد لا يتغيّر.
    const storeCode = async (code: string) => {
      if (c.test) return;
      try {
        const response = await post("store_login_code", {
          p_phone: mobile,
          p_code: code,
        });
        await response.body?.cancel();
        if (!response.ok) throw Error("code store unavailable");
      } catch {
        console.error("[kwtsms] login code store failed");
      }
    };
    // الحدود يعدّلها المالك (20261020170000): p_format 2 ← «send:<المرسل>» و«blocked:<ثوانٍ>». p_format 3
    // (20261021120000) ← «send» كـ JSON فيه المرسل ونص الرسالة؛ قاعدة قبله (أو بعد تراجعه) ترد كالصيغة ٢ فيبقى النص المدمج.
    // قاعدة قبل 20261020170000 (أو بعد تراجعه) لا تعرف المعامل فيرد PostgREST بـ 404 — الدالة ما اشتغلت فلا حجز —
    // فنعيد مرة بالعقد القديم. انقطاع/مهلة لا يُعاد (قد يكون الحجز انحفظ).
    let reservation: unknown;
    try {
      const args = { p_event: event, p_phone: phone, p_test: c.test };
      let response = await post("reserve_kwtsms_send", {
        ...args,
        p_format: 3,
      });
      if (response.status === 404) {
        await response.body?.cancel();
        response = await post("reserve_kwtsms_send", args);
      }
      if (!response.ok) throw Error("storage unavailable");
      reservation = await response.json();
    } catch {
      return fail(503, "SMS service is temporarily unavailable");
    }
    // «accepted» = إعادة Supabase لحدث أُرسل فعلاً — نفس المحاولة، فلا تُسجَّل مرة ثانية
    if (reservation === "accepted") {
      return c.test ? fail(503, "SMS test mode is enabled") : json({});
    }
    const reply = typeof reservation === "string" ? reservation : "";
    const wait = /^blocked:([0-9]{1,6})$/.exec(reply);
    if (wait) {
      await logAttempt("blocked");
      const seconds = Math.min(Math.max(Number(wait[1]), 1), 3600);
      return json({ error: { http_code: 429, message: waitMessage(seconds) } });
    }
    // p_format 3: {"action":"send","sender":…,"template":…,"template_en":…} — JSON تالف أو action آخر = رد غريب
    let detailed: Record<string, unknown> | null = null;
    if (reply.startsWith("{")) {
      try {
        const parsed = JSON.parse(reply);
        if (parsed && typeof parsed === "object" && parsed.action === "send") {
          detailed = parsed;
        }
      } catch {
        detailed = null;
      }
    }
    const go = detailed ? null : /^send(?::(.*))?$/s.exec(reply);
    if (!detailed && !go) {
      // «blocked» بلا ثوانٍ (حدث مكرر، أو قاعدة قديمة) وأي رد غريب: كما كان حرفياً
      await logAttempt("blocked");
      return fail(429, "Please wait a minute before requesting another code");
    }
    // المرسل المحفوظ (kwtsms-admin «set_sender» بعد التحقق من قائمة KWT)؛ بلا قيمة أو قيمة غريبة ← الافتراضي
    const stored = detailed
      ? (typeof detailed.sender === "string" ? detailed.sender : undefined)
      : go![1];
    const sender = stored !== undefined && SENDER.test(stored) ? stored : c.sender;
    // نص الرسالة: من الإعدادات إن وصل سليماً، وإلا المدمج
    const message = messageFrom(
      detailed?.[c.language === "ar" ? "template" : "template_en"],
      otp,
      c.language,
    );

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
          // سبب الفشل (20261020150000) — يُرسل فقط عند الفشل، فالإرسال الناجح بنفس العقد القديم
          ...(errorCode ? { p_error_code: errorCode } : {}),
        });
      } catch {
        console.error("[kwtsms] outcome persistence failed");
      }
    };
    try {
      // Fixed destination, POST JSON; no credentials in URLs or client-side code.
      const response = await send("https://www.kwtsms.com/API/send/", {
        method: "POST",
        signal: AbortSignal.timeout(2500),
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify({
          username: c.username,
          password: c.password,
          sender,
          mobile,
          message,
          test: c.test ? "1" : "0",
        }),
      });
      const result = await response.json().catch(() => null);
      if (
        !response.ok || result?.result !== "OK" || result?.numbers !== 1 ||
        typeof result?.["msg-id"] !== "string" ||
        !/^[a-zA-Z0-9-]{1,64}$/.test(result["msg-id"])
      ) {
        const code = /^ERR[0-9]{3}$/.test(result?.code)
          ? result.code
          : !response.ok
          ? `HTTP_${response.status}`
          : "BAD_RESPONSE";
        console.error("[kwtsms] rejected", response.status, code);
        await Promise.all([
          finish("failed", null, null, null, code),
          logAttempt("failed"),
        ]);
        return fail(503, "SMS provider could not accept the message");
      }
      const number = (v: unknown) =>
        typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : null;
      await Promise.all([
        finish(
          "accepted",
          result["msg-id"],
          number(result["points-charged"]),
          number(result["balance-after"]),
        ),
        logAttempt("sent"),
        storeCode(otp),
      ]);
      // No automatic retries: timeout/ambiguous result may already have incurred a send.
      return c.test ? fail(503, "SMS test mode is enabled") : json({});
    } catch (e) {
      console.error("[kwtsms] transport failure");
      await Promise.all([
        finish(
          "unknown",
          null,
          null,
          null,
          (e as Error)?.name === "TimeoutError" ? "TIMEOUT" : "NETWORK",
        ),
        logAttempt("unknown"),
      ]);
      return fail(503, "SMS service is temporarily unavailable");
    }
  };
}
