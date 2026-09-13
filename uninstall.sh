#!/usr/bin/env bash
# SPDX-License-Identifier: CC-BY-NC-SA-4.0
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/output.sh"

APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mo2-linux-nxm-handler"
desktop_file="$APPS_DIR/mo2-linux-nxm-handler.desktop"

VERSION="$(tr -d '[:space:]' <"$SCRIPT_DIR/VERSION" 2>/dev/null)"

heading "mo2-linux-nxm-handler uninstall ${VERSION:-unknown}"
echo

mimeapps_file="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
if [[ -f "$mimeapps_file" ]] && grep -qxF "x-scheme-handler/nxm=mo2-linux-nxm-handler.desktop" "$mimeapps_file"; then
  sed -i '/^x-scheme-handler\/nxm=mo2-linux-nxm-handler\.desktop$/d' "$mimeapps_file"
  ok "cleared x-scheme-handler/nxm default"
else
  info "x-scheme-handler/nxm default was not ours, left it alone"
fi

if [[ -f "$desktop_file" ]]; then
  rm -f "$desktop_file"
  ok "removed $desktop_file"
else
  info "$desktop_file was already gone"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS_DIR" >/dev/null 2>&1
fi

removed=0
for f in bin/nxm-router.sh lib/output.sh share/mo2-linux-nxm-handler.desktop \
  games.map manual-routes.conf.example install.sh VERSION LICENSE; do
  if [[ -f "$DATA_DIR/$f" ]]; then
    rm -f "$DATA_DIR/$f"
    removed=1
  fi
done
rmdir "$DATA_DIR/bin" "$DATA_DIR/lib" "$DATA_DIR/share" 2>/dev/null
if [[ $removed -eq 1 ]]; then
  ok "removed the installed program files from $DATA_DIR"
else
  info "no installed program files found in $DATA_DIR"
fi

echo
heading "Done"
info "left in place: $DATA_DIR"
info "Your settings and log are still there (routes.conf, manual-routes.conf,"
info "fallback-routes.conf, games.local.map, router.log), along with this"
info "script. Delete the whole directory for a full clean removal."

echo
heading "Goodbye :)"
