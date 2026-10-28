# verify-premium

Edge Function for the free one-league cap (odd/tasks/server-validation.md S5.2).
The app posts the StoreKit transaction's `jwsRepresentation` here; the function
verifies it offline against the embedded Apple Root CA - G3 and upserts the
caller's row in `premium_entitlements`, which `has_active_premium()` and the
league RPCs read.

## Contract

- `POST` with `Authorization: Bearer <user JWT>` and body `{ "jws": "<Transaction.jwsRepresentation>" }`.
- Verified offline: `x5c` chain to Apple Root CA - G3, ES256 signature,
  `bundleId == "com.acrstudio.drivy"`,
  `productId == "com.acrstudio.drivy.premium.monthly"`, `expiresDate` in the
  future, no `revocationDate`.
- Responses: `200 {active, expires_at}`, `400 {error: "invalid_jws", reason}`,
  `401 {error: "unauthorized"}`, `409 {error: "transaction_linked"}`.

## Verification logic and tests

`verify.ts` is pure (no I/O, no clock); `verify_test.ts` builds its own
test root -> intermediate -> leaf ES256 chain and runs without network:

    deno test

## Environment

- `SUPABASE_URL` — project URL (injected automatically when deployed).
- `SUPABASE_SERVICE_ROLE_KEY` — service role secret (injected automatically
  when deployed). The function identifies the caller through
  `auth.getUser` on the bearer JWT and only then writes with the service role.

For local serving, put both in `supabase/functions/.env.local` and run:

    supabase functions serve verify-premium --env-file supabase/functions/.env.local

## Deploy (owner-run; nothing is deployed until the user says yes)

    supabase functions deploy verify-premium

No database migration is needed by the deploy itself; migration
`20261028190100_premium_entitlements.sql` must be applied first
(`supabase db push`), or the upsert will fail with a missing relation.
