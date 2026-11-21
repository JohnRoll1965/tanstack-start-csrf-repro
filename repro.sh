#!/usr/bin/env bash
# For each state (tags a-baseline, b-bug, c-fix): build that state's src/start.ts, start the
# production server, and POST to the server function twice, once from a foreign Origin and once
# from the app's own Origin. Prints the HTTP status of each.
#
# Only src/start.ts differs between the states, so this script swaps that one file in from each
# tag, rebuilds, and puts your working copy back when it finishes.
#
# Usage: ./repro.sh                  all three states
#        ./repro.sh b-bug            one state
set -euo pipefail
cd "$(dirname "$0")"

PORT="${PORT:-3311}"
BASE="http://localhost:$PORT"
STATES=("${@:-a-baseline b-bug c-fix}")
read -r -a STATES <<<"${STATES[*]}"

SERVER_PID=""
ORIGINAL_START="$(mktemp)"
cp src/start.ts "$ORIGINAL_START"
cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
  cp "$ORIGINAL_START" src/start.ts && rm -f "$ORIGINAL_START"
}
trap cleanup EXIT

# The exact body the page's own button sends (captured from Chrome): a seroval-encoded
# { data: <string> }, POSTed as JSON with the x-tsr-serverFn header.
body() { printf '{"t":{"t":10,"i":0,"p":{"k":["data"],"v":[{"t":1,"s":"%s"}]},"o":0},"f":127,"m":[]}' "$1"; }

# curl sends no Sec-Fetch-Site header, so the CSRF check (when present) falls back to comparing
# the Origin header with the request's own origin.
# Prints the status, then either what writeThing returned as written (it ran) or the raw body
# (for a rejection that is the CSRF middleware's "Forbidden").
post() { # $1 = Origin header, $2 = payload
  local out status wrote
  out="$(mktemp)"
  status="$(curl -s -o "$out" -w '%{http_code}' -X POST "$BASE$FN_URL" \
    -H "Origin: $1" -H 'Content-Type: application/json' -H 'x-tsr-serverFn: true' \
    --data "$(body "$2")")"
  wrote="$(sed -n 's/.*"k":\["ok","wrote"\],"v":\[{"t":2,"s":2},{"t":1,"s":"\([^"]*\)"}.*/\1/p' "$out")"
  if [ -n "$wrote" ]; then echo "$status ok, wrote: \"$wrote\""; else echo "$status $(head -c 160 "$out")"; fi
  rm -f "$out"
}

echo "node $(node -v), @tanstack/react-start $(node -p "require('@tanstack/react-start/package.json').version")"
for STATE in "${STATES[@]}"; do
  git show "$STATE:src/start.ts" >src/start.ts
  echo
  echo "== $STATE: $(grep -E '^export const startInstance' src/start.ts)"
  pnpm -s build >/dev/null 2>&1 || { echo "build failed for $STATE"; exit 1; }
  PORT="$PORT" node server.mjs >/dev/null 2>&1 &
  SERVER_PID=$!
  for _ in $(seq 1 50); do curl -s -o /dev/null "$BASE/" && break; sleep 0.2; done
  FN_URL="$(curl -s "$BASE/" | sed -n 's/.*<code id="fn-url">\([^<]*\)<.*/\1/p')"

  echo "foreign origin (Origin: https://evil.example):  $(post https://evil.example "cross-site write")"
  echo "correct origin (Origin: $BASE): $(post "$BASE" "same-site write")"

  kill "$SERVER_PID" && wait "$SERVER_PID" 2>/dev/null || true
  SERVER_PID=""
done
