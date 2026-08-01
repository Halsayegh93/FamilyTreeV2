// ============================================================================
// cleanup-tokens — مهمة دورية لتنظيف توكنات الأجهزة القديمة/غير الصالحة
// ============================================================================
// يُستدعى عبر Supabase Scheduler (cron) أسبوعياً. يحذف:
//  1. Tokens فاضية أو null
//  2. Tokens قصيرة (< 20 حرف — توكن APNs صحيح > 20)
//  3. Tokens ما تحدثت منذ 60 يوماً (المستخدم حذف التطبيق/ما فتحه)
// ============================================================================

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { handleCors, json } from "../_shared/cors.ts";
import { createServiceClient } from "../_shared/auth.ts";

const STALE_DAYS = 60;

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const supabase = createServiceClient();

  try {
    const staleThreshold = new Date();
    staleThreshold.setDate(staleThreshold.getDate() - STALE_DAYS);
    const staleISO = staleThreshold.toISOString();

    // 1. إحصائيات قبل الحذف (للتقرير)
    const { count: totalBefore } = await supabase
      .from("device_tokens")
      .select("*", { count: "exact", head: true });

    // 2-3. جلب كل الصفوف لتحديد null/empty/short tokens بالـ JS (PostgREST filter limited for length)
    const { data: allRows, error: fetchErr } = await supabase
      .from("device_tokens")
      .select("id, token");

    if (fetchErr) {
      console.error("[cleanup-tokens] fetch error:", fetchErr);
      return json(500, { ok: false, message: fetchErr.message });
    }

    const invalidIds = (allRows ?? [])
      .filter((r) => {
        const t = (r.token ?? "").trim();
        return t.length < 20; // يشمل null/empty/short معاً
      })
      .map((r) => r.id);

    let invalidDeleted: { id: number }[] = [];
    if (invalidIds.length > 0) {
      const { data, error } = await supabase
        .from("device_tokens")
        .delete()
        .in("id", invalidIds)
        .select("id");

      if (error) {
        console.error("[cleanup-tokens] invalid delete error:", error);
      } else {
        invalidDeleted = data ?? [];
      }
    }

    // 4. حذف التوكنات القديمة (> STALE_DAYS)
    const { data: staleDeleted, error: staleErr } = await supabase
      .from("device_tokens")
      .delete()
      .lt("updated_at", staleISO)
      .select("id");

    if (staleErr) {
      console.error("[cleanup-tokens] stale delete error:", staleErr);
      return json(500, { ok: false, message: staleErr.message });
    }

    // 5. إحصائيات بعد الحذف
    const { count: totalAfter } = await supabase
      .from("device_tokens")
      .select("*", { count: "exact", head: true });

    const report = {
      ok: true,
      before: totalBefore ?? 0,
      after: totalAfter ?? 0,
      deleted: {
        invalidTokens: invalidDeleted.length,
        stale: staleDeleted?.length ?? 0,
        total: invalidDeleted.length + (staleDeleted?.length ?? 0),
      },
      staleThresholdDays: STALE_DAYS,
    };

    console.log("[cleanup-tokens] report:", report);
    return json(200, report);
  } catch (e) {
    console.error("[cleanup-tokens] exception:", e);
    return json(500, { ok: false, message: (e as Error).message });
  }
});
