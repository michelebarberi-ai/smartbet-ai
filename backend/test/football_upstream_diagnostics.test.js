'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  fetchFootballJson, footballFailurePayload,
  logFootballFailure, respondFootballFailure,
} = require('../football_upstream_diagnostics');

const url = 'https://v3.football.api-sports.io/odds?fixture=123&secret=SHOULD_NOT_LOG';
const apiKey = 'SECRET_FOOTBALL_API_KEY';
const fake = (body, status = 200) => async () => ({
  ok: status >= 200 && status <= 299,
  status,
  async text() { return body; },
});

test('upstream valid JSON: returns provider payload without changing successful response', async () => {
  const payload = {response: [{fixture: 123}], errors: {}, results: 1};
  const data = await fetchFootballJson({
    url, apiKey, fetchImpl: fake(JSON.stringify(payload)),
  });
  assert.deepEqual(data, payload);
});

test('a single API call, no hidden retries or additional provider quota usage', async () => {
  let calls = 0;
  const fetchImpl = async (_url, args) => {
    calls++;
    assert.equal(args.headers['x-apisports-key'], apiKey);
    assert.equal(args.signal?.aborted, false);
    return {ok: false, status: 429, text: async () => '{"errors":{"requests":"limit"}}'};
  };
  await assert.rejects(
    fetchFootballJson({url, apiKey, fetchImpl}),
    {code: 'FOOTBALL_PROVIDER_RATE_LIMIT', statusCode: 502, upstreamStatus: 429},
  );
  assert.equal(calls, 1);
});

test('upstream HTTP 401 and 403 are safely classified as provider authorization', async () => {
  for (const status of [401, 403]) {
    await assert.rejects(
      fetchFootballJson({url, apiKey, fetchImpl: fake('private error', status)}),
      {code: 'FOOTBALL_PROVIDER_AUTH', statusCode: 502, upstreamStatus: status},
    );
  }
});

test('upstream HTTP 500 remains an upstream 502 with safe reason code', async () => {
  await assert.rejects(
    fetchFootballJson({url, apiKey, fetchImpl: fake('error', 500)}),
    {code: 'FOOTBALL_PROVIDER_HTTP_ERROR', statusCode: 502, upstreamStatus: 500},
  );
});

test('HTTP 200 quota-exhausted response is treated as provider rate limiting', async () => {
  await assert.rejects(
    fetchFootballJson({url, apiKey, fetchImpl: fake(JSON.stringify({
      errors: {requests: 'Daily quota limit reached', token: apiKey},
    }))}),
    {code: 'FOOTBALL_PROVIDER_RATE_LIMIT', statusCode: 502, upstreamStatus: 200},
  );
});

test('HTTP 200 other provider error does NOT open a rate-limit cooldown', async () => {
  await assert.rejects(
    fetchFootballJson({url, apiKey, fetchImpl: fake(JSON.stringify({
      errors: {parameters: 'Missing required season'},
    }))}),
    {code: 'FOOTBALL_PROVIDER_REPORTED_ERROR', statusCode: 502, upstreamStatus: 200},
  );
});

test('HTTP 200 invalid JSON, and JSON arrays are rejected, not cached', async () => {
  await assert.rejects(
    fetchFootballJson({url, apiKey, fetchImpl: fake('<html>Cloudflare</html>')}),
    {code: 'FOOTBALL_PROVIDER_INVALID_JSON', statusCode: 502},
  );
  await assert.rejects(
    fetchFootballJson({url, apiKey, fetchImpl: fake('[]')}),
    {code: 'FOOTBALL_PROVIDER_INVALID_JSON', statusCode: 502},
  );
});

test('network failures and timeout are distinguishable without raw error text', async () => {
  const secret = 'token=SUPER_SECRET';
  await assert.rejects(
    fetchFootballJson({
      url, apiKey,
      fetchImpl: async () => {throw Error('Connect failed: ' + secret);},
    }),
    e => e.code === 'FOOTBALL_PROVIDER_NETWORK_ERROR' &&
      !e.message.includes(secret) && e.upstreamStatus === null,
  );
  await assert.rejects(
    fetchFootballJson({
      url, apiKey,
      fetchImpl: async () => {const e = new Error('deadline');e.name='TimeoutError';throw e;},
    }),
    {code: 'FOOTBALL_PROVIDER_TIMEOUT', statusCode: 502},
  );
});

