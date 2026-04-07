import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { handleCors, validatePost, json } from "../_shared/cors.ts";
import { authenticateRequest, parseBody } from "../_shared/auth.ts";

type ContactEmailPayload = {
  category?: string;
  message?: string;
  preferred_contact?: string;
  sender_name?: string;
  sender_phone?: string;
};

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const notPost = validatePost(req);
  if (notPost) return notPost;

  try {
    // JWT verification — require authenticated user
    const auth = await authenticateRequest(req);
    if (auth instanceof Response) return auth;

    const resendApiKey = (Deno.env.get("RESEND_API_KEY") ?? "").trim();
    const sendgridApiKey = (Deno.env.get("SENDGRID_API_KEY") ?? "").trim();
    const emailFrom = (Deno.env.get("CONTACT_EMAIL_FROM") ?? "").trim();
    const emailTo = (Deno.env.get("CONTACT_EMAIL_TO") ?? "").trim();

    if (!emailFrom || !emailTo || (!resendApiKey && !sendgridApiKey)) {
      console.error("Missing env vars: CONTACT_EMAIL_FROM / CONTACT_EMAIL_TO and/or provider key");
      return json(500, {
        ok: false,
        message: "Email service not configured",
      });
    }

    const body = await parseBody<ContactEmailPayload>(req);
    if (body instanceof Response) return body;
    const payload = body;

    const category = (payload.category ?? "تواصل").trim();
    const message = (payload.message ?? "").trim();
    const preferredContact = (payload.preferred_contact ?? "").trim();
    const senderName = (payload.sender_name ?? "مستخدم التطبيق").trim();
    const senderPhone = (payload.sender_phone ?? "").trim();

    if (!message) {
      return json(400, { ok: false, message: "message is required" });
    }

    const recipients = emailTo
      .split(",")
      .map((v) => v.trim())
      .filter((v) => v.length > 0);

    const subject = `رسالة تواصل جديدة - ${category}`;
    const textBody = [
      `التصنيف: ${category}`,
      `الاسم: ${senderName}`,
      `الهاتف: ${senderPhone || "غير متوفر"}`,
      `وسيلة التواصل المفضلة: ${preferredContact || "غير محدد"}`,
      "",
      "محتوى الرسالة:",
      message,
    ].join("\n");

    // Try Resend first
    if (resendApiKey) {
      try {
        const response = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${resendApiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            from: emailFrom,
            to: recipients,
            subject,
            text: textBody,
          }),
        });

        const raw = await response.text();
        if (!response.ok) {
          console.error(`Resend failed: ${response.status} — ${raw}`);
          return json(502, {
            ok: false,
            message: "Email delivery failed. Please try again later.",
          });
        }

        return json(200, { ok: true, message: "Email sent" });
      } catch (resendErr) {
        // If Resend fails and SendGrid is available, fall through
        if (!sendgridApiKey) {
          console.error(`Resend error: ${(resendErr as Error).message}`);
          return json(500, {
            ok: false,
            message: "Email service error. Please try again later.",
          });
        }
      }
    }

    // Try SendGrid
    if (sendgridApiKey) {
      const fromEmail = emailFrom.includes("<")
        ? emailFrom.split("<")[1].replace(">", "").trim()
        : emailFrom;

      const sgResponse = await fetch("https://api.sendgrid.com/v3/mail/send", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${sendgridApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          personalizations: [{ to: recipients.map((email) => ({ email })) }],
          from: { email: fromEmail },
          subject,
          content: [{ type: "text/plain", value: textBody }],
        }),
      });

      const sgRaw = await sgResponse.text();
      if (!sgResponse.ok) {
        console.error(`SendGrid failed: ${sgResponse.status} — ${sgRaw}`);
        return json(502, {
          ok: false,
          message: "Email delivery failed. Please try again later.",
        });
      }

      return json(200, { ok: true, message: "Email sent" });
    }

    return json(500, { ok: false, message: "No email provider configured" });
  } catch (err) {
    console.error(`Unhandled error: ${(err as Error).message}`);
    return json(500, { ok: false, message: "An unexpected error occurred" });
  }
});
