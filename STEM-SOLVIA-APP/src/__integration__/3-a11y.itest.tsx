// @vitest-environment jsdom
// axe-core on every student page with real data. Colour-contrast cannot be judged in jsdom (needs a real browser) and is disabled.
import {describe,it,expect,vi,afterEach} from 'vitest';import {render,cleanup} from '@testing-library/react';import {MemoryRouter,Routes,Route} from 'react-router-dom';import axe from 'axe-core';import {createClient} from '@supabase/supabase-js';
vi.mock('../lib/supabase',async()=>{const {createClient}=await import('@supabase/supabase-js');const fs=await import('fs');const F=JSON.parse(fs.readFileSync('/tmp/fixtures.json','utf8'));
 const c:any=createClient(F.url,F.anon,{global:{headers:{Authorization:'Bearer '+F.s3.jwt}},auth:{persistSession:false,autoRefreshToken:false}});
 return{supabase:new Proxy({},{get:(_,k)=>{const v=c[k];return typeof v==='function'?v.bind(c):v;}})};});
import Home from '../pages/Home';import Auth from '../pages/Auth';import Exam from '../pages/Exam';import Library from '../pages/Library';import Dashboard from '../pages/Dashboard';import Practice from '../pages/Practice';import Saved from '../pages/Saved';import Profile from '../pages/Profile';import Notifications from '../pages/Notifications';import Leaderboard from '../pages/Leaderboard';import Recover from '../pages/Recover';import Intro from '../pages/Intro';
import fs from 'fs';const F=JSON.parse(fs.readFileSync('/tmp/fixtures.json','utf8'));
const s3=createClient(F.url,F.anon,{global:{headers:{Authorization:'Bearer '+F.s3.jwt}},auth:{persistSession:false}});
afterEach(cleanup);
async function check(el:JSX.Element,path='/'){const {container}=render(<MemoryRouter initialEntries={[path]}><Routes><Route path="*" element={el}/></Routes></MemoryRouter>);
 await new Promise(r=>setTimeout(r,1500));
 const r=await axe.run(container,{rules:{'color-contrast':{enabled:false}},resultTypes:['violations']});
 return r.violations.map(v=>`${v.id} (${v.impact}): ${v.nodes.slice(0,2).map(n=>n.html.slice(0,90)).join(' | ')}`);}
describe('axe accessibility (no violations expected)',()=>{
 it('home',async()=>expect(await check(<Home/>)).toEqual([]));
 it('sign-in',async()=>expect(await check(<Auth/>)).toEqual([]));
 it('recover',async()=>expect(await check(<Recover/>)).toEqual([]));
 it('library',async()=>expect(await check(<Library/>)).toEqual([]));
 it('intro',async()=>expect(await check(<Intro/>,'/intro/'+F.exam)).toEqual([]));
 it('dashboard',async()=>expect(await check(<Dashboard/>)).toEqual([]));
 it('practice',async()=>expect(await check(<Practice/>)).toEqual([]));
 it('saved',async()=>expect(await check(<Saved/>)).toEqual([]));
 it('profile',async()=>expect(await check(<Profile/>)).toEqual([]));
 it('notifications',async()=>expect(await check(<Notifications/>)).toEqual([]));
 it('leaderboard',async()=>expect(await check(<Leaderboard/>)).toEqual([]));
 it('exam in progress',async()=>{const A=(await s3.rpc('start_attempt',{p_exam:F.exam})).data as string;expect(await check(<Exam/>,'/exam/'+A)).toEqual([]);});
});
