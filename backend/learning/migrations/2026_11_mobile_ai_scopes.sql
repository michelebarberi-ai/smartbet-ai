-- B65 OPTIONAL migration. Do NOT invoke from LearningRepository.initialize().
-- Run only after an explicit deployment review and database approval.
-- Existing mobile tokens retain the least privilege: learning:predictions.
BEGIN;
ALTER TABLE public.sb_learning_clients_v1
  ADD COLUMN IF NOT EXISTS token_scopes TEXT NOT NULL
  DEFAULT 'learning:predictions';
COMMIT;
