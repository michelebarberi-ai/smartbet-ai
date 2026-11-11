'use strict';

// P20.3J: staging-only, allowlisted diagnostic codes. Never log raw Flutter
// stdout/stderr, input requests, results, tokens or exceptions.
const CODES = Object.freeze(new Set([
  'flutter_exit_nonzero',
  'flutter_timeout',
  'flutter_process_killed',
  'flutter_spawn_failed',
  'flutter_compile_failed',
  'flutter_plugin_unavailable',
  'flutter_network_failure',
  'flutter_provider_auth',
  'flutter_test_failed',
  'result_file_missing',
  'result_read_failed',
  'result_invalid_json',
  'result_contract_invalid',
  'coupon_validation_failed',
  'executor_failed',
]));

const MAX_CAPTURE_CHARS = 12_000;
function limitedAppend(previous, chunk) {
  // Keep the last lines: Flutter test failures usually appear at the end.
  return (previous + String(chunk)).slice(-MAX_CAPTURE_CHARS);
}

function classifyFlutterFailure(output) {
  const s = typeof output === 'string' ? output.slice(0, MAX_CAPTURE_CHARS) : '';
  if (/MissingPluginException|No implementation found for method/i.test(s)) return 'flutter_plugin_unavailable';
  if (/\b(?:401|403)\b.{0,90}(?:API|token|authorization|key)|(?:API.?key|unauthorized|authentication failed|permission denied)/i.test(s)) return 'flutter_provider_auth';
  if (/SocketException|HandshakeException|CERTIFICATE_VERIFY_FAILED|Failed host lookup|Connection refused|TimeoutException|Connection timed out|Network is unreachable/i.test(s)) return 'flutter_network_failure';
  if (/Compilation failed|Failed to compile|Error:.*(?:isn't defined|not found|cannot be assigned)|Could not resolve package|Kernel compilation failed|Failed to load /i.test(s)) return 'flutter_compile_failed';
  if (/Some tests failed|\bFAILED\b|\bException\b|\bError\b/i.test(s)) return 'flutter_test_failed';
  return 'flutter_exit_nonzero';
}

function safeCategory(code) {
  return CODES.has(code) ? code : 'executor_failed';
}

function diagnosticError(category) {
  const error = new Error('Headless execution failed');
  error.headlessCategory = safeCategory(category);
  return error;
}

function reportFailure(category, env = process.env, log = console.warn) {
  if (env.AUTO_COUPON_HEADLESS_DIAGNOSTICS !== 'true') return;
  log(`[headless-staging] failure_category=${safeCategory(category)}`);
}

module.exports = {limitedAppend, classifyFlutterFailure, safeCategory,
  diagnosticError, reportFailure};
