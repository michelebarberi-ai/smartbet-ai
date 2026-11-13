'use strict';

// B47: explicitly opted-in, always-on queue worker inside the EXISTING paid
// private Flutter runner. The public Free API never needs a long-lived timer.
// It wakes this worker only after an authenticated, persisted mobile request.
// The slow recovery sweep handles interrupted wake-ups or runner restarts.
const {Pool}=require('pg');
const {LearningRepository}=require('../learning/learning_repository');
const {OnDemandCouponService}=require('./on_demand_coupon_service');
const {createOfficialEngineAdapter}=require('./official_engine_client');

const IDLE_SWEEP_MS=15*60*1000;
const RETRY_SWEEP_MS=2*60*1000;
const DRAIN_DELAY_MS=2000;
const PINNED_HOST='smartbet-b45-flutter-staging';

// A dedicated queue role requires only SELECT/UPDATE on the job table.
// Never issue schema DDL from the always-on private runner.
class ExistingQueueRepository extends LearningRepository {
  async initialize() {
    if (!this.ready) {
      this.ready=this.pool.query(
        "SELECT to_regclass('public.sb_on_demand_coupon_jobs_v1') IS NOT NULL AS ready"
      ).then(result=>{
        if (result.rows?.[0]?.ready!==true) throw new Error('Job schema not ready');
      }).catch(error=>{this.ready=null;throw error;});
    }
    return this.ready;
  }
}
const VALID_REVISION=/^[a-f0-9]{7,40}$/;

function createPrivateNeonWorker({
  env=process.env,fetchImpl=fetch,poolFactory=opts=>new Pool(opts),
  repositoryFactory=pool=>new ExistingQueueRepository(pool),
  timerFn=setTimeout,clearFn=clearTimeout,
}={}) {
  if(env.AUTO_COUPON_PRIVATE_NEON_WORKER_ENABLED!=='true') return null;
  const token=env.AUTO_COUPON_HEADLESS_B47_TOKEN;
  const revision=env.AUTO_COUPON_HEADLESS_REVISION;
  if(env.AUTO_COUPON_HEADLESS_HOST_ENABLED!=='true' ||
     env.AUTO_COUPON_HEADLESS_PRIVATE_RENDER_BIND!=='true' ||
     typeof env.DATABASE_URL!=='string' || !env.DATABASE_URL.trim() ||
     typeof token!=='string' || token.length<32 ||
     typeof revision!=='string' || !VALID_REVISION.test(revision)) {
    throw new Error('Private Neon worker missing mandatory configuration');
  }
  const adapterEnv={
    AUTO_COUPON_OFFICIAL_ENGINE_ENABLED:'true',
    AUTO_COUPON_OFFICIAL_ENGINE_PRIVATE_RENDER_ENABLED:'true',
    AUTO_COUPON_OFFICIAL_ENGINE_HOSTPORT:PINNED_HOST+':8799',
    AUTO_COUPON_OFFICIAL_ENGINE_TOKEN:token,
    AUTO_COUPON_OFFICIAL_ENGINE_REVISION:revision,
  };
  const localFetch=(url,opts)=>{
    const u=new URL(url);
    if(u.protocol!=='http:' || u.hostname!==PINNED_HOST ||
       u.port!=='8799' || u.search || u.hash ||
       !(u.pathname==='/coupon/generate' ||
         /^\/coupon\/jobs\/[0-9a-f]{32}$/.test(u.pathname))) {
      throw new Error('Worker transport endpoint rejected');
    }
    // Destination is fixed loopback, not supplied by any remote caller.
    return fetchImpl('http://127.0.0.1:8799'+u.pathname,opts);
  };
  const official=createOfficialEngineAdapter({env:adapterEnv,fetchImpl:localFetch});
  if(typeof official!=='function') throw new Error('Private official engine unavailable');
  const pool=poolFactory({
    connectionString:env.DATABASE_URL,max:2,
    connectionTimeoutMillis:5000,idleTimeoutMillis:30000,
    ssl:env.LEARNING_PG_SSL==='true'?{rejectUnauthorized:true}:undefined,
  });
  // runOne only claims/fences hashed jobs; the private runner never receives
  // client identity, device tokens, or the API's subject-hashing salt.
  const service=new OnDemandCouponService({
    repository:repositoryFactory(pool),subjectSalt:null,
    generateOfficialCoupon:official,
  });
  let started=false,stopped=false,running=null,timer=null,databaseVerified=false;
  function schedule(delay) {
    if(stopped) return;
    if(timer!==null) clearFn(timer);
    timer=timerFn(()=>{timer=null;void tick();},delay);
    timer?.unref?.();
  }
  async function tick() {
    if(!started || stopped) return {status:'disabled'};
    if(running) return {status:'busy'};
    if(timer!==null) {clearFn(timer);timer=null;}
    running=(async()=>{
      try {
        const outcome=await service.runOne();
        databaseVerified=true;
        return outcome;
      } catch(_) {
        databaseVerified=false;
        return {status:'error'};
      }
    })();
    let result;
    try {result=await running;}
    finally {
      running=null;
      // Drain additional queued jobs, or back off when there is no work.
      const state=result?.status;
      schedule(state==='idle'?IDLE_SWEEP_MS:
        state==='retry'||state==='error'?RETRY_SWEEP_MS:DRAIN_DELAY_MS);
    }
    return result;
  }
  function start() {
    if(started || stopped) throw new Error('Worker already started or stopped');
    started=true;
    // Recover prior persisted work after a runner restart.
    void tick();
  }
  async function stop() {
    stopped=true;
    if(timer!==null){clearFn(timer);timer=null;}
    if(running) await running;
    await pool.end();
  }
  return {
    start,stop,tick,
    get ready(){return started && !stopped && databaseVerified;},
  };
}

module.exports={createPrivateNeonWorker,IDLE_SWEEP_MS,RETRY_SWEEP_MS};
