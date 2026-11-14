#!/bin/bash
#
# Seed-VC launcher for macOS (Apple Silicon and Intel)
#
# Frozen into the .app by packaging/build-dmg.sh; __VERSION__ is replaced at
# build time. Dependency handling is delegated to the repository's own
# start-mac.command, so there is a single source of truth for the install.
#
set -uo pipefail

VERSION="__VERSION__"

SUPPORT="$HOME/Library/Application Support/Seed-VC"
SRC="$SUPPORT/app"
CHOICE_FILE="$SUPPORT/mode"

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
RES="$(cd "$SELF_DIR/../Resources" 2>/dev/null && pwd)"
BUNDLED_SRC="$RES/app"

if [ -t 1 ]; then :; else
  exec /usr/bin/open -a Terminal "$0"
fi

c_cyan=$'\033[36m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_off=$'\033[0m'
step() { printf '%s==>%s %s\n' "$c_cyan" "$c_off" "$*"; }
ok()   { printf '    %s✓%s %s\n' "$c_cyan" "$c_off" "$*"; }
warn() { printf '    %s!%s %s\n' "$c_yellow" "$c_off" "$*"; }
die()  { printf '\n%serror:%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

printf '\n%sSeed-VC %s%s — macOS\n\n' "$c_cyan" "$VERSION" "$c_off"

command -v brew >/dev/null 2>&1 || die "Нужен Homebrew. Установите: https://brew.sh, затем запустите снова."
[ -d "$BUNDLED_SRC" ] || die "В приложении нет исходников ($BUNDLED_SRC). Скачайте .dmg заново."

mkdir -p "$SUPPORT" "$SUPPORT/logs"

# Python 3.10/3.11 is what start-mac.command expects; install it if missing.
python_ok() { "$1" -c 'import sys; raise SystemExit(0 if (3,10) <= sys.version_info[:2] <= (3,11) else 1)' >/dev/null 2>&1; }
find_python() {
  local c
  for c in python3.11 python3.10; do
    command -v "$c" >/dev/null 2>&1 && python_ok "$c" && { command -v "$c"; return 0; }
  done
  for c in /opt/homebrew/opt/python@3.11/bin/python3.11 /opt/homebrew/opt/python@3.10/bin/python3.10; do
    [ -x "$c" ] && python_ok "$c" && { echo "$c"; return 0; }
  done
  return 1
}
if ! PY="$(find_python)"; then
  step "Python 3.10+ не найден — ставлю python@3.11 через Homebrew"
  brew install python@3.11 >>"$SUPPORT/brew.log" 2>&1 || die "brew install python@3.11 не удался"
  PY="$(find_python || true)"
  [ -n "$PY" ] || die "Python 3.10/3.11 так и не появился"
fi
ok "Python: $PY ($("$PY" -c 'import sys; print(sys.version.split()[0])'))"

# Sources: refresh on every version, but keep .venv, my_models and the choice.
step "Раскладываю исходники в $SRC"
mkdir -p "$SRC"
rsync -a --delete \
  --exclude '.venv' \
  --exclude '.git' \
  --exclude 'my_models' \
  --exclude 'dist' \
  --exclude 'packaging' \
  --exclude '__pycache__' \
  "$BUNDLED_SRC/" "$SRC/" >"$SUPPORT/logs/rsync.log" 2>&1 || die "не удалось скопировать исходники"
mkdir -p "$SRC/my_models"
chmod +x "$SRC/start-mac.command" "$SRC/start-mac-Roman" 2>/dev/null || true
ok "исходники на месте"

# Mode: explicit override > remembered choice > interactive menu.
mode_from_label() {
  case "$1" in
    1|vc|VC)   echo vc ;;
    2|svc|SVC) echo svc ;;
    3|v2|V2)   echo v2 ;;
    4|all|ALL) echo all ;;
    5|check)   echo check ;;
    *)         echo "" ;;
  esac
}

MODE="${SEEDVC_MODE:-}"
if [ -z "$MODE" ]; then
  default="$(cat "$CHOICE_FILE" 2>/dev/null || echo vc)"
  printf 'Что открыть?\n'
  printf '  1) Voice conversion (vc)%s\n' "$([ "$default" = vc ] && echo '  ← по умолчанию')"
  printf '  2) Singing voice conversion (svc)%s\n' "$([ "$default" = svc ] && echo '  ← по умолчанию')"
  printf '  3) V2 — голос и акцент%s\n' "$([ "$default" = v2 ] && echo '  ← по умолчанию')"
  printf '  4) Integrated UI (V1 + V2)%s\n' "$([ "$default" = all ] && echo '  ← по умолчанию')"
  printf '  5) Проверить окружение\n'
  printf 'Номер [Enter = %s]: ' "$default"
  choice=""
  read -r -t 15 choice || true
  printf '\n'
  [ -z "$choice" ] && choice="$default"
  MODE="$(mode_from_label "$choice")"
  [ -n "$MODE" ] || die "неизвестный вариант: $choice"
  echo "$MODE" > "$CHOICE_FILE"
else
  ok "режим из SEEDVC_MODE: $MODE"
fi

cd "$SRC" || die "нет каталога $SRC"

if [ "$MODE" = "check" ]; then
  exec ./start-mac.command check
fi

# Shared setup (venv + deps + torch) runs once, whichever mode is picked.
export SEEDVC_LAUNCHER_VERSION="$VERSION"
exec ./start-mac.command "$MODE"
