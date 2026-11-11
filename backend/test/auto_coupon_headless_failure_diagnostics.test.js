'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {limitedAppend, classifyFlutterFailure, diagnosticError, reportFailure} =
  require('../auto_coupon/headless_failure_diagnostics');

test('diagnostic classification returns only known codes', () => {
  assert.equal(classifyFlutterFailure('MissingPluginException: token=SECRET'), 'flutter_plugin_unavailable');
  assert.equal(classifyFlutterFailure('SocketException: Failed host lookup foo'), 'flutter_network_failure');
  assert.equal(classifyFlutterFailure('401 Unauthorized API key BAD_KEY'), 'flutter_provider_auth');
  assert.equal(classifyFlutterFailure('Kernel compilation failed'), 'flutter_compile_failed');
  assert.equal(classifyFlutterFailure('Some tests failed'), 'flutter_test_failed');
  assert.equal(classifyFlutterFailure('nothing identifiable'), 'flutter_exit_nonzero');
});

test('bounded capture is limited and raw secrets are never logged', () => {
  assert.equal(limitedAppend('a'.repeat(11999), 'TOKENSECRET'), 'a'.repeat(11989)+'TOKENSECRET');
  const records=[];
  const write=msg=>records.push(msg);
  reportFailure('curl TOKEN SECRET full http body', {AUTO_COUPON_HEADLESS_DIAGNOSTICS:'true'}, write);
  reportFailure('flutter_network_failure', {AUTO_COUPON_HEADLESS_DIAGNOSTICS:'true'}, write);
  assert.deepEqual(records, [
    '[headless-staging] failure_category=executor_failed',
    '[headless-staging] failure_category=flutter_network_failure',
  ]);
  assert.doesNotMatch(records.join('\n'), /SECRET|TOKEN|curl/);
});

test('diagnostics are disabled by default, executor error message is sanitized', () => {
  const records=[];
  reportFailure('flutter_network_failure', {}, s=>records.push(s));
  assert.deepEqual(records, []);
  const err=diagnosticError('SECRET');
  assert.equal(err.message, 'Headless execution failed');
  assert.equal(err.headlessCategory, 'executor_failed');
});

test('executor classifies a failing Flutter child without exposing raw output', async () => {
  const {EventEmitter} = require('node:events');
  const {PassThrough} = require('node:stream');
  const {createFlutterExecutor} = require('../auto_coupon/official_headless_runner');
  const original = process.env.AUTO_COUPON_HEADLESS_DIAGNOSTICS;
  process.env.AUTO_COUPON_HEADLESS_DIAGNOSTICS = 'true';
  try {
    const execute = createFlutterExecutor({timeoutMs:1000,
      spawnImpl:(_binary, _args, options) => {
        assert.deepEqual(options.stdio, ['ignore','pipe','pipe']);
        const child = new EventEmitter();
        child.stdout = new PassThrough();
        child.stderr = new PassThrough();
        child.kill = () => {};
        process.nextTick(() => {
          child.stderr.write('SocketException connection refused SECRET_987');
          child.emit('exit', 1);
        });
        return child;
      }});
    await assert.rejects(execute({dayKey:'2026-11-11'},'3e7dc0d'), error => {
      assert.equal(error.headlessCategory, 'flutter_network_failure');
      assert.doesNotMatch(String(error), /SECRET_987/);
      return true;
    });
  } finally {
    if (original === undefined) delete process.env.AUTO_COUPON_HEADLESS_DIAGNOSTICS;
    else process.env.AUTO_COUPON_HEADLESS_DIAGNOSTICS = original;
  }
});
