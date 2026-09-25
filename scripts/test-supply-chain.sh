#!/usr/bin/env bash
# Verify the artifact checksum helper accepts reviewed content and rejects a
# tampered fixture without writing to the repository.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY="$ROOT/scripts/verify-sha256.sh"
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/code-box-supply-chain.XXXXXX")"

cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT INT TERM

[[ -x "$VERIFY" ]] || { echo "ERROR: checksum verifier is not executable" >&2; exit 1; }

printf '%s' 'reviewed artifact' >"$TMPDIR/artifact"
SHA256="$(sha256sum "$TMPDIR/artifact" | cut -d' ' -f1)"
"$VERIFY" "$SHA256" "$TMPDIR/artifact"

printf '%s' 'tampered artifact' >"$TMPDIR/artifact"
if "$VERIFY" "$SHA256" "$TMPDIR/artifact"; then
  echo "ERROR: checksum verifier accepted tampered content" >&2
  exit 1
fi

echo "Supply-chain checksum test passed."
