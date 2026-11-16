#!/usr/bin/env bash
# Validates scripts/smoke.mjs itself against the local test stack (storage/sign-up checks are skipped there: no real Storage/GoTrue).
set -e; cd "$(dirname "$0")"; rm -f /tmp/fixtures.json
python3 rest_harness.py > /tmp/harness.log 2>&1 & HP=$!
trap 'kill $HP 2>/dev/null; kill $(cat /tmp/postgrest.pid 2>/dev/null) 2>/dev/null; true' EXIT
for i in $(seq 1 90); do [ -f /tmp/fixtures.json ] && break; sleep 1; done
cd ../STEM-SOLVIA-APP
SUPABASE_URL=http://127.0.0.1:3001 SUPABASE_ANON_KEY=$(python3 -c "import json;print(json.load(open('/tmp/fixtures.json'))['anon'])") ADMIN_EMAIL=root@x.com ADMIN_PASSWORD=pw npm run smoke
