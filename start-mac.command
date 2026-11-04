#!/bin/bash
#
# Seed-VC — one-command launcher for macOS.
#
# Double-click this file in Finder, or run it from a terminal:
#
#   ./start-mac.command            # voice conversion UI (default)
#   ./start-mac.command svc        # singing voice conversion UI
#   ./start-mac.command v2         # V2 voice / accent conversion UI
#   ./start-mac.command all        # integrated UI (V1 + V2)
#   ./start-mac.command install <model.zip|dir>   # install a custom model
#   ./start-mac.command vc my_models/my-model     # run with a custom model
#   ./start-mac.command check      # show what the launcher detects
#
# Optional environment variables:
#   PORT=7860     HTTP port for the web UI
#   FP16=1        enable half precision (off by default on macOS)
#   SHARE=1       create a public Gradio share link (VC and SVC only)
#   NO_OPEN=1     do not open the browser automatically
#   DRY_RUN=1     print what would be executed, change nothing
#
# The first run creates .venv and installs the dependencies (a few minutes).

set -euo pipefail

cd "$(dirname "$0")"
REPO_DIR="$(pwd)"

VENV_DIR=".venv"
DEPS_STAMP="$VENV_DIR/.seedvc-deps"
REQUIREMENTS="requirements-mac.txt"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Seed-VC launcher for macOS

  ./start-mac.command            voice conversion UI (default)
  ./start-mac.command svc        singing voice conversion UI
  ./start-mac.command v2         V2 voice / accent conversion UI
  ./start-mac.command all        integrated UI (V1 + V2)
  ./start-mac.command install <model.zip|dir>
  ./start-mac.command vc my_models/my-model
  ./start-mac.command check      show what the launcher detects

Environment variables:
  PORT=7860     HTTP port for the web UI
  FP16=1        enable half precision (off by default on macOS)
  SHARE=1       create a public Gradio share link (VC and SVC only)
  NO_OPEN=1     do not open the browser automatically
  DRY_RUN=1     print what would be executed, change nothing
EOF
  exit 0
}

MODE="${1:-vc}"
if [ "$#" -gt 0 ]; then shift; fi
MODEL_SRC="${1:-}"

case "$MODE" in
  vc|svc|v2|all|install|check) ;;
  -h|--help|help) usage ;;
  *) die "unknown mode: $MODE (try: ./start-mac.command help)" ;;
esac

DRY_RUN="${DRY_RUN:-0}"
IS_MAC=0
[ "$(uname -s)" = "Darwin" ] && IS_MAC=1

if [ "$IS_MAC" -eq 0 ] && [ "$DRY_RUN" != "1" ] && [ "$MODE" != "check" ]; then
  die "this launcher is for macOS only (use requirements.txt / README on Linux and Windows)"
fi

# --- Python ---------------------------------------------------------------

python_ok() {
  "$1" -c 'import sys; raise SystemExit(0 if (3, 10) <= sys.version_info[:2] <= (3, 11) else 1)' \
    >/dev/null 2>&1
}

