# Launch hardening

User requested review, brainstorming, bugfixes, optimization, subagents, genuine VM/Playwright smoke, and correction/republication of the Goldwulf website. They authorized autonomous execution and provisioning a disposable VM on Betawulf (Kubuntu).

## Approach

Use focused launch hardening: preserve the six editions and website design; fix demonstrated ownership and mode-transition defects, add portable regressions and smoke tooling, then publish truthful claims. A broad runtime rewrite or redesign adds launch risk without evidence of benefit and is deferred. This is the coordinator's choice under the user's instruction to do whatever is needed.

## Requirements

- Uninstall must preserve files and lock clones it did not create, preserve changed replacements, and retain failed-undo state for retry.
- Fullscreen and battery modes must compose; leaving fullscreen on battery restores the effect in subtle mode. Forced and automatic laptop policies must reconcile actual state, including USB charging.
- Keep configuration precedence and existing installed editions' user edits. No new runtime dependencies.
- Put regression tests in the repository using temporary HOME and a restricted executable PATH. Never run an installer against the real desktop.
- Website copy and simulator describe actual behavior, distinguish installation network access from optional runtime weather access, label the browser simulation's limits, and show no invented test badges.
- VM and browser tests must execute before being described as passed. Betawulf provisioning and Goldwulf publication are authorized, but environment network restrictions remain blockers.
- Preserve deployment rollback and do not alter unrelated guests, services or host configuration.

## Evidence and limitations

Baseline external harness: 518 passes and 6 QML execution failures caused by GTK display initialization in this environment. SSH to 192.168.100.15 fails before authentication with socket EPERM; DNS is unavailable. Chromium and localhost bind also fail with EPERM. No genuine VM or browser smoke has run yet.
