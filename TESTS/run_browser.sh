#!/usr/bin/env bash
# Real-browser e2e: embedded Postgres + PostgREST + auth stand-in, built app served by vite preview, headless Chromium via puppeteer.
set -e; cd "$(dirname "$0")"; rm -f /tmp/fixtures.json
python3 rest_harness.py > /tmp/harness.log 2>&1 & HP=$!
trap 'kill $HP $PP 2>/dev/null; kill $(cat /tmp/postgrest.pid 2>/dev/null) 2>/dev/null; true' EXIT
for i in $(seq 1 90); do [ -f /tmp/fixtures.json ] && break; sleep 1; done
[ -f /tmp/fixtures.json ] || { echo "harness failed"; tail -20 /tmp/harness.log; exit 1; }
ANON=$(python3 -c "import json;print(json.load(open('/tmp/fixtures.json'))['anon'])")
cd ../STEM-SOLVIA-APP
VITE_SUPABASE_URL=http://127.0.0.1:3001 VITE_SUPABASE_ANON_KEY=$ANON npx vite build --outDir /tmp/e2e-dist --emptyOutDir >/dev/null 2>&1
npx vite preview --outDir /tmp/e2e-dist --port 4173 --strictPort >/dev/null 2>&1 & PP=$!
sleep 3; cd ../TESTS/browser && node e2e.mjs
