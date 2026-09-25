#!/usr/bin/env bash
# Run the repository-controlled release gates. Host firewall integration tests
# remain operator steps because they require root and a live proxy.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

./scripts/test-supply-chain.sh
./scripts/test-containment.sh
docker compose -f docker-compose.yaml config --quiet
docker compose -f docker-compose.yaml -f docker-compose.protected-agent.yaml config --quiet

echo "Automated release checks passed."
echo "Complete docs/release-checklist.md before tagging a release."