test('missing football key is 503 before the upstream fetch is called', async () => {
  let calls=0;
  await assert.rejects(fetchFootballJson({
    url, apiKey: '', fetchImpl: async () => {calls++;},
  }), {code:'FOOTBALL_PROVIDER_KEY_MISSING',statusCode:503});
  assert.equal(calls,0);
});

test('client response returns code but never the raw provider payload or stack', async () => {
  let failure;
  try {
    await fetchFootballJson({
      url, apiKey, fetchImpl: fake('{"errors":{"account":"SENSITIVE_PAYLOAD"}}', 429),
    });
  } catch (e) {failure=e;}
  const result = footballFailurePayload(failure);
  assert.equal(result.httpStatus, 502);
  assert.equal(result.body.code, 'FOOTBALL_PROVIDER_RATE_LIMIT');
  assert.equal(result.body.success, false);
  assert.doesNotMatch(JSON.stringify(result), /SENSITIVE_PAYLOAD|SECRET_FOOTBALL_API_KEY/);
  assert.equal(Object.hasOwn(result.body, 'apiResponse'), false);
  const unknown=footballFailurePayload(new Error('credential=RAW_SECRET'));
  assert.equal(unknown.httpStatus,500);
  assert.doesNotMatch(JSON.stringify(unknown),/RAW_SECRET/);
});

test('structured logs include endpoint and provider status, never URLs or bodies', async () => {
  let failure;
  try {
    await fetchFootballJson({
      url, apiKey,
      fetchImpl: fake(JSON.stringify({errors:{requests:'PRIVATE_PAYLOAD'}}),429),
    });
  } catch (e) { failure=e; }
  const output=[];
  logFootballFailure(failure,{
    endpoint:'/odds',
    logger:{warn:(...args)=>output.push(args.join(' '))},
  });
  assert.equal(output.length,1);
  assert.match(output[0],/FOOTBALL_UPSTREAM_DIAGNOSTIC/);
  assert.match(output[0],/"upstreamHttpStatus":429/);
  assert.match(output[0],/"endpoint":"\/odds"/);
  assert.doesNotMatch(output[0],/SHOULD_NOT_LOG|SECRET_FOOTBALL|PRIVATE_PAYLOAD|fixture=123/);
});

test('reject arbitrary endpoint in diagnostic log',()=>{
  const output=[];
  logFootballFailure(new Error('do not log the raw stack'),{
    endpoint:'/odds?token=SHOULD_NOT_LOG',
    logger:{warn:(...args)=>output.push(args.join(' '))},
  });
  assert.match(output[0],/"endpoint":"\/unknown"/);
  assert.doesNotMatch(output[0],/SHOULD_NOT_LOG|do not log the raw stack/);
});

test('Express proxy error handler keeps consistent status and safe JSON',()=>{
  const response={
    statusCode:200,data:null,
    status(n){this.statusCode=n;return this;},
    json(body){this.data=body;return this;},
  };
  const origWarn=console.warn;
  console.warn=()=>{};
  try {
    const result=respondFootballFailure(response,Error('SECRET_DATABASE_URL'),'/fixtures');
    assert.equal(result.statusCode,500);
    assert.equal(result.data.code,'FOOTBALL_PROXY_INTERNAL_ERROR');
    assert.doesNotMatch(JSON.stringify(result.data),/SECRET_DATABASE_URL/);
  }finally{console.warn=origWarn;}
});

test('server routes use the diagnostic helper without dumping provider errors',()=>{
  const server = fs.readFileSync(path.join(__dirname,'..','server.js'),'utf8');
  assert.match(server,/fetchFootballJson\(\{/);
  for(const endpoint of ['/fixtures','/odds','/football/api']){
    assert.ok(server.includes("respondFootballFailure(res, error, '"+endpoint+"')"),
      'diagnostic route missing: '+endpoint);
  }
  assert.doesNotMatch(server,/apiResponse:\s*error\.apiResponse/);
  assert.doesNotMatch(server,/SMARTBET FOOTBALL (FIXTURES|ODDS) ERROR:[^]*?console\.error\(/);
});
