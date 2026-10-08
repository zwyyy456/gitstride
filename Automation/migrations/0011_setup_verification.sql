ALTER TABLE setup_sessions ADD COLUMN verification_code_hash TEXT;
ALTER TABLE setup_sessions ADD COLUMN verification_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE setup_sessions ADD COLUMN browser_token_hash TEXT;

-- Existing unfinished sessions have no device confirmation and must restart.
DELETE FROM setup_sessions WHERE state != 'COMPLETE';
