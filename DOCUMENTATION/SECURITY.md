# Security (as implemented in v0.3)
- Answer keys: `question_keys` has policies only for exam-manager roles; students never read it.
- Students have no INSERT/UPDATE on attempts or answers; all writes go via SECURITY DEFINER functions that check ownership, exam membership, attempt status. Execute is revoked from `anon`.
- Admin functions (`import_exam`, `set_published`, `admin_stats`) re-check roles in SQL. The /admin UI role check is convenience only.
- `import_exam` is one transaction: any invalid question aborts the whole import. Identical files are rejected by SHA-256.
- Audit log: written only by those functions; readable by super_admin; UPDATE/DELETE revoked.
- Not implemented: storage policies, results_manager scoped reads of attempts beyond stats, rate limiting. Untested against a live database.

## v0.5 additions
- Migrations verified on a real PostgreSQL (83 checks, TESTS/db_test.py): students cannot read keys, forge scores/status, write answers directly, self-grant roles, read others' attempts/collections, call admin RPCs, or edit the audit log; registration enforces four names, Egyptian phone and school-specific domain in the database.
- Image reads require the file to be attached to a question/option the user can see. A student who learns a path to an unattached file still cannot read it.
- Remaining risk: not exercised against live Supabase (GoTrue/Storage API/PostgREST); no rate limiting; no CAPTCHA on sign-up.

## Production hardening checklist (settings on Supabase/Vercel, not code)
1. Auth → Providers → Email: keep "Confirm email" ON; set minimum password length 8+ and enable leaked-password protection if your plan offers it.
2. Auth → Rate Limits: lower sign-up / sign-in / password-recovery limits; enable CAPTCHA (Cloudflare Turnstile or hCaptcha) under Auth → Attack Protection. (The app does not render a CAPTCHA widget; if you enable CAPTCHA in Supabase you must add the widget and pass its token to `signUp`/`signInWithPassword`.)
3. Auth → SMTP: configure your own SMTP server; the built-in mailer is rate-limited and for testing only.
4. Auth → URL Configuration: Site URL + redirect URLs set to your production domain only.
5. Never expose the service_role key; rotate the anon key if it ever leaks (it is public by design, RLS is the protection).
6. Create the first super admin with a strong unique password; remove any shared/default credentials.
7. Database → enable daily backups / PITR; review `admin_audit_logs` periodically.
E-mail notifications for new exams/results are not implemented (in-app only). To add them, use a Supabase Database Webhook on `notifications` inserts → an Edge Function that sends via your mail provider.
