#!/usr/bin/env sh
# Verify a downloaded artifact against a reviewed SHA-256 digest.
set -eu

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <sha256> <file>" >&2
  exit 64
fi

printf '%s  %s\n' "$1" "$2" | sha256sum --check --status -
