-- Create stories storage bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('stories', 'stories', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

-- RLS policies for stories bucket

-- Anyone can view (public bucket)
CREATE POLICY "stories_public_read"
ON storage.objects FOR SELECT
USING (bucket_id = 'stories');

-- Authenticated users can upload
CREATE POLICY "stories_auth_upload"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'stories' AND auth.uid() IS NOT NULL);

-- Admins or file owner can delete
CREATE POLICY "stories_delete"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'stories'
  AND (
    auth.uid()::text = (storage.foldername(name))[1]
    OR current_user_role() IN ('admin', 'supervisor', 'owner')
  )
);
