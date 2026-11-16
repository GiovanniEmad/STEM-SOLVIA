// @vitest-environment jsdom
// Renders the real Exam and Auth pages in jsdom against PostgREST/Postgres (RLS on).
import {describe,it,expect,vi,afterEach} from 'vitest';import {render,screen,fireEvent,waitFor,cleanup} from '@testing-library/react';import {MemoryRouter,Routes,Route} from 'react-router-dom';import {createClient} from '@supabase/supabase-js';
vi.mock('../lib/supabase',async()=>{const {createClient}=await import('@supabase/supabase-js');const fs=await import('fs');const F=JSON.parse(fs.readFileSync('/tmp/fixtures.json','utf8'));
 const mk=(j:string)=>createClient(F.url,F.anon,{global:{headers:{Authorization:'Bearer '+j},fetch:(u:any,o:any)=>{if((globalThis as any).__fail&&String(u).includes('save_answer'))return Promise.reject(new TypeError('Failed to fetch'));return fetch(u,o);}},auth:{persistSession:false,autoRefreshToken:false}});
 const cs:any={s1:mk(F.s1.jwt),s3:mk(F.s3.jwt)};(globalThis as any).__who='s3';
 return{supabase:new Proxy({},{get:(_,k)=>{const c=cs[(globalThis as any).__who];const v=c[k];return typeof v==='function'?v.bind(c):v;}})};});
