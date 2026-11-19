'use strict';
// B73 read-only Apple App Store Connect audit. Never writes developer
// capabilities, provisioning profiles, certificates, or GitHub secrets.
const crypto=require('node:crypto');
const ORIGIN='https://api.appstoreconnect.apple.com';
const BUNDLE='com.michelebarberi.smartbetai';

function base64url(value){return Buffer.from(value).toString('base64url');}
function token({keyId,issuerId,keyBase64,now=Math.floor(Date.now()/1000)}) {
  if(!/^[A-Za-z0-9]{10}$/.test(keyId||'') ||
    typeof issuerId!=='string'||issuerId.length<30 ||
    typeof keyBase64!=='string'||keyBase64.length<100) return null;
  const raw=Buffer.from(keyBase64,'base64').toString('utf8');
  const h=base64url(JSON.stringify({alg:'ES256',kid:keyId,typ:'JWT'}));
  const p=base64url(JSON.stringify({iss:issuerId,iat:now,exp:now+480,
    aud:'appstoreconnect-v1'}));
  const input=`${h}.${p}`;
  const signature=crypto.sign('sha256',Buffer.from(input),{
    key:raw,dsaEncoding:'ieee-p1363',
  }).toString('base64url');
  return `${input}.${signature}`;
}
async function readCapability({env=process.env,fetchImpl=fetch}={}) {
  let jwt;
  try{jwt=token({keyId:env.APPSTORE_KEY_ID,
    issuerId:env.APPSTORE_ISSUER_ID,
    keyBase64:env.APPSTORE_PRIVATE_KEY_BASE64});}
  catch(_){return {status:'credentials_invalid'};}
  if(!jwt)return {status:'credentials_missing'};
  async function get(path){
    const url=new URL(path,ORIGIN);
    const r=await fetchImpl(url,{
      method:'GET',headers:{Authorization:`Bearer ${jwt}`,
        Accept:'application/json'},
      redirect:'error',signal:AbortSignal.timeout(18000),
    });
    if(!r.ok)throw new Error(`HTTP_${r.status}`);
    return r.json();
  }
  try{
    const list=await get(`/v1/bundleIds?filter%5Bidentifier%5D=${BUNDLE}&limit=10`);
    const found=Array.isArray(list.data)?list.data.find(x=>x.attributes?.identifier===BUNDLE):null;
    if(!found?.id)return {status:'bundle_not_found'};
    const caps=await get(`/v1/bundleIds/${encodeURIComponent(found.id)}/bundleIdCapabilities?limit=100`);
    if(!Array.isArray(caps.data))return {status:'invalid_apple_response'};
    return {status:'verified',
      pushCapabilityEnabled:caps.data.some(x=>x.attributes?.capabilityType==='PUSH_NOTIFICATIONS')};
  }catch(error){
    return {status:(''+error?.message).startsWith('HTTP_')
      ? 'apple_api_access_denied_or_unavailable' : 'apple_api_unreachable'};
  }
}
if(require.main===module){
  readCapability().then(x=>{
    // No API credentials, Apple IDs or developer account metadata in logs.
    console.log('Apple Push Notifications capability:',x.status,
      x.status==='verified' ? x.pushCapabilityEnabled : 'unknown');
  }).catch(()=>console.log('Apple capability audit unavailable'));
}
module.exports={readCapability,token};
