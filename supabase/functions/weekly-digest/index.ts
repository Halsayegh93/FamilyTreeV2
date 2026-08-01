import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { handleCors, json } from "../_shared/cors.ts";
import { createServiceClient } from "../_shared/auth.ts";

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const supabase = createServiceClient();

  // Calculate date range: last 7 days
  const now = new Date();
  const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  const weekAgoISO = weekAgo.toISOString();

  // Fetch stats in parallel
  const [membersResult, newsResult, diwaniyasResult, upcomingBirthdays] = await Promise.all([
    // New members in the last 7 days
    supabase
      .from("profiles")
      .select("id, first_name, full_name, created_at")
      .gte("created_at", weekAgoISO)
      .eq("status", "active"),

    // News posts in the last 7 days
    supabase
      .from("news")
      .select("id, content, created_at, author_id")
      .gte("created_at", weekAgoISO)
      .eq("approval_status", "approved"),

    // Diwaniyas in the last 7 days
    supabase
      .from("diwaniyas")
      .select("id, title, created_at")
      .gte("created_at", weekAgoISO),

    // Upcoming birthdays (next 7 days)
    (async () => {
      const { data: allMembers } = await supabase
        .from("profiles")
        .select("id, first_name, full_name, birth_date")
        .eq("status", "active")
        .not("birth_date", "is", null)
        .eq("is_deceased", false);

      if (!allMembers) return [];

      const upcoming: Array<{ name: string; date: string }> = [];
      for (const m of allMembers) {
        if (!m.birth_date) continue;
        const parts = (m.birth_date as string).split("-");
        if (parts.length < 3) continue;

        const bMonth = parseInt(parts[1]);
        const bDay = parseInt(parts[2]);

        // Check if birthday falls in the next 7 days
        for (let d = 0; d < 7; d++) {
          const check = new Date(now.getTime() + d * 24 * 60 * 60 * 1000);
          if (check.getMonth() + 1 === bMonth && check.getDate() === bDay) {
            upcoming.push({
              name: m.first_name || m.full_name,
              date: m.birth_date as string,
            });
            break;
          }
        }
      }
      return upcoming;
    })(),
  ]);

  const newMembers = membersResult.data ?? [];
  const newNews = newsResult.data ?? [];
  const newDiwaniyas = diwaniyasResult.data ?? [];
  const birthdays = upcomingBirthdays;

  // Build digest
  const totalMembers = await supabase.from("profiles").select("id", { count: "exact", head: true }).eq("status", "active");
  const totalCount = totalMembers.count ?? 0;

  // Build Arabic notification text
  const lines: string[] = [];

  if (newMembers.length > 0) {
    lines.push(`👤 ${newMembers.length} عضو جديد انضم هالأسبوع`);
  }
  if (newNews.length > 0) {
    lines.push(`📰 ${newNews.length} خبر جديد`);
  }
  if (newDiwaniyas.length > 0) {
    lines.push(`🏠 ${newDiwaniyas.length} ديوانية جديدة`);
  }
  if (birthdays.length > 0) {
    const birthdayNames = birthdays.slice(0, 3).map((b) => b.name).join(" و ");
    lines.push(`🎂 أعياد ميلاد قادمة: ${birthdayNames}${birthdays.length > 3 ? ` و ${birthdays.length - 3} آخرين` : ""}`);
  }

  if (lines.length === 0) {
    lines.push("لا توجد أحداث جديدة هالأسبوع");
  }

  const titleAr = `📋 ملخص الأسبوع — عائلة آل محمد علي`;
  const bodyAr = lines.join("\n");

  // Fetch all active member IDs
  const { data: allActive } = await supabase
    .from("profiles")
    .select("id")
    .eq("status", "active");

  const allActiveIds = (allActive ?? []).map((m) => m.id as string);

  try {
    // 1. Insert notification rows
    const notificationRows = allActiveIds.map((memberId) => ({
      target_member_id: memberId,
      title: titleAr,
      body: bodyAr,
      kind: "weekly_digest",
      is_read: false,
    }));

    if (notificationRows.length > 0) {
      await supabase.from("notifications").insert(notificationRows);
    }

    // 2. Send push notification
    const pushResponse = await supabase.functions.invoke("push-notify", {
      body: {
        title: titleAr,
        body: bodyAr,
        kind: "weekly_digest",
      },
    });

    return json(200, {
      ok: true,
      digest: {
        totalMembers: totalCount,
        newMembers: newMembers.length,
        newNews: newNews.length,
        newDiwaniyas: newDiwaniyas.length,
        upcomingBirthdays: birthdays.length,
      },
      notified: allActiveIds.length,
      push: pushResponse.data,
    });
  } catch (e) {
    return json(500, { ok: false, message: `Error sending digest: ${(e as Error).message}` });
  }
});
