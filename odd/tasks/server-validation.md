# Server-side validation — bugs B1 and B2

The server stops trusting client-written XP inputs it can check (B2) and enforces the free 1-league cap against a server-verified premium entitlement (B1).
Branch `fix/server-validation`; delivery: `single-pr`, one commit per task; test runners: `cd supabase/tests && npm test` (PGlite, local), `deno test` (Edge Function, local), XCTest on GitHub Actions (Swift).

## Specs

- **S1** User (verbatim): «prepara la propuesta de B1 y B2 y lanzala».
- **S2** B2 as verified (`bugs-verified.md`): XP inputs are client-written; `habit_levels` has no time window and pays 50 XP per row; `drives` accepts any `started_at`, score, distance, and the owner `FOR ALL` policy lets a client **update** a drive after uploading it; `daily_scores` (streak) is client-written.
- **S3** B2 fix, migration `supabase/migrations/20261028190000_server_validation.sql` (new file; existing migrations untouched):
  1. `drives`: replace the owner `FOR ALL` policy with select / insert / delete owner policies — **no update** (the app only inserts; it upserts with `ignoreDuplicates`, which never updates). Insert-time trigger rejects: `started_at > now() + 5 min`; `started_at < now() - 30 days` (the app retries failed uploads days later, D4); `duration_s` differing from `ended_at - started_at` by more than 120 s; `duration_s > 86400`; average speed `distance_km / hours > 250`; more than 50 drives per user per Madrid day. Existing rows are not revalidated.
  2. `daily_scores`: a `before insert or update` trigger recomputes `score`, `distance_km`, `drives_count` for `(user_id, day)` from that user's `drives` of that Madrid day (distance-weighted average, same rule as `SupabaseDriveRepository`), ignoring the client values. Old app builds keep working unchanged.
  3. `habit_levels`: insert trigger requires `completed_at` within `[now() - 30 days, now() + 5 min]`; level L>1 requires level L-1 of the same unit; a unit other than the first requires level 3 of the previous unit; and the user's qualifying drives (`distance_km >= 2` and the unit predicate of `HabitUnit.isQualified`) started between the unit's opening (previous unit's level-3 `completed_at`, epoch for the first unit) and `completed_at` must be at least `[3, 7, 15][L-1]`. Predicates and thresholds are ported **exactly** from `HabitPathEngine.swift` / `HabitUnit.swift`, each with a file:line comment.
  4. `quest_completions`: insert trigger checks drive quests against that user's drives of that Madrid day with the exact predicates of `QuestCatalog.swift` (2 km floor, score thresholds, no events of the named kind, connected mode); the lesson quest requires that day's `lesson_completions` row. Ported exactly, with file:line comments.
  5. Every rejection raises a stable error code (`P0001` with message `drive_implausible`, `daily_drive_limit`, `habit_level_unearned`, `quest_unearned`).
  - **Known limit (documented, not fixed)**: the drive `score` is computed on the phone from sensor data that never leaves it (privacy, S10 of the MVP); the server bounds it (0–100, plausibility, 3 scored drives/day in `xp_ledger`) but cannot recompute it.
- **S4** B1 as verified: `create_league` and `join_league_by_code` have no plan or per-user count check; the server has no plan information.
- **S5** B1 fix:
  1. Migration `supabase/migrations/20261028190100_premium_entitlements.sql`: table `premium_entitlements(user_id uuid pk → profiles, original_transaction_id text unique, product_id text, expires_at timestamptz, revoked_at timestamptz, environment text, updated_at timestamptz)`; RLS select own; **no client insert/update/delete** (only `service_role`). Function `has_active_premium(uid)` = row with `revoked_at is null and expires_at > now()`. `create_league` and `join_league_by_code` raise `P0001 league_limit` when the caller is already in ≥ 1 league (as owner or member) and has no active premium. Existing memberships are never removed.
  2. Edge Function `supabase/functions/verify-premium/` (Deno): `POST` with the user's JWT and body `{ "jws": "<Transaction.jwsRepresentation>" }`. Verifies the JWS offline: `x5c` chain up to the embedded **Apple Root CA – G3** certificate, ES256 signature, `bundleId == "com.acrstudio.drivy"`, `productId == "com.acrstudio.drivy.premium.monthly"`, `expiresDate` in the future, no `revocationDate`. Upserts `premium_entitlements` for the JWT user with the service role. An `originalTransactionId` already linked to **another** user → `409 transaction_linked`. Responses: `200 {active, expires_at}`, `400 invalid_jws`, `401` without a valid user JWT, `409`. Verification logic in a pure module with `deno test` tests (valid chain fixture, wrong root, wrong bundle, expired, revoked, tampered payload).
  3. App: the StoreKit provider exposes the verified current entitlement's `jwsRepresentation`; a `PremiumSync` posts it to `verify-premium` at launch and on every `Transaction.updates` (best effort, never blocks the UI). League RPC error `league_limit` maps to the existing paywall/limit copy of `LeagueLimitGate` (no new copy).
- **S6** Invariants: no change to XP amounts, caps, streak rules or user-facing copy; existing 43 SQL tests and all XCTests stay green; each rule above gets a SQL/Deno/XCTest test that fails before the change; migrations are new files only; nothing is applied to the production Supabase project or deployed until the user says yes (L3).

## Tasks

- **T1** (S2, S3, S6) — `server_validation` migration + `supabase/tests/validation.test.mjs`. Risk: items 1, 2 (RLS, triggers on user data). Route: delegated writer `sv-b2` (Pi `nan/glm5.3-flash`), parallel. Status: pending.
- **T2** (S4, S5.1, S5.2, S6) — `premium_entitlements` migration + `supabase/tests/entitlements.test.mjs` + Edge Function with Deno tests. Risk: items 2, 3. Route: delegated writer `sv-b1` (Pi `nan/glm5.3-flash`), parallel. Status: pending.
- **T3** (S5.3, S6) — Swift `PremiumSync` + JWS exposure + `league_limit` mapping + XCTests. Risk: item 3. Route: delegated writer `sv-app` (Pi `nan/glm5.3-flash`), parallel (contract fixed in S5). Status: pending.
- **T4** (S1–S6) — Independent QA (Pi `nan/deepseek-v4-flash`) + CI + user consent → apply both migrations and deploy `verify-premium` through the Supabase MCP → merge + TestFlight. Status: pending.

## Log

- **L1** 2026-10-28 User: «prepara la propuesta de B1 y B2 y lanzala».
- **L2** Map (Pi explorer, `map-b12.md`): XP = `xp_ledger` (drives ≥90→20 / ≥75→10, ≥2 km, best 3/day; lesson 10; quests 15 best 3/day; habit level 50); 43 PGlite SQL tests pass; no Edge Functions yet; premium is a monthly auto-renewable subscription verified only on device.
- **L3** Assumptions (defaults chosen by the parent, change on request): 30-day late-upload window, 50 drives/day, 250 km/h, 120 s duration tolerance; one subscription links to one account. Production apply/deploy waits for an explicit yes.
- **L4** Model rule from the user: only NaN-provider models; no agent may launch subagents.
