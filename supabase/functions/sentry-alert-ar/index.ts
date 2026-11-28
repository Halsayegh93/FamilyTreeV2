// تنبيه الأخطاء بالعربي (طلب المالك ٢٠٢٦-١١-٢٧: إيميلات Sentry إنجليزية — «ابيها بالعربي»).
//
// Sentry ← POST هنا (WebHooks القديم، أو قاعدة تنبيه بإجراء webhook من تكامل داخلي) ← إيميل عربي للمالك + إشعار
// إدارة `app_error` (push عبر `trigger_push_on_notification`، يفتح «الأخطاء» في التطبيق).
//
// الرابط: https://<project>.supabase.co/functions/v1/sentry-alert-ar?key=<SENTRY_ALERT_KEY>   (+ &test=1 للتجربة)
//   • المفتاح في الرابط لأن Sentry لا يرسل ترويسة سرّ — يُقارن بزمن ثابت. بلا مفتاح مضبوط: 503 (مقفول).
//   • verify_jwt = false في config.toml (Sentry لا يحمل جلسة Supabase).
// الحدّ: إيميل واحد لكل خطأ كل ٦ ساعات (`sentry_alert_claim` → private.sentry_alert_log). الأحداث التجريبية تُتجاهل
// إلا مع ?test=1 (وهي لا تُسجَّل في الحدّ ولا تحجبه).
// المستلمون: SENTRY_ALERT_EMAIL_TO إن ضُبط، وإلا إيميل المالكَين المفعّلَين (profiles.email)، وإلا CONTACT_EMAIL_TO.
// الإرسال: Resend بنفس أسرار contact-email (RESEND_API_KEY · CONTACT_EMAIL_FROM).
// التكميل (اختياري): SENTRY_READ_TOKEN نفسه الذي تقرأ به sentry-issues — العدد والأجهزة وأول/آخر ظهور والمنصة.
//
// الردود (Sentry لا يقرؤها، للسجلّ فقط): 200 {ok, emailed, notified} · 200 {ok, skipped} · 401 · 405 · 413 · 502.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { json } from "../_shared/cors.ts";
import { createServiceClient } from "../_shared/auth.ts";
import { buildAlertEmail, parseSentryPayload, type SentryAlert } from "./arabic.ts";

const ORG = Deno.env.get("SENTRY_ORG") ?? "almohaliapp";
const API = "https://sentry.io/api/0";
const WINDOW_HOURS = 6;
const MAX_BODY = 512 * 1024;

/** مقارنة بزمن ثابت (لا تكشف طول التطابق) */
function safeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < y.length; i++) diff |= (x[i] ?? 0) ^ y[i];
  return diff === 0 && y.length > 0;
}

async function sentryGet<T>(token: string, path: string): Promise<T | null> {
  try {
    const res = await fetch(`${API}${path}`, { headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(4000) });
    return res.ok ? await res.json() as T : null;
  } catch { return null; }
}

/** العدد والأجهزة وأول/آخر ظهور والمنصة من Sentry — بلا فشل (ما لم يصل يبقى من الطلب) */
async function enrich(a: SentryAlert): Promise<SentryAlert> {
  const token = Deno.env.get("SENTRY_READ_TOKEN") ?? "";
  if (!token || !a.issueId) return a;
  type Issue = { title?: string; count?: string | number; userCount?: number; firstSeen?: string; lastSeen?: string;
                 platform?: string; permalink?: string; shortId?: string };
  type Tag = { topValues?: { value?: string; count?: number }[] };
  const [issue, appTag] = await Promise.all([
    sentryGet<Issue>(token, `/organizations/${ORG}/issues/${a.issueId}/`),
    a.app ? Promise.resolve(null) : sentryGet<Tag>(token, `/organizations/${ORG}/issues/${a.issueId}/tags/app/`),
  ]);
  const out = { ...a };
  if (issue) {
    const n = Number(issue.count);
    if (Number.isFinite(n)) out.count = n;
    if (typeof issue.userCount === "number") out.userCount = issue.userCount;
    out.firstSeen = issue.firstSeen ?? out.firstSeen;
    out.lastSeen = issue.lastSeen ?? out.lastSeen;
    out.sentryPlatform = out.sentryPlatform ?? issue.platform ?? null;
    out.shortId = issue.shortId ?? out.shortId;
    if (!out.title && issue.title) out.title = issue.title;
    if (!out.url && issue.permalink) out.url = issue.permalink;
  }
  const top = appTag?.topValues?.[0]?.value;
  if (!out.app && top) out.app = top;
  return out;
}

