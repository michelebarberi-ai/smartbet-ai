'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const yaml = fs.readFileSync(path.resolve(__dirname,
  '../../deploy/p20_3d/render.p20_3d.staging.example.yaml'), 'utf8');
function serviceBlock(name) {
  const blocks = yaml.split(/^  - type: /m).slice(1);
  const block = blocks.find(b => b.includes(`    name: ${name}\n`));
  assert.ok(block, `Missing service: ${name}`);
  return block;
}
test('P20.3G template pins source branch, EU region, and disables auto deploy', () => {
  assert.equal((yaml.match(/^  - type: /gm) || []).length, 2);
  for (const name of ['smartbet-b45-flutter-staging',
    'smartbet-b45-coupon-worker-staging']) {
    const block = serviceBlock(name);
    assert.ok(block.includes('    repo: https://github.com/michelebarberi-ai/smartbet-ai\n'));
    assert.ok(block.includes('    branch: staging/b45-render-linux\n'));
    assert.ok(block.includes('    region: frankfurt\n'));
    assert.ok(block.includes('    autoDeployTrigger: off\n'));
  }
});
test('P20.3G staging template has disabled worker and no database URL secrets', () => {
  const worker = serviceBlock('smartbet-b45-coupon-worker-staging');
  for (const key of ['AUTO_COUPON_BACKGROUND_ENABLED', 'AUTO_COUPON_WORKER_ENABLED',
    'AUTO_COUPON_PREFERENCES_ENABLED', 'AUTO_COUPON_OFFICIAL_ENGINE_ENABLED']) {
    assert.ok(worker.includes(`      - key: ${key}\n        value: 'false'\n`));
  }
  assert.ok(worker.includes('      - key: DATABASE_URL\n        sync: false\n'));
  assert.doesNotMatch(yaml, /postgres(?:ql)?:\/\//i);
  assert.doesNotMatch(yaml, /\.neon\.tech/i);
});
