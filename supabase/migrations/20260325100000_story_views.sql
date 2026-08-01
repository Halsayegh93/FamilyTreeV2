-- جدول مشاهدات القصص
CREATE TABLE IF NOT EXISTS family_story_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    story_id UUID NOT NULL REFERENCES family_stories(id) ON DELETE CASCADE,
    viewer_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    viewed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(story_id, viewer_id)
);

-- فهرس للبحث السريع
CREATE INDEX IF NOT EXISTS idx_story_views_story_id ON family_story_views(story_id);
CREATE INDEX IF NOT EXISTS idx_story_views_viewer_id ON family_story_views(viewer_id);

-- RLS
ALTER TABLE family_story_views ENABLE ROW LEVEL SECURITY;

-- الكل يقدر يشوف المشاهدات
CREATE POLICY "story_views_select" ON family_story_views
    FOR SELECT USING (true);

-- المستخدم المسجل يقدر يضيف مشاهدة
CREATE POLICY "story_views_insert" ON family_story_views
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
