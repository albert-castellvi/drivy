// verify-premium Edge Function (odd/tasks/server-validation.md S5.2)
// POST { "jws": "<Transaction.jwsRepresentation>" } with the user's JWT in the
// Authorization header. Verifies the App Store JWS offline (pure verify.ts),
// then upserts premium_entitlements for the JWT user with the service role.
// Responses: 200 {active, expires_at} | 400 invalid_jws | 401 no valid user JWT
// | 409 transaction_linked.
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by the platform in a
// deployed function; for `supabase functions serve` they come from .env.local.

import 'npm:reflect-metadata@0.2.2';
import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
import { productionConfig, verifyPremiumJws } from './verify.ts';

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return json({ error: 'method_not_allowed' }, 405);
  }

  // 401: only a valid user JWT opens this endpoint. The service role is used
  // afterwards for the upsert, never to identify the caller.
  const token = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!token) return json({ error: 'unauthorized' }, 401);

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    console.error('verify-premium: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not configured');
    return json({ error: 'server_misconfigured' }, 500);
  }
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData?.user) {
    return json({ error: 'unauthorized' }, 401);
  }
  const userId = userData.user.id;

  // 400: the JWS must be a string in the body; its verification is offline and
  // pure, so the same code path is unit-tested in verify_test.ts.
  let jws: unknown;
  try {
    jws = (await req.json())?.jws;
  } catch {
    return json({ error: 'invalid_jws', reason: 'malformed' }, 400);
  }
  if (typeof jws !== 'string' || jws.length === 0) {
    return json({ error: 'invalid_jws', reason: 'malformed' }, 400);
  }

  const result = await verifyPremiumJws(jws, productionConfig());
  if (!result.ok) {
    return json({ error: 'invalid_jws', reason: result.reason }, 400);
  }
  const payload = result.payload;
  // verifyPremiumJws already rejected payloads without these.
  const originalTransactionId = payload.originalTransactionId as string;
  const expiresAt = new Date(payload.expiresDate as number).toISOString();

  // 409: one original transaction belongs to one account. If another user
  // already holds it, refuse before touching the caller's row.
  const { data: linked, error: linkedError } = await admin
    .from('premium_entitlements')
    .select('user_id')
    .eq('original_transaction_id', originalTransactionId)
    .maybeSingle();
  if (linkedError) {
    console.error('verify-premium: link check failed', linkedError);
    return json({ error: 'internal_error' }, 500);
  }
  if (linked && linked.user_id !== userId) {
    return json({ error: 'transaction_linked' }, 409);
  }

  // Upsert keyed on the user: a renewal, a restore or a resubscription all
  // replace the user's single row; a unique-violation race on
  // original_transaction_id still answers 409.
  const { error: upsertError } = await admin.from('premium_entitlements').upsert(
    {
      user_id: userId,
      original_transaction_id: originalTransactionId,
      product_id: payload.productId,
      expires_at: expiresAt,
      revoked_at: null,
      environment: payload.environment ?? null,
    },
    { onConflict: 'user_id' },
  );
  if (upsertError) {
    if (upsertError.code === '23505') {
      return json({ error: 'transaction_linked' }, 409);
    }
    console.error('verify-premium: upsert failed', upsertError);
    return json({ error: 'internal_error' }, 500);
  }

  const active = (payload.expiresDate as number) > Date.now();
  return json({ active, expires_at: expiresAt }, 200);
});
