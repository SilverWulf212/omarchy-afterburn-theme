# Ten Improvements Implementation Plan

> For agentic workers: use the Superpowers subagent and independent-review workflows. Work is on the existing isolated feature branches, with disjoint file ownership.

**Goal:** Implement the ten approved reliability, performance and delivery recommendations.
**Architecture:** Shared validated runtime policy and serialized mutation; dependency-local static site with a visibility-aware motion lifecycle; reproducible release packs and generated edition metadata. Preserve existing install paths and user data.
**Tech Stack:** Bash, Python3 unittest, static HTML/CSS/JS, Node built-in tests, GitHub Actions.
**Spec:** ../specs/2026-11-08-ten-improvements-design.md

## Global Constraints

- No real-HOME installer execution or unverified VM/browser/deployment success.
- Preserve precedence, independent user choices, modified files and backwards-compatible clone installation.
- No destructive Git history changes or new desktop services.
- Generated metadata interface is window.AFTERBURN_EDITIONS; native motion setting is MOTION=on|off, default on.

## Review Focus

- Concurrent mutation, lock ownership, nested invocation and interrupted writers.
- Malformed or executable config content and correct defaults/semantic boundaries.
- Motion off/on restoration, all lock styles, preference changes and hidden callbacks.
- Archive traversal, symlinks, hashes, deterministic output and existing file collisions.
- Missing external network, missing generated metadata and candidate-to-evidence linkage.

### Task 1: Runtime reliability and native motion (recommendations 2–6)

Files: specified runtime-owned files in design; tests/test_runtime*.py.
- [x] Add and observe failing tests for serialization, nonexecuting/validated parser, actual command failures/status, socket reconnect, native motion/restoration.
- [x] Implement shared helpers and migrate consumers, preserving existing tests and defaults.
- [x] Verify runtime/ownership suites and shell syntax; document exact command/API changes for coordinator.

### Task 2: Website motion, inactive work and local dependencies (6, 7, 9)

Files: afterburn-site/public/index.html, public/assets/, site lifecycle tests.
- [x] Add executable lifecycle/policy tests; implement motion control and pause/resume with no duplicate loops/listeners, capped DPR and preference changes.
- [x] Vendor pinned script/font assets with licenses, remove external runtime resource URLs; preserve usable no-JS content.
- [x] Load generated edition-data.js through the tooling contract; add meaningful checks for initialization and lifecycle. Static/behavior QA; real browser remains required.

### Task 3: Release evidence, packs and metadata (1, 8, 10)

Files: release/metadata tools and tests, theme/site .github workflows, generated site edition-data.js.
- [x] Add red→green tests for deterministic packs, selective safe extraction, checksum/collision rejection and metadata drift.
- [x] Implement deterministic builder, verified selective pack workflow and source-backed metadata generation/check.
- [x] Add CI for shipped test commands, metadata/static checks and candidate-linked evidence/release checklist.

### Task 4: Integrate, QA, review and publish candidates

- [x] Resolve cross-agent interfaces; update README, verification docs and recommendations statuses truthfully.
- [x] Run full shipped suites, static/behavior checks and appropriate compatibility coverage.
- [x] Independent whole-change review and site QA; fix actionable findings, commit, update draft PRs.
- [x] Attempt authorized VM/deploy only through available access. If blocked, preserve explicit gates and evidence; update Outline/memory and final report.

## Integration and release status

Implemented all ten recommendations in the review candidates. Final local verification:79 shipped Python regressions;14 executable site behavior/hash checks; static assets/anchors/6scripts; metadata JS and generated documentation drift;12 real offscreen QML style/motion loads. Independent site/core review cleared actionable findings after regression fixes.

Live gates remain required and unrun: actual Omarchy VM installation and real browser/visual testing, GitHub Actions remote results, publishing release packs, and Goldwulf deployment/served-response verification. Betawulf SSH was retried and rejected by session socket EPERM. No completed implementation checkbox claims those external actions passed.
