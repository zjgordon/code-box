#!/usr/bin/env bash
# One-command bring-up for code-box and its optional siblings.
#
#   scripts/up.sh --profile local-functional              default desktop profile
#   scripts/up.sh --profile contained-build --build       Sysbox DinD build profile
#   scripts/up.sh --sandbox                               compatibility alias for contained-build
#   scripts/up.sh --profile contained-build --ollama --gpu
#   scripts/up.sh --profile contained-build --down         stop (named volumes are kept)
#   scripts/up.sh --seccomp-unconfined  compatibility exception; see threat model
#
# Wraps the existing compose files only — no extra services, mounts, or networks.
# Explicit -f flags override COMPOSE_FILE from .env. See docs/threat-model.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SANDBOX=0 OLLAMA=0 GPU=0 BUILD=0 DOWN=0 SECCOMP_UNCONFINED=0
PROFILE="" PROFILE_EXPLICIT=0

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

die() { echo "ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || die "--profile requires a value"
      PROFILE="$2"
      PROFILE_EXPLICIT=1
      shift 2
      ;;
    --profile=*)
      PROFILE="${1#--profile=}"
      PROFILE_EXPLICIT=1
      shift
      ;;
    --sandbox) SANDBOX=1; shift ;;
    --ollama)  OLLAMA=1; shift ;;
    --gpu)     GPU=1; shift ;;
    --build)   BUILD=1; shift ;;
    --down)    DOWN=1; shift ;;
    --seccomp-unconfined) SECCOMP_UNCONFINED=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

[[ $GPU -eq 1 && $OLLAMA -eq 0 ]] && die "--gpu requires --ollama"

if [[ $PROFILE_EXPLICIT -eq 0 ]]; then
  [[ $SANDBOX -eq 1 ]] && PROFILE="contained-build" || PROFILE="local-functional"
fi

case "$PROFILE" in
  local-functional)
    [[ $SANDBOX -eq 0 ]] || die "--sandbox conflicts with --profile local-functional"
    ;;
  contained-build)
    SANDBOX=1
    ;;
  protected-agent)
    die "--profile protected-agent is not available yet; it requires WG-06 credential scoping and WG-07 egress policy"
    ;;
  *)
    die "unknown profile: $PROFILE (use local-functional or contained-build)"
    ;;
esac

docker compose version >/dev/null 2>&1 || die "Docker Compose v2 not found (docker compose version)"

DIND=(docker compose -f sandbox-dind/docker-compose.yaml)
MAIN=(docker compose -f docker-compose.yaml)
[[ $SECCOMP_UNCONFINED -eq 1 ]] && MAIN+=(-f docker-compose.seccomp-unconfined.yaml)
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
case "$PROFILE" in
  local-functional) MODE="local functional development (no Docker inside the desktop)" ;;
  contained-build) MODE="contained build execution (Sysbox DinD sandbox)" ;;
esac
if [[ $SECCOMP_UNCONFINED -eq 1 ]]; then
  SECCOMP_MODE="unconfined compatibility override"
else
  SECCOMP_MODE="Docker default profile"
fi
echo
echo "code-box is up: $MODE"
echo "  profile: $PROFILE"
echo "  seccomp: $SECCOMP_MODE"
echo "  http://localhost:${PORT:-3000}  (plain HTTP — see docs/threat-model.md before exposing beyond this machine)"
