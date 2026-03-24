-- AI Rate Limits table for persistent rate limiting
CREATE TABLE IF NOT EXISTS ai_rate_limits (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);

-- Index for fast lookups by user_id and time window
CREATE INDEX IF NOT EXISTS idx_ai_rate_limits_user_time
    ON ai_rate_limits (user_id, created_at DESC);

-- Allow service role full access (edge functions use service role)
ALTER TABLE ai_rate_limits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on ai_rate_limits"
    ON ai_rate_limits
    FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- Auto-cleanup: delete entries older than 5 minutes (optional cron or trigger)
-- For now, cleanup is handled in the edge function itself
