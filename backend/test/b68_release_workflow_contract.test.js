'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const workflow = fs.readFileSync(
  path.join(__dirname, '../../.github/workflows/ios-testflight.yml'),
  'utf8',
);

test('B68: only deliberate release/b68-testflight authorization uploads iOS', () => {
  assert.match(workflow, /^      - release\/b68-testflight$/m);
  assert.doesNotMatch(workflow, /^      - feature\/b68-odds-diagnostics$/m);
  assert.equal(
    (workflow.match(/github\.ref != 'refs\/heads\/release\/b68-testflight'/g) || []).length,
    2,
  );
  assert.match(
    workflow,
    /github\.ref == 'refs\/heads\/release\/b68-testflight' &&\s*github\.event\.head_commit\.message == 'release\(build68\): authorize TestFlight upload'/,
  );
  assert.match(workflow,
    /elif \[\[ "\$GITHUB_REF" == "refs\/heads\/release\/b68-testflight" \]\]; then\s*grep -qx 'version: 1\.2\.5\+68' pubspec\.yaml/);
  assert.match(workflow, /BUILD_NUMBER="68"/);
});

test('B68: all regressions run before signing', () => {
  const backend = workflow.indexOf('- name: B64/B65/B66/B67/B68/B69/B70/B71/B73 full backend regression before signing');
  const flutter = workflow.indexOf('- name: B62/B63/B64/B65/B66/B67/B68/B69/B70/B71/B73 full Flutter regression before signing');
  const signing = workflow.indexOf('- name: Prepare App Store Connect API key');
  assert.ok(backend >= 0);
  assert.ok(flutter > backend);
  assert.ok(signing > flutter);
  assert.match(workflow.slice(backend, flutter), /npm --prefix backend test/);
  assert.match(workflow.slice(flutter, signing), /flutter test --no-pub --reporter compact/);
  assert.match(workflow.slice(backend, flutter), /release\/b68-testflight/);
  assert.match(workflow.slice(flutter, signing), /release\/b68-testflight/);
});

test('B68: candidate metadata never silently regresses existing build numbers', () => {
  const pubspec = fs.readFileSync(path.join(__dirname, '../../pubspec.yaml'), 'utf8');
  assert.match(pubspec, /^version: 1\.2\.5\+(?:67|68|69|70|71|73)$/m);
});
