# Sentry monitoring — Drivy iOS

Crash and error monitoring from day one with Sentry (org `acr-studio`).
Branch `feat/sentry-monitoring`; delivery: single PR; test runner: XCTest on GitHub Actions macOS (no local Mac).

## Specs

- **S1** User (verbatim): «integra sentry vamos a dejarlo bien monitorizado ya desde el principio».
  Sentry org slug `acr-studio`, onboarding run code `ca95b56bcc` (from the user's Sentry onboarding screen).
- **S2** Sentry project for the iOS app exists in org `acr-studio` (slug `drivy`, platform `apple-ios`) and its public DSN is committed in `DrivyConfig` (a DSN is public by design, like the Supabase publishable key).
- **S3** The app starts the Sentry SDK (sentry-cocoa via SPM) at launch: crashes, app hangs, errors and session health are reported. No PII: `sendDefaultPii = false`, no screenshots or view hierarchy (the app handles location data). The SDK does not start under unit tests.
- **S4** Handled auth failures (Apple sign-in, sign-out) are captured to Sentry with the real error, except user cancellation. The signed-in Supabase user ID (ID only, no email) is set as the Sentry user and cleared on sign-out.
- **S5** Release builds upload dSYMs to Sentry from the signed CI job so crashes are symbolicated. Without a `SENTRY_AUTH_TOKEN` secret the step warns and skips; it never fails the build.
- **S6** Verification: CI test job green on the branch; the DSN accepts a test event (Sentry onboarding run shows an error received).

## Tasks

- [x] **T1** S2-S5 — create Sentry project + integrate SDK, auth capture, CI dSYM upload. Route: delegated (Pi `deepseek-v4-flash`; user rule: orchestrator delegates to Pi). Commit: 7f51bee (orchestrator diff review OK; no local compiler, CI is first build).
- [x] **T2** S6 — independent verification (Risk item 5: new dependency + CI). Route: delegated (Pi). Evidence: CI run 40561679036 (310 tests, 0 failures); test event HTTP 200 → issue DRIVY-1; onboarding run steps completed. Verdict S2-S6 PASS, no blockers.

## Log

- **L1** 2026-10-27 User: «funciona, aparentemente perfecto, [Image #1] integra sentry vamos a dejarlo bien monitorizado ya desde el principio». Image: Sentry "Create a Project" page, org slug `acr-studio`, run code `ca95b56bcc`, recommends `npx @sentry/agent-plugin install acr-studio#ca95b56bcc`.
- **L2** Decision: skip the agent plugin (it installs a Claude Code plugin that needs a restart); Pi already has the Sentry MCP connected (`mcp.sentry.dev`, OAuth) and creates the project directly.
- **L3** T1 done by Pi `sentry-dev`: Sentry project `drivy` (id 4512329624125520, region de.sentry.io) created via MCP; onboarding run ca95b56bcc updated (create_project, connect_mcp done; instrument_app active). Commit 7f51bee: S2-S5. PR template gains the `SENTRY_AUTH_TOKEN` note.
- **L4** T2 verified by Pi `sentry-qa`: S2-S6 PASS, no blockers. Advisories: dSYM step only statically verified (signed job is main-only, first proof on the first main run with SENTRY_AUTH_TOKEN); tracesSampleRate 0.2 enables performance tracing (orchestrator choice, not in S3); `--include-sources` uploads sources to Sentry; platform `apple-ios` not readable via MCP.
