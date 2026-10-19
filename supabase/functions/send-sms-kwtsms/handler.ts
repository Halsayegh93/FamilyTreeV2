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
    const rpc = async (name: string, body: unknown) => {
      const response = await send(`${c.supabaseURL}/rest/v1/rpc/${name}`, {
        method: "POST",
        signal: AbortSignal.timeout(800),
        headers: {
          "Content-Type": "application/json",
          apikey: c.serviceKey,
          Authorization: `Bearer ${c.serviceKey}`,
        },
        body: JSON.stringify(body),
      });
      if (!response.ok) throw Error("storage unavailable");
      return await response.json();
    };
    let reservation: unknown;
    try {
      reservation = await rpc("reserve_kwtsms_send", {
        p_event: event,
        p_phone: phone,
        p_test: c.test,
      });
    } catch {
      return fail(503, "SMS service is temporarily unavailable");
    }
    if (reservation === "accepted") {
      return c.test ? fail(503, "SMS test mode is enabled") : json({});
    }
    if (reservation !== "send") {
      return fail(429, "Please wait a minute before requesting another code");
    }

    const finish = async (
      outcome: string,
      msgid: string | null = null,
      charged: number | null = null,
      balance: number | null = null,
    ) => {
      try {
        await rpc("finish_kwtsms_send", {
          p_event: event,
          p_outcome: outcome,
          p_msgid: msgid,
          p_charged: charged,
          p_balance: balance,
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
          sender: c.sender,
          mobile,
          message: messageFor(otp, c.language),
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
          : "UNKNOWN";
        console.error("[kwtsms] rejected", response.status, code);
        await finish("failed");
        return fail(503, "SMS provider could not accept the message");
      }
      const number = (v: unknown) =>
        typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : null;
      await finish(
        "accepted",
        result["msg-id"],
        number(result["points-charged"]),
        number(result["balance-after"]),
      );
      // No automatic retries: timeout/ambiguous result may already have incurred a send.
      return c.test ? fail(503, "SMS test mode is enabled") : json({});
    } catch {
      console.error("[kwtsms] transport failure");
      await finish("unknown");
      return fail(503, "SMS service is temporarily unavailable");
    }
  };
}
