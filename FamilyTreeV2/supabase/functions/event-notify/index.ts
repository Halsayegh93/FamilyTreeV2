import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { handleCors, validatePost, json } from "../_shared/cors.ts";
import { authenticateRequest, parseBody } from "../_shared/auth.ts";

type EventType = "join_request" | "role_changed" | "status_changed" | "contact_reply";

interface BasePayload {
  type: EventType;
}

interface JoinRequestPayload extends BasePayload {
  type: "join_request";
  member_name: string;
  member_phone?: string;
}

interface RoleChangedPayload extends BasePayload {
  type: "role_changed";
  member_name: string;
  member_email?: string;
  old_role: string;
  new_role: string;
}

interface StatusChangedPayload extends BasePayload {
  type: "status_changed";
  member_name: string;
  member_email?: string;
  old_status: string;
  new_status: string;
}

interface ContactReplyPayload extends BasePayload {
  type: "contact_reply";
  member_name: string;
  member_email: string;
  reply_text: string;
  original_message?: string;
}

type EventPayload = JoinRequestPayload | RoleChangedPayload | StatusChangedPayload | ContactReplyPayload;

const ROLE_AR: Record<string, string> = {
  owner: "مدير",
  admin: "مدير",
  monitor: "مراقب",
  supervisor: "مشرف",
  member: "عضو",
  pending: "معلق",
};

const STATUS_AR: Record<string, string> = {
  pending: "معلق",
  active: "نشط",
  frozen: "مجمّد",
};

function roleArabic(r: string): string {
  return ROLE_AR[r.toLowerCase()] ?? r;
}

function statusArabic(s: string): string {
  return STATUS_AR[s.toLowerCase()] ?? s;
}

interface EmailContent {
  subject: string;
  html: string;
  text: string;
}

function buildJoinRequestEmail(p: JoinRequestPayload): EmailContent {
  const subject = `طلب انضمام جديد — ${p.member_name}`;
  const phoneRow = p.member_phone
    ? `<tr><td style="padding:8px 16px;color:#516F80;width:100px">رقم الهاتف</td><td style="padding:8px 16px;color:#1a1a1a;font-weight:500">${escapeHtml(p.member_phone)}</td></tr>`
    : "";
  const html = renderEmail({
    title: "طلب انضمام جديد",
    accentColor: "#2B7A9F",
    body: `
      <p style="margin:0 0 16px;color:#516F80;line-height:1.7">
        تم استلام طلب انضمام جديد لشجرة العائلة. الرجاء مراجعته من لوحة الإدارة.
      </p>
      <table style="width:100%;border-collapse:collapse;background:#F7F9FB;border-radius:10px;overflow:hidden;margin:16px 0">
        <tr><td style="padding:8px 16px;color:#516F80;width:100px">الاسم</td><td style="padding:8px 16px;color:#1a1a1a;font-weight:500">${escapeHtml(p.member_name)}</td></tr>
        ${phoneRow}
      </table>
    `,
  });
  const text = [
    "طلب انضمام جديد لشجرة العائلة",
    "",
    `الاسم: ${p.member_name}`,
    p.member_phone ? `الهاتف: ${p.member_phone}` : "",
    "",
    "الرجاء مراجعته من لوحة الإدارة.",
  ].filter(Boolean).join("\n");
  return { subject, html, text };
}

function buildRoleChangedEmailForMember(p: RoleChangedPayload): EmailContent {
  const newRole = roleArabic(p.new_role);
  const subject = `تحديث صلاحيتك: ${newRole}`;
  const html = renderEmail({
    title: "تم تحديث صلاحيتك",
    accentColor: "#2F5C3E",
    body: `
      <p style="margin:0 0 16px;color:#516F80;line-height:1.7">
        مرحباً ${escapeHtml(p.member_name)}،
      </p>
      <p style="margin:0 0 16px;color:#516F80;line-height:1.7">
        تم تحديث صلاحيتك في تطبيق شجرة عائلة آل محمد علي.
      </p>
      <table style="width:100%;border-collapse:collapse;background:#F7F9FB;border-radius:10px;overflow:hidden;margin:16px 0">
        <tr><td style="padding:8px 16px;color:#516F80;width:120px">الصلاحية السابقة</td><td style="padding:8px 16px;color:#1a1a1a">${escapeHtml(roleArabic(p.old_role))}</td></tr>
        <tr><td style="padding:8px 16px;color:#516F80">الصلاحية الجديدة</td><td style="padding:8px 16px;color:#2F5C3E;font-weight:600">${escapeHtml(newRole)}</td></tr>
      </table>
      <p style="margin:0;color:#888;font-size:13px;line-height:1.6">
        إذا كان عندك أي استفسار، تواصل مع الإدارة من شاشة "التواصل" في التطبيق.
      </p>
    `,
  });
  const text = [
    `مرحباً ${p.member_name}،`,
    "",
    "تم تحديث صلاحيتك في تطبيق شجرة عائلة آل محمد علي.",
    "",
    `الصلاحية السابقة: ${roleArabic(p.old_role)}`,
    `الصلاحية الجديدة: ${newRole}`,
  ].join("\n");
  return { subject, html, text };
}

