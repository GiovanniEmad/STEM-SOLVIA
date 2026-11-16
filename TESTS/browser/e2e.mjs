import fs from 'fs';import chromium from '@sparticuz/chromium';import puppeteer from 'puppeteer-core';
const F=JSON.parse(fs.readFileSync('/tmp/fixtures.json','utf8'));
const axeSrc=fs.readFileSync(new URL('./node_modules/axe-core/axe.min.js',import.meta.url),'utf8');
const tpl=JSON.parse(fs.readFileSync(new URL('../../JSON-TEMPLATES/mcq-template.json',import.meta.url),'utf8'));
const BASE='http://127.0.0.1:4173',SHOT=new URL('../screenshots/',import.meta.url).pathname;fs.mkdirSync(SHOT,{recursive:true});
let pass=0,fail=0;const T=(n,c,x='')=>{c?pass++:fail++;console.log((c?'PASS ':'FAIL ')+n+(c?'':' | '+String(x).slice(0,400)));};
const b=await puppeteer.launch({args:[...chromium.args,'--no-sandbox'],executablePath:await chromium.executablePath(),headless:'shell'});
const page=await b.newPage();const errs=[];page.on('pageerror',e=>errs.push(e.message));page.on('console',m=>{if(m.type()==='error'&&!/Failed to load resource|net::ERR|Failed to fetch/.test(m.text()))errs.push(m.text());});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const go=async p=>{await page.goto(BASE+p,{waitUntil:'networkidle0'});};
const waitText=async(t,ms=15000)=>{try{await page.waitForFunction(t=>document.body.innerText.includes(t),{timeout:ms},t);return true;}catch{return false;}};
const clickText=async(sel,t)=>{const h=await page.evaluateHandle((s,t)=>[...document.querySelectorAll(s)].find(e=>e.textContent.trim()===t&&!e.disabled),sel,t);const el=h.asElement();if(!el)throw new Error('missing '+sel+' "'+t+'"');await el.click();};
const field=async(label,exact)=>{const h=await page.evaluateHandle((l,x)=>{const e=[...document.querySelectorAll('label')].find(e=>x?e.textContent.trim()===l:e.textContent.trim().startsWith(l));return e&&e.querySelector('input,select,textarea');},label,!!exact);return h.asElement();};
const fill=async(label,v,exact)=>{const el=await field(label,exact);if(!el)throw new Error('no field '+label);await el.click({clickCount:3});await el.type(v);};
const setValue=async(sel,v)=>page.evaluate((s,v)=>{const e=document.querySelector(s);const set=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(e),'value').set;set.call(e,v);e.dispatchEvent(new Event('input',{bubbles:true}));},sel,v);
const scheme=async v=>page.emulateMediaFeatures([{name:'prefers-color-scheme',value:v}]);
const axe=async name=>{await page.evaluate(axeSrc);const v=await page.evaluate(async()=>{const r=await axe.run(document,{resultTypes:['violations']});return r.violations.map(x=>x.id+' ('+x.impact+') x'+x.nodes.length+': '+x.nodes[0].html.slice(0,90)+' || '+((x.nodes[0].any[0]||x.nodes[0].all[0]||{}).message||'').slice(0,110));});T('axe '+name,v.length===0,v.join(' ;; '));};
const overflow=async name=>{const o=await page.evaluate(()=>document.documentElement.scrollWidth-window.innerWidth);let who='';if(o>0)who=await page.evaluate(()=>[...document.querySelectorAll('body *')].filter(e=>e.getBoundingClientRect().right>window.innerWidth+0.5).slice(0,4).map(e=>e.tagName+'.'+e.className+' '+Math.round(e.getBoundingClientRect().right)+' '+(e.textContent||'').slice(0,30)).join(' | '));T('no horizontal overflow '+name,o<=0,o+' '+who);};
const tab=async t=>{try{await clickText('button',t);}catch{}};
const shot=n=>page.screenshot({path:SHOT+n+'.png'});
const secs=async()=>{const t=await page.evaluate(()=>document.body.innerText);const m=t.match(/⏱ (\d\d):(\d\d):(\d\d)/);return m?(+m[1])*3600+(+m[2])*60+(+m[3]):-1;};
try{
 // ---- landing: responsive + themes
 for(const [w,h] of [[375,812],[768,1024],[1280,800]]){await page.setViewport({width:w,height:h});await go('/');await overflow('home '+w);}
 await page.setViewport({width:375,height:812});await scheme('light');await go('/');await shot('home-mobile-light');await axe('home light');
 await scheme('dark');await go('/');T('dark mode applies dark background',(await page.evaluate(()=>getComputedStyle(document.body).backgroundColor))==='rgb(14, 21, 18)');await shot('home-mobile-dark');await axe('home dark');
 await scheme('light');
 // ---- sign in (real form)
 await page.setViewport({width:1280,height:800});await go('/auth');await axe('sign-in light');await scheme('dark');await go('/auth');await axe('sign-in dark');await scheme('light');await go('/auth');
 await fill('School email','a.1@stemluxor.moe.edu.eg');await fill('Password','wrong');await clickText('button','Sign in');T('wrong password shows error',await waitText('Invalid login credentials'));
 await fill('Password','pw');await clickText('button','Sign in');T('sign-in redirects to dashboard',await waitText('Welcome, Ali'));
 await go('/dashboard');await shot('dashboard-desktop');
 for(const sch of ['light','dark']){await scheme(sch);for(const p of ['/dashboard','/exams','/practice','/saved','/profile','/notifications','/leaderboard']){await go(p);await sleep(500);await axe(p+' '+sch);}}
 await scheme('light');
 // ---- navigate like a student: dashboard -> exams -> intro -> exam
 await go('/dashboard');await clickText('a','Exams');T('library lists the exam',await waitText('Grade 11 Physics Examination'));
 await clickText('button','Open');T('intro screen',await waitText('Start or continue'));await clickText('button','Start or continue');T('exam opens',await waitText('Question 1: what is'));
 // ---- exam on a phone
 await page.setViewport({width:375,height:812});await go(page.url().replace(BASE,''));await waitText('Question 1: what is');await overflow('exam mobile');await shot('exam-mobile-light');
 await scheme('dark');await go(page.url().replace(BASE,''));await waitText('Question 1: what is');await axe('exam dark');await shot('exam-mobile-dark');await scheme('light');await go(page.url().replace(BASE,''));await waitText('Question 1: what is');await axe('exam light');
 const pick=async re=>{await page.evaluate(src=>{const l=[...document.querySelectorAll('label')].find(e=>new RegExp(src).test(e.textContent));l.querySelector('input').click();},re);};
 await pick("Ohm's Law");T('answer autosaves',await waitText('Saved'));await sleep(2500);const t0=await secs();
 await page.reload({waitUntil:'networkidle0'});await waitText('Question 1: what is');
 T('answer restored after real page refresh',await page.evaluate(()=>[...document.querySelectorAll('label')].find(e=>/Ohm's Law/.test(e.textContent)).querySelector('input').checked));
 const t1=await secs();T('stopwatch kept running across refresh (counts up)',t1>=t0&&t0>=2,`${t0}->${t1}`);
 await clickText('button','Pause');await waitText('(paused)');await sleep(2200);await page.reload({waitUntil:'networkidle0'});await waitText('(paused)');const p1=await secs();await sleep(2200);T('paused clock stays frozen after refresh',(await secs())===p1,p1);
 await clickText('button','Resume');await waitText('Pause');
 await page.setOfflineMode(true);await pick('Faraday');T('offline answer shows failure',await waitText('Save failed',8000));
 await page.setOfflineMode(false);T('autosave recovers when back online',await waitText('Saved',15000));
 await clickText('button','Mark for review');await clickText('button','Next');await pick("Ohm's Law");await sleep(1200);await clickText('button','Submit');
 T('submit dialog shows counts',await waitText('Total 3 · Answered 2 · Unanswered 1 · Marked 1'));await clickText('button','Confirm submit');
 T('exam screen hides the main navigation (distraction-free)',await page.evaluate(()=>!document.body.innerText.includes('Leaderboard')));T('server-graded result shown',await waitText('Score 2/4'),await page.evaluate(()=>document.body.innerText.slice(0,200)));await shot('result-mobile');await axe('result');
 // ---- practice in browser
 await page.setViewport({width:1280,height:800});await go('/practice');await clickText('button','Start');await waitText('1/');await pick('Faraday');T('practice gives immediate feedback',await waitText('Incorrect')||await waitText('Correct'));
 // ---- sign out
 await clickText('button','Sign out');await page.waitForFunction(()=>location.pathname==='/',{timeout:10000});await go('/dashboard');T('signed-out user is sent to sign-in',page.url().includes('/auth'),page.url());
 // ---- admin console
 await go('/admin/login');await axe('admin login');await fill('Email','root@x.com');await fill('Password','pw');await clickText('button','Sign in');T('admin sign-in',await waitText('Admin (super_admin)'));
 T('overview shows real stats',await waitText('Students'));await shot('admin-overview');
 const tabs=['overview','analytics','exams','questions','import','schools','requests','users','settings','audit'];
 for(const sch of ['light','dark']){await scheme(sch);await go('/admin');await waitText('Admin (super_admin)');for(const t of tabs){await tab(t);await sleep(700);await axe('admin '+t+' '+sch);}}
 await scheme('light');await page.setViewport({width:375,height:812});await go('/admin');await waitText('Admin (super_admin)');for(const t of tabs){await tab(t);await sleep(400);await overflow('admin '+t+' mobile');}
 await page.setViewport({width:1280,height:800});
 // import through the UI
 const doc={exam:{...tpl.exam,title:'Browser Imported Exam',grade:'Grade 10',subject:'Chemistry'},questions:[{...tpl.questions[0],question_id:'B1'}]};
 await clickText('button','import');await setValue('textarea[aria-label="JSON"]',JSON.stringify(doc));await clickText('button','Validate & preview');T('import preview valid',await waitText('Valid: 1 questions'));
 await page.evaluate(()=>{});const marks=await page.$('input[aria-label="Marks"]');await marks.click({clickCount:3});await marks.type('3');
 await clickText('button','Import (creates an unpublished exam)');T('import report shown',await waitText('Import report: 1/1 imported'));
 await setValue('textarea[aria-label="JSON"]','{bad');await clickText('button','Validate & preview');T('invalid JSON shows error',await waitText('Invalid JSON'));
 await clickText('button','exams');T('imported exam listed as draft',await waitText('Browser Imported Exam'));
 await page.evaluate(()=>{const c=[...document.querySelectorAll('.card')].find(e=>e.textContent.includes('Browser Imported Exam'));[...c.querySelectorAll('button')].find(x=>x.textContent==='Publish').click();});T('publish from UI',await waitText('Published'));
 // question bank create via UI
 await clickText('button','questions');await clickText('button','New MCQ');await setValue('textarea[aria-label="Question text"]','Browser created question $x^2$?');
 await fill('A','Yes',true);await fill('B','No',true);await clickText('button','Save');T('question created and listed',await waitText('Browser created question'));
 await clickText('button','schools');await fill('New school','Browser School',false).catch(async()=>{await page.type('input[aria-label="New school"]','Browser School');});
 await clickText('button','analytics');T('analytics reflects the submitted attempt',await waitText('Grade 11 Physics Examination'));
 await clickText('button','audit');T('audit log shows import',await waitText('import_exam'));
 await clickText('button','Sign out');
 T('no uncaught page errors',errs.length===0,errs.join(' | '));
}catch(e){T('script completed without exception',false,e.stack||e.message);try{await shot('failure');}catch{}}
await b.close();console.log(`\n${pass}/${pass+fail} passed`);process.exit(fail?1:0);
