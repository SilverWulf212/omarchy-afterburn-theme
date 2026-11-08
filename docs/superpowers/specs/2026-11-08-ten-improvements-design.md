# Ten approved improvements

User approved implementation of all ten recommendations and requested maximum subagent use and final QA/polish. This extends the existing verified launch branches; do not rewrite the previous commits or main.

## Accepted scope

1. Commit repeatable CI and candidate-linked release evidence/checklists. Native/visual checks must remain explicitly pending until actually executed.
2. Serialize mutating CLI/hook state transitions with a shared lock and atomic file writes; avoid deadlocks in nested calls.
3. Surface actual application failures and status diagnostics (watcher health, last error, weather freshness). Do not mistake saved intent for successful application.
4. Rediscover compositor socket and resynchronize fullscreen on reconnect, avoiding another graphical session.
5. Parse user config as validated data through shared helpers for CLI/watcher/hook, preserving defaults, precedence, quotes/comments, last-line behavior and legacy migration semantics.
6. Provide persistent native `MOTION=on|off` (default on) across rotation, cursor effects, fail flashes and lock particles. Add visible web motion control that respects preference changes. Preserve the user's independent settings when motion resumes.
7. Suspend site frame/timer work when hidden or outside the viewport; cap canvas device pixel ratio. No unmeasured energy/performance claims.
8. Produce deterministic smaller base/edition/live-media release artifacts and verified selective installation. Retain existing clone/install path; never rewrite Git history or overwrite user modifications.
9. Self-host needed scripts and fonts with pinned versions and included licenses; remove external page runtime requests. Use available local/vendor sources or authorized connected fetches; no silent font substitution without documentation.
10. Generate site edition metadata from canonical theme sources with an executable drift check, eliminating manually maintained palettes/defaults. Keep editorial prose editable.

## Integration contracts

- Runtime agent owns extras/bin/afterburn, afterburn-watch, afterburn-theme.sh, afterburn-theme-set-hook, afterburn-fail.bash, lock runtime files and tests/test_runtime*.py plus runtime-specific helper files.
- Site agent owns afterburn-site/public/index.html, public/assets/, tools/test-site*.cjs (or .mjs) and site-specific tests. Coordinate generated metadata loading with tooling agent; do not edit its generated file manually.
- Release/tooling agent owns theme tools release/metadata scripts, tests/test_release*.py, tests/test_metadata*.py, .github/, and generated website public/edition-data.js. Generated file must expose `window.AFTERBURN_EDITIONS` with existing `ED` shape fields (name, tag, pers, s, rust, brown, sel, glow, rot, hue, optional on), plus `cursor`, `dim`, `emberStyle`, provenance. Source hue is presentation transform calculated against base or existing intentional per-edition mapping; no wallpaper regeneration required.
- Shared native setting is `MOTION=on|off`, default on. Existing NO_MOTION shell environment remains supported.
- Release scripts must reject archive traversal/symlinks and wrong checksums, use versioned relative pack names, and preserve existing user content. New scripts may use Python3 (already required by smoke/development); no new desktop daemon/service.

## Constraints and release gates

Use temporary HOME/restricted PATH for executable tests. Never install into the real desktop. The session still blocks SSH to Betawulf with EPERM (retested) and browser/localhost; do not bypass. Provisioning Betawulf and publication Goldwulf are authorized but cannot be reported complete without actual evidence. Preserve rollback and independent final review. Update main README, site copy, recommendations status, docs and both draft PRs after integration. Do not merge main or claim a VM pass.
