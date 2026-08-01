-- Add JSON details column for storing structured change metadata on admin-edit notifications
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS details JSONB NULL;

COMMENT ON COLUMN public.notifications.details IS
  'Structured change metadata for admin-edit notifications. Format: { "v": 1, "changes": [{"field": "...", "before": "...", "after": "..."}] }';
