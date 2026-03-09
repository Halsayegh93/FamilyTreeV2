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
    // 1. Verify the user's JWT token
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json(401, { ok: false, message: "Missing authorization header" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Create client with user's JWT to get their identity
    const userClient = createClient(supabaseUrl, serviceRoleKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();

    if (userError || !user) {
      return json(401, { ok: false, message: "Invalid or expired token" });
    }

    const userId = user.id;
    console.log(`🗑️ Delete account requested for user: ${userId}`);

    // 2. Create admin client with service role key
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    // 3. Delete user's personal activity data
    await adminClient.from("news_poll_votes").delete().eq("member_id", userId);
    await adminClient.from("news_posts").delete().eq("author_id", userId);
    await adminClient.from("notifications").delete().eq("member_id", userId);
    await adminClient.from("push_tokens").delete().eq("member_id", userId);
    await adminClient.from("admin_requests").delete().eq("member_id", userId);
    await adminClient.from("diwaniyas").delete().eq("owner_id", userId);
    await adminClient
      .from("member_gallery_photos")
      .delete()
      .eq("member_id", userId);

    // 4. ANONYMIZE profile instead of deleting it
    //    This keeps the tree structure intact — children keep their father_id link
    //    The node stays in the tree but shows as "عضو محذوف" with no personal data
    const { error: updateError } = await adminClient
      .from("profiles")
      .update({
        first_name: "عضو محذوف",
        full_name: "عضو محذوف",
        phone_number: null,
        birth_date: null,
        death_date: null,
        is_deceased: false,
        photo_url: null,
        avatar_url: null,
        bio_json: null,
        role: "member",
        status: "deleted",
        is_phone_hidden: true,
        is_married: null,
      })
      .eq("id", userId);

    if (updateError) {
      console.error("❌ Failed to anonymize profile:", updateError.message);
      return json(500, {
        ok: false,
        message: "Failed to anonymize profile: " + updateError.message,
      });
    }

    // 5. Delete storage files (avatar + gallery)
    try {
      await adminClient.storage.from("avatars").remove([`${userId}.jpg`]);
      // Gallery photos in member-gallery bucket
      const { data: galleryFiles } = await adminClient.storage
        .from("member-gallery")
        .list(`${userId}`);
      if (galleryFiles && galleryFiles.length > 0) {
        const paths = galleryFiles.map((f) => `${userId}/${f.name}`);
        await adminClient.storage.from("member-gallery").remove(paths);
      }
    } catch {
      console.log("⚠️ Storage cleanup best-effort (some files may not exist)");
    }

    // 6. Delete the auth user (they can no longer log in)
    const { error: deleteError } =
      await adminClient.auth.admin.deleteUser(userId);

    if (deleteError) {
      console.error("❌ Failed to delete auth user:", deleteError.message);
      return json(500, {
        ok: false,
        message: "Failed to delete auth user: " + deleteError.message,
      });
    }

    console.log(
      `✅ Account ${userId} anonymized in tree & auth user deleted`
    );
    return json(200, {
      ok: true,
      message: "Account deleted and anonymized successfully",
    });
  } catch (err) {
    console.error("❌ Delete account error:", err);
    return json(500, {
      ok: false,
      message: err instanceof Error ? err.message : "Unknown error",
    });
  }
});