function buildRoleChangedEmailForAdmin(p: RoleChangedPayload): EmailContent {
  const subject = `[سجل] تغيير صلاحية — ${p.member_name}`;
  const html = renderEmail({
    title: "تسجيل تغيير صلاحية",
    accentColor: "#516F80",
    body: `
      <table style="width:100%;border-collapse:collapse;background:#F7F9FB;border-radius:10px;overflow:hidden;margin:0 0 16px">
        <tr><td style="padding:8px 16px;color:#516F80;width:100px">العضو</td><td style="padding:8px 16px;color:#1a1a1a;font-weight:500">${escapeHtml(p.member_name)}</td></tr>
        <tr><td style="padding:8px 16px;color:#516F80">من</td><td style="padding:8px 16px;color:#1a1a1a">${escapeHtml(roleArabic(p.old_role))}</td></tr>
        <tr><td style="padding:8px 16px;color:#516F80">إلى</td><td style="padding:8px 16px;color:#2B7A9F;font-weight:600">${escapeHtml(roleArabic(p.new_role))}</td></tr>
      </table>
      <p style="margin:0;color:#888;font-size:13px">إشعار تلقائي للأرشيف.</p>
    `,
  });
  const text = `[سجل] تغيير صلاحية\n\nالعضو: ${p.member_name}\nمن: ${roleArabic(p.old_role)}\nإلى: ${roleArabic(p.new_role)}`;
  return { subject, html, text };
}

function buildStatusChangedEmailForMember(p: StatusChangedPayload): EmailContent {
  const newStatus = statusArabic(p.new_status);
  const isFrozen = p.new_status.toLowerCase() === "frozen";
  const subject = isFrozen ? "تجميد حسابك" : `تحديث حالة حسابك: ${newStatus}`;
  const accent = isFrozen ? "#8C2A2A" : "#2F5C3E";
  const html = renderEmail({
    title: isFrozen ? "تم تجميد حسابك" : "تم تحديث حالة حسابك",
    accentColor: accent,
    body: `
      <p style="margin:0 0 16px;color:#516F80;line-height:1.7">مرحباً ${escapeHtml(p.member_name)}،</p>
      <p style="margin:0 0 16px;color:#516F80;line-height:1.7">
        ${isFrozen
          ? "تم تجميد حسابك في تطبيق شجرة عائلة آل محمد علي."
          : "تم تحديث حالة حسابك في تطبيق شجرة عائلة آل محمد علي."}
      </p>
      <table style="width:100%;border-collapse:collapse;background:#F7F9FB;border-radius:10px;overflow:hidden;margin:16px 0">
        <tr><td style="padding:8px 16px;color:#516F80;width:120px">الحالة السابقة</td><td style="padding:8px 16px;color:#1a1a1a">${escapeHtml(statusArabic(p.old_status))}</td></tr>
        <tr><td style="padding:8px 16px;color:#516F80">الحالة الجديدة</td><td style="padding:8px 16px;color:${accent};font-weight:600">${escapeHtml(newStatus)}</td></tr>
      </table>
      <p style="margin:0;color:#888;font-size:13px;line-height:1.6">
        ${isFrozen
          ? "إذا تعتقد أن هذا خطأ، تواصل مع الإدارة عبر إيميل الرد أو من شاشة \"التواصل\" قبل التجميد."
          : "إذا كان عندك أي استفسار، تواصل مع الإدارة من شاشة \"التواصل\" في التطبيق."}
      </p>
    `,
  });
  const text = [
    `مرحباً ${p.member_name}،`,
    "",
    isFrozen
      ? "تم تجميد حسابك في تطبيق شجرة عائلة آل محمد علي."
      : "تم تحديث حالة حسابك في تطبيق شجرة عائلة آل محمد علي.",
    "",
    `الحالة السابقة: ${statusArabic(p.old_status)}`,
    `الحالة الجديدة: ${newStatus}`,
  ].join("\n");
  return { subject, html, text };
}

