import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";

type ContactEmailPayload = {
  category?: string;
  message?: string;
  preferred_contact?: string;
  sender_name?: string;
  sender_phone?: string;
};

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    if (req.method !== "POST") {
      return jsonResponse(405, { ok: false, message: "Method not allowed" });
    }

    // JWT verification — require authenticated user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse(401, { ok: false, message: "Missing authorization" });
    }
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? ""
    );
    const { error: authError } = await supabase.auth.getUser(
      authHeader.replace("Bearer ", "")
    );
    if (authError) {
      return jsonResponse(401, { ok: false, message: "Invalid or expired token" });
    }

    const resendApiKey = (Deno.env.get("RESEND_API_KEY") ?? "").trim();
    const sendgridApiKey = (Deno.env.get("SENDGRID_API_KEY") ?? "").trim();
    const emailFrom = (Deno.env.get("CONTACT_EMAIL_FROM") ?? "").trim();
    const emailTo = (Deno.env.get("CONTACT_EMAIL_TO") ?? "").trim();

    if (!emailFrom || !emailTo || (!resendApiKey && !sendgridApiKey)) {
      console.error("Missing env vars: CONTACT_EMAIL_FROM / CONTACT_EMAIL_TO and/or provider key");
      return jsonResponse(500, {
        ok: false,
        message: "Email service not configured",
      });
    }

    let payload: ContactEmailPayload;
    try {
      payload = await req.json();
    } catch (_e) {
      return jsonResponse(400, { ok: false, message: "Invalid JSON body" });
    }

    const category = (payload.category ?? "تواصل").trim();
    const message = (payload.message ?? "").trim();
    const preferredContact = (payload.preferred_contact ?? "").trim();
    const senderName = (payload.sender_name ?? "مستخدم التطبيق").trim();
    const senderPhone = (payload.sender_phone ?? "").trim();

    if (!message) {
      return jsonResponse(400, { ok: false, message: "message is required" });
    }

    const recipients = emailTo
      .split(",")
      .map((v: string) => v.trim())
      .filter((v: string) => v.length > 0);

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
            "Authorization": `Bearer ${resendApiKey}`,
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
          return jsonResponse(502, {
            ok: false,
            message: "Email delivery failed. Please try again later.",
          });
        }

        return jsonResponse(200, { ok: true, message: "Email sent" });
      } catch (resendErr) {
        // If Resend fails and SendGrid is available, fall through
        if (!sendgridApiKey) {
          console.error(`Resend error: ${(resendErr as Error).message}`);
          return jsonResponse(500, {
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
          "Authorization": `Bearer ${sendgridApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          personalizations: [{ to: recipients.map((email: string) => ({ email })) }],
          from: { email: fromEmail },
          subject,
          content: [{ type: "text/plain", value: textBody }],
        }),
      });

      const sgRaw = await sgResponse.text();
      if (!sgResponse.ok) {
        console.error(`SendGrid failed: ${sgResponse.status} — ${sgRaw}`);
        return jsonResponse(502, {
          ok: false,
          message: "Email delivery failed. Please try again later.",
        });
      }

      return jsonResponse(200, { ok: true, message: "Email sent" });
    }

    return jsonResponse(500, { ok: false, message: "No email provider configured" });
  } catch (err) {
    console.error(`Unhandled error: ${(err as Error).message}`);
    return jsonResponse(500, { ok: false, message: "An unexpected error occurred" });
  }
});
