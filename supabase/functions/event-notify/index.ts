import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { handleCors, validatePost, json } from "../_shared/cors.ts";
import { authenticateRequest, parseBody } from "../_shared/auth.ts";
import {
  BRAND,
  dataRow,
  dataTable,
  escapeHtml,
  note,
  paragraph,
  quoteBox,
  renderEmail,
} from "../_shared/email.ts";

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
  const phoneRow = p.member_phone ? dataRow("رقم الهاتف", escapeHtml(p.member_phone)) : "";
  const html = renderEmail({
    title: "طلب انضمام جديد",
    badge: "طلب جديد",
    emoji: "📨",
    accentColor: BRAND.blue,
    preheader: `طلب انضمام من ${p.member_name} — بانتظار المراجعة`,
    body: `
      ${paragraph("تم استلام طلب انضمام جديد لشجرة العائلة. الرجاء مراجعته من لوحة الإدارة.")}
      ${dataTable(`
        ${dataRow("الاسم", escapeHtml(p.member_name), { bold: true })}
        ${phoneRow}
      `)}
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
    badge: "تحديث صلاحية",
    emoji: "🛡️",
    accentColor: BRAND.emerald,
    preheader: `صلاحيتك الجديدة: ${newRole}`,
    body: `
      ${paragraph(`مرحباً <strong style="color:${BRAND.ink}">${escapeHtml(p.member_name)}</strong>،`)}
      ${paragraph("تم تحديث صلاحيتك في تطبيق شجرة عائلة آل محمد علي.")}
      ${dataTable(`
        ${dataRow("الصلاحية السابقة", escapeHtml(roleArabic(p.old_role)))}
        ${dataRow("الصلاحية الجديدة", escapeHtml(newRole), { accent: BRAND.emerald })}
      `)}
      ${note('إذا كان عندك أي استفسار، تواصل مع الإدارة من شاشة "التواصل" في التطبيق.')}
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
    badge: "سجل إداري",
    emoji: "🗂️",
    accentColor: BRAND.indigo,
    preheader: `تغيير صلاحية ${p.member_name}`,
    body: `
      ${dataTable(`
        ${dataRow("العضو", escapeHtml(p.member_name), { bold: true })}
        ${dataRow("من", escapeHtml(roleArabic(p.old_role)))}
        ${dataRow("إلى", escapeHtml(roleArabic(p.new_role)), { accent: BRAND.indigo })}
      `)}
      ${note("إشعار تلقائي للأرشيف.")}
    `,
  });
  const text = `[سجل] تغيير صلاحية\n\nالعضو: ${p.member_name}\nمن: ${roleArabic(p.old_role)}\nإلى: ${roleArabic(p.new_role)}`;
  return { subject, html, text };
}

function buildStatusChangedEmailForMember(p: StatusChangedPayload): EmailContent {
  const newStatus = statusArabic(p.new_status);
  const isFrozen = p.new_status.toLowerCase() === "frozen";
  const subject = isFrozen ? "تجميد حسابك" : `تحديث حالة حسابك: ${newStatus}`;
  const accent = isFrozen ? BRAND.warn : BRAND.gold;
  const html = renderEmail({
    title: isFrozen ? "تم تجميد حسابك" : "تم تحديث حالة حسابك",
    badge: isFrozen ? "تنبيه" : "تحديث حالة",
    emoji: isFrozen ? "⏸️" : "✅",
    accentColor: accent,
    preheader: `حالة حسابك الجديدة: ${newStatus}`,
    body: `
      ${paragraph(`مرحباً <strong style="color:${BRAND.ink}">${escapeHtml(p.member_name)}</strong>،`)}
      ${paragraph(isFrozen
        ? "تم تجميد حسابك في تطبيق شجرة عائلة آل محمد علي."
        : "تم تحديث حالة حسابك في تطبيق شجرة عائلة آل محمد علي.")}
      ${dataTable(`
        ${dataRow("الحالة السابقة", escapeHtml(statusArabic(p.old_status)))}
        ${dataRow("الحالة الجديدة", escapeHtml(newStatus), { accent })}
      `)}
      ${note(isFrozen
        ? 'إذا تعتقد أن هذا خطأ، تواصل مع الإدارة عبر إيميل الرد أو من شاشة "التواصل" قبل التجميد.'
        : 'إذا كان عندك أي استفسار، تواصل مع الإدارة من شاشة "التواصل" في التطبيق.')}
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
    ? quoteBox(p.original_message, { label: "رسالتك الأصلية", accent: BRAND.muted, subtle: true })
    : "";
  const html = renderEmail({
    title: "رد من الإدارة",
    badge: "رد على رسالتك",
    emoji: "💬",
    accentColor: BRAND.blue,
    preheader: "تلقّينا رسالتك وهذا ردّنا",
    body: `
      ${paragraph(`مرحباً <strong style="color:${BRAND.ink}">${escapeHtml(p.member_name)}</strong>،`)}
      ${paragraph("تلقّينا رسالتك في تطبيق شجرة عائلة آل محمد علي وهذا ردّنا:")}
      ${quoteBox(p.reply_text, { accent: BRAND.blue })}
      ${originalSection}
      ${note('لو احتجت متابعة، تقدر ترسل رسالة جديدة من شاشة "التواصل" في التطبيق.')}
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
    badge: "سجل إداري",
    emoji: "🗂️",
    accentColor: BRAND.indigo,
    preheader: `تغيير حالة ${p.member_name}`,
    body: `
      ${dataTable(`
        ${dataRow("العضو", escapeHtml(p.member_name), { bold: true })}
        ${dataRow("من", escapeHtml(statusArabic(p.old_status)))}
        ${dataRow("إلى", escapeHtml(statusArabic(p.new_status)), { accent: BRAND.indigo })}
      `)}
      ${note("إشعار تلقائي للأرشيف.")}
    `,
  });
  const text = `[سجل] تغيير حالة\n\nالعضو: ${p.member_name}\nمن: ${statusArabic(p.old_status)}\nإلى: ${statusArabic(p.new_status)}`;
  return { subject, html, text };
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
