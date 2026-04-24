-- Add environment column to device_tokens for APNs sandbox/production routing.
-- Fixes: Debug builds generate sandbox tokens but the Edge Function was sending
-- them to production APNs host → BadDeviceToken (400) → auto-delete → silent failure.

ALTER TABLE public.device_tokens
  ADD COLUMN IF NOT EXISTS environment TEXT NOT NULL DEFAULT 'production'
  CHECK (environment IN ('sandbox', 'production'));

CREATE INDEX IF NOT EXISTS idx_device_tokens_environment
  ON public.device_tokens(environment);
