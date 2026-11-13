'use strict';

// An opt-in loop inside an already running Node server. Database leasing and
// its official Flutter engine remain the source of truth. No new Render plan
// or scheduled daily AutoSchedina is implied by importing this module.
function createOnDemandScheduler({runOne,intervalMs=60000,onError=()=>{},
  setIntervalFn=setInterval,clearIntervalFn=clearInterval}={}) {
  if (typeof runOne!=='function' || typeof onError!=='function' ||
      !Number.isInteger(intervalMs) || intervalMs<30000 || intervalMs>300000) {
    throw new TypeError('Invalid on-demand scheduler');
  }
  let timer=null;
  let running=null;
  let stopped=false;
  async function tick(){
    if(stopped)return {status:'stopped'};
    if(running)return {status:'busy'};
    running=(async()=>{
      try{return await runOne();}
      catch(_){try{onError('worker_cycle_failed');}catch(_){}return {status:'error'};}
    })();
    try{return await running;}finally{running=null;}
  }
  function start(){
    if(timer!==null||stopped)throw new Error('Scheduler already started or stopped');
    timer=setIntervalFn(()=>{void tick();},intervalMs);
    timer.unref?.();
  }
  async function stop(){
    stopped=true;
    if(timer!==null){clearIntervalFn(timer);timer=null;}
    if(running)await running;
  }
  return{start,stop,tick};
}
module.exports={createOnDemandScheduler};
