'use strict';

// Classifies provider failures without returning raw upstream bodies to clients
// or logging secrets, URL query strings, odds payloads or device information.
// This module does not retry: a retry must not silently multiply API usage.
const ERROR_MESSAGES = Object.freeze({
  FOOTBALL_PROVIDER_KEY_MISSING: 'Dati sportivi non configurati sul server.',
  FOOTBALL_PROVIDER_RATE_LIMIT: 'Limite temporaneo del fornitore sportivo.',
  FOOTBALL_PROVIDER_AUTH: 'Il fornitore sportivo non autorizza la richiesta.',
  FOOTBALL_PROVIDER_HTTP_ERROR: 'Il fornitore sportivo non risponde correttamente.',
  FOOTBALL_PROVIDER_INVALID_JSON: 'Risposta sportiva non valida.',
  FOOTBALL_PROVIDER_REPORTED_ERROR: 'Il fornitore sportivo ha restituito un errore.',
  FOOTBALL_PROVIDER_TIMEOUT: 'Il fornitore sportivo non ha risposto in tempo.',
  FOOTBALL_PROVIDER_NETWORK_ERROR: 'Connessione al fornitore sportivo non riuscita.',
  FOOTBALL_PROXY_INTERNAL_ERROR: 'Dati sportivi temporaneamente non disponibili.',
});
const ERROR_CODES = new Set(Object.keys(ERROR_MESSAGES));

function failure(code, upstreamStatus = null) {
  const error = new Error(ERROR_MESSAGES[code]);
  error.code = code;
  error.statusCode = code === 'FOOTBALL_PROVIDER_KEY_MISSING' ? 503 : 502;
  error.upstreamStatus = Number.isInteger(upstreamStatus) &&
      upstreamStatus >= 100 && upstreamStatus <= 599
    ? upstreamStatus
    : null;
  return error;
}

function httpFailure(status) {
  if (status === 429) return failure('FOOTBALL_PROVIDER_RATE_LIMIT', status);
  if (status === 401 || status === 403) {
    return failure('FOOTBALL_PROVIDER_AUTH', status);
  }
  return failure('FOOTBALL_PROVIDER_HTTP_ERROR', status);
}

function providerReportedError(errors) {
  if (Array.isArray(errors)) return errors.length > 0;
  if (typeof errors === 'string') return errors.trim().length > 0;
  return errors != null && typeof errors === 'object' &&
    Object.keys(errors).length > 0;
}

/**
 * A single request to API-Football. Return only validated JSON objects.
 * Inject fetch in tests. Defaults to a timeout without additional retries.
 */
async function fetchFootballJson({
  url,
  apiKey,
  fetchImpl = fetch,
  timeoutMs = 25000,
}) {
  if (typeof apiKey !== 'string' || !apiKey.trim()) {
    throw failure('FOOTBALL_PROVIDER_KEY_MISSING');
  }
  if (!Number.isInteger(timeoutMs) || timeoutMs < 1000 || timeoutMs > 120000) {
    throw new TypeError('Invalid football upstream timeout');
  }
  let response;
  try {
    response = await fetchImpl(url, {
      headers: {'x-apisports-key': apiKey},
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (error) {
    throw failure(
      error?.name === 'AbortError' || error?.name === 'TimeoutError'
        ? 'FOOTBALL_PROVIDER_TIMEOUT'
        : 'FOOTBALL_PROVIDER_NETWORK_ERROR',
    );
  }

  const status = Number.isInteger(response?.status) ? response.status : null;
  let body;
  try {
    body = await response.text();
  } catch (_) {
    throw failure('FOOTBALL_PROVIDER_NETWORK_ERROR', status);
  }

  let payload;
  try {
    payload = JSON.parse(body);
  } catch (_) {
    if (!response.ok) throw httpFailure(status);
    throw failure('FOOTBALL_PROVIDER_INVALID_JSON', status);
  }

  if (!response.ok) throw httpFailure(status);
  if (payload === null || typeof payload !== 'object' ||
      Array.isArray(payload)) {
    throw failure('FOOTBALL_PROVIDER_INVALID_JSON', status);
  }
  if (providerReportedError(payload.errors)) {
    throw failure('FOOTBALL_PROVIDER_REPORTED_ERROR', status);
  }
  return payload;
}

function safeFootballCode(error) {
  return ERROR_CODES.has(error?.code)
    ? error.code : 'FOOTBALL_PROXY_INTERNAL_ERROR';
}

function footballFailurePayload(error) {
  const code = safeFootballCode(error);
  return {
    httpStatus: code === 'FOOTBALL_PROVIDER_KEY_MISSING' ? 503 :
      code === 'FOOTBALL_PROXY_INTERNAL_ERROR' ? 500 : 502,
    body: {
      success: false,
      code,
      error: ERROR_MESSAGES[code],
    },
  };
}

/**
 * Structured, non-identifying log. Never log URL, request queries, provider
 * error text/body, credentials, fixture IDs, IP address or arbitrary stack.
 */
function logFootballFailure(error, {
  endpoint,
  logger = console,
} = {}) {
  const code = safeFootballCode(error);
  // Endpoint is authored by the server, never derived from arbitrary URL.
  const safeEndpoint = typeof endpoint === 'string' &&
      /^\/[a-z/-]{1,64}$/.test(endpoint)
    ? endpoint : '/unknown';
  const upstream = Number.isInteger(error?.upstreamStatus) &&
      error.upstreamStatus >= 100 && error.upstreamStatus <= 599
    ? error.upstreamStatus : null;
  const status = footballFailurePayload(error).httpStatus;
  logger.warn('FOOTBALL_UPSTREAM_DIAGNOSTIC', JSON.stringify({
    endpoint: safeEndpoint,
    code,
    upstreamHttpStatus: upstream,
    proxyHttpStatus: status,
  }));
}

function respondFootballFailure(res, error, endpoint) {
  logFootballFailure(error, {endpoint});
  const outcome = footballFailurePayload(error);
  return res.status(outcome.httpStatus).json(outcome.body);
}

module.exports = {
  fetchFootballJson,
  footballFailurePayload,
  logFootballFailure,
  respondFootballFailure,
  providerReportedError,
};
