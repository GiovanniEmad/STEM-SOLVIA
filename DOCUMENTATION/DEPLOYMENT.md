# Deploy to Vercel
Push to GitHub → Import in Vercel → Framework Vite, root `STEM-SOLVIA-APP`, build `npm run build`, output `dist`. Add env vars VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY. Add a rewrite of all paths to `/index.html` (vercel.json is included) so deep links work. Then update Supabase Site URL/redirects to the Vercel domain.
