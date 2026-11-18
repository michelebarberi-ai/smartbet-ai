-- Build 66: manual, opt-in schema migration.
-- Apply ONLY after review on staging, then separately authorize production.
-- Existing predictions and their unique keys are preserved; never backfill.
-- Migration is NOT executed automatically by the Node API.
--
-- One optional provenance marker for the mathematical simulator.
-- This is an INPUT dependency, not evidence of an independent engine.
BEGIN;

ALTER TABLE public.sb_learning_predictions_v1
  ADD COLUMN IF NOT EXISTS simulator_input_source TEXT;

ALTER TABLE public.sb_learning_predictions_v1
  DROP CONSTRAINT IF EXISTS sb_learning_predictions_v1_engine_check;

ALTER TABLE public.sb_learning_predictions_v1
  ADD CONSTRAINT sb_learning_predictions_v1_engine_check
  CHECK (engine IN ('smartBet','diego','simulator'));

-- Run-once constraint creation that allows safe re-review of the SQL file.
DO $b66$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.sb_learning_predictions_v1'::regclass
      AND conname = 'sb_learning_simulator_source_b66_check'
  ) THEN
    ALTER TABLE public.sb_learning_predictions_v1
      ADD CONSTRAINT sb_learning_simulator_source_b66_check
      CHECK (
        (engine = 'simulator'
          AND simulator_input_source IS NOT NULL
          AND simulator_input_source IN ('smartBet','diego'))
        OR (engine <> 'simulator' AND simulator_input_source IS NULL)
      );
  END IF;
END
$b66$;

COMMIT;

-- Deployment order:
-- (1) Migrate staging; validate historical rows and constraints.
-- (2) Deploy backend with LEARNING_SIMULATOR_INGEST_ENABLED=false.
-- (3) After explicit approval + production migration, set
--     LEARNING_SIMULATOR_SCHEMA_READY=true and
--     LEARNING_SIMULATOR_INGEST_ENABLED=true.
-- Both flags remain false by default. No Flutter secrets or admin keys.
