-- Family Stories table
CREATE TABLE IF NOT EXISTS public.family_stories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  image_url text NOT NULL,
  caption text,
  approval_status text NOT NULL DEFAULT 'pending',
  approved_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  approved_at timestamptz,
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  expires_at timestamptz NOT NULL DEFAULT timezone('utc', now()) + interval '24 hours'
);

-- RLS
ALTER TABLE public.family_stories ENABLE ROW LEVEL SECURITY;

-- Select: approved & not expired for all, pending for admins, own stories for creator
CREATE POLICY "stories_select" ON public.family_stories
FOR SELECT USING (
  (approval_status = 'approved' AND expires_at > now())
  OR current_user_role() IN ('admin', 'supervisor', 'owner')
  OR created_by = auth.uid()
);

-- Insert: any authenticated user
CREATE POLICY "stories_insert" ON public.family_stories
FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Update: admins only (for approval)
CREATE POLICY "stories_update" ON public.family_stories
FOR UPDATE USING (current_user_role() IN ('admin', 'supervisor', 'owner'));

-- Delete: admins or story creator
CREATE POLICY "stories_delete" ON public.family_stories
FOR DELETE USING (
  created_by = auth.uid()
  OR current_user_role() IN ('admin', 'supervisor', 'owner')
);

-- Index for active stories query
CREATE INDEX IF NOT EXISTS idx_stories_active ON public.family_stories (approval_status, expires_at DESC)
WHERE approval_status = 'approved';

CREATE INDEX IF NOT EXISTS idx_stories_member ON public.family_stories (member_id, created_at DESC);
