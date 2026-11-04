-- SmartBet 1.2.2 P19E - staging. No user names, contacts, IPs or raw device IDs.
CREATE TABLE IF NOT EXISTS sb_learning_predictions_v1 (
  id BIGSERIAL PRIMARY KEY,
  subject_hash CHAR(64) NOT NULL,
  fixture_id INTEGER NOT NULL CHECK (fixture_id > 0),
  engine TEXT NOT NULL CHECK (engine IN ('smartBet', 'diego')),
  market TEXT NOT NULL CHECK (length(market) BETWEEN 1 AND 64),
  original_probability DOUBLE PRECISION NOT NULL CHECK (original_probability BETWEEN 0 AND 1),
  kickoff_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','correct','wrong')),
  actual_home_goals INTEGER,
  actual_away_goals INTEGER,
  resolved_at TIMESTAMPTZ,
  UNIQUE(subject_hash, fixture_id, engine, market)
);
-- Pending fixtures are rotated across repeated resolver runs so abandoned matches
-- cannot permanently starve newer completed fixtures.
ALTER TABLE sb_learning_predictions_v1
  ADD COLUMN IF NOT EXISTS last_checked_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS sb_learning_pending_check_v1
  ON sb_learning_predictions_v1 (last_checked_at, kickoff_at, fixture_id)
  WHERE status='pending';
CREATE INDEX IF NOT EXISTS sb_learning_pending_v1 ON sb_learning_predictions_v1 (kickoff_at, fixture_id) WHERE status='pending';
CREATE INDEX IF NOT EXISTS sb_learning_market_v1 ON sb_learning_predictions_v1 (engine, market, fixture_id) WHERE status!='pending';

-- P23B2A: opaque, admin-provisioned mobile credentials.
-- No raw access tokens are stored (only SHA-256 digests of 256-bit tokens).
-- No public self-enrollment, and no identity or contact information.
CREATE TABLE IF NOT EXISTS sb_learning_clients_v1 (
  client_id UUID PRIMARY KEY,
  token_hash CHAR(64) UNIQUE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS sb_learning_clients_valid_v1
  ON sb_learning_clients_v1 (expires_at)
  WHERE revoked_at IS NULL;
