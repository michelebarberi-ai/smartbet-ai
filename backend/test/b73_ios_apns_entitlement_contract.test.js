'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const read=p=>fs.readFileSync(path.join(__dirname,'../..',p),'utf8');
const project=read('ios/Runner.xcodeproj/project.pbxproj');
const release=read('ios/Runner/GoalVdLinePushProduction.entitlements');
const debug=read('ios/Runner/GoalVdLineKeychain.entitlements');
const wf=read('.github/workflows/ios-testflight.yml');

test('B73: production APNs entitlement exists only in signed Release/Profile',()=>{
  assert.match(release,/<key>aps-environment<\/key>\s*<string>production<\/string>/);
  assert.equal((project.match(/CODE_SIGN_ENTITLEMENTS = Runner\/GoalVdLinePushProduction.entitlements;/g)||[]).length,2);
  assert.equal((project.match(/CODE_SIGN_ENTITLEMENTS = Runner\/GoalVdLineKeychain.entitlements;/g)||[]).length,1);
  assert.doesNotMatch(debug,/<key>aps-environment<\/key>/);
});

test('B73: TestFlight refuses profile without actual APNs production rights',()=>{
  assert.match(wf,/refs\/heads\/release\/b73-testflight/);
  assert.match(wf,/plutil -extract Entitlements\.aps-environment raw/);
  assert.match(wf,/\$APNS_ENTITLEMENT" != "production"/);
  assert.match(wf,/rigenerare il profilo App Store prima della Build 73/);
});
