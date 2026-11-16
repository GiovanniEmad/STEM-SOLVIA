#!/usr/bin/env bash
# Full-stack tests: embedded Postgres + PostgREST + real supabase-js client + real React pages in jsdom.
# Prereqs: pip install pgserver psycopg2-binary; PostgREST static binary at $POSTGREST (default /tmp/postgrest_bin); npm install in STEM-SOLVIA-APP.
set -e; cd "$(dirname "$0")"; rm -f /tmp/fixtures.json
python3 rest_harness.py > /tmp/harness.log 2>&1 & HP=$!
trap 'kill $HP 2>/dev/null; kill $(cat /tmp/postgrest.pid 2>/dev/null) 2>/dev/null; true' EXIT
for i in $(seq 1 90); do [ -f /tmp/fixtures.json ] && break; sleep 1; done
[ -f /tmp/fixtures.json ] || { echo "harness failed"; tail -20 /tmp/harness.log; exit 1; }
cd ../STEM-SOLVIA-APP && npm run test:integration -- "$@"
