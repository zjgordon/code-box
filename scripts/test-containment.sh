#!/usr/bin/env bash
# Disposable containment smoke test. It never mounts the operator's config or
# workspace, and it checks whether the current image works with Docker seccomp.
set -euo pipefail

IMAGE="${CODE_BOX_TEST_IMAGE:-local/code-box:3.14}"
CONTAINER="code-box-wg00-${RANDOM}-${RANDOM}"
DIND_CONTAINER="sandbox-dind-wg00-${RANDOM}-${RANDOM}"
TEST_DIR=""

cleanup() {
  if [[ -n "$TEST_DIR" ]]; then
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    docker rm -f "$DIND_CONTAINER" >/dev/null 2>&1 || true
    # Container processes can create root-owned files in the disposable bind.
    # Use the already-tested image to remove them before cleaning the host path.
    docker run --rm -v "$TEST_DIR:/cleanup" --entrypoint rm "$IMAGE" -rf /cleanup \
      >/dev/null 2>&1 || true
    rm -rf "$TEST_DIR" || true
  fi
}

fail() {
  echo "ERROR: $*" >&2
  if [[ -n "$TEST_DIR" ]]; then
    docker logs --tail 80 "$CONTAINER" >&2 || true
  fi
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

check_compose_config() {
  CODE_BOX_USER=containment-test CODE_BOX_PASSWORD=containment-test-password \
    CODE_BOX_BIND_ADDRESS=127.0.0.1 \
    docker compose "$@" config --quiet
}

check_seccomp_configuration() {
  CODE_BOX_USER=containment-test CODE_BOX_PASSWORD=containment-test-password \
    CODE_BOX_BIND_ADDRESS=127.0.0.1 \
    docker compose -f docker-compose.yaml config >"$TEST_DIR/default-compose.yaml"
  if grep -q 'seccomp=unconfined' "$TEST_DIR/default-compose.yaml"; then
    fail "base Compose configuration disables seccomp"
  fi

  CODE_BOX_USER=containment-test CODE_BOX_PASSWORD=containment-test-password \
    CODE_BOX_BIND_ADDRESS=127.0.0.1 \
    docker compose -f docker-compose.yaml -f docker-compose.seccomp-unconfined.yaml config \
      >"$TEST_DIR/seccomp-unconfined-compose.yaml"
  grep -q 'seccomp=unconfined' "$TEST_DIR/seccomp-unconfined-compose.yaml" \
    || fail "seccomp compatibility overlay is not applied"
}

check_port_configuration() {
  CODE_BOX_USER=containment-test CODE_BOX_PASSWORD=containment-test-password \
    CODE_BOX_BIND_ADDRESS=127.0.0.1 \
    docker compose -f docker-compose.yaml config >"$TEST_DIR/loopback-compose.yaml"
  grep -q 'host_ip: 127.0.0.1' "$TEST_DIR/loopback-compose.yaml" \
    || fail "base Compose configuration does not bind KasmVNC to loopback"

  CODE_BOX_USER=containment-test CODE_BOX_PASSWORD=containment-test-password \
    CODE_BOX_BIND_ADDRESS=0.0.0.0 \
    docker compose -f docker-compose.yaml config >"$TEST_DIR/lan-compose.yaml"
  grep -q 'host_ip: 0.0.0.0' "$TEST_DIR/lan-compose.yaml" \
    || fail "LAN KasmVNC binding is not available through CODE_BOX_BIND_ADDRESS"
}

run_check() {
  local description="$1"
  shift
  "$@" || fail "$description"
}

run_sysbox_dind_check() {
  if ! docker info --format '{{json .Runtimes}}' | grep -q '"sysbox-runc"'; then
    echo "Skipping Sysbox DinD check: sysbox-runc is not installed."
    return
  fi

  require_command openssl
  docker image inspect docker:dind >/dev/null 2>&1 \
    || fail "Docker DinD image is missing: docker:dind"

  echo "Checking disposable Sysbox DinD..."
  CERTS_DIR="$TEST_DIR/certs" ./scripts/generate-dind-certs.sh >/dev/null
  mkdir -p "$TEST_DIR/dind-storage"
  docker run -d \
    --name "$DIND_CONTAINER" \
    --runtime sysbox-runc \
    -e DOCKER_TLS_CERTDIR= \
    -v "$TEST_DIR/certs/server:/certs:ro" \
    -v "$TEST_DIR/dind-storage:/var/lib/docker" \
    docker:dind \
    dockerd \
      --host=tcp://0.0.0.0:2376 \
      --host=unix:///var/run/docker.sock \
      --tlsverify \
      --tlscacert=/certs/ca.pem \
      --tlscert=/certs/server-cert.pem \
      --tlskey=/certs/server-key.pem >/dev/null \
    || fail "Sysbox DinD could not start"

  DIND_READY=0
  for _ in $(seq 1 24); do
    if docker exec "$DIND_CONTAINER" docker info >/dev/null 2>&1; then
      DIND_READY=1
      break
    fi
    sleep 5
  done
  [[ "$DIND_READY" == "1" ]] || fail "Sysbox DinD did not become ready"

  [[ "$(docker inspect --format '{{.HostConfig.Runtime}}' "$DIND_CONTAINER")" == "sysbox-runc" ]] \
    || fail "sandbox daemon is not using sysbox-runc"
  [[ -z "$(docker port "$DIND_CONTAINER" 2>/dev/null || true)" ]] \
    || fail "sandbox daemon published a host port"
  if docker inspect --format '{{range .Mounts}}{{println .Destination}}{{end}}' "$DIND_CONTAINER" \
    | grep -qx '/config'; then
    fail "sandbox daemon received a /config mount"
  fi
}

trap cleanup EXIT INT TERM

require_command docker
require_command curl
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 not found"
docker info >/dev/null 2>&1 || fail "Docker daemon is not available"
docker image inspect "$IMAGE" >/dev/null 2>&1 \
  || fail "image not found: $IMAGE (build it first or set CODE_BOX_TEST_IMAGE)"

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/code-box-wg00.XXXXXX")"
mkdir -p "$TEST_DIR/config" "$TEST_DIR/workspace"

echo "Checking Compose configurations..."
check_compose_config -f docker-compose.yaml
check_compose_config -f docker-compose.yaml -f docker-compose.seccomp-unconfined.yaml
check_compose_config -f docker-compose.yaml -f docker-compose.sandbox.yaml
check_compose_config -f docker-compose.yaml -f docker-compose.ollama.yaml
check_compose_config \
  -f docker-compose.yaml \
  -f docker-compose.sandbox.yaml \
  -f docker-compose.ollama.yaml \
  -f docker-compose.ollama.gpu.yaml
docker compose -f sandbox-dind/docker-compose.yaml config --quiet
check_seccomp_configuration
check_port_configuration
scripts/up.sh --help | grep -q -- '--seccomp-unconfined' \
  || fail "up.sh does not expose the seccomp compatibility option"

docker run --rm --security-opt seccomp=unconfined --entrypoint sh "$IMAGE" \
  -c 'grep -q "^Seccomp:[[:space:]]*0$" /proc/1/status' \
  || fail "seccomp compatibility override is not active"

run_sysbox_dind_check

echo "Starting disposable desktop with Docker's default seccomp profile..."
docker run -d \
  --name "$CONTAINER" \
  --shm-size=1g \
  -p 127.0.0.1::3000 \
  -e PUID=1000 \
  -e PGID=1000 \
  -e CUSTOM_USER=containment-test \
  -e PASSWORD=containment-test-password \
  -e FM_HOME=/workspace \
  -v "$TEST_DIR/config:/config" \
  -v "$TEST_DIR/workspace:/workspace" \
  "$IMAGE" >/dev/null

docker exec "$CONTAINER" sh -c 'grep -q "^Seccomp:[[:space:]]*2$" /proc/1/status' \
  || fail "Docker's default seccomp profile is not active"
docker exec "$CONTAINER" test ! -S /var/run/docker.sock \
  || fail "host Docker socket is present inside code-box"
if docker inspect --format '{{range .Mounts}}{{println .Source .Destination}}{{end}}' "$CONTAINER" \
  | grep -q '/var/run/docker.sock'; then
  fail "host Docker socket is mounted into code-box"
fi

PORT="$(docker port "$CONTAINER" 3000/tcp | awk 'NR == 1 { sub(/^.*:/, ""); print }')"
[[ -n "$PORT" ]] || fail "Docker did not assign a host port for KasmVNC"

echo "Waiting for KasmVNC authentication endpoint..."
HTTP_STATUS=""
for _ in $(seq 1 24); do
  HTTP_STATUS="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --max-time 3 "http://127.0.0.1:${PORT}/" || true)"
  [[ "$HTTP_STATUS" == "401" ]] && break
  sleep 5
done
[[ "$HTTP_STATUS" == "401" ]] \
  || fail "KasmVNC did not return its expected 401 authentication challenge (got ${HTTP_STATUS:-no response})"

docker exec "$CONTAINER" pgrep -x xfce4-session >/dev/null \
  || fail "XFCE session did not start"
docker exec "$CONTAINER" pgrep -x cursor >/dev/null \
  || fail "Cursor did not start"

echo "Checking desktop tools and MCP wrappers..."
run_check "VS Code could not run" \
  docker exec "$CONTAINER" su -s /bin/bash abc -c 'DISPLAY=:1 timeout 30 /usr/local/bin/code --version' >/dev/null
run_check "Cursor could not run" \
  docker exec "$CONTAINER" su -s /bin/bash abc -c 'DISPLAY=:1 timeout 30 cursor --version' >/dev/null
run_check "Claude Code could not run" \
  docker exec "$CONTAINER" su -s /bin/bash abc -c 'claude --version' >/dev/null
run_check "OpenCode could not run" \
  docker exec "$CONTAINER" su -s /bin/bash abc -c 'opencode --version' >/dev/null
run_check "Playwright MCP could not run" \
  docker exec "$CONTAINER" /usr/local/bin/playwright-mcp --help >/dev/null
run_check "Fetch MCP could not import" \
  docker exec "$CONTAINER" /opt/mcp-fetch/bin/python -c 'import mcp_server_fetch' >/dev/null
if docker exec "$CONTAINER" /usr/local/bin/github-mcp >/dev/null 2>&1; then
  fail "GitHub MCP unexpectedly started without disposable gh authentication"
fi

docker exec "$CONTAINER" sh -c \
  'su -s /bin/bash abc -c "DISPLAY=:1 firefox --new-instance about:blank >/tmp/wg00-firefox.log 2>&1 &"' \
  || fail "Firefox could not start"
FIREFOX_STARTED=0
for _ in $(seq 1 10); do
  if docker exec "$CONTAINER" pgrep -x firefox-bin >/dev/null; then
    FIREFOX_STARTED=1
    break
  fi
  sleep 1
done
[[ "$FIREFOX_STARTED" == "1" ]] \
  || fail "Firefox did not remain running under Docker's default seccomp profile"
docker exec "$CONTAINER" sh -c 'pkill -u abc -x firefox-bin || true'

echo "Containment smoke test passed."
