'use strict';

// B47 staging: the iPhone requests once, then only polls persisted Neon state.
// This service NEVER generates a prediction, supplies bookmaker prices, or
// schedules daily AutoSchedina work. The official engine is injected on server.
const {hashClientId} = require('../learning/learning_core');
const {validatePreferences,localClock,validateGeneratedCoupon} = require('./daily_schedule');
const {publicCoupon} = require('./generation_coordinator');

const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const RENEWAL_MS=60000;

function normalizeRequest(body) {
  if (!body || typeof body!=='object' || Array.isArray(body) ||
      Object.keys(body).some(k=>!['requestId','events','minimumMarketProbability',
        'market','systemMode','windowDays'].includes(k)) ||
      !UUID.test(body.requestId||'')) return null;
  const preferences={
    requested:true,hour:0,minute:0,
    events:body.events,
    minimumMarketProbability:body.minimumMarketProbability,
    market:body.market,
    notifyChanges:false,
    systemMode:body.systemMode,
    windowDays:body.windowDays,
  };
  return validatePreferences(preferences)
    ? {requestId:body.requestId.toLowerCase(),preferences} : null;
}

function oddsStrictlyAboveMinimum(coupon) {
  if (!coupon || !Array.isArray(coupon.events)) return false;
  const events=[...coupon.events];
  if (coupon.coupons) {
    if (!Array.isArray(coupon.coupons)) return false;
    for (const variant of coupon.coupons) {
      if (!Array.isArray(variant?.events)) return false;
      events.push(...variant.events);
    }
  }
  return events.every(item=>typeof item?.odds==='number' &&
    Number.isFinite(item.odds) && item.odds>1.20);
}

class OnDemandCouponService {
  constructor({repository,subjectSalt,generateOfficialCoupon=null,
    now=()=>new Date(),leaseRenewalMs=RENEWAL_MS}) {
    this.repository=repository;
    this.subjectSalt=subjectSalt;
    this.generateOfficialCoupon=generateOfficialCoupon;
    this.now=now;
    this.leaseRenewalMs=leaseRenewalMs;
  }

  async submit({clientId,body}) {
    const input=normalizeRequest(body);
    if (!input) return {status:400,body:{success:false,error:'Richiesta non valida.'}};
    if (typeof this.generateOfficialCoupon!=='function') {
      return {status:503,body:{success:false,error:'Motore remoto non disponibile.'}};
    }
    const subjectHash=hashClientId(clientId,this.subjectSalt);
    const dayKey=localClock(this.now()).dayKey;
    await this.repository.initialize();
    const saved=await this.repository.enqueueOnDemandCoupon({
      subjectHash,requestId:input.requestId,dayKey,
      preferences:input.preferences,
    });
    if (saved.conflict) return {status:409,body:{success:false,error:'Richiesta gia utilizzata.'}};
    return {status:202,body:{success:true,jobId:saved.jobId,
      status:saved.status,dayKey:saved.dayKey}};
  }

  async read({clientId,jobId}) {
    if (!UUID.test(jobId||'')) return {status:400,body:{success:false,error:'Job non valido.'}};
    const subjectHash=hashClientId(clientId,this.subjectSalt);
    await this.repository.initialize();
    const job=await this.repository.readOnDemandCoupon({subjectHash,jobId});
    if (!job) return {status:404,body:{success:false,error:'Job non trovato.'}};
    if (job.dayKey!==localClock(this.now()).dayKey) {
      return {status:410,body:{success:false,error:'Richiesta scaduta.'}};
    }
    return {status:job.status==='ready'?200:202,body:{
      success:true,jobId:job.jobId,dayKey:job.dayKey,status:job.status,
      ...(job.status==='ready'?{coupon:job.coupon}:{}),
    }};
  }

  // Explicit server-side trigger only. The mobile HTTP response never waits
  // for the multi-minute Flutter calculation, and no device token is sent
  // to the official engine.
  async runOne() {
    if (typeof this.generateOfficialCoupon!=='function') {
      return {status:'official_engine_not_connected'};
    }
    await this.repository.initialize();
    const job=await this.repository.claimOnDemandCoupon();
    if (!job) return {status:'idle'};
    const lease={jobId:job.jobId,attempts:job.attempts,leaseToken:job.leaseToken};
    const renew=async()=>{
      try {return await this.repository.renewOnDemandCouponLease(lease)===true;}
      catch (_) {return false;}
    };
    let lost=false;
    let pending=Promise.resolve();
    const timer=setInterval(()=>{
      pending=pending.then(async()=>{
        if (!lost && !(await renew())) lost=true;
      });
    },this.leaseRenewalMs);
    timer.unref?.();
    let output,providerError=false;
    try {
      output=await this.generateOfficialCoupon({
        dayKey:job.dayKey,preferences:job.preferences,now:this.now(),
      });
    } catch (_) {providerError=true;}
    finally {clearInterval(timer);await pending;}
    if (lost || !(await renew())) return {status:'superseded'};
    const checked=this.now();
    if (providerError) {
      const ok=await this.repository.finishOnDemandCoupon({...lease,outcome:'retry'});
      return {status:ok?'retry':'superseded'};
    }
    if (output && output.status==='no_coupon' &&
        Object.keys(output).length===1) {
      const ok=await this.repository.finishOnDemandCoupon({...lease,outcome:'no_coupon'});
      return {status:ok?'no_coupon':'superseded'};
    }
    const validated=validateGeneratedCoupon({
      coupon:output,preferences:job.preferences,now:checked,
    });
    if (!validated.valid || validated.dayKey!==job.dayKey ||
        !oddsStrictlyAboveMinimum(output)) {
      const ok=await this.repository.finishOnDemandCoupon({...lease,outcome:'retry'});
      return {status:ok?'retry':'superseded'};
    }
    const ok=await this.repository.finishOnDemandCoupon({...lease,
      outcome:'ready',coupon:publicCoupon(output)});
    return {status:ok?'ready':'superseded'};
  }
}

module.exports={OnDemandCouponService,normalizeRequest,
  oddsStrictlyAboveMinimum};
