# STEM SOLVIA — Think. Solve. Evolve.
**Status: foundation build (v0.1), not the full spec.**
## Status v0.7
All features in the brief are implemented. Verified (details and limits in TESTS/README.md): production build; 17 unit tests (+ .xlsx re-opened with openpyxl); 84 database checks on real PostgreSQL; 29 full-stack tests (real supabase-js + PostgREST + RLS, real React components); 84 real-browser checks in headless Chromium (click-through of student and admin flows, real refresh/offline, responsive at 375/768/1280 px, light + dark, axe incl. colour contrast on every page); load check with 3,000 students / 120,000 answers.
Bugs found by that testing and fixed: question deletion failing for unpublished exams; exam page flashing unanswered state on resume; missing h1 / landmarks on several pages; unlabeled file input; mobile overflow on the import page; unlabeled theme toggle; exam screen now hides the main nav (distraction-free).
Includes: registration (DB-enforced), sign-in, password recovery, landing page, light/dark theme, student dashboard + charts, filterable library, exam intro, exam engine (server-timestamp stopwatch, autosave + retry, resume, mark-for-review, KaTeX, images, shuffling, server grading, scheduled release), practice (incl. retry-incorrect, collections), bookmarks, notifications, profile with approval-gated changes, leaderboards, admin console (overview, filtered analytics + CSV / native .xlsx export, exam & question-bank CRUD, option images, transactional JSON import with editable preview, schools/domains, requests, roles, announcements, audit log).
## Go live
Follow **DEPLOY-CHECKLIST.md** (Supabase → Vercel → `npm run smoke` → phone walk-through). `SUPABASE/all-in-one.sql` is migrations 001–005 in one file; `SUPABASE/first-admin.sql` creates your first super admin.
## Setup (details)
DOCUMENTATION/SUPABASE-SETUP.md → DATABASE-SETUP.md (migrations 001–005) → ADMIN-GUIDE.md → DEPLOYMENT.md.
## Not done / not verified (be aware)
- NOT verified on a live Supabase project: sign-up/verification/reset e-mails, real session refresh, Storage uploads, Vercel deployment. The test stack uses stand-ins (TESTS/README.md). Follow the hardening checklist in DOCUMENTATION/SECURITY.md before going live.
- NOT verified: Safari/Firefox/real phones, screen-reader use, concurrent-user load through the API.
- Not built: e-mail notifications (in-app only), CAPTCHA widget (configure in Supabase and add the widget), Tailwind (the UI is plain CSS with theme variables — a deliberate choice), cross-exam leaderboard normalisation (leaderboards compare one exam at a time by design).
- Visual design is clean and consistent but modest; a designer pass would raise it further.
