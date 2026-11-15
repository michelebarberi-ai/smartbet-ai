'use strict';

// Optional mail transport for B59, disabled until owner verifies email,
// sender domain and provider credentials in server-only environment variables.
// Does not create accounts, recover passwords or leak auth secrets into logs.
function createOwnerRecoverySender({env = process.env, fetchImpl = fetch} = {}) {
  if (env.GOALVDLINE_OWNER_RECOVERY_ENABLED !== 'true' ||
      typeof env.GOALVDLINE_OWNER_RECOVERY_EMAIL !== 'string' ||
      typeof env.GOALVDLINE_OWNER_RECOVERY_EMAIL_FROM !== 'string' ||
      typeof env.GOALVDLINE_OWNER_RECOVERY_RESEND_KEY !== 'string' ||
      !env.GOALVDLINE_OWNER_RECOVERY_RESEND_KEY.startsWith('re_')) {
    return null;
  }
  const from = env.GOALVDLINE_OWNER_RECOVERY_EMAIL_FROM;
  const to = env.GOALVDLINE_OWNER_RECOVERY_EMAIL;
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(from) ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(to)) return null;

  return async ({to: recipient, code, expiresInMinutes}) => {
    if (recipient !== to || !/^\d{8}$/.test(code) ||
        expiresInMinutes !== 10) {
      throw new Error('Invalid owner recovery dispatch');
    }
    const response = await fetchImpl('https://api.resend.com/emails', {
      method: 'POST',
      redirect: 'error',
      headers: {
        Authorization: 'Bearer ' + env.GOALVDLINE_OWNER_RECOVERY_RESEND_KEY,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({
        from, to: [recipient],
        subject: 'GoalVdLine: codice di recupero accesso',
        text: 'Hai richiesto un accesso di emergenza a GoalVdLine. ' +
          'Il codice monouso è: ' + code + '\n' +
          'Scade tra 10 minuti. Se non hai richiesto questo codice, ' +
          'ignora questa email. La tua password non cambia.',
      }),
      signal: AbortSignal.timeout(7000),
    });
    if (response.status !== 200 && response.status !== 201) {
      throw new Error('Owner recovery provider unavailable');
    }
  };
}

module.exports = {createOwnerRecoverySender};