function buildContactReplyEmail(p: ContactReplyPayload): EmailContent {
  const subject = "رد من الإدارة على رسالتك";
  const originalSection = p.original_message
    ? `
      <div style="margin-top:16px;padding:12px 16px;background:#F0F2F5;border-radius:10px;border-right:3px solid #8A9EA9">
        <p style="margin:0 0 6px;color:#888;font-size:12px">رسالتك الأصلية:</p>
        <p style="margin:0;color:#516F80;font-size:13px;line-height:1.6;white-space:pre-wrap">${escapeHtml(p.original_message)}</p>
      </div>
    `
    : "";
  const html = renderEmail({
    title: "رد من الإدارة",
    accentColor: "#2B7A9F",
    body: `
      <p style="margin:0 0 16px;color:#516F80;line-height:1.7">مرحباً ${escapeHtml(p.member_name)}،</p>
      <p style="margin:0 0 16px;color:#516F80;line-height:1.7">
        تلقّينا رسالتك في تطبيق شجرة عائلة آل محمد علي وهذا ردّنا:
      </p>
      <div style="margin:16px 0;padding:16px;background:#E8F1F6;border-radius:10px;border-right:3px solid #2B7A9F">
        <p style="margin:0;color:#1a1a1a;font-size:15px;line-height:1.7;white-space:pre-wrap">${escapeHtml(p.reply_text)}</p>
      </div>
      ${originalSection}
      <p style="margin:16px 0 0;color:#888;font-size:13px;line-height:1.6">
        لو احتجت متابعة، تقدر ترسل رسالة جديدة من شاشة "التواصل" في التطبيق.
      </p>
    `,
  });
  const text = [
    `مرحباً ${p.member_name}،`,
    "",
    "تلقّينا رسالتك في تطبيق شجرة عائلة آل محمد علي وهذا ردّنا:",
    "",
    "─────────────",
    p.reply_text,
    "─────────────",
    p.original_message ? `\nرسالتك الأصلية:\n${p.original_message}` : "",
    "",
    "لو احتجت متابعة، تقدر ترسل رسالة جديدة من شاشة \"التواصل\" في التطبيق.",
  ].filter(Boolean).join("\n");
  return { subject, html, text };
}

function buildStatusChangedEmailForAdmin(p: StatusChangedPayload): EmailContent {
  const subject = `[سجل] تغيير حالة — ${p.member_name}`;
  const html = renderEmail({
    title: "تسجيل تغيير حالة",
    accentColor: "#516F80",
    body: `
      <table style="width:100%;border-collapse:collapse;background:#F7F9FB;border-radius:10px;overflow:hidden;margin:0 0 16px">
        <tr><td style="padding:8px 16px;color:#516F80;width:100px">العضو</td><td style="padding:8px 16px;color:#1a1a1a;font-weight:500">${escapeHtml(p.member_name)}</td></tr>
        <tr><td style="padding:8px 16px;color:#516F80">من</td><td style="padding:8px 16px;color:#1a1a1a">${escapeHtml(statusArabic(p.old_status))}</td></tr>
        <tr><td style="padding:8px 16px;color:#516F80">إلى</td><td style="padding:8px 16px;color:#2B7A9F;font-weight:600">${escapeHtml(statusArabic(p.new_status))}</td></tr>
      </table>
      <p style="margin:0;color:#888;font-size:13px">إشعار تلقائي للأرشيف.</p>
    `,
  });
  const text = `[سجل] تغيير حالة\n\nالعضو: ${p.member_name}\nمن: ${statusArabic(p.old_status)}\nإلى: ${statusArabic(p.new_status)}`;
  return { subject, html, text };
}

