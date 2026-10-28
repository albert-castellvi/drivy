import 'npm:reflect-metadata@0.2.2';

// Pure-verification tests for verify.ts (S5.2). No network, no Supabase: the
// fixtures build their own ES256 test root -> intermediate -> leaf chain and
// inject the trusted root, so no real Apple-signed JWS is needed.
//
//   cd supabase/functions/verify-premium && deno test

import assert from 'node:assert/strict';
import {
  BasicConstraintsExtension,
  X509Certificate,
  X509CertificateGenerator,
} from 'npm:@peculiar/x509@3.0.0';
import {
  APPLE_ROOT_CA_G3_PEM,
  productionConfig,
  verifyPremiumJws,
  type TransactionPayload,
  type VerifyConfig,
} from './verify.ts';

const NOW = new Date('2026-10-28T12:00:00Z');

const BUNDLE = 'com.acrstudio.drivy';
const PRODUCT = 'com.acrstudio.drivy.premium.monthly';

interface FixtureChain {
  root: X509Certificate;
  intermediate: X509Certificate;
  leaf: X509Certificate;
  leafPrivateKey: CryptoKey;
}

async function newKeyPair(): Promise<CryptoKeyPair> {
  return (await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' },
    true,
    ['sign', 'verify'],
  )) as CryptoKeyPair;
}

function caExtension(): BasicConstraintsExtension {
  return new BasicConstraintsExtension(true, 0, true);
}

