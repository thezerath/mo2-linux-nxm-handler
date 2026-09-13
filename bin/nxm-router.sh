#!/usr/bin/env bash
# SPDX-License-Identifier: CC-BY-NC-SA-4.0
set -uo pipefail

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mo2-linux-nxm-handler"
ROUTES_FILE="$DATA_DIR/routes.conf"
MANUAL_FILE="$DATA_DIR/manual-routes.conf"
FALLBACK_FILE="$DATA_DIR/fallback-routes.conf"
LOG_FILE="$DATA_DIR/router.log"
OUR_DESKTOP_NAME="mo2-linux-nxm-handler.desktop"
UMU_RUN="${XDG_DATA_HOME:-$HOME/.local/share}/lutris/runtime/umu/umu-run"
UMU_LOCAL="${XDG_DATA_HOME:-$HOME/.local/share}/umu"

log() {
  mkdir -p "$DATA_DIR"
  printf '%s | %s\n' "$(date -Iseconds)" "${1//$'\n'/ }" >>"$LOG_FILE"
}

VERSION="$(tr -d '[:space:]' <"$DATA_DIR/VERSION" 2>/dev/null)"
log "mo2-linux-nxm-handler ${VERSION:-unknown}"

link="${1:-}"
if [[ -z "$link" ]]; then
  log "no link argument received"
  exit 1
fi

