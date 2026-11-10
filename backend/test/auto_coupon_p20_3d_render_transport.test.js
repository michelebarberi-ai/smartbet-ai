'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {officialEngineConfiguration} = require('../auto_coupon/official_engine_client');
const {headlessListenAddress} = require('../auto_coupon/official_headless_runner');

const base = {AUTO_COUPON_OFFICIAL_ENGINE_ENABLED:'true',
  AUTO_COUPON_OFFICIAL_ENGINE_TOKEN:'abcdefghijklmnopqrstuvwxyz0123456789',
  AUTO_COUPON_OFFICIAL_ENGINE_REVISION:'8d8e3ec'};

const internal = {...base,
  AUTO_COUPON_OFFICIAL_ENGINE_PRIVATE_RENDER_ENABLED:'true',
  AUTO_COUPON_OFFICIAL_ENGINE_HOSTPORT:'smartbet-b45-flutter-staging-abc123:8799'};

test('private staging Render transport needs explicit opt-in and exact host', () => {
  assert.deepEqual(officialEngineConfiguration(internal), {
    url:'http://smartbet-b45-flutter-staging-abc123:8799/coupon/generate',
    token:base.AUTO_COUPON_OFFICIAL_ENGINE_TOKEN,
    revision:base.AUTO_COUPON_OFFICIAL_ENGINE_REVISION,
  });
  for (const invalid of [
    'localhost:8799', '127.0.0.1:8799', 'example.com:8799',
    'smartbet-b45-flutter-staging-abc123:9999',
    'smartbet-b45-flutter-staging-abc123:8799/coupon/generate',
    'bad-flutter-staging-abc123:8799',
  ]) assert.equal(officialEngineConfiguration({...internal,
    AUTO_COUPON_OFFICIAL_ENGINE_HOSTPORT:invalid}), null);
  assert.equal(officialEngineConfiguration({...internal,
    AUTO_COUPON_OFFICIAL_ENGINE_ENABLED:'false'}),null);
  assert.equal(officialEngineConfiguration({...internal,
    AUTO_COUPON_OFFICIAL_ENGINE_URL:'https://example.com/coupon/generate'}),null);
});

test('public HTTPS remains strict; generic HTTP still forbidden', () => {
  assert.equal(officialEngineConfiguration({...base,
    AUTO_COUPON_OFFICIAL_ENGINE_URL:'http://example.com/coupon/generate'}),null);
  assert.ok(officialEngineConfiguration({...base,
    AUTO_COUPON_OFFICIAL_ENGINE_URL:'https://engine.example.com/coupon/generate'}));
  assert.equal(officialEngineConfiguration({...base,
    AUTO_COUPON_OFFICIAL_ENGINE_URL:'https://engine.example.com:8799/coupon/generate'}),null);
});

test('headless runner binds only to loopback by default', () => {
  assert.equal(headlessListenAddress({}), '127.0.0.1');
  assert.throws(() => headlessListenAddress({
    AUTO_COUPON_HEADLESS_PRIVATE_RENDER_BIND:'true',
  }));
  assert.equal(headlessListenAddress({
    AUTO_COUPON_HEADLESS_PRIVATE_RENDER_BIND:'true',
    AUTO_COUPON_HEADLESS_STATE_DIR:'/var/lib/goalvdline-jobs',
  }), '0.0.0.0');
});
