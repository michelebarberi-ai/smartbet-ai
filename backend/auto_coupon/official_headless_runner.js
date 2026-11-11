'use strict';

// P18 experimental service for a SEPARATE Flutter-equipped runner. The real
// SmartBetAutoCouponService runs inside a headless Flutter test process.
// No timers, wagers or user data. Host is loopback-only by default.
const http = require('node:http');
const crypto = require('node:crypto');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs/promises');
const {spawn} = require('node:child_process');
const {limitedAppend, classifyFlutterFailure, diagnosticError, reportFailure} =
  require('./headless_failure_diagnostics');
const {validToken} = require('../learning/learning_core');
const {validatePreferences, localClock, validateGeneratedCoupon} = require('./daily_schedule');
const {PROTOCOL} = require('./official_engine_client');
const {createDurableHeadlessJobStore} = require('./durable_headless_job_store');

const REVISION = /^[a-f0-9]{7,40}$/;
const JOB_ID = /^[0-9a-f]{32}$/;
const MAX_REQUEST_BYTES = 8192;
const MAX_RESULT_BYTES = 65536;
const JOB_TTL_MS = 30 * 60 * 1000;

function validateRequest(body, at = new Date()) {
  if (!body || typeof body !== 'object' || Array.isArray(body) ||
      Object.keys(body).some(k => !['protocol','dayKey','generatedAfter','preferences'].includes(k)) ||
      body.protocol !== PROTOCOL || !/^\d{4}-\d{2}-\d{2}$/.test(body.dayKey || '') ||
      !validatePreferences(body.preferences) || !body.preferences.requested ||
      typeof body.generatedAfter !== 'string') return false;
  const timestamp = new Date(body.generatedAfter);
  return Number.isFinite(timestamp.getTime()) &&
    timestamp.getTime() >= at.getTime() - 20 * 60 * 1000 &&
    timestamp.getTime() <= at.getTime() + 60 * 1000 &&
    body.dayKey === localClock(at).dayKey;
}

function createFlutterExecutor({projectRoot = path.resolve(__dirname, '../..'),
  flutterBinary = 'flutter', spawnImpl = spawn, timeoutMs = 18 * 60 * 1000} = {}) {
  return async (request, revision) => {
    const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), 'goalvdline-p18-'));
    const output = path.join(tempDir, 'result.json');
    try {
      const input = Buffer.from(JSON.stringify(request), 'utf8').toString('base64');
      await new Promise((resolve, reject) => {
        const diagnostics = process.env.AUTO_COUPON_HEADLESS_DIAGNOSTICS === 'true';
        let captured = '';
        const child = spawnImpl(flutterBinary, ['test', '--reporter', 'compact',
          'test/engine/goalvdline_official_headless_worker_test.dart'], {
          cwd: projectRoot, shell: false,
          env: {...process.env, GOALVDLINE_HEADLESS_RUN: '1',
            GOALVDLINE_HEADLESS_REQUEST_B64: input,
            GOALVDLINE_HEADLESS_REVISION: revision,
            GOALVDLINE_HEADLESS_RESULT_PATH: output},
          stdio: diagnostics ? ['ignore', 'pipe', 'pipe'] : ['ignore', 'ignore', 'ignore'],
        });
        // Capture a bounded diagnostic sample only when explicitly enabled.
        // Do not emit the sample or include it in any API response/journal.
        if (diagnostics) {
          for (const stream of [child.stdout, child.stderr]) {
            if (stream && typeof stream.on === 'function') {
              stream.on('data', bytes => {captured = limitedAppend(captured, bytes);});
            }
          }
        }
        let timedOut = false;
        const timer = setTimeout(() => {timedOut = true; child.kill('SIGKILL');}, timeoutMs);
        child.once('error', () => {
          clearTimeout(timer); reject(diagnosticError('flutter_spawn_failed'));
        });
        child.once('exit', (code, signal) => {
          clearTimeout(timer);
          if (code === 0) resolve();
          else reject(diagnosticError(timedOut ? 'flutter_timeout' :
            (signal === 'SIGKILL' ? 'flutter_process_killed' :
              (diagnostics ? classifyFlutterFailure(captured) : 'flutter_exit_nonzero'))));
        });
      });
      let stats;
      try { stats = await fs.stat(output); } catch (_) {
        throw diagnosticError('result_file_missing');
      }
      if (stats.size > MAX_RESULT_BYTES) throw diagnosticError('result_read_failed');
      let raw;
      try { raw = await fs.readFile(output, 'utf8'); } catch (_) {
        throw diagnosticError('result_read_failed');
      }
      let result;
      try { result = JSON.parse(raw); } catch (_) {
        throw diagnosticError('result_invalid_json');
      }
      if (result.protocol !== PROTOCOL || result.officialEngine !== true ||
          result.revision !== revision ||
          (result.status !== 'ready' && result.status !== 'no_eligible_coupon')) {
        throw diagnosticError('result_contract_invalid');
      }
      return result;
    } finally {
      await fs.rm(tempDir, {recursive: true, force: true});
    }
  };
}

