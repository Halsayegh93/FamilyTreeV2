import { deliveryGuard } from "../_shared/delivery-guard.ts";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { handleCors, validatePost, json } from "../_shared/cors.ts";
import { authenticateRequest, parseBody, createServiceClient } from "../_shared/auth.ts";

/** تنبيه الإدارة برسالة تواصل جديدة — نفس القالب المبسّط. */
type ContactEmailPayload = { category?: string; message?: string; preferred_contact?: string; sender_name?: string; sender_phone?: string };

const APP_NAME = "عائلة المحمدعلي";
const INK = "#1B2A33";
const MUTED = "#8A97A0";
const LINE = "#E6EBEE";
const ACCENT = "#2B7A9F";
const FONT = "-apple-system,'SF Arabic','Segoe UI','Noto Naskh Arabic',Tahoma,Arial,sans-serif";

function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;");
}

function row(label: string, value: string): string {
  return `<tr><td style="padding:11px 0;border-top:1px solid ${LINE};text-align:right"><span style="color:${MUTED};font-size:13px;font-weight:600">${esc(label)}</span><span style="color:${INK};font-size:15px;font-weight:700;margin-right:8px">${esc(value)}</span></td></tr>`;
}

function simpleEmail(opts: { name: string; phone: string; contact: string; category: string; message: string }): string {
  return `<!doctype html>
<html lang="ar" dir="rtl">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(APP_NAME)}</title></head>
<body style="margin:0;padding:0;background:#F4F6F8;font-family:${FONT}">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F4F6F8;padding:28px 14px">
    <tr><td align="center">
      <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="width:100%;max-width:560px;background:#ffffff;border:1px solid ${LINE};border-radius:14px;overflow:hidden">
        <tr><td style="padding:18px 24px;border-bottom:1px solid ${LINE}">
          <span style="color:${ACCENT};font-size:15px;font-weight:800">${esc(APP_NAME)}</span>
          <span style="color:${MUTED};font-size:13px;margin-right:8px">— رسالة تواصل جديدة</span>
        </td></tr>
        <tr><td style="padding:22px 24px 8px;text-align:right">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse">
            ${row("المُرسِل", opts.name || "مستخدم التطبيق")}
            ${row("التصنيف", opts.category || "تواصل")}
            ${opts.phone ? row("الهاتف", opts.phone) : ""}
            ${opts.contact ? row("وسيلة التواصل للرد", opts.contact) : ""}
          </table>
        </td></tr>
        <tr><td style="padding:8px 24px 30px;text-align:right">
          <div style="color:${MUTED};font-size:12px;font-weight:700;margin:0 0 8px">نص الرسالة</div>
          <div style="padding:16px 18px;border-right:3px solid ${ACCENT};background:#FAFBFC;border-radius:8px;color:${INK};font-size:15.5px;line-height:1.95;white-space:pre-wrap">${esc(opts.message)}</div>
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
    const auth = await authenticateRequest(req, undefined, { allowInactive: true }); if (auth instanceof Response) return auth;
    if (!["active", "pending", "frozen"].includes(auth.status ?? "")) return json(403, { ok: false, message: "Account not authorized" });
    const resendApiKey = (Deno.env.get("RESEND_API_KEY") ?? "").trim();
    const sendgridApiKey = (Deno.env.get("SENDGRID_API_KEY") ?? "").trim();
    const emailFrom = (Deno.env.get("CONTACT_EMAIL_FROM") ?? "").trim();
    const emailTo = (Deno.env.get("CONTACT_EMAIL_TO") ?? "").trim();
    if (!emailFrom || !emailTo || (!resendApiKey && !sendgridApiKey)) { console.error("Missing env vars"); return json(500, { ok: false, message: "Email service not configured" }); }
    const body = await parseBody<ContactEmailPayload>(req); if (body instanceof Response) return body;
    const category = (body.category ?? "تواصل").trim();
    const message = (body.message ?? "").trim();
    const preferredContact = (body.preferred_contact ?? "").trim();
    const { data: sender, error: senderError } = await createServiceClient().from("profiles")
      .select("full_name,phone_number").eq("id", auth.profileId).single();
    if (senderError) return json(503, { ok: false, message: "Unable to verify sender" });
    const senderName = sender.full_name || "مستخدم التطبيق";
    const senderPhone = sender.phone_number || "";
    if (!message) return json(400, { ok: false, message: "message is required" });
    if (message.length > 10000 || category.length > 100 || preferredContact.length > 320) return json(400, { ok: false, message: "Message too long" });
    const limited = await deliveryGuard("contact-email", auth.profileId, [category,message,preferredContact], 5);
    if (limited) return limited;
    const recipients = emailTo.split(",").map((v) => v.trim()).filter((v) => v.length > 0);
    const subject = `رسالة تواصل جديدة — ${category}`;
    const textBody = [`المُرسِل: ${senderName}`, `التصنيف: ${category}`, `الهاتف: ${senderPhone || "غير متوفر"}`, `وسيلة التواصل للرد: ${preferredContact || "غير محدد"}`, "", "نص الرسالة:", message].join("\n");
    const htmlBody = simpleEmail({ name: senderName, phone: senderPhone, contact: preferredContact, category, message });
    if (resendApiKey) {
      try {
        const response = await fetch("https://api.resend.com/emails", { method: "POST", headers: { Authorization: `Bearer ${resendApiKey}`, "Content-Type": "application/json" }, body: JSON.stringify({ from: emailFrom, to: recipients, reply_to: preferredContact && preferredContact.includes("@") ? preferredContact : undefined, subject, text: textBody, html: htmlBody }) });
        const raw = await response.text();
        if (!response.ok) { console.error(JSON.stringify({event:"email_provider_failed", provider:"resend", status:response.status})); return json(502, { ok: false, message: "Email delivery failed. Please try again later." }); }
        return json(200, { ok: true, message: "Email sent" });
      } catch (resendErr) { if (!sendgridApiKey) { console.error(`Resend error: ${(resendErr as Error).message}`); return json(500, { ok: false, message: "Email service error. Please try again later." }); } }
    }
    if (sendgridApiKey) {
      const fromEmail = emailFrom.includes("<") ? emailFrom.split("<")[1].replace(">", "").trim() : emailFrom;
      const sgResponse = await fetch("https://api.sendgrid.com/v3/mail/send", { method: "POST", headers: { Authorization: `Bearer ${sendgridApiKey}`, "Content-Type": "application/json" }, body: JSON.stringify({ personalizations: [{ to: recipients.map((email) => ({ email })) }], from: { email: fromEmail }, subject, content: [{ type: "text/plain", value: textBody }, { type: "text/html", value: htmlBody }] }) });
      const sgRaw = await sgResponse.text();
      if (!sgResponse.ok) { console.error(JSON.stringify({event:"email_provider_failed", provider:"sendgrid", status:sgResponse.status})); return json(502, { ok: false, message: "Email delivery failed. Please try again later." }); }
      return json(200, { ok: true, message: "Email sent" });
    }
    return json(500, { ok: false, message: "No email provider configured" });
  } catch (err) { console.error(`Unhandled error: ${(err as Error).message}`); return json(500, { ok: false, message: "An unexpected error occurred" }); }
});
