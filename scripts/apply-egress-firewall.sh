#!/usr/bin/env bash
# Limit Docker bridge egress to a host-managed proxy. Run as root after the
# target Docker networks exist. This intentionally does not filter host-local
# services; WG-08 addresses nested-container access to those services.
set -euo pipefail

CHAIN=CODE_BOX_EGRESS
PROXY_HOST=""
PROXY_PORT=3128
REMOVE=0
NETWORKS=()

usage() {
  echo "Usage: sudo $0 --proxy-host <IPv4> [--proxy-port 3128] --network <name> [--network <name>] [--remove]" >&2
  exit "${1:-0}"
}

die() { echo "ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proxy-host) [[ $# -ge 2 ]] || usage 1; PROXY_HOST="$2"; shift 2 ;;
    --proxy-port) [[ $# -ge 2 ]] || usage 1; PROXY_PORT="$2"; shift 2 ;;
    --network) [[ $# -ge 2 ]] || usage 1; NETWORKS+=("$2"); shift 2 ;;
    --remove) REMOVE=1; shift ;;
    -h|--help) usage 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ $EUID -eq 0 ]] || die "run as root"
command -v iptables >/dev/null 2>&1 || die "iptables is required"
command -v docker >/dev/null 2>&1 || die "docker is required"
[[ ${#NETWORKS[@]} -gt 0 ]] || die "at least one --network is required"

subnets=()
for network in "${NETWORKS[@]}"; do
  subnet="$(docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' "$network")"
  [[ -n "$subnet" ]] || die "network has no IPv4 subnet: $network"
  subnets+=("$subnet")
done

if [[ $REMOVE -eq 1 ]]; then
  for subnet in "${subnets[@]}"; do
    iptables -D DOCKER-USER -s "$subnet" -j "$CHAIN" 2>/dev/null || true
  done
  iptables -F "$CHAIN" 2>/dev/null || true
  iptables -X "$CHAIN" 2>/dev/null || true
  exit 0
fi

[[ -n "$PROXY_HOST" ]] || die "--proxy-host is required"
[[ "$PROXY_PORT" =~ ^[0-9]+$ ]] || die "--proxy-port must be numeric"

iptables -N "$CHAIN" 2>/dev/null || true
iptables -F "$CHAIN"
iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
iptables -A "$CHAIN" -d "$PROXY_HOST" -p tcp --dport "$PROXY_PORT" -j RETURN
iptables -A "$CHAIN" -j DROP

for subnet in "${subnets[@]}"; do
  iptables -C DOCKER-USER -s "$subnet" -j "$CHAIN" 2>/dev/null \
    || iptables -I DOCKER-USER -s "$subnet" -j "$CHAIN"
done

echo "Applied $CHAIN to: ${NETWORKS[*]}"
