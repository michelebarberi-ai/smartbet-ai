'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const wf=fs.readFileSync(path.join(__dirname,'../../.github/workflows/ios-testflight.yml'),'utf8');
test('B73: signed TestFlight requires exact release authorization and version',()=>{
  assert.match(wf,/^      - release\/b73-testflight$/m);
  assert.doesNotMatch(wf,/^      - feature\/b73-daily-palinsesto-push-delivery$/m);
  assert.equal((wf.match(/github\.ref != 'refs\/heads\/release\/b73-testflight'/g)||[]).length,2);
  assert.match(wf,/github\.ref == 'refs\/heads\/release\/b73-testflight' &&\s*github\.event\.head_commit\.message == 'release\(build73\): authorize TestFlight upload'/);
  assert.match(wf,/elif \[\[ "\$GITHUB_REF" == "refs\/heads\/release\/b73-testflight" \]\]; then\s*grep -qx 'version: 1\.2\.5\+73' pubspec\.yaml/);
  assert.match(wf,/BUILD_NUMBER="73"/);
});
test('B73: full Flutter and backend regressions run before signing',()=>{
  const backend=wf.indexOf('- name: B64/B65/B66/B67/B68/B69/B70/B71/B73 full backend regression before signing');
  const flutter=wf.indexOf('- name: B62/B63/B64/B65/B66/B67/B68/B69/B70/B71/B73 full Flutter regression before signing');
  const signing=wf.indexOf('- name: Prepare App Store Connect API key');
  assert.ok(backend>0 && flutter>backend && signing>flutter);
  assert.match(wf.slice(backend,flutter),/npm --prefix backend test/);
  assert.match(wf.slice(flutter,signing),/flutter test --no-pub --reporter compact/);
  assert.match(wf.slice(backend,flutter),/release\/b73-testflight/);
  assert.match(wf.slice(flutter,signing),/release\/b73-testflight/);
});
test('B73: feature stays at prior build until release branch is created',()=>{
  const p=fs.readFileSync(path.join(__dirname,'../../pubspec.yaml'),'utf8');
  assert.match(p,/^version: 1\.2\.5\+(?:71|73|74|75|76|77|78)$/m);
});
