'use strict';

const {randomUUID} = require('node:crypto');

const HASH = /^[0-9a-f]{64}$/;
const CURSOR = /^[0-9a-f]{64}$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const ENVS = new Set(['sandbox','production']);

class DailyPalinsestoSubscriptionRepository {
  constructor(pool) {
    if (!pool || typeof pool.query !== 'function') {
      throw new TypeError('Database required');
    }
    this.pool=pool;
  }

  async upsert({subjectHash, hour, minute, environment,
    ciphertext, nonce, authTag}) {
    if (!HASH.test(subjectHash || '') ||
        !Number.isInteger(hour) || hour < 0 || hour > 23 ||
        !Number.isInteger(minute) || minute < 0 || minute > 59 ||
        !ENVS.has(environment) ||
        [ciphertext,nonce,authTag].some(x=>typeof x!=='string'||!x.length||x.length>1024)) {
      throw new TypeError('Invalid digest registration');
    }
    await this.pool.query(
      `INSERT INTO public.sb_daily_palinsesto_subscriptions_v1
       (subject_hash,hour,minute,apns_environment,
        token_ciphertext,token_nonce,token_auth_tag)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT (subject_hash) DO UPDATE SET
       hour=excluded.hour, minute=excluded.minute,
       apns_environment=excluded.apns_environment,
       token_ciphertext=excluded.token_ciphertext,
       token_nonce=excluded.token_nonce,
       token_auth_tag=excluded.token_auth_tag,
       updated_at=clock_timestamp()`,
      [subjectHash,hour,minute,environment,ciphertext,nonce,authTag],
    );
  }

  async unsubscribe(subjectHash) {
    if (!HASH.test(subjectHash || '')) throw new TypeError('Invalid subscriber');
    // Deleting the active subscription prevents further dispatch immediately;
    // history retained only for duplicate guard, to be cleared on user erasure.
    await this.pool.query(
      'DELETE FROM public.sb_daily_palinsesto_subscriptions_v1 WHERE subject_hash=$1',
      [subjectHash],
    );
  }

  async listDue({dayKey, now, minuteOfDay, limit=20, afterSubjectHash=null}={}) {
    if (!DAY.test(dayKey || '') || !(now instanceof Date) ||
        !Number.isFinite(now.getTime()) ||
        !Number.isInteger(minuteOfDay) || minuteOfDay < 0 || minuteOfDay > 1439 ||
        !Number.isInteger(limit) || limit < 1 || limit > 25 ||
        (afterSubjectHash!==null && !CURSOR.test(afterSubjectHash))) {
      throw new TypeError('Invalid due sweep');
    }
    // A 12:00 cut-off avoids sending "morning" updates in the afternoon
    // after a delayed job. Retry claims may be attempted until 12:00.
    if (minuteOfDay>=720) return [];
    const r=await this.pool.query(
      `SELECT p.subject_hash AS "subjectHash"
       FROM public.sb_daily_palinsesto_subscriptions_v1 p
       LEFT JOIN public.sb_daily_palinsesto_deliveries_v1 d
         ON d.subject_hash=p.subject_hash AND d.local_day=$1::date
       WHERE p.hour*60+p.minute<=$2
         AND ($4::text IS NULL OR p.subject_hash>$4::text)
         AND (d.subject_hash IS NULL OR (
           d.attempts<5 AND (
             (d.status='retry' AND d.next_retry_at <= $3)
             OR (d.status='processing'
               AND d.updated_at <= $3 - INTERVAL '15 minutes')
           )
         ))
       ORDER BY p.subject_hash ASC LIMIT $5`,
      [dayKey,minuteOfDay,now,afterSubjectHash,limit],
    );
    return r.rows;
  }

  async claim({subjectHash,dayKey,now}) {
    if (!HASH.test(subjectHash||'') || !DAY.test(dayKey||'') ||
        !(now instanceof Date) || !Number.isFinite(now.getTime())) {
      throw new TypeError('Invalid daily claim');
    }
    const lockToken=randomUUID();
    const r=await this.pool.query(
      `INSERT INTO public.sb_daily_palinsesto_deliveries_v1
       (subject_hash,local_day,status,attempts,lock_token,updated_at)
       SELECT $1,$2::date,'processing',1,$3::uuid,$4
       WHERE EXISTS (SELECT 1 FROM public.sb_daily_palinsesto_subscriptions_v1
                     WHERE subject_hash=$1)
       ON CONFLICT (subject_hash,local_day) DO UPDATE SET
         status='processing',
         attempts=sb_daily_palinsesto_deliveries_v1.attempts+1,
         lock_token=excluded.lock_token,
         updated_at=$4
       WHERE sb_daily_palinsesto_deliveries_v1.attempts<5
         AND ((
           sb_daily_palinsesto_deliveries_v1.status='retry'
           AND sb_daily_palinsesto_deliveries_v1.next_retry_at<=$4
         ) OR (
           sb_daily_palinsesto_deliveries_v1.status='processing'
           AND sb_daily_palinsesto_deliveries_v1.updated_at<=$4-INTERVAL '15 minutes'
         ))
       RETURNING attempts`,
      [subjectHash,dayKey,lockToken,now],
    );
    return r.rows.length ? {attempts:Number(r.rows[0].attempts),lockToken} : null;
  }

  async read(subjectHash) {
    if (!HASH.test(subjectHash||'')) throw new TypeError('Invalid subscriber');
    const r=await this.pool.query(
      `SELECT apns_environment AS environment,
          token_ciphertext AS ciphertext,token_nonce AS nonce,
          token_auth_tag AS "authTag"
       FROM public.sb_daily_palinsesto_subscriptions_v1 WHERE subject_hash=$1`,
      [subjectHash],
    );
    return r.rows[0]||null;
  }

  async finish({subjectHash,dayKey,lockToken,now,status}) {
    if (!HASH.test(subjectHash||'') || !DAY.test(dayKey||'') ||
        !/^[0-9a-f-]{36}$/.test(lockToken||'') ||
        !(now instanceof Date) || !Number.isFinite(now.getTime()) ||
        !['sent','retry','unregistered','failed'].includes(status)) {
      throw new TypeError('Invalid dispatch completion');
    }
    const r=await this.pool.query(
      `UPDATE public.sb_daily_palinsesto_deliveries_v1 SET
        status=$4,
        updated_at=$5,
        accepted_at=CASE WHEN $4='sent' THEN $5 ELSE accepted_at END,
        next_retry_at=CASE WHEN $4='retry' THEN $5+INTERVAL '20 minutes'
          ELSE NULL END
       WHERE subject_hash=$1 AND local_day=$2::date AND lock_token=$3::uuid
         AND status='processing' AND EXISTS (
           SELECT 1 FROM public.sb_daily_palinsesto_subscriptions_v1
           WHERE subject_hash=$1)
       RETURNING attempts`,
      [subjectHash,dayKey,lockToken,status,now],
    );
    return r.rowCount>0;
  }
}

module.exports={DailyPalinsestoSubscriptionRepository};
