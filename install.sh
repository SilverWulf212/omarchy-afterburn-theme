#!/usr/bin/env bash
# Short entry point for the same Omarchy theme + interactive extras installation.
set -euo pipefail

if ! command -v omarchy >/dev/null 2>&1; then
  echo 'Afterburn requires Omarchy. Run this on your Omarchy desktop.' >&2
  exit 1
fi

omarchy theme install https://github.com/silverwulf212/omarchy-afterburn-theme

installer="$HOME/.config/omarchy/themes/afterburn/extras/install.sh"
if [[ ! -x $installer ]]; then
  echo "Afterburn extras installer is missing or not executable: $installer" >&2
  exit 1
fi
exec "$installer" "$@"
