import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { handleCors, json } from "../_shared/cors.ts";
import { authenticateRequest, createServiceClient } from "../_shared/auth.ts";

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    // 1. التحقق من توكن المدير
    const auth = await authenticateRequest(req, ["owner", "admin"]);
    if (auth instanceof Response) return auth;

    const adminClient = createServiceClient();

    // 2. قراءة memberId من الطلب
    const { memberId } = await req.json();
    if (!memberId) {
      return json(400, { ok: false, message: "memberId is required" });
    }

    console.log(
      `🔓 Admin ${auth.user.id} unlinking phone for member: ${memberId}`
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
