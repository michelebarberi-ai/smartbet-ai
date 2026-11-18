'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const workflow = fs.readFileSync(
  path.join(__dirname, '../../.github/workflows/ios-testflight.yml'),
  'utf8',
);

test('B66: GitHub upload is restricted to authorized release branch only', () => {
  assert.match(workflow, /^      - release\/b66-testflight$/m);
  assert.doesNotMatch(workflow, /^      - feature\/b66-three-engine-neon-sync$/m);
  assert.equal(
    (workflow.match(/github\.ref != 'refs\/heads\/release\/b66-testflight'/g) || []).length,
    2,
    'B66 must be excluded from generic push and manual workflow_dispatch paths',
  );
  assert.match(
    workflow,
    /github\.ref == 'refs\/heads\/release\/b66-testflight' &&\s*github\.event\.head_commit\.message == 'release\(build66\): authorize TestFlight upload'/,
  );
  assert.match(workflow, /elif \[\[ "\$GITHUB_REF" == "refs\/heads\/release\/b66-testflight" \]\]; then\s*grep -qx 'version: 1\.2\.5\+66' pubspec\.yaml/);
  assert.match(workflow, /BUILD_NUMBER="66"/);
});

test('B66: backend and Flutter regressions run before signing in release job', () => {
  const backend = workflow.indexOf('- name: B64/B65/B66/B67/B68/B69 full backend regression before signing');
  const flutter = workflow.indexOf('- name: B62/B63/B64/B65/B66/B67/B68/B69 full Flutter regression before signing');
  const signing = workflow.indexOf('- name: Prepare App Store Connect API key');
  assert.ok(backend >= 0);
  assert.ok(flutter > backend);
  assert.ok(signing > flutter);
  assert.match(workflow.slice(backend, flutter), /npm --prefix backend test/);
  assert.match(workflow.slice(flutter, signing), /flutter test --no-pub --reporter compact/);
  assert.match(workflow.slice(backend, flutter), /release\/b66-testflight/);
  assert.match(workflow.slice(flutter, signing), /release\/b66-testflight/);
});

test('B66: feature build 65 and release build 66 have valid version metadata', () => {
  const pubspec = fs.readFileSync(
    path.join(__dirname, '../../pubspec.yaml'),
    'utf8',
  );
  assert.match(pubspec, /^version: 1\.2\.5\+(?:65|66|67|68|69)$/m);
});
