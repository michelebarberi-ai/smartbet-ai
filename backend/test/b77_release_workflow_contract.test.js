const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('B77: upload requires explicit authorization and exact iOS build 77', () => {
  const root = path.resolve(__dirname, '../..');
  const workflow = fs.readFileSync(
    path.join(root, '.github/workflows/ios-testflight.yml'), 'utf8');
  const pubspec = fs.readFileSync(path.join(root, 'pubspec.yaml'), 'utf8');

  assert.match(pubspec, /^version: 1\.2\.5\+(?:77|78|79)$/m);
  assert.match(workflow, /^      - release\/b77-testflight$/m);
  assert.equal(
    (workflow.match(/github\.ref != 'refs\/heads\/release\/b77-testflight'/g) || []).length,
    2,
  );
  assert.match(workflow,
    /github\.ref == 'refs\/heads\/release\/b77-testflight' &&\s*github\.event\.head_commit\.message == 'release\(build77\): authorize TestFlight upload'/);
  assert.match(workflow,
    /elif \[\[ "\$GITHUB_REF" == "refs\/heads\/release\/b77-testflight" \]\]; then\s*grep -qx 'version: 1\.2\.5\+77' pubspec\.yaml/);
  assert.match(workflow, /BUILD_NUMBER="77"/);

  const backend = workflow.indexOf('full backend regression before signing');
  const flutter = workflow.indexOf('full Flutter regression before signing');
  const signing = workflow.indexOf('- name: Prepare App Store Connect API key');
  assert.ok(backend > 0 && flutter > backend && signing > flutter);
  assert.match(workflow.slice(backend, flutter), /release\/b77-testflight/);
  assert.match(workflow.slice(flutter, signing), /release\/b77-testflight/);
  assert.match(workflow, /"refs\/heads\/release\/b77-testflight" \]\]; then/);
});
