-- B73: separate daily fixture-summary subscription, NOT automatic betting coupons.
-- Staging-first: never apply to production without separate approval.
-- No raw client id, bearer token, APNs plaintext token, betting selections or odds.
CREATE TABLE IF NOT EXISTS public.sb_daily_palinsesto_subscriptions_v1 (
  subject_hash CHAR(64) PRIMARY KEY,
  hour SMALLINT NOT NULL DEFAULT 8 CHECK (hour BETWEEN 0 AND 23),
  minute SMALLINT NOT NULL DEFAULT 0 CHECK (minute BETWEEN 0 AND 59),
  apns_environment TEXT NOT NULL CHECK (apns_environment IN ('sandbox','production')),
  token_ciphertext TEXT NOT NULL,
  token_nonce TEXT NOT NULL,
  token_auth_tag TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- A durable per-recipient, per-Rome-calendar-day claim avoids repeats.
-- A processing claim can be recovered after 15 min; APNs can still
-- deliver a duplicate if acceptance happened before the process died.
CREATE TABLE IF NOT EXISTS public.sb_daily_palinsesto_deliveries_v1 (
  subject_hash CHAR(64) NOT NULL,
  local_day DATE NOT NULL,
  status TEXT NOT NULL CHECK(status IN
    ('processing','retry','sent','unregistered','failed')),
  attempts SMALLINT NOT NULL DEFAULT 1 CHECK (attempts BETWEEN 1 AND 5),
  lock_token UUID NOT NULL,
  next_retry_at TIMESTAMPTZ,
  accepted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (subject_hash,local_day)
);
CREATE INDEX IF NOT EXISTS sb_daily_palinsesto_retry_v1
  ON public.sb_daily_palinsesto_deliveries_v1(next_retry_at)
  WHERE status='retry';
