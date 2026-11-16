# Go-live checklist (≈30–45 minutes). Do these in order; tick each box.

## A. Supabase (supabase.com)
- [ ] 1. New project (choose the region closest to Egypt, e.g. Frankfurt). Save the database password.
- [ ] 2. SQL Editor → New query → paste **SUPABASE/all-in-one.sql** → Run. (Expect "Success"; if an error appears, send me the exact message.)
- [ ] 3. Authentication → Users → Add user → your admin e-mail + a strong password you choose → tick "Auto Confirm User".
- [ ] 4. SQL Editor → run **SUPABASE/first-admin.sql** (replace the e-mail). The last query must list your e-mail as `super_admin`.
- [ ] 5. Authentication → Providers → Email: "Confirm email" ON, minimum password length 8.
- [ ] 6. Authentication → URL Configuration: Site URL = your Vercel URL (set after step B3; you can come back); add Redirect URLs `<site>/dashboard` and `<site>/recover`.
- [ ] 7. Storage: confirm bucket `question-images` exists and is **private**.
- [ ] 8. Settings → API: copy **Project URL** and the **anon public** key (never the service_role key).
- [ ] 9. Follow DOCUMENTATION/SECURITY.md "Production hardening checklist" (SMTP, rate limits, CAPTCHA).

## B. Vercel (vercel.com)
- [ ] 1. Push this folder to a GitHub repo (do not commit any `.env`).
- [ ] 2. Vercel → Add New → Project → import the repo → **Root Directory = `STEM-SOLVIA-APP`**, Framework = Vite.
- [ ] 3. Environment Variables: `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` (from A8) → Deploy. Copy the live URL back into A6.

## C. Automated check against your live project (2 minutes)
```
cd STEM-SOLVIA-APP && npm install
SUPABASE_URL=https://YOUR.supabase.co SUPABASE_ANON_KEY=YOUR_ANON_KEY \
ADMIN_EMAIL=you@example.com ADMIN_PASSWORD='your password' SMOKE_STORAGE=1 SMOKE_SIGNUP=1 npm run smoke
```
Every line must say PASS. It checks that anonymous visitors cannot read private tables or call privileged functions, the admin can sign in and has a role, the private image bucket accepts only images and refuses anonymous access, and a sign-up with an unapproved e-mail domain is rejected.
(Windows PowerShell: set the variables with `$env:NAME="value"` first, then run `npm run smoke`.)

## D. 10-minute acceptance walk-through on a real phone
- [ ] Open `<your-url>/admin/login` → sign in → Schools tab → add each school's real e-mail domain.
- [ ] Import tab → download `mcq-template.json` → edit/paste your first real exam → Validate → Import → Exams tab → Publish.
- [ ] On a phone, open the site → Sign up with a real school e-mail → open the verification e-mail → sign in.
- [ ] Library → open the exam → answer two questions → close the browser tab → reopen → your answers and the stopwatch are still there.
- [ ] Turn on airplane mode → answer a question ("Save failed") → turn it off → it says "Saved".
- [ ] Submit → check the score. Admin → Analytics shows the attempt.
- [ ] Try dark mode (phone setting) and landscape orientation.
If anything in C or D fails, copy the FAIL line / a screenshot and send it to me.