function renderEmail(args: { title: string; accentColor: string; body: string }): string {
  return `<!doctype html>
<html lang="ar" dir="rtl">
<head><meta charset="utf-8"><title>${escapeHtml(args.title)}</title></head>
<body style="margin:0;padding:24px 12px;background:#F0F2F5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Tahoma,sans-serif">
  <table style="max-width:560px;margin:0 auto;width:100%;background:#fff;border-radius:14px;overflow:hidden;box-shadow:0 2px 16px rgba(0,0,0,0.06)" cellpadding="0" cellspacing="0">
    <tr><td style="background:${args.accentColor};padding:20px 24px">
      <h1 style="margin:0;color:#fff;font-size:18px;font-weight:600">${escapeHtml(args.title)}</h1>
    </td></tr>
    <tr><td style="padding:24px">${args.body}</td></tr>
    <tr><td style="background:#F7F9FB;padding:16px 24px;border-top:1px solid #E5E8EB">
      <p style="margin:0;color:#888;font-size:12px;text-align:center">
        تطبيق شجرة عائلة آل محمد علي
      </p>
    </td></tr>
  </table>
</body></html>`;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

async function sendEmail(args: {
  resendApiKey: string;
  from: string;
  to: string[];
  subject: string;
  html: string;
  text: string;
}): Promise<{ ok: boolean; status: number; body: string }> {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${args.resendApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: args.from,
      to: args.to,
      subject: args.subject,
      html: args.html,
      text: args.text,
    }),
  });
  const raw = await response.text();
  return { ok: response.ok, status: response.status, body: raw };
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const notPost = validatePost(req);
  if (notPost) return notPost;

  try {
    // التحقق من JWT — أي مستخدم مسجّل دخول
    const auth = await authenticateRequest(req);
    if (auth instanceof Response) return auth;

    const resendApiKey = (Deno.env.get("RESEND_API_KEY") ?? "").trim();
    const emailFrom = (Deno.env.get("CONTACT_EMAIL_FROM") ?? "").trim();
    const emailTo = (Deno.env.get("CONTACT_EMAIL_TO") ?? "").trim();

    if (!resendApiKey || !emailFrom || !emailTo) {
      console.error("Missing env: RESEND_API_KEY / CONTACT_EMAIL_FROM / CONTACT_EMAIL_TO");
      return json(500, { ok: false, message: "Email service not configured" });
    }

    const body = await parseBody<EventPayload>(req);
    if (body instanceof Response) return body;
    const payload = body;

    if (!payload?.type) {
      return json(400, { ok: false, message: "type is required" });
    }

    const adminRecipients = emailTo.split(",").map((v) => v.trim()).filter(Boolean);
    const results: Array<{ target: string; ok: boolean; status: number }> = [];

    if (payload.type === "join_request") {
      const content = buildJoinRequestEmail(payload as JoinRequestPayload);
      const r = await sendEmail({
        resendApiKey, from: emailFrom, to: adminRecipients,
        subject: content.subject, html: content.html, text: content.text,
      });
      results.push({ target: "admin", ok: r.ok, status: r.status });
      if (!r.ok) console.error(`Resend (admin) failed: ${r.status} — ${r.body}`);
    } else if (payload.type === "role_changed") {
      const p = payload as RoleChangedPayload;

      // إيميل للعضو (إذا عنده إيميل)
      if (p.member_email && p.member_email.trim()) {
        const content = buildRoleChangedEmailForMember(p);
        const r = await sendEmail({
          resendApiKey, from: emailFrom, to: [p.member_email.trim()],
          subject: content.subject, html: content.html, text: content.text,
        });
        results.push({ target: "member", ok: r.ok, status: r.status });
        if (!r.ok) console.error(`Resend (member) failed: ${r.status} — ${r.body}`);
      }

      // إيميل للإدارة (سجل)
      const adminContent = buildRoleChangedEmailForAdmin(p);
      const r = await sendEmail({
        resendApiKey, from: emailFrom, to: adminRecipients,
        subject: adminContent.subject, html: adminContent.html, text: adminContent.text,
      });
      results.push({ target: "admin", ok: r.ok, status: r.status });
      if (!r.ok) console.error(`Resend (admin) failed: ${r.status} — ${r.body}`);
    } else if (payload.type === "status_changed") {
      const p = payload as StatusChangedPayload;

      if (p.member_email && p.member_email.trim()) {
        const content = buildStatusChangedEmailForMember(p);
        const r = await sendEmail({
          resendApiKey, from: emailFrom, to: [p.member_email.trim()],
          subject: content.subject, html: content.html, text: content.text,
        });
        results.push({ target: "member", ok: r.ok, status: r.status });
        if (!r.ok) console.error(`Resend (member) failed: ${r.status} — ${r.body}`);
      }

      const adminContent = buildStatusChangedEmailForAdmin(p);
      const r = await sendEmail({
        resendApiKey, from: emailFrom, to: adminRecipients,
        subject: adminContent.subject, html: adminContent.html, text: adminContent.text,
      });
      results.push({ target: "admin", ok: r.ok, status: r.status });
      if (!r.ok) console.error(`Resend (admin) failed: ${r.status} — ${r.body}`);
    } else if (payload.type === "contact_reply") {
      const p = payload as ContactReplyPayload;
      if (!p.member_email || !p.member_email.trim()) {
        return json(400, { ok: false, message: "member_email is required for contact_reply" });
      }
      if (!p.reply_text || !p.reply_text.trim()) {
        return json(400, { ok: false, message: "reply_text is required" });
      }
      const content = buildContactReplyEmail(p);
      const r = await sendEmail({
        resendApiKey, from: emailFrom, to: [p.member_email.trim()],
        subject: content.subject, html: content.html, text: content.text,
      });
      results.push({ target: "member", ok: r.ok, status: r.status });
      if (!r.ok) console.error(`Resend (member) failed: ${r.status} — ${r.body}`);
    } else {
      return json(400, { ok: false, message: `Unknown type: ${(payload as { type: string }).type}` });
    }

    const allOk = results.every((r) => r.ok);
    return json(allOk ? 200 : 502, {
      ok: allOk,
      results,
      message: allOk ? "Notifications sent" : "Some notifications failed",
    });
  } catch (err) {
    console.error(`Unhandled error: ${(err as Error).message}`);
    return json(500, { ok: false, message: "An unexpected error occurred" });
  }
});
