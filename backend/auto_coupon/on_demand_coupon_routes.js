'use strict';

// Mobile requests are separately gated from daily subscriptions. No job is
// executed inside a mobile POST. The trusted worker can be invoked only with
// its own independent secret; it never receives mobile bearer credentials.
const {validToken}=require('../learning/learning_core');
const {OnDemandCouponService}=require('./on_demand_coupon_service');

const BASE='/learning/v1/mobile/on-demand-coupon/jobs';
const WORKER='/learning/v1/on-demand-coupon/worker/run';
const JOB=/^\/learning\/v1\/mobile\/on-demand-coupon\/jobs\/([0-9a-f-]{36})$/i;

function registerOnDemandCouponRoutes(app,{env,mobileEnabled,
  authorizeMobile,getLearningService,generateOfficialCoupon,
  verifyExternalWorker=null,wakeExternalWorker=null,
  workerRunning=false,now=()=>new Date()}) {
  // Never let an iPhone queue work unless an actual server-side processing
  // loop has started. Configured HTTP worker triggers alone are not a queue.
  const configured=mobileEnabled &&
    env.ON_DEMAND_COUPON_REQUESTS_ENABLED==='true' &&
    typeof generateOfficialCoupon==='function';
  const enabled=configured && workerRunning===true;
  const workerEnabled=configured && env.ON_DEMAND_COUPON_WORKER_ENABLED==='true' &&
    typeof env.ON_DEMAND_COUPON_WORKER_TOKEN==='string' &&
    env.ON_DEMAND_COUPON_WORKER_TOKEN.length>=32;
  let service;
  const getService=()=>service??=(new OnDemandCouponService({
    repository:getLearningService().repository,
    subjectSalt:env.LEARNING_SUBJECT_SALT,
    generateOfficialCoupon,now,
  }));
  const safe=async(res,fn)=>{
    try {
      const result=await fn();
      res.set('Cache-Control','no-store');
      return res.status(result.status).json(result.body);
    } catch (error) {
      console.error('ON DEMAND COUPON:',error?.code||error?.name||'error');
      return res.status(503).json({success:false,error:'Servizio temporaneamente non disponibile.'});
    }
  };
  app.post(BASE,authorizeMobile,(req,res)=>{
    if(!enabled) return res.status(503).json({success:false,error:'Schedine remote non abilitate.'});
    return safe(res,async()=>{
      const external=env.ON_DEMAND_COUPON_EXTERNAL_WORKER_ENABLED==='true';
      // Fail closed before writing a queued job unless the private paid
      // runner confirms its real worker is live and version-pinned.
      if(external && (typeof verifyExternalWorker!=='function' ||
          !(await verifyExternalWorker()))) {
        return {status:503,body:{success:false,
          error:'Elaboratore remoto temporaneamente non disponibile.'}};
      }
      const result=await getService().submit({
        clientId:req.learningClientId,body:req.body,
      });
      if(external && result.status===202) {
        const notified=typeof wakeExternalWorker==='function' &&
          await wakeExternalWorker();
        // Persisted jobId is always returned. A missed wake is recovered
        // by the runner's periodic Neon sweep after an interrupted request.
        result.body.workerNotified=notified===true;
      }
      return result;
    });
  });
  app.get(BASE+'/:jobId',authorizeMobile,(req,res)=>{
    if(!enabled) return res.status(503).json({success:false,error:'Schedine remote non abilitate.'});
    return safe(res,()=>getService().read({
      clientId:req.learningClientId,jobId:req.params?.jobId,
    }));
  });
  app.post(WORKER,(req,res)=>{
    if(!workerEnabled) return res.status(503).json({success:false,error:'Worker disabilitato.'});
    if(!validToken(req.get('x-goalvdline-on-demand-worker-token'),
      env.ON_DEMAND_COUPON_WORKER_TOKEN)) {
      return res.status(401).json({success:false,error:'Non autorizzato.'});
    }
    if(!req.body || typeof req.body!=='object' || Array.isArray(req.body) ||
       Object.keys(req.body).length!==0) {
      return res.status(400).json({success:false,error:'Payload non valido.'});
    }
    return safe(res,async()=>({status:200,body:{
      success:true,...await getService().runOne(),
    }}));
  });
  return {enabled,workerEnabled};
}
module.exports={registerOnDemandCouponRoutes,BASE,WORKER,JOB};
