'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '../..');
const workflow = fs.readFileSync(
  path.join(root, '.github/workflows/ios-testflight.yml'), 'utf8');
const pubspec = fs.readFileSync(path.join(root, 'pubspec.yaml'), 'utf8');

test('B81: only exact authorized release/build 81 may upload', () => {
  assert.match(pubspec, /^version: 1\.2\.5\+81$/m);
  assert.match(workflow, /- release\/b81-testflight/);
  assert.match(workflow,
    /github\.ref == 'refs\/heads\/release\/b81-testflight' &&\s*github\.event\.head_commit\.message == 'release\(build81\): authorize TestFlight upload'/);
  assert.match(workflow,
    /elif \[\[ "\$GITHUB_REF" == "refs\/heads\/release\/b81-testflight" \]\]; then\s*grep -qx 'version: 1\.2\.5\+81' pubspec\.yaml/);
  assert.match(workflow,
    /github\.ref != 'refs\/heads\/release\/b81-testflight'/);
});
