'use strict';

// P20.3A: optional single-host, persistent-volume job journal for the
// Flutter-enabled runner. It is NOT a substitute for the Neon worker claims.
// Records contain only generation preferences and verified output, never a
// mobile identifier, APNs token, HTTP bearer token or backend credential.
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');

const JOB_ID = /^[a-f0-9]{32}$/;
const SIGNATURE = /^[a-f0-9]{64}$/;
const MAX_FILE_BYTES = 131072;
const STATUSES = new Set(['running', 'ready', 'failed', 'no_coupon']);

function fromRecord(record) {
  if (!record || !JOB_ID.test(record.id || '') ||
      !SIGNATURE.test(record.signature || '') ||
      !STATUSES.has(record.status) ||
      typeof record.createdAt !== 'string' ||
      !Number.isFinite(Date.parse(record.createdAt)) ||
      !record.request || typeof record.request !== 'object' ||
      Array.isArray(record.request)) return null;
  return {
    createdAt: new Date(record.createdAt),
    signature: record.signature,
    request: record.request,
    // An interrupted Flutter subprocess may have died with the host.  Never
    // publish an in-progress result as ready after a process restart.
    status: record.status === 'running' ? 'failed' : record.status,
    result: record.status === 'ready' ? record.result : null,
  };
}

function createDurableHeadlessJobStore(directory) {
  if (typeof directory !== 'string' || !path.isAbsolute(directory)) {
    throw new Error('Headless journal requires an absolute directory');
  }
  const fileFor = id => {
    if (!JOB_ID.test(id)) throw new Error('Invalid job identifier');
    return path.join(directory, `${id}.json`);
  };
  async function initialize() {
    await fs.mkdir(directory, {recursive: true, mode: 0o700});
    const stat = await fs.lstat(directory);
    if (!stat.isDirectory() || stat.isSymbolicLink()) {
      throw new Error('Invalid journal directory');
    }
  }
  return {
    async load() {
      await initialize();
      const records = new Map();
      for (const filename of await fs.readdir(directory)) {
        if (!/^[a-f0-9]{32}\.json$/.test(filename)) continue;
        const file = fileFor(filename.slice(0, -5));
        const stat = await fs.lstat(file);
        if (!stat.isFile() || stat.isSymbolicLink() ||
            stat.size > MAX_FILE_BYTES) throw new Error('Invalid journal entry');
        const body = await fs.readFile(file, 'utf8');
        let parsed;
        try { parsed = JSON.parse(body); } catch (_) { throw new Error('Invalid journal JSON'); }
        const job = fromRecord(parsed);
        if (!job || parsed.id !== filename.slice(0, -5)) {
          throw new Error('Invalid journal record');
        }
        // Incomplete work is treated as failed, not silently resumed or
        // advertised as completed. The caller can retry via its Neon claim.
        if (parsed.status === 'running') await this.save(parsed.id, job);
        records.set(parsed.id, job);
      }
      return records;
    },
    async save(id, job) {
      await initialize();
      const record = {id, createdAt:job.createdAt.toISOString(),
        signature:job.signature, request:job.request, status:job.status,
        result:job.status === 'ready' ? job.result : null};
      if (!fromRecord(record)) throw new Error('Invalid journal write');
      const data = JSON.stringify(record);
      if (Buffer.byteLength(data) > MAX_FILE_BYTES) throw new Error('Journal record too large');
      const temp = path.join(directory, `.${id}.${crypto.randomBytes(8).toString('hex')}.tmp`);
      try {
        await fs.writeFile(temp, data, {encoding:'utf8', mode:0o600, flag:'wx'});
        await fs.rename(temp, fileFor(id));
      } finally { await fs.rm(temp, {force:true}); }
    },
    async remove(id) {
      await fs.rm(fileFor(id), {force:true});
    },
  };
}

module.exports = {createDurableHeadlessJobStore};
