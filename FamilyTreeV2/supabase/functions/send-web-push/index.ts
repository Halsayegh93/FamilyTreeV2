// send-web-push — Edge Function لإرسال Web Push للمتصفحات
// يستخدم web-push protocol مع VAPID

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAPID_PUBLIC = Deno.env.get("VAPID_PUBLIC_KEY")!;
const VAPID_PRIVATE = Deno.env.get("VAPID_PRIVATE_KEY")!;
const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT") || "mailto:admin@familytree.app";

webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC, VAPID_PRIVATE);

interface Payload {
  title: string;
  body: string;
  icon?: string;
  tag?: string;
  url?: string;
  member_ids?: string[]; // إذا فاضي → broadcast لكل المدراء
  request_id?: string;
  request_type?: string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  try {
    const payload = (await req.json()) as Payload;
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

    // اجلب الاشتراكات
    let subsQuery = supabase.from("web_push_subscriptions").select("endpoint, p256dh, auth_key, member_id");
    if (payload.member_ids?.length) {
      subsQuery = subsQuery.in("member_id", payload.member_ids);
    } else {
      // broadcast لكل المدراء
      const { data: admins } = await supabase
        .from("profiles")
        .select("id")
        .in("role", ["owner", "admin", "monitor", "supervisor"]);
      const adminIds = admins?.map((a) => a.id) || [];
      if (adminIds.length === 0) return new Response(JSON.stringify({ sent: 0 }), { status: 200 });
      subsQuery = subsQuery.in("member_id", adminIds);
    }

    const { data: subs, error: subsErr } = await subsQuery;
    if (subsErr) throw subsErr;
    if (!subs || subs.length === 0) {
      return new Response(JSON.stringify({ sent: 0, reason: "no subscriptions" }), { status: 200 });
    }

    const notification = JSON.stringify({
      title: payload.title,
      body: payload.body,
      icon: payload.icon,
      tag: payload.tag,
      data: {
        url: payload.url || "/home",
        request_id: payload.request_id,
        request_type: payload.request_type,
      },
    });

    let sent = 0;
    let failed = 0;
    const expired: string[] = [];

    await Promise.all(
      subs.map(async (sub) => {
        const subscription = {
          endpoint: sub.endpoint,
          keys: { p256dh: sub.p256dh, auth: sub.auth_key },
        };
        try {
          await webpush.sendNotification(subscription, notification);
          sent++;
        } catch (e: any) {
          failed++;
          // 410 Gone أو 404 = الاشتراك انتهى صلاحيته
          if (e.statusCode === 410 || e.statusCode === 404) {
            expired.push(sub.endpoint);
          }
        }
      })
    );

    // نظف الاشتراكات المنتهية
    if (expired.length > 0) {
      await supabase.from("web_push_subscriptions").delete().in("endpoint", expired);
    }

    return new Response(JSON.stringify({ sent, failed, cleaned: expired.length }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  } catch (e: any) {
    console.error("[send-web-push] error:", e);
    return new Response(JSON.stringify({ error: e?.message || "unknown" }), { status: 500 });
  }
});
