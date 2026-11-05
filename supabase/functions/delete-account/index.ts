import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { handleCors, validatePost, json } from "../_shared/cors.ts";
import { authenticateRequest, createServiceClient } from "../_shared/auth.ts";
import { deleteAccountWorkflow, type DeletionFile } from "../_shared/delete-account-workflow.ts";

// عضوية معتمدة = حساب مفعّل بدور من أدوار العائلة (نفس is_approved_member في السيرفر)
const APPROVED_ROLES = ["member", "supervisor", "monitor", "admin", "owner"];
const DEFAULT_SMS = "تم حذف حسابك في تطبيق عائلة المحمدعلي بناءً على طلبك.";
const SENDER_RE = /^[A-Za-z0-9 -]{1,11}$/;

// الكويت فقط (مثل خطّاف رمز الدخول send-sms-kwtsms)
function kuwaitMobile(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const digits = value.replace(/[^0-9]/g, "").replace(/^00/, "");
  const full = digits.length === 8 ? `965${digits}` : digits;
  return /^965[4569][0-9]{7}$/.test(full) ? full : null;
}

// رسالة تأكيد الحذف (قرار المالك ٢٠٢٦-١٠-٢٩) — بأفضل جهد: أي خطأ يُبلع والحذف يبقى ناجحاً.
async function sendDeletedSms(client: ReturnType<typeof createServiceClient>, phone: string | null) {
  try {
    const mobile = kuwaitMobile(phone);
    const username = Deno.env.get("KWTSMS_USERNAME") ?? "";
    const password = Deno.env.get("KWTSMS_PASSWORD") ?? "";
    if (!mobile || !username || !password) return;
    const [{ data: cfg }, { data: settings }] = await Promise.all([
      client.from("app_config").select("value").eq("key", "account_deleted_sms").maybeSingle(),
      client.from("app_settings").select("sms_sender").order("updated_at", { ascending: false }).limit(1).maybeSingle(),
    ]);
    const text = typeof cfg?.value === "string" && cfg.value.trim() && !/[\u0000-\u001f\u007f]/.test(cfg.value)
      ? cfg.value.trim()
      : DEFAULT_SMS;
    const stored = settings?.sms_sender;
    const sender = typeof stored === "string" && SENDER_RE.test(stored)
      ? stored
      : (Deno.env.get("KWTSMS_SENDER") || "KWT-SMS");
    const test = Deno.env.get("KWTSMS_TEST_MODE") !== "false";
    const response = await fetch("https://www.kwtsms.com/API/send/", {
      method: "POST",
      signal: AbortSignal.timeout(5000),
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ username, password, sender, mobile, message: text, test: test ? "1" : "0" }),
    });
    const result = await response.json().catch(() => null);
    if (!response.ok || result?.result !== "OK") {
      console.error("[delete-account] confirmation sms rejected", response.status, result?.code ?? "");
    }
  } catch {
    console.error("[delete-account] confirmation sms failed");
  }
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  const method = validatePost(req);
  if (method) return method;
  try {
    // Frozen / already anonymized accounts must be able to retry partial cleanup.
    const auth = await authenticateRequest(req, undefined, { allowInactive: true, allowMissingProfile: true });
    if (auth instanceof Response) return auth;
    const client = createServiceClient();

    // Admin mode (privacy policy art. 9, 2026-10-28): the member files an `account_delete` request
    // in the app; the owner/an admin completes it here with { request_id } within 7 days.
    let body: { request_id?: string } = {};
    try { body = await req.json(); } catch { body = {}; }
    let targetAuthId = auth.user.id;
    let targetProfileId = auth.profileId;
    let requestId: string | null = null;
    if (body.request_id) {
      if (auth.role !== "owner" && auth.role !== "admin") return json(403, { ok: false, message: "not_allowed" });
      const { data: r, error: rErr } = await client.from("admin_requests")
        .select("id,member_id,request_type,status").eq("id", body.request_id).maybeSingle();
      if (rErr) throw rErr;
      if (!r || r.request_type !== "account_delete") return json(404, { ok: false, message: "request_not_found" });
      if (r.status !== "pending") return json(409, { ok: false, message: "already_handled" });
      const { data: target } = await client.from("profiles").select("id,role").eq("id", r.member_id).maybeSingle();
      if (!target) return json(404, { ok: false, message: "member_not_found" });
      if (target.role === "owner") return json(403, { ok: false, message: "Owner account is protected" });
      const { data: authId, error: aErr } = await client.rpc("account_auth_id", { p_profile_id: r.member_id });
      if (aErr) throw aErr;
      if (!authId) return json(404, { ok: false, message: "no_login_account" });
      targetAuthId = authId as string;
      targetProfileId = r.member_id as string;
      requestId = r.id as string;
    } else if (auth.role === "owner") {
      return json(403, { ok: false, message: "Owner account is protected" });
    } else if (auth.status === "active" && APPROVED_ROLES.includes(auth.role ?? "")) {
      // العضو المعتمد يحذف حسابه بطلب للإدارة فقط (قرار المالك ٢٠٢٦-١٠-٢٩)؛ الحذف الذاتي المباشر
      // لمن لم يُعتمد بعد (معلّق/بلا ملف) أو حساب غير مفعّل يُكمل تنظيفاً سابقاً.
      return json(403, {
        ok: false,
        error: "use_request",
        message: "use_request",
        message_ar: "حذف حساب العضو المعتمد يتم بطلب للإدارة: أرسل «طلب حذف الحساب» من الإعدادات، وتنفّذه الإدارة خلال ٧ أيام.",
      });
    }

    // الرقم قبل الحذف (الحذف يمسحه) — لرسالة التأكيد
    let phone: string | null = null;
    try {
      const [{ data: p }, { data: u }] = await Promise.all([
        client.from("profiles").select("phone_number").eq("id", targetProfileId).maybeSingle(),
        client.auth.admin.getUserById(targetAuthId),
      ]);
      phone = (u?.user?.phone as string | undefined) || (p?.phone_number as string | undefined) || null;
    } catch {
      phone = null;
    }

    await deleteAccountWorkflow({
      async prepare() {
        const { data, error } = await client.rpc("prepare_account_deletion", {
          p_auth_id: targetAuthId, p_profile_id: targetProfileId,
        });
        if (error) throw error;
        if (!data || !Array.isArray(data.storage_files)) throw new Error("Invalid cleanup job");
        return data.storage_files as DeletionFile[];
      },
      async remove(bucket, paths) {
        const { error } = await client.storage.from(bucket).remove(paths);
        if (error) throw error;
      },
      async finalize() {
        const { error } = await client.rpc("finalize_account_deletion", { p_auth_id: targetAuthId });
        if (error) throw error;
      },
      async deleteAuth() {
        const { error } = await client.auth.admin.deleteUser(targetAuthId);
        if (error) throw error;
      },
    });
    if (requestId) {
      await client.from("admin_requests").update({
        status: "approved", replied_at: new Date().toISOString(), replied_by: auth.profileId,
      }).eq("id", requestId);
    }
    await sendDeletedSms(client, phone);
    return json(200, { ok: true, message: "Account deleted" });
  } catch {
    console.error("Account deletion incomplete; retry the retained cleanup job");
    return json(500, { ok: false, message: "Account cleanup incomplete. Please retry." });
  }
});
