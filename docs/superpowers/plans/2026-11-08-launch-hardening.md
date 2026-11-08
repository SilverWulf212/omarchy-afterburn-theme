# Launch Hardening Implementation Plan

> For agentic workers: use Superpowers subagent workflows for focused fixes and independent review. Tasks use checkboxes to track progress.

**Goal:** Fix reproducible launch defects and align the launch site with verified behavior.

**Architecture:** Retain Bash configuration and CLI with per-resource ownership records and explicit mode reconciliation. Keep the static website design, correcting claims and simulator semantics.

**Tech Stack:** Bash, Python unittest, static HTML/JavaScript, Playwright-core.

**Spec:** ../specs/2026-11-08-launch-hardening-design.md

## Global Constraints

- No installation into the user's real HOME; all executable regressions use temporary HOME and restricted PATH.
- Preserve preexisting resources and user-modified replacements; failed undo must be retryable.
- No new runtime dependencies; leave installed edition.conf choices intact.
- Do not claim VM/browser/deployment success without execution evidence.

## Review Focus

- Existing files when optional install is skipped or blocked.
- Lock clones with upstream ancestry but no Afterburn ownership.
- Failed cleanup and subsequent retry.
- Quiet/saver overlap and policy changes without physical power events.
- USB power, offline launch-page behavior and honest simulation labels.

### Task 1: Installation ownership and retryable cleanup

Files: extras/install.sh, extras/uninstall.sh, extras/lock/lock-embers.sh; tests/test_install_ownership.py.
- [x] Reproduce skipped-install deletion, existing-lock adoption, and failed-remove retry with isolated behavior tests; observe failures.
- [x] Record ownership for created resources, skip collisions, preserve modified replacements, keep unresolved cleanup state and return failure.
- [x] Verify new tests and shell syntax. Independently review scope and safety.

### Task 2: Runtime mode reconciliation

Files: extras/bin/afterburn, extras/bin/afterburn-watch, extras/afterburn-theme.sh if needed; tests/test_runtime_modes.py.
- [x] Test quiet/saver overlap, FULLSCREEN_QUIET disable, forced/auto LAPTOP_MODE transitions, stale saved state and USB external power; observe failures.
- [x] Restore saved effect before applying subtle; reconcile policy with persisted state and bounded polling.
- [x] Verify transitions and shell syntax. Independently review behavior.

### Task 3: Launch website and portable checks

Files: /home/silverwulf/afterburn-site/public/index.html, README.md; tools smoke scripts and docs in the theme repository.
- [x] Correct mismatched prompt sequencing, dependency/runtime network statements and claims about previews. Retain accurate current-main defaults and current Cyber effect (PR is pending, so do not imply merged behavior).
- [x] Provide native VM smoke and browser smoke with explicit prerequisites, artifacts, failures and cleanup. No fabricated VM evidence.
- [x] Run available syntax/static/asset and regression checks, attempt authorized deployment only through reachable access, preserve rollback.

### Task 4: Verification and handoff

- [x] Run committed regression suite plus external baseline harness; report all failures by name and cause.
- [x] Review combined changes, fix actionable regressions, record exact remaining environment blockers.
- [x] Update Outline project hub and local memory with changes, file paths and undo.

## Execution outcome

Implementation and independent review are complete. Both sites have static validation and recommendations demo logic QA; the shipped isolated suite passes 38 tests. The compatibility harness was migrated only in scratch for explicit ownership fixtures and intended preservation expectations; its full run passes 524 checks including six real offscreen QML styles.

Required external execution remains pending: provisioning an Omarchy VM on Betawulf, native guest integration, real Playwright/browser/visual checks, Goldwulf publication and served-response verification. Session restrictions block SSH sockets, browser startup and loopback binding; browser file previews are also denied. No checkbox above represents these unrun actions as successful.
