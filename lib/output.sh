# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-only

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
  c_bold=$'\033[1m'
  c_green=$'\033[32m'
  c_yellow=$'\033[33m'
  c_red=$'\033[31m'
  c_cyan=$'\033[36m'
  c_reset=$'\033[0m'
else
  c_bold='' c_green='' c_yellow='' c_red='' c_cyan='' c_reset=''
fi

heading() { printf '%s%s%s\n' "${c_bold}${c_cyan}" "$*" "$c_reset"; }
ok()      { printf '  %s%s%s %s\n' "$c_green" '✓' "$c_reset" "$*"; }
warn()    { printf '  %s%s%s %s\n' "$c_yellow" '!' "$c_reset" "$*"; }
err()     { printf '%sERROR:%s %s\n' "$c_red" "$c_reset" "$*" >&2; }
info()    { printf '  %s\n' "$*"; }
