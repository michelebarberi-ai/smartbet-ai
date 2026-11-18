'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {LearningRepository} = require('../learning/learning_repository');

test('AI authorization SQL requires explicit ai:analyze scope and valid token', async () => {
  const received = [];
  const repository = new LearningRepository({
    query: async (sql, args) => {
      received.push({sql, args});
      if (sql.includes('AND $3 = ANY') && args[2] === 'ai:analyze') {
        return {rows: [{client_id: 'valid-ai-install'}]};
      }
      return {rows: []};
    },
  });
  assert.equal(await repository.findValidClientForScope(
    'a'.repeat(64), new Date('2026-11-18T10:00:00Z'), 'ai:analyze',
  ), 'valid-ai-install');
  assert.match(received[0].sql, /token_hash=\$1/);
  assert.match(received[0].sql, /expires_at>\$2/);
  assert.match(received[0].sql, /revoked_at IS NULL/);
  assert.match(received[0].sql, /token_scopes/);
  assert.equal(await repository.findValidClientForScope(
    'a'.repeat(64), new Date(), 'learning:predictions',
  ), null);
  assert.equal(received.length, 1);
});

test('legacy default scope stays learning-only', async () => {
  const entries = [];
  const repository = new LearningRepository({
    query: async (sql, args) => {
      entries.push({sql, args});
      return {rows: [{client_id: 'legacy'}]};
    },
  });
  await repository.insertClientCredential({
    clientId: 'legacy', tokenHash: 'b'.repeat(64),
    expiresAt: new Date('2026-12-20T00:00:00Z'),
  });
  assert.deepEqual(entries[0].args.slice(0, 3), [
    'legacy', 'b'.repeat(64), new Date('2026-12-20T00:00:00Z'),
  ]);
  assert.equal(entries[0].args.length, 3);
  assert.doesNotMatch(entries[0].sql, /token_scopes/);
  await assert.rejects(repository.insertClientCredential({
    clientId: 'invalid', tokenHash: 'x'.repeat(64), expiresAt: new Date(),
    scopes: 'ai:analyze owner:admin',
  }));
});

test('AI scope check is an exact token, not a substring match', async () => {
  let sql, params;
  const repo = new LearningRepository({
    query: async (q, p) => {
      sql = q;
      params = p;
      return {rows: []};
    },
  });
  await repo.findValidClientForScope('c'.repeat(64), new Date(), 'ai:analyze');
  assert.match(sql, /\$3 = ANY\(string_to_array\(token_scopes, ' '\)\)/);
  assert.equal(params[2], 'ai:analyze');
});

test('repository initialize never applies the optional AI scope migration', async () => {
  let startupSql = null;
  const repo = new LearningRepository({
    query: async (sql) => {
      startupSql = sql;
      return {rows: []};
    },
  });
  await repo.initialize();
  assert.equal(typeof startupSql, 'string');
  assert.match(startupSql, /CREATE TABLE IF NOT EXISTS sb_learning_clients_v1/);
  assert.doesNotMatch(startupSql, /ALTER TABLE sb_learning_clients_v1[\\s\\S]*token_scopes/);
  assert.doesNotMatch(startupSql, /ADD COLUMN IF NOT EXISTS token_scopes/);
});

test('AI credential issuance fails closed until optional migration is approved', async () => {
  const calls = [];
  const repo = new LearningRepository({
    query: async (sql, args) => {
      calls.push({sql, args});
      if (/token_scopes/.test(sql)) {
        const err = new Error('column token_scopes does not exist');
        err.code = '42703';
        throw err;
      }
      return {rows: []};
    },
  });
  await repo.insertClientCredential({
    clientId: 'legacy',
    tokenHash: 'd'.repeat(64),
    expiresAt: new Date('2026-12-20T00:00:00Z'),
  });
  assert.equal(calls[0].args.length, 3);
  await assert.rejects(
    repo.insertClientCredential({
      clientId: 'ai',
      tokenHash: 'e'.repeat(64),
      expiresAt: new Date('2026-12-20T00:00:00Z'),
      scopes: 'learning:predictions ai:analyze',
    }),
    {code: '42703'},
  );
  await assert.rejects(
    repo.findValidClientForScope('e'.repeat(64), new Date(), 'ai:analyze'),
    {code: '42703'},
  );
});
