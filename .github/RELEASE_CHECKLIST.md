Candidate evidence is scoped to a full commit SHA. A green isolated CI job is only one gate.
Copy this checklist into the release/PR evidence and attach the actual logs and screenshots.

- [ ] Theme candidate SHA: `<40-character remote commit>`; site candidate SHA: `<40-character remote commit>`.
- [ ] Link each candidate's successful Verify candidate workflow run and downloaded evidence artifact.
- [ ] Site `.github/theme-source-ref` pins the exact remote theme candidate SHA; source metadata drift check passes.
- [ ] Confirm `release.json` sourceCommit matches the candidate and sourceDirty is false; record archive SHA256SUMS.
- [ ] Build same source twice and compare archives; install base, base-live and one selected edition into disposable destinations.
- [ ] Actual native VM evidence: new install, existing install, user-modified preservation, rollback/uninstall; record OS/Omarchy/Hyprland versions.
- [ ] Actual native behavior evidence: fullscreen and reconnect resync, saved-vs-applied failure, motion off/on and independent settings restoration.
- [ ] Actual Chromium desktop/mobile evidence: edition selection, motion preference/override, hidden/offscreen resume, offline runtime resources, network/errors and screenshot review.
- [ ] Attach native/browser results to the exact candidates tested. Any code change requires relevant reruns.
- [ ] Publish approved candidates, then record production URL and actual production smoke results.

Until these execute, label native/browser/publication gates **pending** or **blocked**, with the observed access error. Never infer them from mocked tests or static checks.

Selective packs stage source files only. Install base first, then base-live and/or only the selected edition packs into the same source directory; edition files live under `.editions/<name>/` so the existing extras installer discovers them. Run that existing installer separately to activate/copy the staged files. An edition archive includes its own media; base-live adds only base videos. Existing clone/install commands remain valid. Do not describe this as a reduction to GitHub's source archive or clone size.

The trusted release.json records archive SHA256 hashes; each archive contains a per-file SHA256/mode manifest. Obtain the manifest from the trusted release channel: checksums detect damage/mismatch, not a malicious replacement of both manifest and archive. The staging tool rejects links, unsafe paths, wrong hashes and conflicting existing files, and permits identical reinstallations. It never overwrites changed files. Local concurrent writers are outside its transaction model; use a fresh staging directory, and delete that disposable directory to undo staging.

Clone-free bootstrap (run only after these files are published as release assets):

```bash
version=vX.Y.Z
release="https://github.com/SilverWulf212/omarchy-afterburn-theme/releases/download/$version"
mkdir -p "$HOME/Downloads/afterburn-$version"
cd "$HOME/Downloads/afterburn-$version"
for file in SHA256SUMS release.json afterburn-pack-tool.py "afterburn-$version-base.tar.gz" "afterburn-$version-edition-voltage.tar.gz"; do
  curl --fail --location --remote-name "$release/$file" || exit 1
done
sha256sum --check --ignore-missing SHA256SUMS || exit 1
# Fresh destination recommended; a conflicting existing file is preserved and fails.
destination="$HOME/.config/omarchy/themes/afterburn"
python3 afterburn-pack-tool.py install --manifest release.json --pack "afterburn-$version-base.tar.gz" --destination "$destination"
python3 afterburn-pack-tool.py install --manifest release.json --pack "afterburn-$version-edition-voltage.tar.gz" --destination "$destination"
# Optional: download/verify/install afterburn-$version-base-live.tar.gz the same way.
# Activation is separate; inspect and run the usual extras installer if wanted:
# bash "$destination/extras/install.sh"
# omarchy theme set afterburn
```

`afterburn-pack-tool.py` is emitted beside every build's archives and included in SHA256SUMS and release.json. The CI artifact includes the whole output folder, including this helper. Downloading only the helper, manifests, base and selected edition avoids a Git checkout; do not execute an unverified downloaded helper. SHA256SUMS and release.json themselves must come from the trusted release channel. The extra installer copies staged editions but does not install a base staged in an arbitrary directory: either stage into the intended fresh theme directory as above, or keep the temporary staging directory for review only.


Complete-bundle installation: ship `install-afterburn.sh`, `afterburn-pack-tool.py`,
`release.json`, `SHA256SUMS`, base, base-live and the five edition packs together.
Both executable helpers are recorded in the manifest/checksums. Extract the bundle
and run `bash install-afterburn.sh`; this verifies/stages supplied packs, then runs
the effects consent prompts. The older Python staging command remains available.
Test new interactive installs with cursor/glow Yes/Yes, Yes/No, No/Yes and No/No,
and verify TUI app IDs (`org.omarchy.btop`, `org.omarchy.terminal`, `TUI.float`).
Check each edition's immediate cursor effect, theme switching, basic effects with
the subtle pack declined, fresh-shell PATH, failed effect application, and retained
consent on reinstall. Native GPU/rendered behavior remains a separate release gate.
