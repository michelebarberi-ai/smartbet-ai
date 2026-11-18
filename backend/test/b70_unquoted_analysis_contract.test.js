'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const coupon = fs.readFileSync(path.join(
  __dirname, '../../lib/screens/create_ai_coupon_screen.dart'), 'utf8');
const panel = fs.readFileSync(path.join(
  __dirname, '../../lib/widgets/goalvdline_three_brains_expansion.dart'), 'utf8');

test('B70: unquoted sports forecasts always retain a motor AI panel', () => {
  const sectionStart = coupon.indexOf("'ALTRE STIME AI — NON CONFERMATE PER LA SCHEDINA'");
  const sectionEnd = coupon.indexOf('if (!_loading && _errors > 0)', sectionStart);
  assert.ok(sectionStart > 0 && sectionEnd > sectionStart);
  const unquoted = coupon.slice(sectionStart, sectionEnd);
  assert.match(unquoted, /\.\.\._sportsOnlyPreview/);
  assert.match(unquoted, /GoalVdLineThreeBrainsExpansion\(/);
  assert.match(unquoted, /fixtureId: forecast\.match\.fixtureId/);
  assert.match(unquoted, /smartBet: forecast\.analysis/);
  assert.match(unquoted, /dual: forecast\.dualAnalysis/);
  assert.match(unquoted, /selectedMarket: forecast\.market/);
  assert.match(unquoted, /selectedProbability: forecast\.probability/);
  assert.doesNotMatch(unquoted, /getFixtureMarketOdds\(/);
  assert.doesNotMatch(unquoted, /_results\.add\(/);
});

test('B70: no Diego means no claim of a new fourth-brain synthesis', () => {
  assert.match(panel, /final metaRecords = diego == null\s*\?/);
  assert.match(panel, /Non disponibile: Diego AI senza dati per questa analisi/);
  assert.match(panel, /storico SHADOW della partita/);
});

test('B70: displayed unquoted predictions are not inserted into coupon', () => {
  assert.match(coupon, /READ-ONLY and never enter _results\/portfolio/);
  assert.match(coupon, /quota\/mercato non confermati/);
  assert.match(coupon, /non modificano le schedine|Non vengono inventate quote/);
});
