-- Add device_id column for identifying devices independent of push tokens
ALTER TABLE device_tokens ADD COLUMN IF NOT EXISTS device_id TEXT;

-- Allow token to be nullable (device may register before getting push token)
ALTER TABLE device_tokens ALTER COLUMN token DROP NOT NULL;

-- Drop old unique index on token (since token can now be null)
DROP INDEX IF EXISTS idx_device_tokens_token_unique;

-- Create unique index on device_id per member (one entry per device per member)
CREATE UNIQUE INDEX IF NOT EXISTS idx_device_tokens_member_device_unique
  ON public.device_tokens(member_id, device_id);

-- Add delete policy so users can remove their own devices
DROP POLICY IF EXISTS "device_tokens_delete_self" ON public.device_tokens;
CREATE POLICY "device_tokens_delete_self" ON public.device_tokens
FOR DELETE
USING (member_id = auth.uid());
