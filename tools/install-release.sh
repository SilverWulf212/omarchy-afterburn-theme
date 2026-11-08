#!/usr/bin/env bash
# Install an extracted complete Afterburn release bundle, then ask about effects.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
args=()
case ${1:-} in
  --yes|-y) args=(--yes) ;;
  '') ;;
  *) echo "Usage: bash install-afterburn.sh [--yes]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo 'Only --yes is supported' >&2; exit 2; }
destination="$HOME/.config/omarchy/themes/afterburn"
echo "Afterburn: install theme files into $destination, then configure Ghostty, glow and cursor effects."
echo 'Existing differing files are preserved and stop installation. The extras installer asks before enabling effects.'
if (( ${#args[@]} == 0 )); then
  read -rp 'Continue? [Y/n] ' answer || exit 1
  [[ -z $answer || $answer =~ ^[Yy] ]] || exit 0
fi
for command in python3 sha256sum; do
  command -v "$command" >/dev/null || { echo "Missing prerequisite: $command" >&2; exit 1; }
done
# Verify all files before executing the packaged Python helper. Obtain the whole
# bundle through a trusted channel; hashes alone do not authenticate its publisher.
(cd "$HERE" && sha256sum --check --ignore-missing SHA256SUMS)
version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$HERE/release.json")
[[ $version =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || { echo 'Invalid release version' >&2; exit 1; }
install_pack() {
  python3 "$HERE/afterburn-pack-tool.py" install --manifest "$HERE/release.json" \
    --pack "$1" --destination "$destination"
}
install_pack "$HERE/afterburn-$version-base.tar.gz"
# Complete bundles include base-live and every edition; selective downloads may
# omit these. Only supplied packs are staged and offered by the extras installer.
shopt -s nullglob
for pack in "$HERE/afterburn-$version-base-live.tar.gz" "$HERE/afterburn-$version-edition-"*.tar.gz; do
  [[ -f $pack ]] || continue
  install_pack "$pack"
done
bash "$destination/extras/install.sh" "${args[@]}"
