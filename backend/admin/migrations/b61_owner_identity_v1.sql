-- B61 OWNER V2: schema proposal only. NOT applied to production Neon.
-- One owner account, password hash and encrypted TOTP material only.
-- Never store a password, a clear TOTP seed, or a clear email OTP here.
CREATE TABLE IF NOT EXISTS public.sb_owner_account_v1 (
  id smallint PRIMARY KEY CHECK (id = 1),
  state jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.sb_owner_account_v1 (id, state)
VALUES (1, '{}'::jsonb)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.sb_owner_sessions_v1 (
  token_digest char(64) PRIMARY KEY,
  expires_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS sb_owner_sessions_expiry_idx
  ON public.sb_owner_sessions_v1 (expires_at);

-- Prior to enabling: apply in approved database branch, test, then
-- authorize production migration and verify role permissions.
-- Revoke public access: only the backend database role may read/write.
REVOKE ALL ON public.sb_owner_account_v1 FROM PUBLIC;
REVOKE ALL ON public.sb_owner_sessions_v1 FROM PUBLIC;
