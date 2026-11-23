'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const workflow = fs.readFileSync(path.join(root, '.github/workflows/ios-testflight.yml'), 'utf8');
const pubspec = fs.readFileSync(path.join(root, 'pubspec.yaml'), 'utf8');

test('B78: TestFlight only from exact authorized release commit', () => {
  assert.match(pubspec, /^version: 1\.2\.5\+78$/m);
  assert.match(workflow, /^      - release\/b78-testflight$/m);
  assert.equal(
    (workflow.match(/github\.ref != 'refs\/heads\/release\/b78-testflight'/g) || []).length,
    2,
    'ordinary pushes and manual dispatch cannot upload build 78',
  );
  assert.match(workflow,
    /github\.ref == 'refs\/heads\/release\/b78-testflight' &&\s*github\.event\.head_commit\.message == 'release\(build78\): authorize TestFlight upload'/);
  assert.match(workflow,
    /elif \[\[ "\$GITHUB_REF" == "refs\/heads\/release\/b78-testflight" \]\]; then\s*grep -qx 'version: 1\.2\.5\+78' pubspec\.yaml/);
  assert.match(workflow, /BUILD_NUMBER="78"/);
});

test('B78: full backend and Flutter tests run before signing', () => {
  const backend = workflow.indexOf('- name: B64/B65/B66/B67/B68/B69/B70/B71/B73 full backend regression before signing');
  const flutter = workflow.indexOf('- name: B62/B63/B64/B65/B66/B67/B68/B69/B70/B71/B73 full Flutter regression before signing');
  const signing = workflow.indexOf('- name: Prepare App Store Connect API key');
  assert.ok(backend > 0 && flutter > backend && signing > flutter);
  assert.match(workflow.slice(backend, flutter), /release\/b78-testflight/);
  assert.match(workflow.slice(flutter, signing), /release\/b78-testflight/);
  assert.match(workflow.slice(backend, flutter), /npm --prefix backend test/);
  assert.match(workflow.slice(flutter, signing), /flutter test --no-pub --reporter compact/);
});

test('B78: shipping profile must carry production APNs entitlement', () => {
  const install = workflow.indexOf('- name: Install iOS signing assets');
  const archive = workflow.indexOf('- name: Archive SmartBet for App Store');
  assert.ok(install > 0 && archive > install);
  const signing = workflow.slice(install, archive);
  assert.match(signing, /refs\/heads\/release\/b78-testflight/);
  assert.match(signing, /plutil -extract Entitlements\.aps-environment raw/);
  assert.match(signing, /"\$APNS_ENTITLEMENT" != "production"/);
});
