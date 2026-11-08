# Launch verification

These tools generate evidence for a specific candidate. They do not provision a VM,
install browser dependencies, deploy the website, or imply a pass merely because a
guest boots. Keep the output directories with the candidate commit/diff and the VM
snapshot identity. A nonzero exit is a failed or blocked run, never partial success.

## Current execution limits

The launch-review environment has no accessible `/dev/kvm`, QEMU installation or
cached guest disk. SSH and loopback listening fail with socket `EPERM`. Existing
`playwright-core` and `/usr/bin/chromium` were located, but Chromium exits with
`SIGTRAP` at Crashpad's `setsockopt: Operation not permitted` before opening a page.
Neither native Omarchy VM smoke nor browser assertions have passed here. The shipped
isolated regression suite passes 38 tests. The migrated local compatibility harness
passes 524 checks, including real offscreen execution of all six QML styles with
`QT_QPA_PLATFORMTHEME=` and display variables cleared. Those checks do not establish
native desktop integration; smoke-tool syntax checks establish only parseability.

## Prepare a disposable Omarchy guest on Betawulf

Use Betawulf's local desktop or an authorized connection from an unrestricted
environment. Do not redirect this work to another server. Betawulf is Kubuntu;
the following is standard KVM/virt-manager guidance, **not a tested image builder
or validated Omarchy bootstrap recipe**.

1. Check virtualization availability with `test -e /dev/kvm` and `virt-host-validate`.
   Inspect existing libvirt configuration before changing it. If needed, install
   Kubuntu's `qemu-kvm`, `libvirt-daemon-system` and `virt-manager` packages using
   `sudo apt install`; resolve the host's normal libvirt access requirements.
2. Obtain the current official Omarchy installation media following Omarchy's own
   installation instructions and verify its published checksum. Create a new guest
   in virt-manager with a clearly disposable name, NAT networking, a fresh virtual
   disk, and RAM/CPU limits that leave comfortable host headroom. Do not attach host
   home directories, existing disks, password stores or USB devices.
3. Install Omarchy and log into its graphical session as a dedicated guest user.
   Confirm its Hyprland version supports the candidate's Lua configuration. Install
   the normal documented theme prerequisites, including Ghostty, the pinned
   cursor-fx version documented in README, jq, Python 3, and optionally grim for
   screenshots. Native smoke requires these already available; it deliberately
   does not bootstrap cursor-fx or exercise privileged boot-splash installation.
4. Take a clean guest snapshot before copying the candidate. Transfer the exact
   working tree (including hidden `.editions/`, excluding `.git` and private files)
   into a guest directory such as `~/candidate`. Record its source commit and any
   uncommitted patch separately. Copy that tree to the **fresh** installed base
   directory `~/.config/omarchy/themes/afterburn`. Do not install from the public
   GitHub URL when validating unpublished changes.
5. Inside the guest only, create the safety marker:

   ```sh
   sudo touch /etc/afterburn-disposable-vm
   ```

   The marker plus command-line confirmation and VM detection prevent accidental
   desktop execution. They are an explicit operator safeguard, not a security
   boundary. Never create this marker on the live laptop or Betawulf host.

6. From a terminal in the guest's actual Hyprland session, run:

   ```sh
   bash ~/candidate/tools/smoke-vm.sh \
     --confirm-disposable-guest --candidate ~/candidate \
     --away-theme EXISTING_NON_AFTERBURN_THEME \
     --artifacts ~/afterburn-evidence/native
   ```

The candidate manifest compares installed runtime code and theme assets with the
provided tree before mutation. The script runs extras installation with `--yes`
and closed stdin (boot/login remains skipped), switches six editions, requires no
Hyprland configuration errors, compares increasing live heat shadow ranges, checks
overlapping quiet/saver cursor and shadow behavior, checks restoration on an away
theme, then uninstalls/reinstalls the same extras. It stops the watcher during CLI
checks to prevent asynchronous fullscreen/time/power events changing expectations.
That means automatic watcher power/fullscreen event delivery is **not** established
by this smoke. Generated credentials, PAM, suspend, boot screens and physical GPU
or battery behavior remain outside its coverage.

Output: `run.log`, `exit-status.txt`, candidate SHA-256 manifest, live compositor
responses, status records and optional screenshots. Screenshots need human visual
inspection. On failure inspect the log; do not repeatedly run a partly completed
mutation sequence and call a later pass clean. Export evidence, revert the snapshot,
and retry. Snapshot reversion undoes installer changes, links, services and optional
lock clone together; delete the disposable guest when review is complete. The
script intentionally leaves the final guest in the reinstalled state with the
watcher stopped, so it does not claim to restore an arbitrary prior desktop.

## Run real browser smoke inside the guest

Use an already installed `playwright-core` and Chromium. No npm install occurs in
the runner. `PW_MODULE_PATH` accepts an absolute CommonJS module directory or entry
file; omit it if normal Node resolution finds `playwright-core`. `CHROMIUM_PATH`
selects an existing browser; omit it only if Playwright already has its browser.

```sh
PW_MODULE_PATH=/path/to/node_modules/playwright-core \
CHROMIUM_PATH=/usr/bin/chromium \
node ~/candidate/tools/smoke-site.mjs \
  https://afterburn.silverwulf.org/ ~/afterburn-evidence/browser
```

For an unpublished website candidate, copy the website's `public/` tree into the
guest, serve it with an available local server bound to guest loopback, and pass
that URL. For example, in a separate guest terminal:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory ~/site-candidate/public
```

Then use `http://127.0.0.1:8765/` as the browser target. This server command has not
been demonstrated in the restricted launch-review environment. HTTPS or guest
loopback is needed for Chromium's clipboard APIs. Keep the Chromium sandbox on;
`PW_NO_SANDBOX=1` exists for explicitly sandboxed disposable environments whose
browser sandbox cannot initialize, not as a workaround for blocked host sockets.

The browser script checks six distinct palettes and edition hashes across reload,
wallpaper controls/keyboard, terminal commands, real clipboard writes, simulated
installer abort/completion/undo guidance, a loaded video preview, mobile layout,
reduced motion, JavaScript errors and requested same-origin asset failures. It
writes `result.json`, `desktop.png` and `mobile-reduced-motion.png`. External CDN
request failures are reported separately, so a font CDN outage is distinguishable
from a missing site-owned asset. Unrequested assets, every video codec and visual
correctness of screenshots are not exhaustively verified. A launch failure writes
a failed result and returns nonzero; it cannot yield passed browser checks.

Playwright operates the browser DOM. Native Omarchy is not a DOM; using noVNC would
require a separately installed VNC/WebSocket bridge and canvas/pixel assertions.
These tools instead pair guest-native checks with Playwright running in the same
guest. No noVNC infrastructure or unverified provisioning automation is required.

## Local static checks

```sh
bash -n tools/smoke-vm.sh
node --check tools/smoke-site.mjs
bash tools/smoke-vm.sh --help
```

These are prerequisite/tooling checks only. Publish genuine VM/browser outcomes
only after reviewing `exit-status.txt`, `result.json`, logs and screenshots from
the actual candidate run.
