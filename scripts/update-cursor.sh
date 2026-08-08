#!/usr/bin/env bash
# Query Cursor's stable release API and compare to the pinned CURSOR_VERSION.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ENV_FILE="${ENV_FILE:-.env}"
DOCKERFILE="${DOCKERFILE:-Dockerfile}"

current() {
    local val
    if [[ -f "$ENV_FILE" ]] && val="$(grep -E '^CURSOR_VERSION=' "$ENV_FILE" | cut -d= -f2)" && [[ -n "$val" ]]; then
        echo "$val"
        return
    fi
    grep -E '^ARG CURSOR_VERSION=' "$DOCKERFILE" | head -1 | sed 's/.*=//'
}

pinned="$(current)"
echo "Pinned CURSOR_VERSION: ${pinned}"
echo

api_json="$(curl -fsSL "https://api2.cursor.sh/updates/api/download/stable/linux-x64/cursor")"
stable_version="$(echo "$api_json" | jq -r '.version')"

echo "Stable channel metadata from Cursor API:"
echo "$api_json" | jq .
echo
echo "Stable version: ${stable_version}"

# Compare major.minor (pin style) against stable when pin is major.minor only.
pinned_prefix="${pinned}"
if [[ "$stable_version" == "${pinned}"* ]] || [[ "$stable_version" == "${pinned}."* ]]; then
    echo "Status: up to date (stable ${stable_version} matches pin ${pinned})"
elif [[ "$stable_version" == "$pinned" ]]; then
    echo "Status: up to date"
else
    echo "Status: UPDATE AVAILABLE — pin is ${pinned}, stable is ${stable_version}"
fi

echo
echo "To update: set CURSOR_VERSION in .env and Dockerfile, then:"
echo "  docker compose build --no-cache && docker compose up -d"
