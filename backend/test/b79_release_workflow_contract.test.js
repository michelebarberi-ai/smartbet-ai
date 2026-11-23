'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const workflow = fs.readFileSync(path.join(root, '.github/workflows/ios-testflight.yml'), 'utf8');
const pubspec = fs.readFileSync(path.join(root, 'pubspec.yaml'), 'utf8');

test('B79: release 79 requires its own exact authorization commit and number', () => {
  assert.match(pubspec, /^version: 1\.2\.5\+(?:79|80|81)$/m);
  assert.match(workflow, /^      - release\/b79-testflight$/m);
  assert.equal(
    (workflow.match(/github\.ref != 'refs\/heads\/release\/b79-testflight'/g) || []).length,
    2,
    'an ordinary push or workflow_dispatch cannot upload build 79',
  );
  assert.match(
    workflow,
    /github\.ref == 'refs\/heads\/release\/b79-testflight' &&\s*github\.event\.head_commit\.message == 'release\(build79\): authorize TestFlight upload'/,
  );
  assert.match(
    workflow,
    /elif \[\[ "\$GITHUB_REF" == "refs\/heads\/release\/b79-testflight" \]\]; then\s*grep -qx 'version: 1\.2\.5\+79' pubspec\.yaml/,
  );
  assert.match(workflow, /BUILD_NUMBER="79"/);
});

test('B79: backend, Flutter and APNs signing gates remain enabled', () => {
  const backend = workflow.indexOf('- name: B64/B65/B66/B67/B68/B69/B70/B71/B73 full backend regression before signing');
  const flutter = workflow.indexOf('- name: B62/B63/B64/B65/B66/B67/B68/B69/B70/B71/B73 full Flutter regression before signing');
  const signing = workflow.indexOf('- name: Prepare App Store Connect API key');
  assert.ok(backend > 0 && flutter > backend && signing > flutter);
  assert.match(workflow.slice(backend, flutter), /release\/b79-testflight/);
  assert.match(workflow.slice(flutter, signing), /release\/b79-testflight/);
  const install = workflow.indexOf('- name: Install iOS signing assets');
  const archive = workflow.indexOf('- name: Archive SmartBet for App Store');
  assert.match(workflow.slice(install, archive), /refs\/heads\/release\/b79-testflight/);
  assert.match(workflow.slice(install, archive), /plutil -extract Entitlements\.aps-environment raw/);
});
