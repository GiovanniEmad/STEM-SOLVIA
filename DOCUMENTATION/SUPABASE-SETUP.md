# Supabase setup
1. Create a project. Auth → Providers: enable Email, with "Confirm email" ON. Auth → URL Configuration: set Site URL to your Vercel URL and add `<url>/dashboard` and `<url>/recover` to Redirect URLs.
2. SQL editor: run SUPABASE/migrations 001, 002, 003, 004 in order (see DATABASE-SETUP.md).
3. Storage: migration 004 creates the private `question-images` bucket (2 MB, PNG/JPEG/WebP). Check it exists under Storage.
4. Copy Project URL and anon key into `.env` (VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY). Never use the service_role key in the frontend.
5. Create the first super admin (ADMIN-GUIDE.md).
