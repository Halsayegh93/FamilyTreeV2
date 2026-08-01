-- Add request_id and request_type to notifications for actionable push
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS request_id  UUID NULL,
  ADD COLUMN IF NOT EXISTS request_type TEXT NULL;
