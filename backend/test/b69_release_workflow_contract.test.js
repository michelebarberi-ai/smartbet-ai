'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const workflow = fs.readFileSync(
  path.join(__dirname, '../../.github/workflows/ios-testflight.yml'),
  'utf8',
);

test('B69: only a release branch with exact authorization can publish to TestFlight', () => {
  assert.match(workflow, /^      - release\/b69-testflight$/m);
  assert.doesNotMatch(workflow, /^      - feature\/b69-audit-clarity$/m);
  assert.equal(
    (workflow.match(/github\.ref != 'refs\/heads\/release\/b69-testflight'/g) || []).length,
    2,
  );
  assert.match(workflow,
    /github\.ref == 'refs\/heads\/release\/b69-testflight' &&\s*github\.event\.head_commit\.message == 'release\(build69\): authorize TestFlight upload'/);
  assert.match(workflow,
    /elif \[\[ "\$GITHUB_REF" == "refs\/heads\/release\/b69-testflight" \]\]; then\s*grep -qx 'version: 1\.2\.5\+69' pubspec\.yaml/);
  assert.match(workflow, /BUILD_NUMBER="69"/);
});

test('B69: full backend and Flutter tests run before signing and upload', () => {
  const backend = workflow.indexOf('- name: B64/B65/B66/B67/B68/B69/B70/B71/B73 full backend regression before signing');
  const flutter = workflow.indexOf('- name: B62/B63/B64/B65/B66/B67/B68/B69/B70/B71/B73 full Flutter regression before signing');
  const signing = workflow.indexOf('- name: Prepare App Store Connect API key');
  assert.ok(backend > 0);
  assert.ok(flutter > backend);
  assert.ok(signing > flutter);
  assert.match(workflow.slice(backend, flutter), /npm --prefix backend test/);
  assert.match(workflow.slice(flutter, signing), /flutter test --no-pub --reporter compact/);
  assert.match(workflow.slice(backend, flutter), /release\/b69-testflight/);
  assert.match(workflow.slice(flutter, signing), /release\/b69-testflight/);
});

test('B69: feature base retains last version until release branch is prepared', () => {
  const pubspec = fs.readFileSync(path.join(__dirname, '../../pubspec.yaml'), 'utf8');
  assert.match(pubspec, /^version: 1\.2\.5\+(?:68|69|70|71|73|74|75|76|77)$/m);
});
