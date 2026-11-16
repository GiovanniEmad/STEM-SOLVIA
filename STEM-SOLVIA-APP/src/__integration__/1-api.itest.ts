// Runs the app's real supabase-js queries against PostgREST + Postgres (RLS on). Needs TESTS/rest_harness.py running.
import {describe,it,expect} from 'vitest';import {createClient} from '@supabase/supabase-js';import fs from 'fs';
const F=JSON.parse(fs.readFileSync('/tmp/fixtures.json','utf8'));
const mk=(j?:string)=>createClient(F.url,F.anon,{global:{headers:{Authorization:'Bearer '+(j||F.anon)}},auth:{persistSession:false,autoRefreshToken:false}});
const s1=mk(F.s1.jwt),s2=mk(F.s2.jwt),adm=mk(F.admin.jwt),anon=mk();
const ok=async(p:PromiseLike<{data:any;error:any}>)=>{const r=await p;expect(r.error,JSON.stringify(r.error)).toBeNull();return r.data as any;};
const bad=async(p:PromiseLike<{data:any;error:any}>)=>{const r=await p;expect(r.error).not.toBeNull();};
const Q=F.q;let A='',DUP='';
describe('student flow',()=>{
 it('library query + counts + grade isolation',async()=>{
  const ex=await ok(s1.from('exams').select('id,title,academic_year,semester,difficulty,total_marks,created_at,subjects(name),exam_questions(count)').eq('published',true));
  expect(ex).toHaveLength(1);expect(ex[0].subjects.name).toBe('Physics');expect(ex[0].exam_questions[0].count).toBe(3);
  expect(await ok(s2.from('exams').select('id'))).toHaveLength(0);
  const i=await ok(s1.from('exams').select('title,description,instructions,suggested_minutes,total_marks,exam_questions(count)').eq('id',F.exam).single());expect(i.total_marks).toBe(4);});
 it('start, load questions without answer keys',async()=>{
  A=await ok(s1.rpc('start_attempt',{p_exam:F.exam}));expect(A).toMatch(/^[0-9a-f-]{36}$/);
  const eq=await ok(s1.from('exam_questions').select('position,questions(id,text,image_path,marks,question_options(opt_id,text,image_path))').eq('exam_id',F.exam).order('position'));
  expect(eq).toHaveLength(3);expect(eq[0].questions.question_options).toHaveLength(4);expect(JSON.stringify(eq)).not.toMatch(/correct/i);
  const fl=await ok(s1.from('exams').select('shuffle_questions,shuffle_options').eq('id',F.exam).single());expect(fl.shuffle_questions).toBe(false);});
 it('answer, change, mark, pause, submit, grade',async()=>{
  for(const [q,o] of [['P1','A'],['P1','B'],['P2','B'],['P3','A']])await ok(s1.rpc('save_answer',{p_attempt:A,p_q:Q[q],p_opt:o}));
  expect(await ok(s1.from('student_answers').select('question_id,chosen_opt').eq('attempt_id',A))).toHaveLength(3);
  expect(await ok(s1.rpc('toggle_mark',{p_attempt:A,p_q:Q.P3}))).toContain(Q.P3);
  await ok(s1.rpc('set_clock',{p_attempt:A,p_run:false}));
  const a=await ok(s1.from('exam_attempts').select('*').eq('id',A).single());expect(a.running_since).toBeNull();expect(a.status).toBe('in_progress');
  const r=await ok(s1.rpc('submit_attempt',{p_attempt:A}));expect(r).toMatchObject({score:3,total:4,correct:2,incorrect:1,unanswered:0,percentage:75});
  expect(r.review).toHaveLength(3);expect(r.review[0].correct_text).toBe("Ohm's Law");
  await bad(s1.rpc('submit_attempt',{p_attempt:A}));});
 it('dashboard, profile, notifications queries',async()=>{
  const p=await ok(s1.from('profiles').select('full_name,grade,schools(name)').single());expect(p.schools.name).toBe('Luxor STEM School');
  const st=await ok(s1.rpc('student_stats',{}));expect(st).toMatchObject({completed:1,avg:75});expect(st.by_subject[0].label).toBe('Physics');expect(st.history).toHaveLength(1);
  expect(await ok(s1.from('exam_attempts').select('id,exams(title)').eq('status','in_progress'))).toHaveLength(0);
  const n=await ok(s1.from('notifications').select('id,title,created_at,read').order('created_at',{ascending:false}).limit(5));expect(n[0].title).toBe('New exam published');
  await ok(s1.rpc('mark_read',{}));const c=await s1.from('notifications').select('id',{count:'exact',head:true}).eq('read',false);expect(c.count).toBe(0);
  const pf=await ok(s1.from('profiles').select('full_name,phone,grade,created_at,school_id,schools(name)').single());await ok(s1.rpc('update_profile',{p_name:'Ali Ahmed Hassan Omar',p_phone:pf.phone}));
  await bad(s1.rpc('update_profile',{p_name:'Too Short',p_phone:pf.phone}));await bad(s1.rpc('update_profile',{p_name:'Ali Ahmed Hassan Omar',p_phone:'123'}));
  await ok(s1.rpc('request_change',{p_school:F.school,p_grade:12}));expect(await ok(s1.from('profile_requests').select('status,grade').eq('status','pending'))).toHaveLength(1);});
 it('practice, bookmarks, collections',async()=>{
  const ps=await ok(s1.rpc('practice_set',{p_subject:null,p_topic:'',p_wrong:false,p_collection:null,p_limit:10}));expect(ps).toHaveLength(3);expect(JSON.stringify(ps)).not.toMatch(/correct/i);
  const pc=await ok(s1.rpc('practice_check',{p_q:Q.P1,p_opt:'A'}));expect(pc).toMatchObject({correct:false,correct_opt:'B'});
  expect(await ok(s1.rpc('practice_set',{p_subject:null,p_topic:'',p_wrong:true,p_collection:null,p_limit:10}))).toHaveLength(1);
  await ok(s1.from('bookmarks').insert({question_id:Q.P2}));expect(await ok(s1.from('bookmarks').select('question_id,questions(text)'))).toHaveLength(1);
  const col=await ok(s1.from('collections').insert({name:'Mine'}).select('id').single());await ok(s1.from('collection_items').insert({collection_id:col.id,question_id:Q.P2}));
  const cs=await ok(s1.from('collections').select('id,name,collection_items(question_id,questions(text))'));expect(cs[0].collection_items).toHaveLength(1);
  expect(await ok(s1.rpc('practice_set',{p_subject:null,p_topic:'',p_wrong:false,p_collection:col.id,p_limit:10}))).toHaveLength(1);
  await ok(s1.from('collections').update({name:'Renamed'}).eq('id',col.id));await ok(s1.from('collection_items').delete().eq('collection_id',col.id));await ok(s1.from('collections').delete().eq('id',col.id));
  await ok(s1.from('bookmarks').delete().eq('question_id',Q.P2));
  const lb=await ok(s1.rpc('leaderboard',{p_scope:'grade',p_exam:F.exam}));expect(lb.rows[0].name).toBe('Ali A.');await bad(s2.rpc('leaderboard',{p_scope:'national',p_exam:F.exam}));});
 it('attacks via the REST API fail',async()=>{
  expect(await ok(s1.from('question_keys').select('*'))).toHaveLength(0);
  expect(await ok(s1.from('exam_attempts').update({score:999}).eq('id',A).select())).toHaveLength(0);
  expect((await ok(s1.from('exam_attempts').select('score').eq('id',A).single())).score).toBe(3);
  await bad(s1.from('student_answers').insert({attempt_id:A,question_id:Q.P3,chosen_opt:'B'}));
  await bad(s1.from('user_roles').insert({user_id:F.s1.id,role:'super_admin'}));await bad(s1.rpc('admin_stats',{}));await bad(s1.rpc('import_exam',{p:{},p_hash:'x'}));
  expect(await ok(s1.from('admin_audit_logs').select('*'))).toHaveLength(0);expect(await ok(s1.from('profiles').select('id'))).toHaveLength(1);
  await bad(anon.rpc('start_attempt',{p_exam:F.exam}));await bad(s1.from('profiles').update({grade:12}).eq('id',F.s1.id).select().then(r=>({data:r.data,error:r.data?.length?null:{m:'none'}})));});
});
describe('admin flow',()=>{
 it('roles, stats, exams, question bank queries',async()=>{
  expect(await ok(adm.from('user_roles').select('role'))).toEqual([{role:'super_admin'}]);
  const s=await ok(adm.rpc('admin_stats',{}));expect(s).toMatchObject({students:3,exams:1,published:1,questions:3,submitted:1});
  const ex=await ok(adm.from('exams').select('id,title,grade,published,total_marks,practice_enabled,show_answers,allow_retakes,results_mode,shuffle_questions,shuffle_options,results_release_at,exam_assignments(school_id)'));expect(ex[0].exam_assignments).toEqual([]);
  const qs=await ok(adm.from('questions').select('id,text,topic,difficulty,marks,explanation,image_path,created_at,question_options(opt_id,text,image_path),question_keys(correct_opt)').order('created_at',{ascending:false}).range(0,19).ilike('text','%Question%'));
  const k=Array.isArray(qs[0].question_keys)?qs[0].question_keys[0]:qs[0].question_keys;expect(k.correct_opt).toBe('B');
  const pv=await ok(adm.from('exam_questions').select('position,questions(text,question_options(opt_id,text),question_keys(correct_opt))').eq('exam_id',F.exam).order('position'));expect(pv).toHaveLength(3);});
 it('exam management RPCs on a duplicate',async()=>{
  DUP=await ok(adm.rpc('duplicate_exam',{p_exam:F.exam}));
  await ok(adm.rpc('set_exam_flags',{p_exam:DUP,p_practice:true,p_show:true,p_mode:'immediate',p_retakes:false}));
  await ok(adm.rpc('set_exam_options',{p_exam:DUP,p_shuf_q:true,p_shuf_o:true,p_release:new Date(Date.now()+86400000).toISOString()}));
  await ok(adm.rpc('set_exam_meta',{p_exam:DUP,p_title:'Dup exam',p_instructions:'Read carefully'}));
  await ok(adm.rpc('set_assignments',{p_exam:DUP,p_schools:[F.school]}));
  const q=await ok(adm.rpc('create_question',{p_text:'New $x^2$?',p_options:[{id:'A',text:'1'},{id:'B',text:'2'}],p_correct:'B',p_marks:2,p_topic:'T',p_diff:'Easy',p_expl:'e',p_image:'',p_exam:DUP}));
  await ok(adm.rpc('admin_update_question',{p_q:q,p_text:'Edited',p_expl:'e2',p_marks:3,p_topic:'T',p_diff:'Hard',p_image:'',p_correct:'A'}));
  await ok(adm.rpc('set_option',{p_q:q,p_opt:'A',p_text:'One',p_image:''}));await bad(adm.rpc('delete_question',{p_q:Q.P1}));
  await ok(adm.rpc('delete_question',{p_q:q}));await ok(adm.rpc('set_published',{p_exam:DUP,p_pub:true}));await ok(adm.rpc('set_published',{p_exam:DUP,p_pub:false}));
  await ok(adm.rpc('delete_exam',{p_exam:DUP}));await bad(adm.rpc('delete_exam',{p_exam:F.exam}));});
 it('import via REST: valid, duplicate, invalid',async()=>{
  const d={exam:{title:'Imp',grade:'Grade 10',subject:'Chemistry',academic_year:'2025-2026',semester:'First',difficulty:'Easy'},questions:[{question_id:'C1',question_text:'q',question_type:'MCQ',options:[{id:'A',text:'a'},{id:'B',text:'b'}],correct_answer:'A',marks:1}]};
  const r=await ok(adm.rpc('import_exam',{p:d,p_hash:'h1'}));expect(r).toMatchObject({total:1,imported:1});await bad(adm.rpc('import_exam',{p:d,p_hash:'h1'}));
  await bad(adm.rpc('import_exam',{p:{...d,questions:[{...d.questions[0],correct_answer:'Z'}]},p_hash:'h2'}));});
 it('schools, domains, analytics, announcements, roles, audit',async()=>{
  expect((await ok(adm.from('schools').select('id,name,active').order('name'))).length).toBe(25);await ok(adm.from('school_domains').select('id,school_id,domain'));
  const sid=await ok(adm.rpc('upsert_school',{p_id:null,p_name:'Test School',p_active:true}));await ok(adm.rpc('add_domain',{p_school:sid,p_domain:'test.edu.eg'}));await bad(adm.rpc('add_domain',{p_school:sid,p_domain:'bad domain'}));
  const an=await ok(adm.rpc('admin_analytics',{p_from:null,p_to:null,p_school:null,p_grade:11,p_year:null}));expect(an.by_grade).toHaveLength(1);expect(an.by_exam.length).toBeGreaterThan(0);
  expect((await ok(adm.rpc('admin_analytics',{p_from:'2999-01-01',p_to:null,p_school:null,p_grade:null,p_year:null}))).by_grade).toEqual([]);
  await ok(adm.rpc('send_announcement',{p_title:'Hi',p_body:'b',p_grade:null}));await ok(adm.rpc('set_setting',{p_key:'leaderboards_enabled',p_value:true}));
  expect(await ok(adm.rpc('list_admins',{}))).toHaveLength(1);await bad(adm.rpc('revoke_role',{p_user:F.admin.id,p_role:'super_admin'}));
  expect((await ok(adm.from('admin_audit_logs').select('*').order('id',{ascending:false}).limit(100))).length).toBeGreaterThan(10);});
 it('change request approval (last: it moves S1 to grade 12)',async()=>{
  const r=await ok(adm.from('profile_requests').select('id,grade,status,profiles(full_name),schools(name)').eq('status','pending'));expect(r[0].profiles.full_name).toBe('Ali Ahmed Hassan Omar');
  await ok(adm.rpc('decide_request',{p_id:r[0].id,p_ok:true}));expect((await ok(adm.from('profiles').select('grade').eq('id',F.s1.id).single())).grade).toBe(12);});
});
