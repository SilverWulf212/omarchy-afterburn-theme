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
afterburn set HEAT_SOURCE time
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
echo 'PASS: native guest CLI/configuration smoke completed; screenshots require visual review.'
echo 'Watcher automatic power events, lock/PAM, boot splash and physical hardware are not covered.'
echo "Revert the disposable VM snapshot to undo all smoke changes. Artifacts: $artifacts"
