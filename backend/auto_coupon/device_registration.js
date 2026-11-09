'use strict';
const crypto = require('node:crypto');

const APNS_DEVICE_TOKEN = /^[0-9a-fA-F]{64}$/;
const ENCRYPTION_KEY = /^[0-9a-fA-F]{64}$/;
const SUBJECT_HASH = /^[0-9a-f]{64}$/;
const ENVIRONMENTS = new Set(['production', 'sandbox']);

function registrationReady(env = process.env) {
  return env.AUTO_COUPON_PUSH_REGISTRATION_ENABLED === 'true' &&
    ENCRYPTION_KEY.test(env.AUTO_COUPON_PUSH_TOKEN_ENCRYPTION_KEY || '') &&
    ENVIRONMENTS.has(env.APNS_ENVIRONMENT);
}

// AES-256-GCM: a stolen database alone must not expose iPhone device tokens.
// NEVER log tokens, plaintext, encryption keys, ciphertext or authentication tags.
function encryptDeviceToken({deviceToken, subjectHash, environment, keyHex,
  randomBytes = crypto.randomBytes}) {
  if (!APNS_DEVICE_TOKEN.test(deviceToken || '') ||
      !SUBJECT_HASH.test(subjectHash || '') ||
      !ENVIRONMENTS.has(environment) || !ENCRYPTION_KEY.test(keyHex || '')) {
    throw new Error('Invalid push registration input');
  }
  const nonce = randomBytes(12);
  if (!Buffer.isBuffer(nonce) || nonce.length !== 12) {
    throw new Error('Invalid cipher nonce');
  }
  const cipher = crypto.createCipheriv('aes-256-gcm', Buffer.from(keyHex, 'hex'), nonce);
  cipher.setAAD(Buffer.from(`${subjectHash}:${environment}`, 'utf8'));
  const ciphertext = Buffer.concat([
    cipher.update(deviceToken.toLowerCase(), 'utf8'), cipher.final(),
  ]);
  return {
    ciphertext: ciphertext.toString('base64'),
    nonce: nonce.toString('base64'),
    authTag: cipher.getAuthTag().toString('base64'),
  };
}

function decryptDeviceToken({record, subjectHash, keyHex}) {
  if (!SUBJECT_HASH.test(subjectHash || '') || !ENCRYPTION_KEY.test(keyHex || '') ||
      !ENVIRONMENTS.has(record?.environment)) throw new Error('Invalid push identity');
  const nonce = Buffer.from(record.nonce, 'base64');
  const authTag = Buffer.from(record.authTag, 'base64');
  if (nonce.length !== 12 || authTag.length !== 16) throw new Error('Invalid encrypted token');
  const decipher = crypto.createDecipheriv('aes-256-gcm', Buffer.from(keyHex,'hex'), nonce);
  decipher.setAAD(Buffer.from(`${subjectHash}:${record.environment}`, 'utf8'));
  decipher.setAuthTag(authTag);
  const token = Buffer.concat([
    decipher.update(Buffer.from(record.ciphertext, 'base64')), decipher.final(),
  ]).toString('utf8');
  if (!APNS_DEVICE_TOKEN.test(token)) throw new Error('Invalid decrypted token');
  return token;
}

module.exports = {registrationReady, encryptDeviceToken, decryptDeviceToken};
