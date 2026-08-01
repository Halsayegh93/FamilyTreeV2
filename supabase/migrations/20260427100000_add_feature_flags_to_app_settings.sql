ALTER TABLE app_settings
  ADD COLUMN IF NOT EXISTS polls_enabled      BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS stories_enabled    BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS diwaniyas_enabled  BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS projects_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS albums_enabled     BOOLEAN NOT NULL DEFAULT TRUE;

UPDATE app_settings
SET
  polls_enabled     = COALESCE(polls_enabled, TRUE),
  stories_enabled   = COALESCE(stories_enabled, TRUE),
  diwaniyas_enabled = COALESCE(diwaniyas_enabled, TRUE),
  projects_enabled  = COALESCE(projects_enabled, TRUE),
  albums_enabled    = COALESCE(albums_enabled, TRUE);