async function recipients(db: ReturnType<typeof createServiceClient>): Promise<string[]> {
  const split = (v: string) => v.split(",").map((s) => s.trim()).filter((s) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(s));
  const explicit = split(Deno.env.get("SENTRY_ALERT_EMAIL_TO") ?? "");
  if (explicit.length) return explicit;
  const { data, error } = await db.from("profiles").select("email").eq("role", "owner").eq("status", "active");
  if (error) console.error("[sentry-alert-ar] owners", error.code);
  const owners = [...new Set((data ?? []).flatMap((r: { email?: string | null }) => split(r.email ?? "")))];
  return owners.length ? owners : split(Deno.env.get("CONTACT_EMAIL_TO") ?? "");
}

async function sendEmail(to: string[], subject: string, text: string, html: string): Promise<boolean> {
  const key = (Deno.env.get("RESEND_API_KEY") ?? "").trim();
  const from = (Deno.env.get("CONTACT_EMAIL_FROM") ?? "").trim();
  if (!key || !from || !to.length) { console.error("[sentry-alert-ar] email not configured"); return false; }
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from, to, subject, text, html }),
      signal: AbortSignal.timeout(10000),
    });
    await res.text();
    if (!res.ok) console.error(JSON.stringify({ event: "email_provider_failed", provider: "resend", status: res.status }));
    return res.ok;
  } catch (e) {
    console.error("[sentry-alert-ar] resend", e instanceof Error ? e.message : "error");
    return false;
  }
}

serve(async (req) => {
  if (req.method !== "POST") return json(405, { ok: false, error: { code: "post_only" } });
  const url = new URL(req.url);
  const expected = (Deno.env.get("SENTRY_ALERT_KEY") ?? "").trim();
  if (!expected) return json(503, { ok: false, error: { code: "not_configured" } });
  if (!safeEqual(url.searchParams.get("key") ?? "", expected)) return json(401, { ok: false, error: { code: "unauthorized" } });
  const test = url.searchParams.get("test") === "1";

  const raw = await req.text();
  if (raw.length > MAX_BODY) return json(413, { ok: false, error: { code: "too_large" } });
  let body: unknown;
  try { body = JSON.parse(raw); } catch { return json(400, { ok: false, error: { code: "bad_json" } }); }

  const parsed = parseSentryPayload(body);
  if (!parsed) return json(200, { ok: true, skipped: "not_an_error" });
  if (parsed.isSample && !test) return json(200, { ok: true, skipped: "test_event" });

  const db = createServiceClient();
  // الحدّ: خطأ حقيقي واحد كل ٦ ساعات. التجربة (?test=1) لا تُحسب
  const limited = !test && parsed.issueId;
  if (limited) {
    const { data: go, error } = await db.rpc("sentry_alert_claim", { p_issue: parsed.issueId, p_hours: WINDOW_HOURS });
    if (error) { console.error("[sentry-alert-ar] claim", error.code); return json(500, { ok: false, error: { code: "db_error" } }); }
    if (go !== true) return json(200, { ok: true, skipped: "rate_limited" });
  }

  const alert = await enrich(parsed);
  const mail = buildAlertEmail(alert, ORG);
  const prefix = test ? "تجربة: " : "";

  const to = await recipients(db);
  const emailed = await sendEmail(to, prefix + mail.subject, mail.text, mail.html);
  const { data: notified, error: notifyErr } = await db.rpc("sentry_alert_notify_owners", {
    p_title: prefix + mail.push.title, p_body: mail.push.body,
  });
  if (notifyErr) console.error("[sentry-alert-ar] notify", notifyErr.code);

  // لا وصل شيء: أعد فتح الحدّ حتى يرسل النداء التالي لنفس الخطأ
  if (limited && !emailed && (notifyErr || !notified)) {
    await db.rpc("sentry_alert_release", { p_issue: parsed.issueId });
    return json(502, { ok: false, error: { code: "delivery_failed" } });
  }
  console.log(JSON.stringify({ event: "sentry_alert_sent", issue: alert.issueId, source: alert.source, test, emailed,
                               recipients: to.length, notified: notified ?? 0 }));
  return json(200, { ok: true, emailed, notified: notified ?? 0 });
});