import Exam from '../pages/Exam';import Auth from '../pages/Auth';
import fs from 'fs';const F=JSON.parse(fs.readFileSync('/tmp/fixtures.json','utf8'));
const s3=createClient(F.url,F.anon,{global:{headers:{Authorization:'Bearer '+F.s3.jwt}},auth:{persistSession:false}});
const show=(id:string)=>render(<MemoryRouter initialEntries={['/exam/'+id]}><Routes><Route path="/exam/:id" element={<Exam/>}/></Routes></MemoryRouter>);
const answers=async(A:string)=>(await s3.from('student_answers').select('question_id,chosen_opt').eq('attempt_id',A)).data||[];
afterEach(()=>{cleanup();(globalThis as any).__fail=false;});
const T=15000;
describe('exam page (real components, real API)',()=>{
 it('full flow: stopwatch, autosave, pause/resume, mark, submit dialog, server grade',async()=>{
  const A=(await s3.rpc('start_attempt',{p_exam:F.exam})).data as string;show(A);
  await screen.findByText(/Question 1: what is/);expect(screen.getByText(/⏱ 00:00:0\d/)).toBeTruthy();expect(screen.queryByText(/Ohm's Law/)).toBeTruthy();
  fireEvent.click(screen.getByLabelText(/Ohm's Law/));
  await waitFor(async()=>expect((await answers(A))[0]?.chosen_opt).toBe('B'),{timeout:T});await screen.findByText('Saved');
  fireEvent.click(screen.getByText('Pause'));await screen.findByText('Resume');expect(screen.getByText(/\(paused\)/)).toBeTruthy();
  expect((screen.getByLabelText(/Ohm's Law/) as HTMLInputElement).disabled).toBe(true);
  fireEvent.click(screen.getByText('Resume'));await screen.findByText('Pause');
  fireEvent.click(screen.getByText('Mark for review'));await screen.findByText('Unmark review');
  fireEvent.click(screen.getByText('Next'));await screen.findByText(/Question 2: what is/);fireEvent.click(screen.getByLabelText(/Ohm's Law/));
  await waitFor(async()=>expect(await answers(A)).toHaveLength(2),{timeout:T});
  fireEvent.click(screen.getByText('Next'));await screen.findByText(/Question 3: what is/);
  fireEvent.click(screen.getByText('Submit'));await screen.findByText(/Total 3 · Answered 2 · Unanswered 1 · Marked 1/);
  fireEvent.click(screen.getByText('Confirm submit'));await screen.findByText(/Score 3\/4 \(75%\)/,{},{timeout:T});
  expect(screen.getByText(/Correct 2 · Incorrect 0 · Unanswered 1/)).toBeTruthy();
  const a=(await s3.from('exam_attempts').select('status,score').eq('id',A).single()).data;expect(a).toEqual({status:'submitted',score:3});},40000);
 it('resumes after a refresh with saved answer, marks and elapsed time; survives a network failure',async()=>{
  const A=(await s3.rpc('start_attempt',{p_exam:F.exam})).data as string;
  await s3.rpc('save_answer',{p_attempt:A,p_q:F.q.P1,p_opt:'A'});await s3.rpc('toggle_mark',{p_attempt:A,p_q:F.q.P1});
  await new Promise(r=>setTimeout(r,2300));await s3.rpc('set_clock',{p_attempt:A,p_run:false});
  show(A);await screen.findByText(/Question 1: what is/);
  expect(screen.getByText(/⏱ 00:00:0[2-9]/)).toBeTruthy();expect(screen.getByText(/\(paused\)/)).toBeTruthy();
  expect((screen.getByLabelText(/Newton's First Law/) as HTMLInputElement).checked).toBe(true);expect(screen.getByText('Unmark review')).toBeTruthy();
  fireEvent.click(screen.getByText('Resume'));await screen.findByText('Pause');
  expect((await s3.from('exam_attempts').select('running_since').eq('id',A).single()).data?.running_since).not.toBeNull();
  (globalThis as any).__fail=true;fireEvent.click(screen.getByLabelText(/Faraday's Law/));
  await screen.findByText(/Save failed/,{},{timeout:T});expect((await answers(A)).find((x:any)=>x.question_id===F.q.P1)?.chosen_opt).toBe('A');
  (globalThis as any).__fail=false;await screen.findByText('Saved',{},{timeout:T});
  expect((await answers(A)).find((x:any)=>x.question_id===F.q.P1)?.chosen_opt).toBe('C');
  await new Promise(r=>setTimeout(r,1500));
  const el=screen.getByText(/⏱/).textContent||'';expect(el).toMatch(/⏱ 00:00:0[4-9]|⏱ 00:00:[1-5]\d/);},60000);
});
describe('sign-up form (real component, real schools/domains)',()=>{
 const fill=async(o:any)=>{render(<MemoryRouter><Auth/></MemoryRouter>);fireEvent.click(screen.getByText('Need an account?'));
  await waitFor(()=>expect(screen.getByLabelText('School').querySelectorAll('option').length).toBeGreaterThanOrEqual(26),{timeout:T});
  const sch=[...screen.getByLabelText('School').querySelectorAll('option')].find(x=>x.textContent==='Luxor STEM School')!.value;
  const set=(l:string,v:string)=>fireEvent.change(screen.getByLabelText(l),{target:{value:v}});
  set('Full name (4 names)',o.name);set('Phone',o.phone);set('School',sch);set('School email',o.email);set('Password',o.pw);set('Confirm password',o.pw2);
  fireEvent.click(screen.getByText('Create account'));};
 const ok={name:'Ali Ahmed Hassan Omar',phone:'01275856450',email:'new@stemluxor.moe.edu.eg',pw:'password1',pw2:'password1'};
 it('lists the 25 seeded schools',async()=>{await fill({...ok,name:'A B C'});await screen.findByText('Enter four names.');});
 it('rejects bad phone',async()=>{await fill({...ok,phone:'123'});await screen.findByText('Invalid Egyptian phone number.');});
 it('rejects short/mismatched passwords',async()=>{await fill({...ok,pw2:'different1'});await screen.findByText(/Password: min 8 chars and must match/);});
 it('rejects unapproved email domain (real DB lookup)',async()=>{await fill({...ok,email:'x@gmail.com'});await screen.findByText('Email domain is not approved for this school.',{},{timeout:T});});
});
