import { deliveryGuard } from "../_shared/delivery-guard.ts";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { handleCors, validatePost, json } from "../_shared/cors.ts";
import { authenticateRequest, parseBody } from "../_shared/auth.ts";

/** رد الإدارة — قالب بسيط: الرد أولاً، ثم الرسالة الأصلية مقتبسة. */
type ReplyPayload = {
  to?: string;
  reply?: string;
  member_name?: string;
  original_message?: string;
  category?: string;
};

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const APP_NAME = "عائلة المحمدعلي";
const INK = "#1B2A33";
const MUTED = "#8A97A0";
const LINE = "#E6EBEE";
const ACCENT = "#2B7A9F";
const FONT = "-apple-system,'SF Arabic','Segoe UI','Noto Naskh Arabic',Tahoma,Arial,sans-serif";

function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#039;");
}

function simpleEmail(opts: { greeting: string; reply: string; original: string }): string {
  const original = opts.original
    ? `
      <div style="margin:26px 0 0;padding:16px 18px;border-right:3px solid ${LINE};background:#FAFBFC;border-radius:8px">
        <div style="color:${MUTED};font-size:12px;font-weight:700;margin:0 0 8px">رسالتك الأصلية</div>
        <div style="color:${MUTED};font-size:14.5px;line-height:1.9;white-space:pre-wrap">${esc(opts.original)}</div>
      </div>`
    : "";
  return `<!doctype html>
<html lang="ar" dir="rtl">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(APP_NAME)}</title></head>
<body style="margin:0;padding:0;background:#F4F6F8;font-family:${FONT}">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F4F6F8;padding:28px 14px">
    <tr><td align="center">
      <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="width:100%;max-width:560px;background:#ffffff;border:1px solid ${LINE};border-radius:14px;overflow:hidden">
        <tr><td style="padding:18px 24px;border-bottom:1px solid ${LINE}">
          <span style="color:${ACCENT};font-size:15px;font-weight:800">${esc(APP_NAME)}</span>
        </td></tr>
        <tr><td style="padding:26px 24px 30px;text-align:right">
          <p style="margin:0 0 16px;color:${INK};font-size:16px;font-weight:700">${esc(opts.greeting)}</p>
          <div style="color:${INK};font-size:16px;line-height:2;white-space:pre-wrap">${esc(opts.reply)}</div>
          ${original}
          <p style="margin:28px 0 0;color:${MUTED};font-size:13.5px">مع تحيات إدارة ${esc(APP_NAME)}</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}

serve(async (req) => {
  const cors = handleCors(req); if (cors) return cors;
  const notPost = validatePost(req); if (notPost) return notPost;
  try {
    const auth = await authenticateRequest(req, ["owner", "admin", "monitor", "supervisor"]);
    if (auth instanceof Response) return auth;

    const resendApiKey = (Deno.env.get("RESEND_API_KEY") ?? "").trim();
    const sendgridApiKey = (Deno.env.get("SENDGRID_API_KEY") ?? "").trim();
    const emailFrom = (Deno.env.get("CONTACT_EMAIL_FROM") ?? "").trim();
    const replyTo = (Deno.env.get("CONTACT_EMAIL_TO") ?? "").split(",")[0].trim();
    if (!emailFrom || (!resendApiKey && !sendgridApiKey)) {
      console.error("Missing email env vars");
      return json(500, { ok: false, message: "Email service not configured" });
    }

    const body = await parseBody<ReplyPayload>(req); if (body instanceof Response) return body;
    const to = (body.to ?? "").trim();
    const reply = (body.reply ?? "").trim();
    const memberName = (body.member_name ?? "").trim();
    const original = (body.original_message ?? "").trim();
    const category = (body.category ?? "").trim();

    if (!EMAIL_RE.test(to)) return json(400, { ok: false, message: "invalid recipient email" });
    if (!reply) return json(400, { ok: false, message: "reply is required" });

    if (reply.length > 10000 || original.length > 10000 || category.length > 100) return json(400, { ok: false, message: "Message too long" });
    const limited = await deliveryGuard("admin-reply-email", auth.profileId, [to,reply], 30);
    if (limited) return limited;
    const subject = category ? `رد على رسالتك — ${category}` : "رد على رسالتك";
    // تحية قريبة بدل «عزيزنا» — طلب المالك
    const greeting = memberName ? `حيّاك الله ${memberName}،` : "حيّاك الله،";
    const textBody = [greeting, "", reply, original ? `\n— رسالتك الأصلية —\n${original}` : "", `\nمع تحيات إدارة ${APP_NAME}`]
      .filter((v) => v !== "").join("\n");
    const htmlBody = simpleEmail({ greeting, reply, original });

    if (resendApiKey) {
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${resendApiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ from: emailFrom, to: [to], reply_to: replyTo || undefined, subject, text: textBody, html: htmlBody }),
      });
      if (!response.ok) {
        console.error(JSON.stringify({event:"email_provider_failed", provider:"resend", status:response.status}));
        return json(502, { ok: false, message: "Email delivery failed" });
      }
      return json(200, { ok: true, message: "Reply sent" });
    }

    const fromEmail = emailFrom.includes("<") ? emailFrom.split("<")[1].replace(">", "").trim() : emailFrom;
    const sg = await fetch("https://api.sendgrid.com/v3/mail/send", {
      method: "POST",
      headers: { Authorization: `Bearer ${sendgridApiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        personalizations: [{ to: [{ email: to }] }],
        from: { email: fromEmail },
        reply_to: replyTo ? { email: replyTo } : undefined,
        subject,
        content: [{ type: "text/plain", value: textBody }, { type: "text/html", value: htmlBody }],
      }),
    });
    if (!sg.ok) {
      console.error(`SendGrid failed: ${sg.status} — ${await sg.text()}`);
      return json(502, { ok: false, message: "Email delivery failed" });
    }
    return json(200, { ok: true, message: "Reply sent" });
  } catch (err) {
    console.error(`Unhandled error: ${(err as Error).message}`);
    return json(500, { ok: false, message: "An unexpected error occurred" });
  }
});
