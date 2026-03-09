-- Add device_name column to device_tokens table
ALTER TABLE device_tokens ADD COLUMN IF NOT EXISTS device_name TEXT;
