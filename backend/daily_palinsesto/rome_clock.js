'use strict';

// Local calendar date used by the fixture digest, independent of legacy
// automatic-coupon scheduling. No timers, provider requests, or push.
function romeDayKey(date) {
  if (!(date instanceof Date) || !Number.isFinite(date.getTime())) {
    throw new TypeError('Invalid calendar instant');
  }
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Europe/Rome',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const values=Object.fromEntries(parts.map(x=>[x.type,x.value]));
  return `${values.year}-${values.month}-${values.day}`;
}
module.exports={romeDayKey};
