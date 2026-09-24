#!/usr/bin/env bash
# One-command bring-up for code-box and its optional siblings.
#
#   scripts/up.sh                     dev box (desktop only; no Docker inside, no host socket)
#   scripts/up.sh --sandbox           walled garden (Sysbox DinD sibling over TLS)
#   scripts/up.sh --sandbox --ollama --gpu --build
#   scripts/up.sh --sandbox --down    stop (named volumes are kept)
#
# Wraps the existing compose files only — no extra services, mounts, or networks.
# Explicit -f flags override COMPOSE_FILE from .env. See docs/threat-model.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SANDBOX=0 OLLAMA=0 GPU=0 BUILD=0 DOWN=0

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

die() { echo "ERROR: $*" >&2; exit 1; }

for arg in "$@"; do
  case "$arg" in
    --sandbox) SANDBOX=1 ;;
    --ollama)  OLLAMA=1 ;;
    --gpu)     GPU=1 ;;
    --build)   BUILD=1 ;;
    --down)    DOWN=1 ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $arg" >&2; usage 1 ;;
  esac
done

[[ $GPU -eq 1 && $OLLAMA -eq 0 ]] && die "--gpu requires --ollama"

docker compose version >/dev/null 2>&1 || die "Docker Compose v2 not found (docker compose version)"

DIND=(docker compose -f sandbox-dind/docker-compose.yaml)
MAIN=(docker compose -f docker-compose.yaml)
[[ $SANDBOX -eq 1 ]] && MAIN+=(-f docker-compose.sandbox.yaml)
[[ $OLLAMA -eq 1 ]] && MAIN+=(-f docker-compose.ollama.yaml)
[[ $GPU -eq 1 ]] && MAIN+=(-f docker-compose.ollama.gpu.yaml)

if [[ $DOWN -eq 1 ]]; then
  "${MAIN[@]}" down
  [[ $SANDBOX -eq 1 ]] && "${DIND[@]}" down
  exit 0
fi

# --- Preflight ---------------------------------------------------------------

[[ -f .env ]] || die ".env not found. Run: cp .env.example .env  (then set CODE_BOX_USER and CODE_BOX_PASSWORD)"

# Read a key from .env without sourcing it (last assignment wins, quotes stripped).
env_value() {
  local v
  v="$(grep -E "^[[:space:]]*$1=" .env | tail -n1 | cut -d= -f2- || true)"
  v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
  printf '%s' "$v"
}

[[ -n "$(env_value CODE_BOX_USER)" ]] || die "Set CODE_BOX_USER in .env"
PASSWORD="$(env_value CODE_BOX_PASSWORD)"
[[ -n "$PASSWORD" ]] || die "Set CODE_BOX_PASSWORD in .env"
[[ "$PASSWORD" != "changeme" ]] || die "CODE_BOX_PASSWORD is the placeholder 'changeme'; set a real password in .env"
unset PASSWORD

if [[ $SANDBOX -eq 1 ]]; then
  docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"sysbox-runc"' \
    || die "sysbox-runc runtime not found on this Docker host. Install Sysbox first: docs/sandbox-docker.md#host-requirements"

  if [[ ! -f certs/client/cert.pem || ! -f certs/server/server-cert.pem ]]; then
    echo "Generating sandbox-dind TLS certs..."
    ./scripts/generate-dind-certs.sh
  fi
fi

# --- Bring-up ----------------------------------------------------------------

if [[ $SANDBOX -eq 1 ]]; then
  echo "Starting sandbox-dind (waiting for healthy)..."
  "${DIND[@]}" up -d --wait
fi

CURSOR_VERSION="$(env_value CURSOR_VERSION)"
if [[ $BUILD -eq 1 ]] || ! docker image inspect "local/code-box:${CURSOR_VERSION:-3.14}" >/dev/null 2>&1; then
  "${MAIN[@]}" build
fi

UP_ARGS=(up -d)
[[ $OLLAMA -eq 1 ]] && UP_ARGS+=(--force-recreate)
"${MAIN[@]}" "${UP_ARGS[@]}"

PORT="$(env_value CODE_BOX_PORT)"
if [[ $SANDBOX -eq 1 ]]; then
  MODE="walled garden (Sysbox DinD sandbox)"
else
  MODE="dev box (no Docker inside the desktop; add --sandbox for isolated Docker)"
fi
echo
echo "code-box is up: $MODE"
echo "  http://localhost:${PORT:-3000}  (plain HTTP — see docs/threat-model.md before exposing beyond this machine)"
