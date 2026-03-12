-- Allow admins/supervisors to delete any member's device tokens
DROP POLICY IF EXISTS "device_tokens_delete_moderator" ON public.device_tokens;
CREATE POLICY "device_tokens_delete_moderator" ON public.device_tokens
FOR DELETE
USING (
  public.current_user_role() IN ('supervisor', 'admin')
);

-- Ensure token column is nullable (may not have been applied in some environments)
ALTER TABLE device_tokens ALTER COLUMN token DROP NOT NULL;

-- Ensure device_id and device_name columns exist
ALTER TABLE device_tokens ADD COLUMN IF NOT EXISTS device_id TEXT;
ALTER TABLE device_tokens ADD COLUMN IF NOT EXISTS device_name TEXT;

-- Ensure unique index on member_id + device_id exists
CREATE UNIQUE INDEX IF NOT EXISTS idx_device_tokens_member_device_unique
  ON public.device_tokens(member_id, device_id);
