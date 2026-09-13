#!/usr/bin/env bash
# SPDX-License-Identifier: CC-BY-NC-SA-4.0
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/output.sh"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mo2-linux-nxm-handler"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
LUTRIS_GAMES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/lutris/games"
LUTRIS_RUNNERS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/lutris/runners/wine"
LUTRIS_UMU_RUN="${XDG_DATA_HOME:-$HOME/.local/share}/lutris/runtime/umu/umu-run"
NSENTER_KEY="UMU_CONTAINER_NSENTER"
STEAM_DATA_DIRS=(
  "$HOME/.steam/debian-installation"
  "$HOME/.steam"
  "$HOME/.local/share/steam"
  "$HOME/.local/share/Steam"
  "$HOME/snap/steam/common/.local/share/Steam"
  "$HOME/.steam/steam"
  "$HOME/.var/app/com.valvesoftware.Steam/data/steam"
  "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
  "/usr/share/steam"
  "/usr/local/share/steam"
)

read_version() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  tr -d '[:space:]' <"$f"
}

VERSION="$(read_version "$SCRIPT_DIR/VERSION")" || VERSION="unknown"

usage() {
  cat <<EOF
mo2-linux-nxm-handler $VERSION

Usage: install.sh [--dry-run] [--version] [--help]

  --dry-run   scan and report what would be set up, change nothing
  --version   print the version and exit
  --help      print this message and exit

Finds the Mod Organizer 2 installs Lutris manages, points this machine's
nxm:// links at the right one for each game, and copies itself into
$DATA_DIR
so the folder you ran it from can be deleted afterwards.
EOF
}

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --version) echo "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; echo >&2; usage >&2; exit 1 ;;
  esac
done

# key<TAB>value pairs for exe/prefix (under "game:") and version (under "wine:")
# from a Lutris game YAML. Values keep embedded spaces intact.
extract_yaml_fields() {
  awk '
    /^[^[:space:]]/ { section = $0; sub(/:.*/, "", section); next }
    section == "game" && /^[[:space:]]+exe:/ {
      line = $0; sub(/^[[:space:]]+exe:[[:space:]]*/, "", line); print "EXE\t" line; next
    }
    section == "game" && /^[[:space:]]+prefix:/ {
      line = $0; sub(/^[[:space:]]+prefix:[[:space:]]*/, "", line); print "PREFIX\t" line; next
    }
    section == "wine" && /^[[:space:]]+version:/ {
      line = $0; sub(/^[[:space:]]+version:[[:space:]]*/, "", line); print "VERSION\t" line; next
    }
  ' "$1"
}

resolve_wine_binary() {
  local version="$1" runner_dir
  runner_dir="$LUTRIS_RUNNERS_DIR/$version"
  if [[ -x "$runner_dir/files/bin/wine64" ]]; then
    echo "$runner_dir/files/bin/wine64"
  elif [[ -x "$runner_dir/bin/wine64" ]]; then
    echo "$runner_dir/bin/wine64"
  fi
}

# Lutris 0.5.20+ routes these version names through its bundled umu-run
# instead of a runners/wine/<version> folder, resolving to whichever
# GE-Proton/UMU-Proton build is currently newest in Steam's
# compatibilitytools.d - a moving target we should not try to resolve to a
# fixed path ourselves. Keywords per umu's own ProtonVersion enum.
resolve_umu_protonpath() {
  local version_lc="$1"
  case "$version_lc" in
    ge-proton) echo "GE-Proton" ;;
    umu-proton) echo "UMU-Proton" ;;
    ge-latest) echo "GE-Latest" ;;
    umu-latest) echo "UMU-Latest" ;;
    umu-scout) echo "umu-scout" ;;
    umu-soldier) echo "umu-soldier" ;;
    umu-sniper) echo "umu-sniper" ;;
    umu-steamrt4) echo "umu-steamrt4" ;;
    umu-steamrt4-arm64) echo "umu-steamrt4-arm64" ;;
  esac
}

