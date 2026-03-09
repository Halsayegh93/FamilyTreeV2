import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

type ContactEmailPayload = {
  category?: string;
  message?: string;
  preferred_contact?: string;
  sender_name?: string;
  sender_phone?: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json(405, { ok: false, message: "Method not allowed" });
  }

  const resendApiKey = (Deno.env.get("RESEND_API_KEY") ?? "").trim();
  const sendgridApiKey = (Deno.env.get("SENDGRID_API_KEY") ?? "").trim();
  const emailFrom = (Deno.env.get("CONTACT_EMAIL_FROM") ?? "").trim();
  const emailTo = (Deno.env.get("CONTACT_EMAIL_TO") ?? "").trim();

  if (!emailFrom || !emailTo || (!resendApiKey && !sendgridApiKey)) {
    return json(500, {
      ok: false,
      message: "Missing env vars: CONTACT_EMAIL_FROM / CONTACT_EMAIL_TO and one provider key (RESEND_API_KEY or SENDGRID_API_KEY)",
    });
  }

  let payload: ContactEmailPayload;
  try {
    payload = await req.json();
  } catch {
    return json(400, { ok: false, message: "Invalid JSON body" });
  }

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

  if (resendApiKey) {
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
      return json(502, {
        ok: false,
        provider: "resend",
        message: `Resend failed: ${response.status}`,
        details: raw,
      });
    }

    return json(200, { ok: true, provider: "resend", message: "Email sent", details: raw });
  }

  const sgResponse = await fetch("https://api.sendgrid.com/v3/mail/send", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${sendgridApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      personalizations: [{ to: recipients.map((email) => ({ email })) }],
      from: { email: emailFrom.includes("<") ? emailFrom.split("<")[1].replace(">", "").trim() : emailFrom },
      subject,
      content: [{ type: "text/plain", value: textBody }],
    }),
  });

  const sgRaw = await sgResponse.text();
  if (!sgResponse.ok) {
    return json(502, {
      ok: false,
      provider: "sendgrid",
      message: `SendGrid failed: ${sgResponse.status}`,
      details: sgRaw,
    });
  }

  return json(200, { ok: true, provider: "sendgrid", message: "Email sent", details: sgRaw });
});
