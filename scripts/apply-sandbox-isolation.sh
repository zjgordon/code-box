#!/usr/bin/env bash
# Block new sandbox-dind-to-code-box connections while retaining replies to the
# desktop's TLS connection to dockerd. Run as root while both containers exist.
set -euo pipefail

CHAIN=CODE_BOX_SANDBOX_ISOLATION
NETWORK=sandbox-net
CODE_BOX=code-box
DIND=sandbox-dind
REMOVE=0

usage() {
  echo "Usage: sudo $0 [--network sandbox-net] [--code-box code-box] [--dind sandbox-dind] [--remove]" >&2
  exit "${1:-0}"
}

die() { echo "ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --network) [[ $# -ge 2 ]] || usage 1; NETWORK="$2"; shift 2 ;;
    --code-box) [[ $# -ge 2 ]] || usage 1; CODE_BOX="$2"; shift 2 ;;
    --dind) [[ $# -ge 2 ]] || usage 1; DIND="$2"; shift 2 ;;
    --remove) REMOVE=1; shift ;;
    -h|--help) usage 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ $EUID -eq 0 ]] || die "run as root"
command -v iptables >/dev/null 2>&1 || die "iptables is required"
command -v docker >/dev/null 2>&1 || die "docker is required"

network_ip() {
  docker inspect --format "{{with index .NetworkSettings.Networks \"$NETWORK\"}}{{.IPAddress}}{{end}}" "$1"
}

DIND_IP="$(network_ip "$DIND")"
CODE_BOX_IP="$(network_ip "$CODE_BOX")"
[[ -n "$DIND_IP" ]] || die "$DIND is not attached to $NETWORK"
[[ -n "$CODE_BOX_IP" ]] || die "$CODE_BOX is not attached to $NETWORK"

if [[ $REMOVE -eq 1 ]]; then
  iptables -D DOCKER-USER -s "$DIND_IP" -d "$CODE_BOX_IP" -j "$CHAIN" 2>/dev/null || true
  iptables -F "$CHAIN" 2>/dev/null || true
  iptables -X "$CHAIN" 2>/dev/null || true
  exit 0
fi

iptables -N "$CHAIN" 2>/dev/null || true
iptables -F "$CHAIN"
iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
iptables -A "$CHAIN" -j DROP
iptables -C DOCKER-USER -s "$DIND_IP" -d "$CODE_BOX_IP" -j "$CHAIN" 2>/dev/null \
  || iptables -I DOCKER-USER -s "$DIND_IP" -d "$CODE_BOX_IP" -j "$CHAIN"

echo "Blocked new $DIND ($DIND_IP) connections to $CODE_BOX ($CODE_BOX_IP) on $NETWORK"
