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
  authorizeMobile,getLearningService,generateOfficialCoupon,now=()=>new Date()}) {
  const enabled=mobileEnabled &&
    env.ON_DEMAND_COUPON_REQUESTS_ENABLED==='true' &&
    typeof generateOfficialCoupon==='function';
  const workerEnabled=enabled && env.ON_DEMAND_COUPON_WORKER_ENABLED==='true' &&
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
    return safe(res,()=>getService().submit({
      clientId:req.learningClientId,body:req.body,
    }));
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