// test root -> intermediate -> leaf, all ES256.
async function buildChain(): Promise<FixtureChain> {
  const rootKeys = await newKeyPair();
  const root = await X509CertificateGenerator.createSelfSigned({
    name: 'CN=Fixture Root CA',
    keys: rootKeys,
    notBefore: new Date('2026-01-01T00:00:00Z'),
    notAfter: new Date('2046-01-01T00:00:00Z'),
    extensions: [caExtension()],
  });

  const intermediateKeys = await newKeyPair();
  const intermediate = await X509CertificateGenerator.create({
    subject: 'CN=Fixture Intermediate CA',
    issuer: 'CN=Fixture Root CA',
    publicKey: intermediateKeys.publicKey,
    signingKey: rootKeys.privateKey,
    notBefore: new Date('2026-01-01T00:00:00Z'),
    notAfter: new Date('2046-01-01T00:00:00Z'),
    extensions: [caExtension()],
  });

  const leafKeys = await newKeyPair();
  const leaf = await X509CertificateGenerator.create({
    subject: 'CN=Fixture Leaf',
    issuer: 'CN=Fixture Intermediate CA',
    publicKey: leafKeys.publicKey,
    signingKey: intermediateKeys.privateKey,
    notBefore: new Date('2026-01-01T00:00:00Z'),
    notAfter: new Date('2046-01-01T00:00:00Z'),
  });

  return { root, intermediate, leaf, leafPrivateKey: leafKeys.privateKey };
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function base64UrlEncode(text: string): string {
  return btoa(text).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlDecode(part: string): Uint8Array {
  const padded = part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '=');
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function defaultPayload(): TransactionPayload {
  return {
    transactionId: '200000000000001',
    originalTransactionId: '200000000000001',
    bundleId: BUNDLE,
    productId: PRODUCT,
    purchaseDate: NOW.getTime() - 60_000,
    expiresDate: NOW.getTime() + 30 * 24 * 60 * 60 * 1000,
    environment: 'Production',
  };
}

// Signs a compact JWS with the leaf key over header.payload, exactly like the
// App Store server does: ES256 with raw r||s and an x5c chain.
async function signJws(
  chain: FixtureChain,
  payload: TransactionPayload,
  { headerOverrides = {}, tamper = false }: {
    headerOverrides?: Record<string, unknown>;
    tamper?: boolean;
  } = {},
): Promise<string> {
  const header = { alg: 'ES256', x5c: [chain.leaf, chain.intermediate, chain.root].map((c) =>
    bytesToBase64(new Uint8Array(c.rawData)),
  ), ...headerOverrides };
  const signingInput = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(payload))}`;
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    chain.leafPrivateKey,
    new TextEncoder().encode(signingInput),
  );
  const signaturePart = base64UrlEncode(
    String.fromCharCode(...new Uint8Array(signature)),
  );
  // Tamper: flip one payload character without touching the signature.
  const payloadPart = tamper
    ? base64UrlEncode(JSON.stringify(payload).replace('200000000000001', '999999999999999'))
    : base64UrlEncode(JSON.stringify(payload));
  return `${signingInput.split('.')[0]}.${payloadPart}.${signaturePart}`;
}

function config(trustedRootPem: string): VerifyConfig {
  return { trustedRootPem, bundleId: BUNDLE, productId: PRODUCT, now: NOW };
}

// A second, unrelated root: a chain to it must never verify against a
// different trusted root.
async function buildOtherRoot(): Promise<X509Certificate> {
  const keys = await newKeyPair();
  return X509CertificateGenerator.createSelfSigned({
    name: 'CN=Other Root CA',
    keys,
    notBefore: new Date('2026-01-01T00:00:00Z'),
    notAfter: new Date('2046-01-01T00:00:00Z'),
    extensions: [caExtension()],
  });
}

Deno.test('a JWS signed by the fixture chain verifies against its own trusted root', async () => {
  const chain = await buildChain();
  const result = await verifyPremiumJws(await signJws(chain, defaultPayload()), config(chain.root.toString('pem')));
  assert.equal(result.ok, true);
  if (result.ok) {
    assert.equal(result.payload.originalTransactionId, '200000000000001');
    assert.equal(result.payload.bundleId, BUNDLE);
    assert.equal(result.payload.productId, PRODUCT);
  }
});

Deno.test('a tampered payload fails the signature check', async () => {
  const chain = await buildChain();
  const result = await verifyPremiumJws(await signJws(chain, defaultPayload(), { tamper: true }), config(chain.root.toString('pem')));
  assert.equal(result.ok, false);
  assert.ok(!result.ok && result.reason === 'bad_signature', `reason was ${!result.ok ? result.reason : 'ok'}`);
});

Deno.test('a JWS signed by a foreign root is refused', async () => {
  const chain = await buildChain();
  const otherRoot = await buildOtherRoot();
  const result = await verifyPremiumJws(await signJws(chain, defaultPayload()), config(otherRoot.toString('pem')));
  assert.equal(result.ok, false);
  assert.ok(!result.ok && result.reason === 'unknown_root', `reason was ${!result.ok ? result.reason : 'ok'}`);
});

Deno.test('production config refuses a chain that does not reach the Apple Root CA - G3', async () => {
  const chain = await buildChain();
  const result = await verifyPremiumJws(await signJws(chain, defaultPayload()), productionConfig());
  assert.equal(result.ok, false);
  assert.ok(!result.ok && result.reason === 'unknown_root', `reason was ${!result.ok ? result.reason : 'ok'}`);
});

Deno.test('a wrong bundleId is refused', async () => {
  const chain = await buildChain();
  const payload = { ...defaultPayload(), bundleId: 'com.acrstudio.other' };
  const result = await verifyPremiumJws(await signJws(chain, payload), config(chain.root.toString('pem')));
  assert.equal(result.ok, false);
  assert.ok(!result.ok && result.reason === 'wrong_bundle');
});

Deno.test('a wrong productId is refused', async () => {
  const chain = await buildChain();
  const payload = { ...defaultPayload(), productId: 'com.acrstudio.drivy.premium.yearly' };
  const result = await verifyPremiumJws(await signJws(chain, payload), config(chain.root.toString('pem')));
  assert.equal(result.ok, false);
  assert.ok(!result.ok && result.reason === 'wrong_product');
});

Deno.test('an expired transaction is refused', async () => {
  const chain = await buildChain();
  const payload = { ...defaultPayload(), expiresDate: NOW.getTime() - 1000 };
  const result = await verifyPremiumJws(await signJws(chain, payload), config(chain.root.toString('pem')));
  assert.equal(result.ok, false);
  assert.ok(!result.ok && result.reason === 'expired');
});

Deno.test('a revoked transaction is refused', async () => {
  const chain = await buildChain();
  const payload = { ...defaultPayload(), revocationDate: NOW.getTime() - 1000 };
  const result = await verifyPremiumJws(await signJws(chain, payload), config(chain.root.toString('pem')));
  assert.equal(result.ok, false);
  assert.ok(!result.ok && result.reason === 'revoked');
});

Deno.test('malformed input is refused without throwing', async () => {
  const chain = await buildChain();
  for (const jws of ['', 'not-a-jws', 'a.b', 'a.b.c.d', `${base64UrlEncode('{"alg":"ES256"}')}.x.y`]) {
    const result = await verifyPremiumJws(jws, config(chain.root.toString('pem')));
    assert.equal(result.ok, false, jws);
  }
});

Deno.test('a non-ES256 header is refused', async () => {
  const chain = await buildChain();
  const result = await verifyPremiumJws(
    await signJws(chain, defaultPayload(), { headerOverrides: { alg: 'RS256' } }),
    config(chain.root.toString('pem')),
  );
  assert.equal(result.ok, false);
  assert.ok(!result.ok && result.reason === 'unsupported_algorithm');
});

Deno.test('the embedded Apple Root CA - G3 PEM parses as a CA certificate', () => {
  const appleRoot = new X509Certificate(APPLE_ROOT_CA_G3_PEM);
  assert.equal(appleRoot.subject, 'CN=Apple Root CA - G3, OU=Apple Certification Authority, O=Apple Inc., C=US');
  const raw = new Uint8Array(appleRoot.rawData);
  // SHA-256 fingerprint of the DER, verified out of band against openssl:
  // 63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179
  assert.equal(raw.length, 583);
});

async function sha256Hex(bytes: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new Uint8Array(bytes));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('').toUpperCase();
}

Deno.test('the embedded Apple Root CA - G3 PEM matches the published SHA-256 fingerprint', async () => {
  const appleRoot = new X509Certificate(APPLE_ROOT_CA_G3_PEM);
  const fingerprint = await sha256Hex(appleRoot.rawData);
  assert.equal(fingerprint, '63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179');
});