# Container re-entry
add_nsenter_env() {
  local yml="$1" tmp
  tmp="$(mktemp)" || return 1

  awk -v key="$NSENTER_KEY" -v val="'1'" '
    { lines[NR] = $0 }
    END {
      sys_start = 0
      for (i = 1; i <= NR; i++)
        if (lines[i] ~ /^system:[[:space:]]*$/) { sys_start = i; break }

      if (sys_start) {
        sys_end = NR
        for (i = sys_start + 1; i <= NR; i++)
          if (lines[i] ~ /^[^[:space:]#]/) { sys_end = i - 1; break }

        env_start = 0
        for (i = sys_start + 1; i <= sys_end; i++)
          if (lines[i] ~ /^  env:[[:space:]]*$/) { env_start = i; break }

        if (env_start) {
          at = env_start
          count = 1
          text[1] = "    " key ": " val
        } else {
          at = sys_start
          count = 2
          text[1] = "  env:"
          text[2] = "    " key ": " val
        }
      } else {
        at = NR
        for (i = 1; i <= NR; i++)
          if (lines[i] ~ /^[^[:space:]#]/ && lines[i] > "system:") { at = i - 1; break }
        count = 3
        text[1] = "system:"
        text[2] = "  env:"
        text[3] = "    " key ": " val
      }

      if (at == 0)
        for (j = 1; j <= count; j++) print text[j]
      for (i = 1; i <= NR; i++) {
        print lines[i]
        if (i == at)
          for (j = 1; j <= count; j++) print text[j]
      }
    }
  ' "$yml" >"$tmp" || { rm -f "$tmp"; return 1; }

  [[ -s "$tmp" ]] || { rm -f "$tmp"; return 1; }
  cp "$yml" "$yml.bak" || { rm -f "$tmp"; return 1; }
  cat "$tmp" >"$yml" || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
}

# Pinned Proton builds
proton_search_dirs() {
  local d p old_ifs
  printf '%s\n' "$LUTRIS_RUNNERS_DIR"

  if [[ -n "${STEAM_EXTRA_COMPAT_TOOLS_PATHS:-}" ]]; then
    old_ifs="$IFS"
    IFS=':'
    for d in $STEAM_EXTRA_COMPAT_TOOLS_PATHS; do
      [[ -n "$d" ]] && printf '%s\n' "$d"
    done
    IFS="$old_ifs"
  fi

  for d in "${STEAM_DATA_DIRS[@]}"; do
    printf '%s\n%s\n%s\n' "$d/steamapps/common" "$d/steamapps" "$d/compatibilitytools.d"
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      printf '%s\n%s\n' "$p/steamapps/common" "$p/steamapps"
    done < <(sed -n 's/.*"path"[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$d/steamapps/libraryfolders.vdf" 2>/dev/null)
  done
}

resolve_proton_dir() {
  local version="$1" base
  [[ -n "$version" ]] || return 1
  while IFS= read -r base; do
    if [[ -f "$base/$version/proton" ]]; then
      printf '%s\n' "$base/$version"
      return 0
    fi
  done < <(proton_search_dirs)
  return 1
}

newest_modorganizer_ini() {
  local prefix="$1" newest="" newest_mtime=0 f mtime
  while IFS= read -r -d '' f; do
    mtime=$(stat -c '%Y' "$f" 2>/dev/null) || continue
    if (( mtime > newest_mtime )); then
      newest_mtime=$mtime
      newest=$f
    fi
  done < <(find "$prefix" -ipath '*/ModOrganizer/*/ModOrganizer.ini' -print0 2>/dev/null)
  echo "$newest"
}

# Program files
install_program_files() {
  local f
  local -a files=(
    bin/nxm-router.sh
    lib/output.sh
    share/mo2-linux-nxm-handler.desktop
    games.map
    manual-routes.conf.example
    install.sh
    uninstall.sh
    VERSION
    LICENSE
  )

  for f in "${files[@]}"; do
    [[ -f "$SCRIPT_DIR/$f" ]] || continue
    mkdir -p "$DATA_DIR/$(dirname "$f")" || return 1
    cp "$SCRIPT_DIR/$f" "$DATA_DIR/$f" || return 1
  done

  chmod +x "$DATA_DIR/bin/nxm-router.sh" "$DATA_DIR/install.sh" \
    "$DATA_DIR/uninstall.sh" 2>/dev/null
  return 0
}

lookup_domain() {
  local game_name="$1" domain="" name slug map_file
  for map_file in "$SCRIPT_DIR/games.map" "$DATA_DIR/games.local.map"; do
    [[ -f "$map_file" ]] || continue
    while IFS='|' read -r name slug; do
      [[ -z "$name" || "$name" == \#* ]] && continue
      if [[ "${name,,}" == "${game_name,,}" ]]; then
        domain="$slug"
      fi
    done < "$map_file"
  done
  echo "$domain"
}

heading "mo2-linux-nxm-handler install $VERSION"
[[ $DRY_RUN -eq 1 ]] && warn "dry run: nothing will be written or registered"

if ! command -v xdg-mime >/dev/null 2>&1; then
  err "xdg-mime not found - install xdg-utils first."
  exit 1
fi

declare -A routes=()  # domain -> "wine_bin|prefix|nxmhandler"
declare -A route_yml=()  # domain -> Lutris game YAML, umu routes only
declare -a skipped=()

if ! command -v lutris >/dev/null 2>&1; then
  warn "lutris not found on PATH, skipping auto-discovery (manual routes only)"
elif [[ ! -d "$LUTRIS_GAMES_DIR" ]]; then
  warn "no Lutris games directory at $LUTRIS_GAMES_DIR, skipping auto-discovery"
else
  echo
  heading "Scanning for MO2 instances"
  info "$LUTRIS_GAMES_DIR"
  for yml in "$LUTRIS_GAMES_DIR"/*.yml; do
    [[ -f "$yml" ]] || continue
    exe="" prefix="" version=""
    while IFS=$'\t' read -r key val; do
      case "$key" in
        EXE) exe="$val" ;;
        PREFIX) prefix="$val" ;;
        VERSION) version="$val" ;;
      esac
    done < <(extract_yaml_fields "$yml")

    [[ -n "$exe" ]] || continue
    shopt -s nocasematch
    [[ "$exe" == *ModOrganizer.exe ]] || { shopt -u nocasematch; continue; }
    shopt -u nocasematch

    label="$(basename "$yml" .yml)"
    install_dir="$(dirname "$exe")"
    nxmhandler=$(find "$install_dir" -maxdepth 1 -iname 'nxmhandler.exe' 2>/dev/null | head -n1)
    if [[ -z "$nxmhandler" ]]; then
      skipped+=("$label: no nxmhandler.exe next to $exe")
      continue
    fi

    protonpath=$(resolve_umu_protonpath "${version,,}")
    [[ -n "$protonpath" ]] || protonpath=$(resolve_proton_dir "$version")
    if [[ -n "$protonpath" ]]; then
      if [[ ! -f "$LUTRIS_UMU_RUN" ]]; then
        skipped+=("$label: runner '$version' is UMU-managed but $LUTRIS_UMU_RUN was not found")
        continue
      fi
      wine_bin="umu:$protonpath"
    else
      wine_bin=$(resolve_wine_binary "$version")
      if [[ -z "$wine_bin" ]]; then
        skipped+=("$label: could not resolve wine binary for runner '$version'")
        continue
      fi
    fi

    ini=$(newest_modorganizer_ini "$prefix")
    if [[ -z "$ini" ]]; then
      skipped+=("$label: no ModOrganizer.ini found under $prefix")
      continue
    fi
    game_name=$(grep -im1 '^gameName=' "$ini" | cut -d'=' -f2- | tr -d '\r')
    if [[ -z "$game_name" ]]; then
      skipped+=("$label: ModOrganizer.ini has no gameName= ($ini)")
      continue
    fi

    domain=$(lookup_domain "$game_name")
    if [[ -z "$domain" ]]; then
      skipped+=("$label: gameName '$game_name' not in games.map - add it to games.local.map")
      continue
    fi

    routes["$domain"]="$wine_bin|$prefix|$nxmhandler"
    [[ "$wine_bin" == umu:* ]] && route_yml["$domain"]="$yml"
    ok "$label -> domain '$domain' (game '$game_name')"
  done
fi

manual_file="$DATA_DIR/manual-routes.conf"
if [[ ! -f "$manual_file" ]]; then
  echo
  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$DATA_DIR"
    cp "$SCRIPT_DIR/manual-routes.conf.example" "$manual_file"
    info "seeded empty manual routes file: $manual_file"
  else
    info "would seed empty manual routes file: $manual_file"
  fi
fi

if [[ -f "$manual_file" ]]; then
  manual_found=0
  while IFS='|' read -r domain wine_bin prefix nxmhandler; do
    [[ -z "$domain" || "$domain" == \#* ]] && continue
    if [[ $manual_found -eq 0 ]]; then
      echo
      heading "Manual routes"
      manual_found=1
    fi
    routes["${domain,,}"]="$wine_bin|$prefix|$nxmhandler"
    ok "$domain -> $prefix (manual)"
  done < "$manual_file"
fi

if [[ ${#skipped[@]} -gt 0 ]]; then
  echo
  heading "Skipped instances"
  for s in "${skipped[@]}"; do
    warn "$s"
  done
fi

if [[ ${#routes[@]} -eq 0 ]]; then
  echo
  err "no routes resolved (auto-discovered or manual); nothing to install"
  info "add entries to $manual_file and re-run, or fix the issues above"
  exit 1
fi

echo
heading "Resolved routes"
for domain in "${!routes[@]}"; do
  IFS='|' read -r _ route_prefix _ <<<"${routes[$domain]}"
  ok "$domain -> $route_prefix"
done

if [[ ${#route_yml[@]} -gt 0 ]]; then
  echo
  heading "Container re-entry"
  lutris_running=0
  pgrep -x lutris >/dev/null 2>&1 && lutris_running=1
  for domain in "${!route_yml[@]}"; do
    yml="${route_yml[$domain]}"
    label="$(basename "$yml" .yml)"

    if grep -q "$NSENTER_KEY" "$yml"; then
      ok "$label already sets $NSENTER_KEY"
      continue
    fi

    warn "$label does not set $NSENTER_KEY"
    info "Without it, an MO2 started from Lutris cannot be handed a link while"
    info "it is running. With it, MO2 takes about five seconds longer to start."
    info "$yml"

    if [[ $DRY_RUN -eq 1 ]]; then
      info "dry run: would add $NSENTER_KEY: '1' under system.env"
      continue
    fi
    if [[ ! -t 0 ]]; then
      warn "not running on a terminal, leaving $yml unchanged"
      continue
    fi
    if [[ $lutris_running -eq 1 ]]; then
      warn "Lutris is running and may overwrite this file, close it first"
    fi

    read -rp "    Add it now? [y/N] " reply
    case "${reply,,}" in
      y|yes)
        if add_nsenter_env "$yml"; then
          ok "patched $yml (backup at $yml.bak)"
          info "restart MO2 for it to take effect"
        else
          err "could not patch $yml, left unchanged"
        fi
        ;;
      *)
        info "left alone; add it in Lutris under Configure, System options, Environment variables"
        ;;
    esac
  done
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo
  warn "dry run: not copying program files, writing routes.conf or registering the handler"
  exit 0
fi

echo
heading "Installing"
mkdir -p "$DATA_DIR"

installed_version="$(read_version "$DATA_DIR/VERSION")" || installed_version=""

if [[ -z "$installed_version" ]]; then
  if [[ -f "$DATA_DIR/bin/nxm-router.sh" ]]; then
    info "updating an older unversioned install to $VERSION"
  else
    info "fresh install of $VERSION"
  fi
elif [[ "$installed_version" == "$VERSION" ]]; then
  info "reinstalling $VERSION over the same version"
elif [[ "$(printf '%s\n%s\n' "$installed_version" "$VERSION" | sort -V | head -n1)" == "$VERSION" ]]; then
  warn "downgrading: $installed_version is already installed, this is $VERSION"
else
  info "updating $installed_version to $VERSION"
fi

if [[ "$SCRIPT_DIR" == "$DATA_DIR" ]]; then
  info "running from $DATA_DIR, program files already in place"
elif install_program_files; then
  ok "copied program files to $DATA_DIR"
else
  err "could not copy program files to $DATA_DIR"
  exit 1
fi

routes_file="$DATA_DIR/routes.conf"
: >"$routes_file"
for domain in "${!routes[@]}"; do
  printf '%s|%s\n' "$domain" "${routes[$domain]}" >>"$routes_file"
done

router_script="$DATA_DIR/bin/nxm-router.sh"

mkdir -p "$APPS_DIR"
desktop_file="$APPS_DIR/mo2-linux-nxm-handler.desktop"
sed "s|__NXM_ROUTER__|$router_script|" "$SCRIPT_DIR/share/mo2-linux-nxm-handler.desktop" >"$desktop_file"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS_DIR" >/dev/null 2>&1
fi

xdg-mime default mo2-linux-nxm-handler.desktop x-scheme-handler/nxm

echo
heading "Done"
ok "wrote $routes_file"
ok "installed $desktop_file"
ok "registered as the default handler for nxm:// links"
echo
info "Everything needed now lives in $DATA_DIR"
info "so the folder you ran this from is safe to delete."
info "To pick up a new game later: $DATA_DIR/install.sh"
info "To remove it all: $DATA_DIR/uninstall.sh"
echo
heading "Enjoy :)"
