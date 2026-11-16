# Tests — what each proves, and what it does not
| Suite | Run | Count | Covers |
|---|---|---|---|
| Unit | `cd STEM-SOLVIA-APP && npm test` then `python3 TESTS/xlsx_check.py` | 17 | import validator, stopwatch maths, seeded shuffle, .xlsx writer (file re-opened with openpyxl), CSV formula-injection guard |
| Database | `python3 TESTS/db_test.py` | 84 | migrations 001–005 on real PostgreSQL: registration rules, transactional import, grading, RLS/role attacks, result release, analytics filters, storage policy |
| Full stack | `bash TESTS/run_integration.sh` | 29 | the app's real supabase-js queries → PostgREST → Postgres (RLS on); real Exam/Auth components in jsdom (stopwatch, autosave, pause/resume, mark, submit, refresh-resume, network failure + retry); axe scans |
| Real browser | `bash TESTS/run_browser.sh` | 84 | headless Chromium clicking through sign-in → dashboard → library → intro → exam (real refresh, offline/online, pause) → result → practice → sign-out → admin console (every tab, JSON import, publish, question create); responsive overflow at 375/768/1280 px; light + dark mode; axe **including colour contrast** on every page and admin tab |
| Load | `python3 TESTS/db_perf.py` | – | 3,000 students / 120,000 answers: heaviest query (unfiltered admin analytics) 96 ms, others < 15 ms, grading a 40-question attempt 4 ms |
| Smoke (live) | `npm run smoke` in STEM-SOLVIA-APP, see DEPLOY-CHECKLIST.md | 21 locally | post-deploy check of a real Supabase project; its logic is self-tested by `TESTS/run_smoke_selftest.sh` |
Screenshots from the browser run are in `TESTS/screenshots/`.

Prereqs: `pip install pgserver psycopg2-binary openpyxl`; the PostgREST static binary (github.com/PostgREST/postgrest/releases) saved as `/tmp/postgrest_bin` (or `$POSTGREST`); `npm install` in `STEM-SOLVIA-APP` and in `TESTS/browser`. Every run starts a fresh database.

## Stand-ins — results are NOT a live-Supabase guarantee
- GoTrue (auth server) is replaced by a tiny stub (password sign-in, `/user`, logout) and locally signed JWTs. Sign-up e-mails, verification and reset links, token refresh and rate limits are NOT exercised.
- Supabase Storage API is replaced by a plain `storage.objects` table: only the RLS policies are tested, not uploads, signed URLs or bucket size/MIME limits.
- `/rest/v1` is emulated by a proxy in front of PostgREST. Timings are for a local database (no network latency).
## Not covered
Safari/Firefox/real phones, screen-reader use, Vercel deployment, concurrent-user load through the API layer, e-mail delivery.
