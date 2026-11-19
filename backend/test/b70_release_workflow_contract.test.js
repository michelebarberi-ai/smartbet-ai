'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const wf = fs.readFileSync(path.join(
  __dirname, '../../.github/workflows/ios-testflight.yml'), 'utf8');
const screen = fs.readFileSync(path.join(
  __dirname, '../../lib/screens/create_ai_coupon_screen.dart'), 'utf8');

test('B70: exact release authorization required; no feature push uploads', () => {
  assert.match(wf, /^      - release\/b70-testflight$/m);
  assert.doesNotMatch(wf, /^      - feature\/b70-unquoted-ai-panels$/m);
  assert.equal((wf.match(/github\.ref != 'refs\/heads\/release\/b70-testflight'/g) || []).length, 2);
  assert.match(wf,
    /github\.ref == 'refs\/heads\/release\/b70-testflight' &&\s*github\.event\.head_commit\.message == 'release\(build70\): authorize TestFlight upload'/);
  assert.match(wf,
    /elif \[\[ "\$GITHUB_REF" == "refs\/heads\/release\/b70-testflight" \]\]; then\s*grep -qx 'version: 1\.2\.5\+70' pubspec\.yaml/);
  assert.match(wf, /BUILD_NUMBER="70"/);
});

test('B70: release runs full backend and Flutter regression before signing', () => {
  const backend = wf.indexOf('- name: B64/B65/B66/B67/B68/B69/B70/B71/B73 full backend regression before signing');
  const flutter = wf.indexOf('- name: B62/B63/B64/B65/B66/B67/B68/B69/B70/B71/B73 full Flutter regression before signing');
  const signing = wf.indexOf('- name: Prepare App Store Connect API key');
  assert.ok(backend > 0 && flutter > backend && signing > flutter);
  assert.match(wf.slice(backend, flutter), /npm --prefix backend test/);
  assert.match(wf.slice(flutter, signing), /flutter test --no-pub --reporter compact/);
  assert.match(wf.slice(backend, flutter), /release\/b70-testflight/);
  assert.match(wf.slice(flutter, signing), /release\/b70-testflight/);
});

test('B70: weekend, early Italian screen and competition-diverse shortlist wired', () => {
  assert.match(screen, /case _CouponPeriod\.weekend:\s*return GoalVdLineCouponScreeningPolicy\.nextWeekend\(today\)/);
  assert.match(screen, /GoalVdLineCouponScreeningPolicy\.eligibleMatches\(/);
  assert.match(screen, /italianScheduleOnly: _italyScheduleOnly/);
  assert.match(screen, /GoalVdLineCouponScreeningPolicy\.diversifiedTop\(/);
  assert.match(screen, /GoalVdLineCouponScreeningPolicy\s*\.comparableMarketProbability\(analysis\)/);
  assert.match(screen, /GoalVdLineThreeBrainsExpansion\(\s*fixtureId: forecast\.match\.fixtureId/);
});

test('B70: feature base must retain valid version prior to release', () => {
  const pubspec = fs.readFileSync(path.join(__dirname, '../../pubspec.yaml'), 'utf8');
  assert.match(pubspec, /^version: 1\.2\.5\+(?:69|70|71|73|74)$/m);
});
