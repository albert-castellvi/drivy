// reflect-metadata is required by @peculiar/x509's dependency tsyringe before anything else loads.
import 'npm:reflect-metadata@0.2.2';

// Offline verification of an App Store signed transaction (JWS) — the pure
// core of the verify-premium Edge Function (odd/tasks/server-validation.md
// S5.2). No I/O, no clock, no Supabase: everything it needs arrives in
// `config`, so verify_test.ts can build its own fixture chain and run it with
// `deno test`.

import { X509Certificate } from 'npm:@peculiar/x509@3.0.0';

// Apple Root CA - G3 (https://www.apple.com/certificateauthority/), the trust
// anchor every App Store Server API JWS chain must reach.
// Downloaded from https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
// SHA-256 fingerprint (DER): 63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179
export const APPLE_ROOT_CA_G3_PEM = `-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
6BgD56KyKA==
-----END CERTIFICATE-----`;

export const PRODUCTION_BUNDLE_ID = 'com.acrstudio.drivy';
export const PRODUCTION_PRODUCT_ID = 'com.acrstudio.drivy.premium.monthly';

// Fields of the App Store signed transaction the function actually uses.
// Dates are epoch milliseconds, as the App Store Server API signs them.
export interface TransactionPayload {
  transactionId?: string;
  originalTransactionId?: string;
  bundleId?: string;
  productId?: string;
  purchaseDate?: number;
  expiresDate?: number;
  revocationDate?: number;
  revocationReason?: number;
  environment?: string;
  [key: string]: unknown;
}

export interface VerifyConfig {
  trustedRootPem: string;
  bundleId: string;
  productId: string;
  now: Date;
}

export function productionConfig(now = new Date()): VerifyConfig {
  return {
    trustedRootPem: APPLE_ROOT_CA_G3_PEM,
    bundleId: PRODUCTION_BUNDLE_ID,
    productId: PRODUCTION_PRODUCT_ID,
    now,
  };
}

export type VerifyFailReason =
  | 'malformed'
  | 'unsupported_algorithm'
  | 'unknown_root'
  | 'bad_chain'
  | 'bad_signature'
  | 'wrong_bundle'
  | 'wrong_product'
  | 'expired'
  | 'revoked';

export type VerifyResult =
  | { ok: true; payload: TransactionPayload }
  | { ok: false; reason: VerifyFailReason };

const fail = (reason: VerifyFailReason): VerifyResult => ({ ok: false, reason });

function base64UrlDecode(part: string): Uint8Array<ArrayBuffer> {
  const padded = part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '=');
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(padded)) throw new Error('not base64url');
  const binary = atob(padded);
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a[i] ^ b[i];
  return diff === 0;
}

async function es256PublicKeyOf(cert: X509Certificate): Promise<CryptoKey> {
  return cert.publicKey.export({ name: 'ECDSA', namedCurve: 'P-256' }, ['verify']);
}

/**
 * Verifies an App Store signed transaction completely offline:
 *   1. compact JWS shape, ES256 alg, x5c chain present;
 *   2. each certificate is signed by the next one, and the chain reaches the
 *      configured trusted root byte-for-byte;
 *   3. the JWS signature verifies with the leaf's ES256 key;
 *   4. payload checks: bundleId, productId, expiresDate in the future, no
 *      revocationDate.
 */
export async function verifyPremiumJws(jws: string, config: VerifyConfig): Promise<VerifyResult> {
  // 1. shape and header
  const parts = jws.split('.');
  if (parts.length !== 3 || parts.some((p) => p.length === 0)) return fail('malformed');
  const [headerPart, payloadPart, signaturePart] = parts;
  let header: { alg?: string; x5c?: string[] };
  let payload: TransactionPayload;
  let signature: Uint8Array<ArrayBuffer>;
  try {
    header = JSON.parse(new TextDecoder().decode(base64UrlDecode(headerPart)));
    payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(payloadPart)));
    signature = base64UrlDecode(signaturePart);
  } catch {
    return fail('malformed');
  }
  if (header.alg !== 'ES256') return fail('unsupported_algorithm');
  const x5c = header.x5c;
  if (!Array.isArray(x5c) || x5c.length < 2) return fail('malformed');

  // 2. certificate chain up to the trusted root
  let certs: X509Certificate[];
  try {
    certs = x5c.map((der) => new X509Certificate(base64UrlDecode(der)));
  } catch {
    return fail('malformed');
  }
  const trustedRoot = new X509Certificate(config.trustedRootPem);
  if (!bytesEqual(new Uint8Array(certs[certs.length - 1].rawData), new Uint8Array(trustedRoot.rawData))) {
    return fail('unknown_root');
  }
  for (let i = 0; i < certs.length - 1; i += 1) {
    let signed: boolean;
    try {
      signed = await certs[i].verify({ publicKey: certs[i + 1].publicKey, signatureOnly: true });
    } catch {
      return fail('bad_chain');
    }
    if (!signed) return fail('bad_chain');
  }

  // 3. leaf ES256 signature over header.payload (raw r||s, as WebCrypto wants)
  let valid: boolean;
  try {
    const leafKey = await es256PublicKeyOf(certs[0]);
    const signingInput = Uint8Array.from(
      new TextEncoder().encode(`${headerPart}.${payloadPart}`),
    );
    valid = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, leafKey, signature, signingInput);
  } catch {
    return fail('bad_signature');
  }
  if (!valid) return fail('bad_signature');

  // 4. payload checks
  if (payload.bundleId !== config.bundleId) return fail('wrong_bundle');
  if (payload.productId !== config.productId) return fail('wrong_product');
  if (typeof payload.expiresDate !== 'number' || payload.expiresDate <= config.now.getTime()) {
    return fail('expired');
  }
  if (typeof payload.revocationDate === 'number' || payload.revocationDate !== undefined) {
    return fail('revoked');
  }

  return { ok: true, payload };
}
