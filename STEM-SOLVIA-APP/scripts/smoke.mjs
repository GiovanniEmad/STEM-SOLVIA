// Post-deploy smoke test against a LIVE Supabase project.  Usage:
//   SUPABASE_URL=https://xxxx.supabase.co SUPABASE_ANON_KEY=... [ADMIN_EMAIL=.. ADMIN_PASSWORD=..] [SMOKE_STORAGE=1] [SMOKE_SIGNUP=1] npm run smoke
// Non-destructive: only reads, plus (optional) one 1x1 PNG upload that is deleted again, and one sign-up attempt with an unapproved
// e-mail domain that MUST be rejected by the database trigger.
import {createClient} from '@supabase/supabase-js';
const {SUPABASE_URL:U,SUPABASE_ANON_KEY:K,ADMIN_EMAIL:AE,ADMIN_PASSWORD:AP}=process.env;
if(!U||!K){console.error('Set SUPABASE_URL and SUPABASE_ANON_KEY');process.exit(2);}
let pass=0,fail=0;const T=(n,c,x='')=>{c?pass++:fail++;console.log((c?'PASS ':'FAIL ')+n+(c?'':' | '+String(x).slice(0,200)));};
const mk=()=>createClient(U,K,{auth:{persistSession:false,autoRefreshToken:false}});
const anon=mk();
const rows=async(p)=>{const r=await p;return r.error?{err:r.error.message}:{n:(r.data||[]).length,data:r.data};};
const s=await rows(anon.from('schools').select('id,name').eq('active',true));T('schools are publicly readable (>=25 seeded)',s.n>=25,JSON.stringify(s).slice(0,120));
for(const t of ['profiles','question_keys','exam_attempts','student_answers','admin_audit_logs','notifications','user_roles','import_batches','profile_requests'])
  {const r=await rows(anon.from(t).select('*').limit(5));T(`anonymous cannot read ${t}`,r.n===0||!!r.err,JSON.stringify(r).slice(0,120));}
for(const [fn,a] of [['start_attempt',{p_exam:'00000000-0000-0000-0000-000000000000'}],['admin_stats',{}],['import_exam',{p:{},p_hash:'x'}],['submit_attempt',{p_attempt:'00000000-0000-0000-0000-000000000000'}]])
  {const r=await anon.rpc(fn,a);T(`anonymous cannot call ${fn}()`,!!r.error,JSON.stringify(r.data));}
T('anonymous cannot grant roles',!!(await anon.from('user_roles').insert({user_id:'00000000-0000-0000-0000-000000000000',role:'super_admin'})).error);
T('platform settings readable',(await rows(anon.from('platform_settings').select('*'))).n>=1);
if(process.env.SMOKE_SIGNUP==='1'){const sid=s.data[0].id;const r=await anon.auth.signUp({email:`smoke${Date.now()}@example.invalid`,password:'Passw0rd!smoke',options:{data:{full_name:'Smoke Test Bot User',phone:'01012345678',school_id:sid,grade:11}}});
  T('sign-up with an unapproved e-mail domain is rejected',!!r.error,'a user may have been created: '+JSON.stringify(r.data?.user?.email));}
if(AE&&AP){const a=mk();const si=await a.auth.signInWithPassword({email:AE,password:AP});T('admin can sign in',!si.error,si.error?.message);
  if(!si.error){const roles=await rows(a.from('user_roles').select('role'));T('admin has a role in user_roles',roles.n>=1,JSON.stringify(roles));
   const st=await a.rpc('admin_stats',{});T('admin_stats() works for admin',!st.error,st.error?.message);
   const an=await a.rpc('admin_analytics',{});T('admin_analytics() works for admin',!an.error,an.error?.message);
   T('admin can list exams',!(await a.from('exams').select('id').limit(1)).error);
   if(process.env.SMOKE_STORAGE==='1'){const png=Uint8Array.from(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==','base64'));const path=`smoke/${Date.now()}.png`;
     const up=await a.storage.from('question-images').upload(path,png,{contentType:'image/png'});T('admin can upload to the private question-images bucket',!up.error,up.error?.message);
     if(!up.error){const sg=await a.storage.from('question-images').createSignedUrl(path,60);T('signed URL is issued for an admin',!!sg.data?.signedUrl,sg.error?.message);
      const anonSg=await anon.storage.from('question-images').createSignedUrl(path,60);T('anonymous cannot get a signed URL',!anonSg.data?.signedUrl);
      const bad=await a.storage.from('question-images').upload(`smoke/${Date.now()}.html`,new Blob(['<script>']),{contentType:'text/html'});T('non-image uploads are rejected',!!bad.error);
      await a.storage.from('question-images').remove([path]);}}
   await a.auth.signOut();}}
else console.log('(skipping admin checks: set ADMIN_EMAIL and ADMIN_PASSWORD)');
console.log(`\n${pass}/${pass+fail} passed`);process.exit(fail?1:0);
