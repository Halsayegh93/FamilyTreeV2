import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { handleCors, json } from "../_shared/cors.ts";
import { createServiceClient } from "../_shared/auth.ts";

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const supabase = createServiceClient();

  try {
    // 1. جلب الستوريات المنتهية
    const { data: expiredStories, error: fetchError } = await supabase
      .from("family_stories")
      .select("id, member_id, image_url")
      .lt("expires_at", new Date().toISOString());

    if (fetchError) {
      console.error("Error fetching expired stories:", fetchError);
      return json(500, { ok: false, message: fetchError.message });
    }

    if (!expiredStories || expiredStories.length === 0) {
      return json(200, {
        ok: true,
        message: "No expired stories to clean up",
        deleted: 0,
      });
    }

    // 2. حذف الصور من Storage
    const storagePaths: string[] = [];
    for (const story of expiredStories) {
      // استخراج المسار من URL
      // URL format: .../storage/v1/object/public/stories/story_{memberId}/{storyId}.jpg
      const url = story.image_url as string;
      const storiesIndex = url.indexOf("/stories/");
      if (storiesIndex !== -1) {
        const path = url.substring(storiesIndex + "/stories/".length);
        storagePaths.push(path);
      }
    }

    let storageDeleted = 0;
    if (storagePaths.length > 0) {
      // حذف دفعة واحدة (max 1000 per batch)
      const batchSize = 100;
      for (let i = 0; i < storagePaths.length; i += batchSize) {
        const batch = storagePaths.slice(i, i + batchSize);
        const { data: removeData, error: removeError } = await supabase.storage
          .from("stories")
          .remove(batch);

        if (removeError) {
          console.error(
            `Storage delete error (batch ${i / batchSize + 1}):`,
            removeError
          );
        } else {
          storageDeleted += removeData?.length ?? 0;
        }
      }
    }

    // 3. حذف السجلات من القاعدة
    const expiredIds = expiredStories.map((s) => s.id);
    const { error: deleteError } = await supabase
      .from("family_stories")
      .delete()
      .in("id", expiredIds);

    if (deleteError) {
      console.error("Error deleting expired story records:", deleteError);
      return json(500, {
        ok: false,
        message: `Storage cleaned (${storageDeleted}), but DB delete failed: ${deleteError.message}`,
      });
    }

    console.log(
      `Cleanup complete: ${expiredStories.length} stories, ${storageDeleted} files`
    );

    return json(200, {
      ok: true,
      deleted: expiredStories.length,
      storageFilesRemoved: storageDeleted,
    });
  } catch (e) {
    console.error("Cleanup error:", e);
    return json(500, {
      ok: false,
      message: `Cleanup failed: ${(e as Error).message}`,
    });
  }
});