function createHeadlessEngineHost({token, revision, execute = createFlutterExecutor(),
  now = () => new Date(), jobStore = null} = {}) {
  if (typeof token !== 'string' || token.length < 32 ||
      !REVISION.test(revision || '')) throw new Error('Headless engine disabled');
  const jobs = new Map();
  let runningJob = null;
  // Load the durable journal before handling any request. A corrupt or
  // unavailable journal fails closed instead of silently using memory.
  const loaded = jobStore ? jobStore.load().then(records => {
    for (const [id, job] of records) jobs.set(id, job);
  }) : Promise.resolve();
  async function save(id, job) {
    if (jobStore) await jobStore.save(id, job);
    jobs.set(id, job);
  }
  function respond(res, code, payload) {
    res.writeHead(code, {'Content-Type':'application/json; charset=utf-8',
      'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
    res.end(JSON.stringify(payload));
  }
  const server = http.createServer(async (req, res) => {
    try { await loaded; } catch (_) {
      return respond(res, 503, {error:'job_store_unavailable'});
    }
    if (!validToken(/^Bearer ([A-Za-z0-9_-]{32,})$/.exec(req.headers.authorization || '')?.[1], token)) {
      return respond(res, 401, {error:'unauthorized'});
    }
    const current = now();
    for (const [id, job] of jobs) {
      if (current.getTime() - job.createdAt.getTime() > JOB_TTL_MS && job.status !== 'running') {
        // Failure to remove an old record is not permission to forget it.
        try { if (jobStore) await jobStore.remove(id); } catch (_) {
          return respond(res, 503, {error:'job_store_unavailable'});
        }
        jobs.delete(id);
      }
    }
    if (req.method === 'POST' && req.url === '/coupon/generate') {
      let raw = '';
      try {
        for await (const chunk of req) {
          raw += chunk.toString('utf8');
          if (Buffer.byteLength(raw) > MAX_REQUEST_BYTES) return respond(res, 413, {error:'payload_too_large'});
        }
        const body = JSON.parse(raw);
        if (!validateRequest(body, current)) return respond(res, 400, {error:'invalid_request'});
        // Repeat requests for the same day/preferences share the same job.
        const signature = crypto.createHash('sha256').update(JSON.stringify({
          revision, dayKey:body.dayKey, preferences:body.preferences,
        })).digest('hex');
        for (const [id, job] of jobs) {
          if (job.signature !== signature || job.status === 'failed' ||
              job.status === 'no_coupon') continue;
          if (job.status === 'ready' && (job.result?.protocol !== PROTOCOL ||
              job.result?.officialEngine !== true || job.result?.revision !== revision ||
              !validateGeneratedCoupon({
                coupon:job.result?.coupon, preferences:body.preferences, now:current,
              }).valid)) continue;
          return respond(res, 202, {protocol:PROTOCOL,jobId:id});
        }
        if (runningJob) return respond(res, 429, {error:'engine_busy'});
        const id = crypto.randomBytes(16).toString('hex');
        const job = {createdAt:current,signature,request:body,status:'running',result:null};
        // Reserve the single executor BEFORE the first asynchronous journal
        // write; concurrent POST handlers must not launch two Flutter jobs.
        runningJob = id;
        try { await save(id, job); } catch (_) {
          runningJob = null;
          return respond(res, 503, {error:'job_store_unavailable'});
        }
        // Detached from HTTP response, but within this separate runner process.
        Promise.resolve().then(() => execute(body, revision)).then(async result => {
          let final = {...job, status:'no_coupon', result:null};
          if (result?.status === 'ready' && result.coupon) {
            const checkedAt = now();
            const valid = validateGeneratedCoupon({coupon:result.coupon,
              preferences:body.preferences,now:checkedAt});
            if (result.protocol !== PROTOCOL || result.officialEngine !== true ||
                result.revision !== revision || !valid.valid ||
                valid.dayKey !== body.dayKey) {
              final.status = 'failed';
              reportFailure('coupon_validation_failed');
            } else {
              final = {...job, status:'ready', result:{protocol:PROTOCOL,
                officialEngine:true,revision,coupon:result.coupon}};
            }
          } else if (result?.status !== 'no_eligible_coupon') {
            final.status = 'failed';
            reportFailure('result_contract_invalid');
          }
          await save(id, final);
        }).catch(async error => {
          reportFailure(error?.headlessCategory);
          try { await save(id, {...job, status:'failed',result:null}); }
          catch (_) { jobs.set(id, {...job, status:'failed',result:null}); }
        }).finally(() => {runningJob = null;});
        return respond(res, 202, {protocol:PROTOCOL,jobId:id});
      } catch (_) {return respond(res, 400, {error:'invalid_json'});}
    }
    const match = /^\/coupon\/jobs\/([0-9a-f]{32})$/.exec(req.url || '');
    if (req.method === 'GET' && match && JOB_ID.test(match[1])) {
      const job = jobs.get(match[1]);
      if (!job) return respond(res, 404, {error:'unknown_job'});
      if (job.status === 'running') return respond(res, 202, {protocol:PROTOCOL,jobId:match[1]});
      if (job.status === 'ready') {
        if (job.result?.protocol !== PROTOCOL ||
            job.result?.officialEngine !== true ||
            job.result?.revision !== revision) {
          return respond(res, 503, {error:'invalid_stored_result'});
        }
        const valid = validateGeneratedCoupon({coupon:job.result?.coupon,
          preferences:job.request.preferences,now:current});
        if (!valid.valid || valid.dayKey !== job.request.dayKey) {
          return respond(res, 503, {error:'expired_coupon'});
        }
        return respond(res, 200, job.result);
      }
      return respond(res, 503, {error:job.status});
    }
    return respond(res, 404, {error:'not_found'});
  });
  return server;
}

// P20.3D: never bind beyond loopback unless explicitly enabled for a Render
// PRIVATE service with a mounted durable journal. An exposed web service is
// not a supported deployment topology for this flag.
function headlessListenAddress(env = process.env) {
  if (env.AUTO_COUPON_HEADLESS_PRIVATE_RENDER_BIND !== 'true') return '127.0.0.1';
  if (typeof env.AUTO_COUPON_HEADLESS_STATE_DIR !== 'string' ||
      !env.AUTO_COUPON_HEADLESS_STATE_DIR.startsWith('/')) {
    throw new Error('Private headless bind requires durable state directory');
  }
  return '0.0.0.0';
}

if (require.main === module) {
  const env = process.env;
  if (env.AUTO_COUPON_HEADLESS_HOST_ENABLED !== 'true') {
    console.error('Headless engine disabled by default.'); process.exitCode = 2;
  } else {
    try {
      const stateDir = env.AUTO_COUPON_HEADLESS_STATE_DIR;
      const jobStore = stateDir ? createDurableHeadlessJobStore(stateDir) : null;
      const host = createHeadlessEngineHost({token:env.AUTO_COUPON_HEADLESS_TOKEN,
        revision:env.AUTO_COUPON_HEADLESS_REVISION,jobStore});
      const port = Number(env.AUTO_COUPON_HEADLESS_PORT || '8799');
      if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid port');
      host.listen(port, headlessListenAddress(env), () => console.log('Headless runner listening (authenticated).'));
    } catch (_) {console.error('Invalid headless runner configuration.');process.exitCode = 2;}
  }
}

module.exports = {validateRequest,createFlutterExecutor,createHeadlessEngineHost,headlessListenAddress};
