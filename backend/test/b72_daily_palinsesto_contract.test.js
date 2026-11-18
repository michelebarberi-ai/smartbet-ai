'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const read = p => fs.readFileSync(path.join(__dirname,'../..',p),'utf8');

const settings = read('lib/screens/settings_screen.dart');
const backend = read('backend/server.js');
const widget = read('lib/widgets/goalvdline_palinsesto_digest_settings_card.dart');
const prefs = read('lib/services/goalvdline_palinsesto_digest_preferences.dart');

test('B72: settings no longer offer automatic daily bet slips', () => {
  assert.doesNotMatch(settings, /GoalVdLineAutoCouponSettingsCard/);
  assert.doesNotMatch(settings, /AutoSchedina AI quotidiana/);
  assert.match(settings, /GoalVdLinePalinsestoDigestSettingsCard/);
  assert.match(settings, /Riepilogo mattutino del palinsesto/);
});

test('B72: daily fixture summary reads one shared cached provider request', () => {
  assert.match(backend,/app\.get\('\/football\/palinsesto\/oggi'/);
  const section=backend.split("app.get('/football/palinsesto/oggi'")[1]
    ?.split('// FIXTURES')[0] || '';
  assert.match(section,/requestApiFootball\(/);
  assert.match(section,/path: '\/fixtures'/);
  assert.match(section,/query: \{date: dayKey, timezone: 'Europe\/Rome'\}/);
  assert.match(section,/ttlMs: FIXTURES_TTL_MS/);
  assert.match(section,/normalizeFixtureDigest/);
  assert.doesNotMatch(section,/odds|bookmaker|generate.*Coupon|push.*send/i);
});

test('B72: opt-in is persisted locally but never pretends a push is active', () => {
  assert.match(widget, /configurazione in preparazione|Configurazione in preparazione/);
  assert.match(widget, /non attiva ancora la notifica push/);
  assert.match(widget, /Non genera automaticamente schedine/);
  assert.match(prefs, /this\.requested = false/);
  assert.match(prefs, /this\.hour = 8/);
  assert.doesNotMatch(prefs, /goalvdline_auto_coupon_preferences_v1/);
});