find_python() {
  local candidate
  for candidate in python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1 && python_ok "$candidate"; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

PYTHON="$(find_python || true)"

suggest_python() {
  cat >&2 <<'EOF'
Python 3.10 or 3.11 is required (the pinned dependencies are not tested on 3.12+).

Install one with Homebrew:

    brew install python@3.11

or download it from https://www.python.org/downloads/
EOF
}

if [ -z "$PYTHON" ]; then
  warn "no suitable Python found"
  suggest_python
  exit 1
fi

ARCH="$(uname -m)"

# --- Environment ----------------------------------------------------------

VENV_PY="$VENV_DIR/bin/python"

ensure_venv() {
  if [ -d "$VENV_DIR" ]; then
    if [ ! -x "$VENV_PY" ] || ! python_ok "$VENV_PY"; then
      warn "existing .venv uses an unsupported Python version, recreating it"
      rm -rf "$VENV_DIR"
    fi
  fi

  if [ ! -d "$VENV_DIR" ]; then
    say "Creating virtual environment in $VENV_DIR"
    if [ "$DRY_RUN" = "1" ]; then
      VENV_PY="$VENV_DIR/bin/python"
      return 0
    fi
    "$PYTHON" -m venv "$VENV_DIR" || die "failed to create the virtual environment"
  fi

  VENV_PY="$VENV_DIR/bin/python"
}

stamp_value() {
  local hasher="shasum -a 256"
  command -v shasum >/dev/null 2>&1 || hasher="sha256sum"

  {
    printf '%s\n' "$ARCH"
    "$VENV_PY" -c 'import sys; print(sys.version)'
    cat "$REQUIREMENTS"
  } 2>/dev/null | $hasher | awk '{print $1}'
}

install_torch() {
  say "Installing PyTorch for $ARCH"
  if [ "$ARCH" = "arm64" ]; then
    # Apple Silicon: stable wheels with MPS support.
    "$VENV_PY" -m pip install --upgrade \
      "torch==2.4.1" "torchvision==0.19.1" "torchaudio==2.4.1"
  else
    # Intel Mac: 2.2.2 is the last release with macOS x86_64 wheels.
    "$VENV_PY" -m pip install --upgrade \
      "torch==2.2.2" "torchvision==0.17.2" "torchaudio==2.2.2"
  fi
}

install_deps() {
  local stamp
  stamp="$(stamp_value)"

  if [ -f "$DEPS_STAMP" ] && [ "$(cat "$DEPS_STAMP")" = "$stamp" ]; then
    say "Dependencies are already installed"
    return 0
  fi

  say "Upgrading pip"
  "$VENV_PY" -m pip install --upgrade pip setuptools wheel

  install_torch

  say "Installing requirements from $REQUIREMENTS"
  "$VENV_PY" -m pip install -r "$REQUIREMENTS"

  printf '%s\n' "$stamp" > "$DEPS_STAMP"
  say "Dependencies installed"
}

check_media_tools() {
  if ! command -v ffmpeg >/dev/null 2>&1; then
    warn "ffmpeg not found — mp3 output and some audio formats will not work"
    warn "install it with: brew install ffmpeg"
  fi
}

# --- Model selection ------------------------------------------------------

CHECKPOINT=""
CONFIG=""

resolve_model() {
  local dir="$1"
  [ -d "$dir" ] || die "model directory not found: $dir"

  CHECKPOINT="$(find "$dir" -maxdepth 3 -type f -name '*.pth' | head -n 1)"
  CONFIG="$(find "$dir" -maxdepth 3 -type f \( -name 'config*.yml' -o -name 'config*.yaml' \) | head -n 1)"

  [ -n "$CHECKPOINT" ] || die "no .pth file found in $dir"
  [ -n "$CONFIG" ]     || die "no config*.yml/.yaml file found in $dir"
}

# --- Modes ----------------------------------------------------------------

show_check() {
  say "Repository : $REPO_DIR"
  say "System     : $(uname -s) $(uname -r)"
  say "Arch       : $ARCH"
  say "Python     : $PYTHON ($("$PYTHON" -c 'import sys; print(sys.version.split()[0])'))"
  if [ -x "$VENV_PY" ]; then
    say "Venv       : $VENV_DIR"
    if "$VENV_PY" -c 'import torch' >/dev/null 2>&1; then
      "$VENV_PY" - <<'EOF'
import torch
mps = getattr(torch.backends, "mps", None)
mps_ok = bool(mps and mps.is_available())
print(f"==> PyTorch    : {torch.__version__}")
print(f"==> Device     : {'mps' if mps_ok else 'cpu'}")
EOF
    else
      warn "PyTorch is not installed yet (run ./start-mac.command)"
    fi
  else
    warn "no .venv yet (it is created on first launch)"
  fi
  command -v ffmpeg >/dev/null 2>&1 \
    && say "ffmpeg     : $(command -v ffmpeg)" \
    || warn "ffmpeg     : not found"
}

run_ui() {
  local mode="$1"
  local fp16="False"
  [ "${FP16:-0}" = "1" ] && fp16="True"

  export GRADIO_SERVER_PORT="${PORT:-7860}"
  export GRADIO_SERVER_NAME="${HOST:-127.0.0.1}"
  export GRADIO_ANALYTICS_ENABLED=False
  export PYTORCH_ENABLE_MPS_FALLBACK=1
  export HF_HUB_DISABLE_TELEMETRY=1

  local cmd=("$VENV_PY")

  case "$mode" in
    vc)
      cmd+=(app_vc.py --fp16 "$fp16")
      [ -n "$CHECKPOINT" ] && cmd+=(--checkpoint "$CHECKPOINT" --config "$CONFIG")
      [ "${SHARE:-0}" = "1" ] && cmd+=(--share True)
      ;;
    svc)
      cmd+=(app_svc.py --fp16 "$fp16")
      [ -n "$CHECKPOINT" ] && cmd+=(--checkpoint "$CHECKPOINT" --config "$CONFIG")
      [ "${SHARE:-0}" = "1" ] && cmd+=(--share True)
      ;;
    v2)
      cmd+=(app_vc_v2.py)
      [ -n "$MODEL_SRC" ] && warn "V2 ignores custom checkpoints; use app_vc.py or app_svc.py for those"
      ;;
    all)
      cmd+=(app.py --enable-v1 --enable-v2)
      [ -n "$MODEL_SRC" ] && warn "the integrated UI ignores custom checkpoints; use app_vc.py or app_svc.py for those"
      ;;
  esac

  local url="http://127.0.0.1:${GRADIO_SERVER_PORT}"

  say "Starting: ${cmd[*]}"
  say "Web UI:   $url  (Ctrl+C to stop)"

  if [ "$DRY_RUN" = "1" ]; then
    return 0
  fi

  if [ "${NO_OPEN:-0}" != "1" ]; then
    ( sleep "${OPEN_DELAY:-8}"; command -v open >/dev/null 2>&1 && open "$url" ) >/dev/null 2>&1 &
  fi

  exec "${cmd[@]}"
}

# --- Main -----------------------------------------------------------------

if [ "$MODE" = "check" ]; then
  show_check
  exit 0
fi

if [ "$MODE" = "install" ]; then
  [ -n "$MODEL_SRC" ] || die "usage: ./start-mac.command install <model.zip|directory>"
  say "Installing model from $MODEL_SRC"
  if [ "$DRY_RUN" = "1" ]; then
    echo "$PYTHON install-model.py $MODEL_SRC"
  else
    "$PYTHON" install-model.py "$MODEL_SRC"
  fi
  exit 0
fi

if [ -n "$MODEL_SRC" ]; then
  resolve_model "$MODEL_SRC"
fi

say "Python : $PYTHON"
say "Arch   : $ARCH"

ensure_venv

if [ "$DRY_RUN" = "1" ]; then
  say "DRY_RUN: skipping dependency installation"
else
  install_deps
  check_media_tools
fi

run_ui "$MODE"