if [[ ! "$link" =~ ^nxm:// ]]; then
  log "ignoring non-nxm link: $link"
  exit 1
fi

domain="${link#nxm://}"
domain="${domain%%/*}"
domain="${domain,,}"

if [[ ! "$domain" =~ ^[a-z0-9]+$ ]]; then
  log "rejected malformed domain: $domain"
  exit 1
fi

# Container re-entry
launch_client_path() {
  local f newest=""
  for f in "$UMU_LOCAL"/*/pressure-vessel/bin/steam-runtime-launch-client; do
    [[ -x "$f" ]] && newest="$f"
  done
  [[ -n "$newest" ]] || return 1
  printf '%s\n' "$newest"
}

prefix_bus_name() {
  local real
  real="$(readlink -f "$1")"
  printf 'com.steampowered.App%s\n' "$(printf '%s' "$real" | md5sum | cut -d' ' -f1)"
}

container_bus_up() {
  local client
  client="$(launch_client_path)" || return 1
  "$client" --list 2>/dev/null | grep -qxF -- "--bus-name=$1"
}

mo2_running_in() {
  local real pid
  real="$(readlink -f "$1")"
  while IFS= read -r pid; do
    grep -qzF "WINEPREFIX=$real" "/proc/$pid/environ" 2>/dev/null && return 0
  done < <(pgrep -if 'ModOrganizer\.exe' 2>/dev/null)
  return 1
}

no_bus_message() {
  printf '%s\n' \
    "Mod Organizer 2 is already running for this instance, but it was started" \
    "without container re-entry, so the download cannot be handed to it." \
    "" \
    "In Lutris: Configure the game, System options, Environment variables," \
    "add UMU_CONTAINER_NSENTER set to 1, then restart MO2." \
    "Running install.sh again offers to do this for you." \
    "" \
    "Close MO2 and click the link again to download it right now."
}

launch() {
  local wine_bin="$1" prefix="$2" nxmhandler="$3" protonpath bus

  if [[ "$wine_bin" == umu:* ]]; then
    protonpath="${wine_bin#umu:}"
    if [[ ! -f "$UMU_RUN" ]]; then
      log "cannot route domain=$domain via umu: $UMU_RUN not found"
      return 1
    fi

    bus="$(prefix_bus_name "$prefix")"
    if container_bus_up "$bus"; then
      log "joining running container for prefix=$prefix bus=$bus"
    elif mo2_running_in "$prefix"; then
      log "MO2 already running in prefix=$prefix but exposes no bus $bus, refusing to start a second session"
      if command -v zenity >/dev/null 2>&1; then
        zenity --error --title="mo2-linux-nxm-handler" --text="$(no_bus_message)" 2>/dev/null
      fi
      return 1
    else
      log "no container for prefix=$prefix, starting a new umu session"
    fi

    log "routing domain=$domain -> prefix=$prefix via umu PROTONPATH=$protonpath"
    WINEPREFIX="$prefix" PROTONPATH="$protonpath" GAMEID=umu-default \
      UMU_CONTAINER_NSENTER=1 \
      python3 "$UMU_RUN" "$nxmhandler" "$link" >>"$LOG_FILE" 2>&1 &
    disown
    return 0
  fi

  log "routing domain=$domain -> prefix=$prefix wine=$wine_bin"
  WINEPREFIX="$prefix" "$wine_bin" "$nxmhandler" "$link" >>"$LOG_FILE" 2>&1 &
  disown
}

handoff() {
  local desktop_file="$1"
  log "handing domain=$domain to $desktop_file"
  gio launch "$desktop_file" "$link" >>"$LOG_FILE" 2>&1 &
  disown
}

discover_other_handlers() {
  local dirs=() base f id mimetype name old_ifs
  dirs+=("${XDG_DATA_HOME:-$HOME/.local/share}/applications")
  old_ifs="$IFS"
  IFS=':'
  for base in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
    dirs+=("$base/applications")
  done
  IFS="$old_ifs"

  local -A seen=()
  for base in "${dirs[@]}"; do
    [[ -d "$base" ]] || continue
    for f in "$base"/*.desktop; do
      [[ -f "$f" ]] || continue
      id="$(basename "$f")"
      [[ "$id" == "$OUR_DESKTOP_NAME" ]] && continue
      [[ -n "${seen[$id]:-}" ]] && continue
      mimetype="$(grep -m1 '^MimeType=' "$f")"
      [[ "$mimetype" == *x-scheme-handler/nxm* ]] || continue
      seen["$id"]=1
      name="$(grep -m1 '^Name=' "$f" | cut -d'=' -f2-)"
      [[ -n "$name" ]] || name="${id%.desktop}"
      printf '%s|%s\n' "$f" "$name"
    done
  done
}

route_line=""
if [[ -f "$ROUTES_FILE" ]]; then
  route_line="$(grep -i "^${domain}|" "$ROUTES_FILE" | tail -n1)"
fi

if [[ -n "$route_line" ]]; then
  IFS='|' read -r _ wine_bin prefix nxmhandler <<<"$route_line"
  launch "$wine_bin" "$prefix" "$nxmhandler"
  exit $?
fi

log "no MO2 route for domain=$domain"

if [[ -f "$FALLBACK_FILE" ]]; then
  fallback_line="$(grep -i "^${domain}|" "$FALLBACK_FILE" | tail -n1)"
  if [[ -n "$fallback_line" ]]; then
    IFS='|' read -r _ fallback_desktop <<<"$fallback_line"
    if [[ -f "$fallback_desktop" ]] && command -v gio >/dev/null 2>&1; then
      handoff "$fallback_desktop"
      exit 0
    fi
    log "remembered handler $fallback_desktop for domain=$domain is missing or gio unavailable, re-prompting"
  fi
fi

if ! command -v zenity >/dev/null 2>&1; then
  log "zenity not available, cannot prompt - giving up on domain=$domain"
  exit 1
fi

if command -v gio >/dev/null 2>&1; then
  mapfile -t other_handlers < <(discover_other_handlers)
  if [[ ${#other_handlers[@]} -gt 0 ]]; then
    other_names=()
    for entry in "${other_handlers[@]}"; do
      other_names+=("${entry#*|}")
    done
    picked_name="$(printf '%s\n' "${other_names[@]}" | zenity --list --title="mo2-linux-nxm-handler" \
      --text="No MO2 instance for '$domain'. Send it to a different handler instead?" \
      --column="Handler" 2>/dev/null)"

    picked_desktop=""
    if [[ -n "$picked_name" ]]; then
      for entry in "${other_handlers[@]}"; do
        if [[ "${entry#*|}" == "$picked_name" ]]; then
          picked_desktop="${entry%%|*}"
          break
        fi
      done
    fi

    if [[ -n "$picked_desktop" ]]; then
      handoff "$picked_desktop"
      if zenity --question --text="Always send '$domain' links to '$picked_name'?" 2>/dev/null; then
        mkdir -p "$DATA_DIR"
        printf '%s|%s\n' "$domain" "$picked_desktop" >>"$FALLBACK_FILE"
        log "remembered domain=$domain -> $picked_desktop"
      fi
      exit 0
    fi
  fi
fi

if [[ ! -f "$ROUTES_FILE" ]] || [[ ! -s "$ROUTES_FILE" ]]; then
  zenity --error --text="mo2-linux-nxm-handler: no MO2 instances configured.\nRun install.sh first." 2>/dev/null
  log "routes file missing/empty, aborting prompt"
  exit 1
fi

mapfile -t domains < <(cut -d'|' -f1 "$ROUTES_FILE")
chosen="$(printf '%s\n' "${domains[@]}" | zenity --list --title="mo2-linux-nxm-handler" \
  --text="No route for '$domain'. Send this download to:" --column="MO2 instance" 2>/dev/null)"

if [[ -z "$chosen" ]]; then
  log "user cancelled instance picker for domain=$domain"
  exit 1
fi

chosen_line="$(grep -i "^${chosen}|" "$ROUTES_FILE" | tail -n1)"
if [[ -z "$chosen_line" ]]; then
  log "picked instance '$chosen' not found in routes file"
  exit 1
fi

IFS='|' read -r _ wine_bin prefix nxmhandler <<<"$chosen_line"
if ! launch "$wine_bin" "$prefix" "$nxmhandler"; then
  exit 1
fi

if zenity --question --text="Always send '$domain' links to '$chosen'?" 2>/dev/null; then
  mkdir -p "$DATA_DIR"
  printf '%s|%s|%s|%s\n' "$domain" "$wine_bin" "$prefix" "$nxmhandler" >>"$MANUAL_FILE"
  log "remembered domain=$domain -> $chosen (appended to manual-routes.conf)"
fi

exit 0
