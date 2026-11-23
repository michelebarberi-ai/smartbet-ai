const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('B76: TestFlight upload only from explicitly authorized B76 release', () => {
  const root = path.resolve(__dirname, '../..');
  const workflow = fs.readFileSync(
    path.join(root, '.github/workflows/ios-testflight.yml'), 'utf8',
  );
  const pubspec = fs.readFileSync(path.join(root, 'pubspec.yaml'), 'utf8');
  assert.match(pubspec, /^version: 1\.2\.5\+(?:76|77|78|79|80)$/m);
  assert.match(workflow, /- release\/b76-testflight/);
  assert.match(workflow, /github\.ref != 'refs\/heads\/release\/b76-testflight'/);
  assert.match(workflow, /github\.event\.head_commit\.message == 'release\(build76\): authorize TestFlight upload'/);
  assert.match(workflow, /grep -qx 'version: 1\.2\.5\+76' pubspec\.yaml/);
  assert.match(workflow, /BUILD_NUMBER="76"/);
  assert.match(workflow, /'refs\/heads\/release\/b76-testflight'/);
});
