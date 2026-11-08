#!/usr/bin/env bash
# Mutating integration smoke: only run inside a disposable, snapshotted Omarchy VM.
set -euo pipefail
usage() { echo 'Usage: smoke-vm.sh --confirm-disposable-guest --candidate DIR --away-theme NAME [--artifacts DIR]'; }
candidate= away= confirmed=false
artifacts="${TMPDIR:-/tmp}/afterburn-vm-smoke-$(date -u +%Y%m%dT%H%M%SZ)"
while (($#)); do
  case $1 in
    --confirm-disposable-guest) confirmed=true; shift ;;
    --candidate) candidate=${2:?}; shift 2 ;;
    --away-theme) away=${2:?}; shift 2 ;;
    --artifacts) artifacts=${2:?}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
$confirmed && [[ -n $candidate && -n $away ]] || { usage >&2; exit 2; }
[[ -f /etc/afterburn-disposable-vm ]] || { echo 'REFUSED: missing disposable-VM marker' >&2; exit 2; }
[[ $(systemd-detect-virt --vm 2>/dev/null) != none ]] && systemd-detect-virt --vm --quiet || {
  echo 'REFUSED: no VM detected (containers are not sufficient)' >&2; exit 2;
}
[[ $away != afterburn* && $away =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Choose an installed non-Afterburn away theme' >&2; exit 2; }
for cmd in omarchy hyprctl cursor-fx ghostty jq python3 systemctl sha256sum; do
  command -v "$cmd" >/dev/null || { echo "Missing prerequisite: $cmd" >&2; exit 2; }
done
[[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || { echo 'Run as the guest desktop user inside its Hyprland session' >&2; exit 2; }
[[ ${XDG_CONFIG_HOME:-$HOME/.config} == "$HOME/.config" && ${XDG_STATE_HOME:-$HOME/.local/state} == "$HOME/.local/state" ]] || {
  echo 'Use the guest standard XDG paths' >&2; exit 2;
}
installed=$HOME/.config/omarchy/themes/afterburn
state=$HOME/.local/state/afterburn
current=$HOME/.local/state/omarchy/current
[[ -d $HOME/.config/omarchy/themes/$away ]] || { echo 'Away theme is not installed' >&2; exit 2; }
candidate=$(realpath -- "$candidate")
mkdir -p -- "$artifacts"
artifacts=$(realpath -- "$artifacts")
exec > >(tee "$artifacts/run.log") 2>&1
trap 'rc=$?; printf "exit=%s\n" "$rc" > "$artifacts/exit-status.txt"; if ((rc)); then echo "FAILED: inspect $artifacts; revert the VM snapshot before retrying"; fi' EXIT
echo "Guest: $(hostname); candidate: $candidate; artifacts: $artifacts"
cat /etc/os-release > "$artifacts/guest-os-release.txt"
hyprctl version > "$artifacts/hyprland-version.txt"
# A candidate checkout must already be staged as the installed base theme. No GitHub
# install here: that could silently exercise the public release instead of this patch.
python3 - "$candidate" "$installed" > "$artifacts/candidate-sha256.txt" <<'PY'
import hashlib, pathlib, sys
source, installed = map(pathlib.Path, sys.argv[1:])
for name in ('extras', '.editions', 'backgrounds', 'colors.toml', 'hyprland.lua', 'icons.theme', 'unlock.png'):
    root = source / name
    assert root.exists(), f'missing candidate {name}'
    for item in sorted(root.rglob('*') if root.is_dir() else [root]):
        if item.is_file():
            relative = item.relative_to(source)
            digest = hashlib.sha256(item.read_bytes()).hexdigest()
            target = installed / relative
            assert target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest() == digest, f'candidate mismatch: {relative}'
            print(digest, relative)
PY
check_errors() {
  local errors
  errors=$(hyprctl configerrors)
  printf '%s\n' "$errors"
  [[ -z ${errors//[[:space:]]/} ]] || { echo 'Hyprland configuration errors' >&2; return 1; }
}
effect() { sed -nE 's/^config-file[[:space:]]*=[[:space:]]*\??cursor-effects\/([^.]+).*/\1/p' "$HOME/.config/ghostty/config" | head -1; }
stop_watch() { systemctl --user stop afterburn-watch.service; }
select_theme() {
  omarchy theme set "$1"
  stop_watch # deterministic CLI transition checks; automatic watcher behavior is separate
  [[ $(cat "$current/theme.name") == "$1" ]]
  check_errors
}
install_extras() { bash "$installed/extras/install.sh" --yes </dev/null; stop_watch; }
echo 'Installing extras noninteractively (preinstalled cursor-fx prevents its network bootstrap)'
install_extras
export PATH="$HOME/.local/bin:$PATH"
command -v afterburn >/dev/null
# Disable the asynchronous watcher and weather source during deterministic checks.
afterburn set HEAT_SOURCE off
afterburn set MOTION on
afterburn set LAPTOP_MODE off
for theme in afterburn afterburn-voltage afterburn-cyber afterburn-overdrive afterburn-redline afterburn-phantom; do
  select_theme "$theme"
  afterburn quiet off; afterburn saver off
  afterburn status | tee "$artifacts/$theme-status.txt"
  last_range=0
  for level in cool normal hot; do
    afterburn level "$level"
    [[ $(afterburn level) == "$level" ]]
    # CLI state alone is insufficient: require the live compositor response too.
    range=$(hyprctl getoption decoration:shadow:range -j | tee "$artifacts/$theme-$level-shadow.json" | jq -er '.int')
    ((range > last_range))
    last_range=$range
    check_errors
  done
  if command -v grim >/dev/null; then grim "$artifacts/$theme.png"; fi
done
select_theme afterburn
afterburn quiet off; afterburn saver off; cursor-fx subtle off
baseline=$(effect)
[[ -n $baseline ]]
afterburn saver on; afterburn quiet on
[[ $(cat "$state/quiet") == on && $(cat "$state/saver") == on && -z $(effect) ]]
hyprctl getoption decoration:shadow:enabled -j | tee "$artifacts/quiet-saver-shadow.json" | jq -e '.int == 0' >/dev/null
afterburn quiet off
[[ $(effect) == "$baseline" ]]
hyprctl getoption decoration:shadow:enabled -j | tee "$artifacts/saver-shadow.json" | jq -e '.int == 0' >/dev/null
cursor-fx subtle | tee "$artifacts/saver-after-quiet.txt" | grep -Eq ': on \('
afterburn saver off
[[ $(effect) == "$baseline" ]]
cursor-fx subtle | tee "$artifacts/after-saver.txt" | grep -Eq ': off \('
# Capture exactly what the hook promises to restore before switching away.
previous=$(cat "$state/prev-cursor-fx")
select_theme "$away"
expected=$previous
if [[ $expected == off ]]; then expected=''; fi
[[ $expected == "$(effect)" ]]
[[ ! -e $state/quiet && ! -e $state/saver ]]
! systemctl --user is-active --quiet afterburn-watch.service
select_theme afterburn
echo 'Uninstall and reinstall the same candidate extras'
bash "$installed/extras/uninstall.sh" </dev/null
[[ ! -L $HOME/.local/bin/afterburn && ! -e $HOME/.config/omarchy/hooks/theme-set.d/50-afterburn-extras ]]
check_errors
install_extras
select_theme afterburn-voltage
afterburn status | tee "$artifacts/reinstalled-status.txt"
check_errors
# Exercise the real background watcher separately from deterministic CLI checks.
# Lua dispatcher syntax matches the Omarchy/Hyprland Lua API required by this theme.
echo 'Checking automatic watcher policy and actual fullscreen event delivery'
wait_value() {
  local file=$1 expected=$2 deadline=$((SECONDS + 20))
  until [[ $(cat "$file" 2>/dev/null || true) == "$expected" ]]; do
    (( SECONDS < deadline )) || { echo "Timed out waiting for $file=$expected" >&2; return 1; }
    sleep 0.2
  done
}
wait_shadow() {
  local expected=$1 deadline=$((SECONDS + 20))
  until hyprctl getoption decoration:shadow:enabled -j | jq -e --argjson expected "$expected" '.int == $expected' >/dev/null; do
    (( SECONDS < deadline )) || { echo "Timed out waiting for applied shadow=$expected" >&2; return 1; }
    sleep 0.2
  done
}
afterburn set FULLSCREEN_QUIET yes
afterburn set LAPTOP_MODE off
window=$(hyprctl activewindow -j)
[[ $(jq -r '.address // empty' <<<"$window") != '' ]] || { echo 'An active guest terminal window is required for fullscreen smoke' >&2; exit 1; }
[[ $(jq -r '.fullscreen // 0' <<<"$window") == 0 ]] || { echo 'Start the smoke in a non-fullscreen guest terminal' >&2; exit 1; }
rm -f "$state/fullscreen-socket"
systemctl --user start afterburn-watch.service
systemctl --user is-active --quiet afterburn-watch.service
socket_deadline=$((SECONDS + 20))
until [[ -s $state/fullscreen-socket && -S $(cat "$state/fullscreen-socket") ]]; do
  (( SECONDS < socket_deadline )) || { echo 'Watcher did not confirm a fullscreen event socket connection' >&2; exit 1; }
  sleep 0.2
done
cat "$state/fullscreen-socket" > "$artifacts/watcher-connected-socket.txt"
# Direct data edit bypasses the CLI reconciliation: only the watcher can apply it.
python3 - "$HOME/.config/afterburn/afterburn.conf" <<'POLICY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
s = re.sub(r'^LAPTOP_MODE=.*$', 'LAPTOP_MODE=on', s, flags=re.M)
p.write_text(s)
POLICY
wait_value "$state/saver" on
wait_shadow 0
python3 - "$HOME/.config/afterburn/afterburn.conf" <<'POLICY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
s = re.sub(r'^LAPTOP_MODE=.*$', 'LAPTOP_MODE=off', p.read_text(), flags=re.M)
p.write_text(s)
POLICY
wait_value "$state/saver" off
wait_shadow 1
# Native mode and visible compositor response, not synthetic socket fixtures.
hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "fullscreen", action = "set" })'
wait_value "$state/quiet" on
wait_shadow 0
hyprctl getoption decoration:shadow:enabled -j | tee "$artifacts/watcher-fullscreen-shadow.json" | jq -e '.int == 0' >/dev/null
hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "fullscreen", action = "unset" })'
wait_value "$state/quiet" off
wait_shadow 1
stop_watch
# Persistent motion off must disable the active cursor without erasing its setting.
chosen_cursor=$(afterburn get CURSOR_FX)
afterburn set MOTION off
[[ -z $(effect) && $(afterburn get CURSOR_FX) == "$chosen_cursor" ]]
afterburn set MOTION on
[[ $(effect) == "$chosen_cursor" ]]
afterburn status | tee "$artifacts/after-watcher-and-motion-status.txt"
check_errors
printf '%s\n' 'policy-reread' 'fullscreen-enter-event' 'fullscreen-exit-event' 'motion-off-on' > "$artifacts/automatic-checks.txt"
echo 'PASS: native guest CLI/configuration and automatic watcher smoke completed; screenshots require visual review.'
echo 'Physical power-source changes, lock/PAM, boot splash and hardware performance are not covered.'
echo "Revert the disposable VM snapshot to undo all smoke changes. Artifacts: $artifacts"
