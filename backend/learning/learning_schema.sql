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


-- B45 P2: historical copies are RESEARCH ONLY, never mixed with prospective predictions.
-- All dates, outcomes and probabilities in this table are supplied by the device,
-- NOT certified as pre-match or verified against the sports provider.
CREATE TABLE IF NOT EXISTS sb_learning_retrospective_v1 (
  id BIGSERIAL PRIMARY KEY,
  subject_hash CHAR(64) NOT NULL,
  fixture_id INTEGER NOT NULL CHECK (fixture_id > 0),
  engine TEXT NOT NULL CHECK (engine IN ('smartBet','diego')),
  market TEXT NOT NULL CHECK (length(market) BETWEEN 1 AND 64),
  original_probability DOUBLE PRECISION NOT NULL CHECK (original_probability BETWEEN 0 AND 1),
  claimed_first_seen_at TIMESTAMPTZ NOT NULL,
  claimed_kickoff_at TIMESTAMPTZ NOT NULL,
  local_status_hint TEXT NOT NULL CHECK (local_status_hint IN ('pending','correct','wrong')),
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  source_kind TEXT NOT NULL DEFAULT 'retrospective_unverified_v1',
  UNIQUE (subject_hash, fixture_id, engine, market)
);
CREATE INDEX IF NOT EXISTS sb_learning_retrospective_market_v1
  ON sb_learning_retrospective_v1(engine, market, fixture_id);


-- B45 P7: user preference draft only. NO automatic generation/worker/push.
-- Identifiers are HMAC-hashed; no raw user token or contact details stored.
CREATE TABLE IF NOT EXISTS sb_auto_coupon_preferences_v1 (
  subject_hash CHAR(64) PRIMARY KEY,
  preferences JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- B45 P8: coupon outcomes are private to each authenticated device and day.
-- This table does NOT start jobs and NEVER invents football predictions.
CREATE TABLE IF NOT EXISTS sb_auto_coupon_daily_runs_v1 (
  subject_hash CHAR(64) NOT NULL,
  local_day DATE NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('processing','ready','retry','unavailable')),
  attempts INTEGER NOT NULL DEFAULT 1 CHECK (attempts BETWEEN 1 AND 5),
  coupon_json JSONB,
  generated_at TIMESTAMPTZ,
  next_retry_at TIMESTAMPTZ,
  failure_reason TEXT CHECK (failure_reason IN ('insufficient_events','provider_unavailable')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (subject_hash, local_day),
  CONSTRAINT coupon_ready_requires_data CHECK (
    (status='ready' AND coupon_json IS NOT NULL AND generated_at IS NOT NULL)
    OR (status<>'ready' AND coupon_json IS NULL)
  )
);
CREATE INDEX IF NOT EXISTS sb_auto_coupon_retry_v1
  ON sb_auto_coupon_daily_runs_v1(next_retry_at) WHERE status='retry';

-- B45 P12: explicit push registration only. Tokens are AES-256-GCM encrypted
-- with a separate server-side key and purged when consent/device is revoked.
CREATE TABLE IF NOT EXISTS sb_auto_coupon_push_devices_v1 (
  subject_hash CHAR(64) PRIMARY KEY,
  apns_environment TEXT NOT NULL CHECK (apns_environment IN ('sandbox','production')),
  token_ciphertext TEXT NOT NULL,
  token_nonce TEXT NOT NULL,
  token_auth_tag TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- B45 P13: durable push-attempt guard, separate from coupon generation.
-- At most one successful APNs acceptance per subject/day while this record
-- survives; transport ambiguity can still cause APNs-level redelivery.
CREATE TABLE IF NOT EXISTS sb_auto_coupon_push_deliveries_v1 (
  subject_hash CHAR(64) NOT NULL,
  local_day DATE NOT NULL,
  status TEXT NOT NULL CHECK
    (status IN ('processing','sent','retry','unregistered','unavailable')),
  attempts INTEGER NOT NULL DEFAULT 1 CHECK (attempts BETWEEN 1 AND 5),
  failure_reason TEXT,
  next_retry_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (subject_hash,local_day)
);
CREATE INDEX IF NOT EXISTS sb_auto_coupon_push_retry_v1
  ON sb_auto_coupon_push_deliveries_v1(next_retry_at) WHERE status='retry';
