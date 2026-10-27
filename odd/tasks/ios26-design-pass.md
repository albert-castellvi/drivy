# iOS design pass — apply SwiftUI skills to Drivy UI

Apply `swiftui-expert-skill` (AvdLee @204dba7) and `swiftui-liquid-glass` (FloWritesCode @3a6c74b) to the existing UI.
Branch `feat/ios26-design-pass`; delivery: single PR (chain if > ~400 lines); test runner: XCTest on GitHub Actions macOS (no local Mac).

## Specs

- **S1** User (verbatim): «perfecto, pues aplica los skills al diseño actual».
- **S2** Constraints: deployment target iOS 17.0 (`project.yml:13`). CI moves both jobs (test + signed release) to the stable `runs-on: macos-26` image with its default Xcode 26.6 (user decision L4); iOS 26 APIs (Liquid Glass) sit behind `if #available(iOS 26, *)` with the current look as fallback. iOS 27-only APIs are out of scope (no Xcode 27 on stable images).
- **S3** No behavior changes: same screens, flows, copy and data. Existing tests stay green; new tests only where a change has testable logic.

## Tasks

- [x] **T1** S1-S3 — audit every view against both skills; produce a findings list and a change plan split into units with disjoint files. Route: delegated read-only (Pi `glm5.3-flash`: judgment; `glm5.3` returns 401 for this API key). Evidence: audit report F1-F7 (scratchpad report-audit.md), plan U1-U4.
- [x] **T2** S2 — U4: both CI jobs to `macos-26` + Xcode 26.6, drop `DEVELOPER_DIR` pin, simulator name valid on iOS 26 runtimes. Risk item 5 (CI). Route: delegated (Pi deepseek, one writer for T2-T5, one commit per task). Commit: 6c2e844
- [x] **T3** S1,S3 — U1/F1: stable `HistoryRow.id`, `ForEach(rows)` in HistoryView + id test. Commit: 1d6e0b5
- [x] **T4** S1,S3 — U2/F3-F5: `@ScaledMetric` fonts, VoiceOver hidden/combined elements, 44 pt Histórico link (TodayView, SignInView). Commit: cdefffd
- [x] **T5** S1-S3 — U3/F2,F6,F7: `safeAreaBar` in paywall, glass button helper on fixed chrome only (PaywallView bottom bar, ShareCardSheet; L6), `Tab` API in MainTabView; all iOS 26 code behind `#available` with today's look as fallback. Commit: aac4e85 + fix c520cf1 (see L6)
- [x] **T6** S1-S3 — verification: CI green on the PR (independent Pi verifier, item 5). Evidence: run 40581187787 on macos-26-arm64, Xcode 26.6, iPhone 17 found, 312 tests 0 failures; T2-T5 and S1-S3 PASS, no blockers. Release job macos-26 change static-only (main-only job).

## Log

- **L1** 2026-10-27 User: «perfecto, pues aplica los skills al diseño actual».
- **L2** Assumption: keep deployment target 17.0 (raising it drops users; product decision not asked). Liquid Glass gated by availability.
- **L3** User: «el ci de github no tiene la version actual de xcode?». Verified (actions/runner-images, 2026-10-27): S2 assumption "no Xcode 27 in CI" was wrong. `runs-on: xcode-27` (preview image, macOS 27 base, issue #14404) has Xcode 27; `macos-26` defaults to Xcode 26.6; `macos-15` (current CI) defaults to 16.4 and has up to 26.3. Our release job pins the oldest one, Xcode_26.0.
- **L4** User (verbatim): «nono dejamos estable». Decision: both CI jobs on `macos-26` + Xcode 26.6; no `xcode-27` preview image.
- **L5** Audit (glm5.3-flash): F1-F7 accepted. F6 widened by orchestrator from paywall-only to every primary/secondary button via the shared helper (consistent look). Out of scope: DriveDetailView Map inside ScrollView (needs hands-on testing).
- **L6** Orchestrator review of T5: the L5 widening broke swiftui-liquid-glass rule 7 (no glass inside ScrollView/List). Reverted the Hoy and Histórico call sites to `.borderedProminent`/`.bordered`; glass stays on fixed chrome only (paywall bottom bar, share sheet); unused `glassOrBordered` removed. project.yml comment updated to macos-26.
- **L7** T6 advisories: pre-iOS-26 fallback branches are compile-only in CI (manual check on an older simulator/device before release); destination could pin `OS=latest`; `.glassProminent` uses the default accent tint.
