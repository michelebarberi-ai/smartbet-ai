'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const dockerfile = fs.readFileSync(
  path.resolve(__dirname, '../../deploy/p20_3d/Dockerfile.headless'),
  'utf8',
);

test('P20.3H: GNU tar does not restore unsupported Flutter artifact owners', () => {
  const tarOption = dockerfile.indexOf('ENV TAR_OPTIONS="--no-same-owner"');
  const precache = dockerfile.indexOf('flutter precache --linux');
  assert.ok(tarOption > 0, 'TAR_OPTIONS must be set in the image');
  assert.ok(precache > tarOption, 'TAR_OPTIONS must precede Flutter precache');
  assert.match(dockerfile, /flutter config --no-analytics/);
});

test('P20.3H: Docker build remains pinned to Flutter ref and starts the official host', () => {
  assert.match(dockerfile, /^ARG FLUTTER_REF$/m);
  assert.match(dockerfile, /git clone --depth 1 --branch "\$FLUTTER_REF"/);
  assert.match(dockerfile, /CMD \["node", "backend\/auto_coupon\/official_headless_runner\.js"\]/);
  assert.doesNotMatch(dockerfile, /--privileged|chmod\s+777/);
});
