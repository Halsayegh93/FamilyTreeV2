import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // 1. التحقق من توكن المدير
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json(401, { ok: false, message: "Missing authorization header" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // التحقق من أن المستدعي هو مدير
    const callerClient = createClient(supabaseUrl, serviceRoleKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user: caller },
      error: callerError,
    } = await callerClient.auth.getUser();

    if (callerError || !caller) {
      return json(401, { ok: false, message: "Invalid or expired token" });
    }

    // التحقق من صلاحية المدير
    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    const { data: callerProfile } = await adminClient
      .from("profiles")
      .select("role")
      .eq("id", caller.id)
      .single();

    if (
      !callerProfile ||
      (callerProfile.role !== "admin" && callerProfile.role !== "supervisor")
    ) {
      return json(403, {
        ok: false,
        message: "Only admins can unlink phone numbers",
      });
    }

    // 2. قراءة memberId من الطلب
    const { memberId } = await req.json();
    if (!memberId) {
      return json(400, { ok: false, message: "memberId is required" });
    }

    console.log(
      `🔓 Admin ${caller.id} unlinking phone for member: ${memberId}`
    );

    // 3. جلب بيانات العضو لمعرفة رقمه
    const { data: memberProfile } = await adminClient
      .from("profiles")
      .select("id, phone_number, full_name")
      .eq("id", memberId)
      .single();

    if (!memberProfile) {
      return json(404, { ok: false, message: "Member not found" });
    }

    // 4. البحث عن auth user المرتبط بهذا المعرف وحذفه
    try {
      const { error: deleteAuthError } =
        await adminClient.auth.admin.deleteUser(memberId);

      if (deleteAuthError) {
        console.log(
          `⚠️ Could not delete auth user ${memberId}: ${deleteAuthError.message}`
        );
        // ليس خطأ حرج — قد لا يكون هناك auth user مرتبط
      } else {
        console.log(`✅ Auth user ${memberId} deleted`);
      }
    } catch (e) {
      console.log(`⚠️ Auth user deletion skipped: ${e}`);
    }

    // 5. مسح الرقم وتعليق الحساب في profiles
    await adminClient
      .from("profiles")
      .update({
        phone_number: null,
        status: "pending",
      })
      .eq("id", memberId);

    // 6. حذف device tokens
    await adminClient
      .from("device_tokens")
      .delete()
      .eq("user_id", memberId);

    console.log(
      `✅ Phone unlinked for ${memberProfile.full_name} (${memberId})`
    );
    return json(200, {
      ok: true,
      message: "Phone unlinked and auth user deleted successfully",
    });
  } catch (err) {
    console.error("❌ Admin unlink phone error:", err);
    return json(500, {
      ok: false,
      message: err instanceof Error ? err.message : "Unknown error",
    });
  }
});
