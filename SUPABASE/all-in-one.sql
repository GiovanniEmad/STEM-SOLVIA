-- STEM SOLVIA: all migrations in order (001-005). Paste into Supabase SQL Editor and run once on a NEW project.

-- ===== 001_schema.sql =====
create table schools(id uuid primary key default gen_random_uuid(),name text unique not null,active boolean default true,created_at timestamptz default now());
create table school_domains(id uuid primary key default gen_random_uuid(),school_id uuid not null references schools on delete cascade,domain text not null unique);
create table profiles(id uuid primary key references auth.users on delete cascade,full_name text not null,phone text not null,school_id uuid references schools,grade smallint not null check(grade in(10,11,12)),created_at timestamptz default now());
create table user_roles(user_id uuid references auth.users on delete cascade,role text not null check(role in('super_admin','admin','exam_manager','results_manager')),primary key(user_id,role));
create table subjects(id uuid primary key default gen_random_uuid(),name text unique not null);
create table exams(id uuid primary key default gen_random_uuid(),title text not null,description text,grade smallint not null check(grade in(10,11,12)),subject_id uuid references subjects,academic_year text,semester text,difficulty text,total_marks numeric,suggested_minutes int,published boolean default false,allow_retakes boolean default false,show_answers boolean default true,created_at timestamptz default now());
create index on exams(grade,published);
create table questions(id uuid primary key default gen_random_uuid(),external_id text,text text not null,image_path text,explanation text,marks numeric not null check(marks>0),difficulty text,topic text,batch_id uuid,created_at timestamptz default now());
create table question_options(question_id uuid references questions on delete cascade,opt_id text not null,text text not null,primary key(question_id,opt_id));
-- correct answers live apart: no student policy exists on this table
create table question_keys(question_id uuid primary key references questions on delete cascade,correct_opt text not null);
create table exam_questions(exam_id uuid references exams on delete cascade,question_id uuid references questions,position int not null,primary key(exam_id,question_id));
create table exam_attempts(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users,exam_id uuid not null references exams,status text not null default 'in_progress' check(status in('in_progress','submitted')),elapsed_seconds int not null default 0,running_since timestamptz default now(),marked uuid[] default '{}',score numeric,started_at timestamptz default now(),submitted_at timestamptz);
create unique index one_active on exam_attempts(user_id,exam_id) where status='in_progress';
create table student_answers(attempt_id uuid references exam_attempts on delete cascade,question_id uuid references questions,chosen_opt text not null,primary key(attempt_id,question_id));
create table import_batches(id uuid primary key default gen_random_uuid(),admin_id uuid references auth.users,file_hash text unique,total int,imported int,report jsonb,created_at timestamptz default now());
create table admin_audit_logs(id bigserial primary key,admin_id uuid,action text,detail jsonb,created_at timestamptz default now());
create or replace function is_admin(r text[]) returns boolean language sql stable security definer as $$select exists(select 1 from user_roles where user_id=auth.uid() and role=any(r))$$;
alter table profiles enable row level security; alter table schools enable row level security; alter table school_domains enable row level security;
alter table subjects enable row level security; alter table exams enable row level security; alter table questions enable row level security;
alter table question_options enable row level security; alter table question_keys enable row level security; alter table exam_questions enable row level security;
alter table exam_attempts enable row level security; alter table student_answers enable row level security; alter table user_roles enable row level security;
alter table import_batches enable row level security; alter table admin_audit_logs enable row level security;
create policy own_profile on profiles for select using(id=auth.uid() or is_admin('{super_admin,admin}'));
create policy own_profile_ins on profiles for insert with check(id=auth.uid());
create policy schools_read on schools for select using(true);
create policy domains_read on school_domains for select using(true);
create policy schools_admin on schools for all using(is_admin('{super_admin,admin}'));
create policy subjects_read on subjects for select using(true);
create policy exams_read on exams for select using(published and grade=(select grade from profiles where id=auth.uid()) or is_admin('{super_admin,admin,exam_manager}'));
create policy exams_write on exams for all using(is_admin('{super_admin,admin,exam_manager}'));
create policy q_admin on questions for all using(is_admin('{super_admin,admin,exam_manager}'));
create policy q_student on questions for select using(exists(select 1 from exam_questions eq join exams e on e.id=eq.exam_id where eq.question_id=questions.id and e.published and e.grade=(select grade from profiles where id=auth.uid())));
create policy o_admin on question_options for all using(is_admin('{super_admin,admin,exam_manager}'));
create policy o_student on question_options for select using(exists(select 1 from questions q where q.id=question_id));
create policy k_admin on question_keys for all using(is_admin('{super_admin,admin,exam_manager}'));
create policy eq_read on exam_questions for select using(true);
create policy eq_admin on exam_questions for all using(is_admin('{super_admin,admin,exam_manager}'));
create policy att_own on exam_attempts for select using(user_id=auth.uid() or is_admin('{super_admin,admin,results_manager}'));
create policy ans_own on student_answers for all using(exists(select 1 from exam_attempts a where a.id=attempt_id and a.user_id=auth.uid() and a.status='in_progress'));
create policy roles_read on user_roles for select using(user_id=auth.uid() or is_admin('{super_admin}'));
create policy imp_admin on import_batches for all using(is_admin('{super_admin,admin,exam_manager}'));
create policy audit_read on admin_audit_logs for select using(is_admin('{super_admin}'));
-- students never write attempts directly; these RPCs are the only write path
create or replace function start_attempt(p_exam uuid) returns uuid language plpgsql security definer as $$
declare a uuid; begin
 if not exists(select 1 from exams e join profiles p on p.id=auth.uid() where e.id=p_exam and e.published and e.grade=p.grade) then raise exception 'not allowed'; end if;
 select id into a from exam_attempts where user_id=auth.uid() and exam_id=p_exam and status='in_progress';
 if a is null then
  if exists(select 1 from exam_attempts where user_id=auth.uid() and exam_id=p_exam and status='submitted') and not (select allow_retakes from exams where id=p_exam) then raise exception 'retakes disabled'; end if;
  insert into exam_attempts(user_id,exam_id) values(auth.uid(),p_exam) returning id into a; end if;
 return a; end $$;
create or replace function set_clock(p_attempt uuid,p_run boolean) returns void language plpgsql security definer as $$
begin update exam_attempts set elapsed_seconds=elapsed_seconds+case when running_since is not null then extract(epoch from now()-running_since)::int else 0 end,
 running_since=case when p_run then now() else null end where id=p_attempt and user_id=auth.uid() and status='in_progress'; end $$;
create or replace function submit_attempt(p_attempt uuid) returns jsonb language plpgsql security definer as $$
declare s numeric; t numeric; c int; w int; n int; begin
 perform set_clock(p_attempt,false);
 select coalesce(sum(q.marks),0),count(*) filter(where k.correct_opt=a.chosen_opt),count(*) filter(where k.correct_opt<>a.chosen_opt) into s,c,w
  from student_answers a join questions q on q.id=a.question_id join question_keys k on k.question_id=q.id where a.attempt_id=p_attempt;
 select coalesce(sum(q.marks),0) into s from student_answers a join questions q on q.id=a.question_id join question_keys k on k.question_id=q.id where a.attempt_id=p_attempt and k.correct_opt=a.chosen_opt;
 select coalesce(sum(q.marks),0),count(*) into t,n from exam_questions eq join questions q on q.id=eq.question_id where eq.exam_id=(select exam_id from exam_attempts where id=p_attempt);
 update exam_attempts set status='submitted',score=s,submitted_at=now() where id=p_attempt and user_id=auth.uid() and status='in_progress';
 if not found then raise exception 'not submittable'; end if;
 return jsonb_build_object('score',s,'total',t,'correct',c,'incorrect',w,'unanswered',n-c-w); end $$;
insert into schools(name) values('6th of October STEM School (Boys)'),('6th of October District 11 STEM School'),('Maadi STEM School (Girls)'),('New Cairo STEM School'),('Alexandria STEM School'),('Kafr El-Sheikh STEM School'),('Dakahlia STEM School'),('Ismailia STEM School'),('Red Sea STEM School'),('Assiut STEM School'),('Luxor STEM School'),('Sers El-Layan STEM School (Girls)'),('El-Sadat STEM School (Boys)'),('Gharbia STEM School'),('Obour STEM School'),('Sharkia STEM School'),('Qena STEM School'),('Fayoum STEM School (Boys)'),('Beni Suef STEM School'),('Minya STEM School (Boys)'),('Sohag STEM School (Girls)'),('El-Arish STEM School'),('Suez STEM School'),('Aswan STEM School'),('Damietta STEM School');
insert into school_domains(school_id,domain) select id,'stemluxor.moe.edu.eg' from schools where name='Luxor STEM School';
insert into subjects(name) values('Mathematics'),('Physics'),('Chemistry'),('Biology'),('Computer Science'),('English');

-- ===== 002_exam_engine.sql =====
-- Fixes to 001: students could INSERT student_answers directly (any question, incl. ones outside the exam) and
-- submit_attempt did not restrict scoring to the exam's questions. Writes now go through validated RPCs only.
drop policy if exists ans_own on student_answers;
create policy ans_read on student_answers for select using(exists(select 1 from exam_attempts a where a.id=attempt_id and a.user_id=auth.uid()));
alter table exams add column if not exists instructions text;
alter table exams add column if not exists results_mode text not null default 'immediate' check(results_mode in('immediate','hidden'));
create or replace function save_answer(p_attempt uuid,p_q uuid,p_opt text) returns void language plpgsql security definer as $$
begin
 if not exists(select 1 from exam_attempts a join exam_questions eq on eq.exam_id=a.exam_id where a.id=p_attempt and a.user_id=auth.uid() and a.status='in_progress' and eq.question_id=p_q) then raise exception 'not allowed'; end if;
 if not exists(select 1 from question_options where question_id=p_q and opt_id=p_opt) then raise exception 'invalid option'; end if;
 insert into student_answers(attempt_id,question_id,chosen_opt) values(p_attempt,p_q,p_opt)
 on conflict(attempt_id,question_id) do update set chosen_opt=excluded.chosen_opt; end $$;
create or replace function toggle_mark(p_attempt uuid,p_q uuid) returns uuid[] language plpgsql security definer as $$
declare m uuid[]; begin
 update exam_attempts set marked=case when p_q=any(marked) then array_remove(marked,p_q) else array_append(marked,p_q) end
 where id=p_attempt and user_id=auth.uid() and status='in_progress' returning marked into m;
 if m is null then raise exception 'not allowed'; end if; return m; end $$;
create or replace function submit_attempt(p_attempt uuid) returns jsonb language plpgsql security definer as $$
declare s numeric; t numeric; c int; w int; n int; ex uuid; begin
 select exam_id into ex from exam_attempts where id=p_attempt and user_id=auth.uid() and status='in_progress' for update;
 if ex is null then raise exception 'not submittable'; end if;
 perform set_clock(p_attempt,false);
 select coalesce(sum(q.marks),0),count(*) into t,n from exam_questions eq join questions q on q.id=eq.question_id where eq.exam_id=ex;
 select coalesce(sum(q.marks) filter(where k.correct_opt=a.chosen_opt),0),count(*) filter(where k.correct_opt=a.chosen_opt),count(*) filter(where k.correct_opt<>a.chosen_opt)
  into s,c,w from student_answers a join exam_questions eq on eq.question_id=a.question_id and eq.exam_id=ex join questions q on q.id=a.question_id join question_keys k on k.question_id=q.id where a.attempt_id=p_attempt;
 update exam_attempts set status='submitted',score=s,submitted_at=now() where id=p_attempt;
 return get_result(p_attempt); end $$;
create or replace function get_result(p_attempt uuid) returns jsonb language plpgsql security definer as $$
declare a exam_attempts; e exams; t numeric; n int; c int; w int; rev jsonb; begin
 select * into a from exam_attempts where id=p_attempt and user_id=auth.uid() and status='submitted'; if not found then raise exception 'not available'; end if;
 select * into e from exams where id=a.exam_id;
 if e.results_mode='hidden' then return jsonb_build_object('hidden',true,'time_seconds',a.elapsed_seconds); end if;
 select coalesce(sum(q.marks),0),count(*) into t,n from exam_questions eq join questions q on q.id=eq.question_id where eq.exam_id=e.id;
 select count(*) filter(where k.correct_opt=sa.chosen_opt),count(*) filter(where k.correct_opt<>sa.chosen_opt) into c,w
  from student_answers sa join exam_questions eq on eq.question_id=sa.question_id and eq.exam_id=e.id join question_keys k on k.question_id=sa.question_id where sa.attempt_id=p_attempt;
 if e.show_answers then
  select jsonb_agg(jsonb_build_object('question_id',q.id,'text',q.text,'chosen',sa.chosen_opt,'correct',k.correct_opt,'explanation',q.explanation) order by eq.position) into rev
  from exam_questions eq join questions q on q.id=eq.question_id join question_keys k on k.question_id=q.id left join student_answers sa on sa.question_id=q.id and sa.attempt_id=p_attempt where eq.exam_id=e.id; end if;
 return jsonb_build_object('score',a.score,'total',t,'percentage',case when t>0 then round(a.score/t*100,1) else 0 end,'correct',c,'incorrect',w,'unanswered',n-c-w,'time_seconds',a.elapsed_seconds,'review',rev); end $$;
revoke all on function save_answer,toggle_mark,submit_attempt,get_result,start_attempt,set_clock from public,anon;
grant execute on function save_answer,toggle_mark,submit_attempt,get_result,start_attempt,set_clock to authenticated;

-- ===== 003_admin.sql =====
-- Server-side import commit (one function call = one transaction; any exception rolls everything back)
create or replace function import_exam(p jsonb,p_hash text) returns jsonb language plpgsql security definer as $$
declare e jsonb:=p->'exam'; q jsonb; o jsonb; qid uuid; eid uuid; bid uuid; i int:=0; ids text[]; ext text[]:='{}'; g smallint; sid uuid;
begin
 if not is_admin('{super_admin,admin,exam_manager}') then raise exception 'forbidden'; end if;
 if exists(select 1 from import_batches where file_hash=p_hash) then raise exception 'duplicate import (same file already imported)'; end if;
 g:=nullif(regexp_replace(coalesce(e->>'grade',''),'\D','','g'),'')::smallint;
 if g is null or g not in(10,11,12) then raise exception 'exam.grade must be Grade 10/11/12'; end if;
 if coalesce(trim(e->>'title'),'')='' then raise exception 'exam.title missing'; end if;
 select id into sid from subjects where lower(name)=lower(coalesce(e->>'subject',''));
 if sid is null then raise exception 'unknown subject "%"',e->>'subject'; end if;
 if jsonb_typeof(p->'questions')<>'array' or jsonb_array_length(p->'questions')=0 then raise exception 'questions[] missing or empty'; end if;
 insert into exams(title,description,grade,subject_id,academic_year,semester,difficulty,suggested_minutes) values(e->>'title',e->>'description',g,sid,e->>'academic_year',e->>'semester',e->>'difficulty',nullif(e->>'duration_minutes','')::int) returning id into eid;
 for q in select * from jsonb_array_elements(p->'questions') loop
  i:=i+1;
  if q->>'question_type' is distinct from 'MCQ' then raise exception 'Q%: unsupported question_type "%" (MCQ only)',i,q->>'question_type'; end if;
  if coalesce(trim(q->>'question_id'),'')='' or (q->>'question_id')=any(ext) then raise exception 'Q%: question_id missing or duplicate',i; end if;
  ext:=ext||(q->>'question_id');
  if coalesce(trim(q->>'question_text'),'')='' then raise exception 'Q%: question_text missing',i; end if;
  select array_agg(x->>'id') into ids from jsonb_array_elements(q->'options') x;
  if coalesce(array_length(ids,1),0)<2 or array_position(ids,null) is not null or (select count(distinct v) from unnest(ids) v)<>array_length(ids,1) then raise exception 'Q%: need >=2 options with unique non-empty ids',i; end if;
  if exists(select 1 from jsonb_array_elements(q->'options') x where coalesce(trim(x->>'text'),'')='') then raise exception 'Q%: empty option text',i; end if;
  if not coalesce(q->>'correct_answer','')=any(ids) then raise exception 'Q%: correct_answer does not match an option',i; end if;
  if coalesce((q->>'marks')::numeric,0)<=0 then raise exception 'Q%: marks must be positive',i; end if;
  insert into questions(external_id,text,image_path,explanation,marks,difficulty,topic) values(q->>'question_id',q->>'question_text',q->>'image_path',q->>'explanation',(q->>'marks')::numeric,q->>'difficulty',q->>'topic') returning id into qid;
  for o in select * from jsonb_array_elements(q->'options') loop insert into question_options values(qid,o->>'id',o->>'text'); end loop;
  insert into question_keys values(qid,q->>'correct_answer');
  insert into exam_questions values(eid,qid,i);
 end loop;
 update exams set total_marks=(select sum(qq.marks) from exam_questions eq join questions qq on qq.id=eq.question_id where eq.exam_id=eid) where id=eid;
 insert into import_batches(admin_id,file_hash,total,imported,report) values(auth.uid(),p_hash,i,i,jsonb_build_object('exam_id',eid)) returning id into bid;
 update questions set batch_id=bid where id in(select question_id from exam_questions where exam_id=eid);
 insert into admin_audit_logs(admin_id,action,detail) values(auth.uid(),'import_exam',jsonb_build_object('exam_id',eid,'batch_id',bid,'questions',i));
 return jsonb_build_object('exam_id',eid,'batch_id',bid,'total',i,'imported',i,'rejected',0);
end $$;
create or replace function set_published(p_exam uuid,p_pub boolean) returns void language plpgsql security definer as $$
begin
 if not is_admin('{super_admin,admin,exam_manager}') then raise exception 'forbidden'; end if;
 if p_pub and not exists(select 1 from exam_questions where exam_id=p_exam) then raise exception 'exam has no questions'; end if;
 update exams set published=p_pub where id=p_exam;
 insert into admin_audit_logs(admin_id,action,detail) values(auth.uid(),case when p_pub then 'publish_exam' else 'unpublish_exam' end,jsonb_build_object('exam_id',p_exam)); end $$;
create or replace function admin_stats() returns jsonb language plpgsql security definer as $$
begin
 if not is_admin('{super_admin,admin,exam_manager,results_manager}') then raise exception 'forbidden'; end if;
 return jsonb_build_object('students',(select count(*) from profiles),'schools',(select count(*) from schools where active),
  'exams',(select count(*) from exams),'published',(select count(*) from exams where published),'questions',(select count(*) from questions),
  'attempts',(select count(*) from exam_attempts),'submitted',(select count(*) from exam_attempts where status='submitted'),
  'avg_pct',(select round(avg(a.score/nullif(t.total,0)*100),1) from exam_attempts a join (select eq.exam_id,sum(q.marks) total from exam_questions eq join questions q on q.id=eq.question_id group by 1) t on t.exam_id=a.exam_id where a.status='submitted'),
  'by_grade',(select coalesce(jsonb_object_agg(grade,c),'{}') from(select grade,count(*) c from profiles group by 1)x)); end $$;
-- audit log is append-only: no update/delete for anyone through the API
revoke update,delete on admin_audit_logs from authenticated,anon;
drop policy if exists imp_admin on import_batches;
create policy imp_read on import_batches for select using(is_admin('{super_admin,admin,exam_manager}'));
revoke all on function import_exam,set_published,admin_stats from public,anon;
grant execute on function import_exam,set_published,admin_stats to authenticated;

-- ===== 004_platform.sql =====
-- 1. Registration: profile is created by a trigger from signUp metadata (no session exists before email verification) and re-validates the school domain server-side.
create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
declare m jsonb:=coalesce(new.raw_user_meta_data,'{}'); sid uuid; g smallint; begin
 if coalesce(m->>'school_id','')='' then return new; end if; -- users created by an operator in the dashboard
 sid:=(m->>'school_id')::uuid; g:=nullif(m->>'grade','')::smallint;
 if g is null or g not in(10,11,12) or array_length(regexp_split_to_array(trim(coalesce(m->>'full_name','')),'\s+'),1)<4 or coalesce(m->>'phone','') !~ '^(\+20|0)1[0125][0-9]{8}$' then raise exception 'invalid registration data'; end if;
 if not exists(select 1 from school_domains d join schools s on s.id=d.school_id where d.school_id=sid and s.active and d.domain=lower(split_part(new.email,'@',2))) then raise exception 'email domain not approved for this school'; end if;
 insert into profiles(id,full_name,phone,school_id,grade) values(new.id,trim(m->>'full_name'),m->>'phone',sid,g); return new; end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();
-- 2. Tables
create table platform_settings(key text primary key,value jsonb not null); insert into platform_settings values('leaderboards_enabled','true');
alter table exams add column if not exists practice_enabled boolean not null default false;
create table exam_assignments(exam_id uuid references exams on delete cascade,school_id uuid references schools on delete cascade,primary key(exam_id,school_id));
create table notifications(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users on delete cascade,title text not null,body text,read boolean default false,created_at timestamptz default now());
create index on notifications(user_id,read,created_at desc);
create table bookmarks(user_id uuid not null default auth.uid() references auth.users on delete cascade,question_id uuid references questions on delete cascade,created_at timestamptz default now(),primary key(user_id,question_id));
create table collections(id uuid primary key default gen_random_uuid(),user_id uuid not null default auth.uid() references auth.users on delete cascade,name text not null check(length(trim(name))>0));
create table collection_items(collection_id uuid references collections on delete cascade,question_id uuid references questions on delete cascade,primary key(collection_id,question_id));
create table practice_history(id bigserial primary key,user_id uuid references auth.users on delete cascade,question_id uuid references questions on delete cascade,chosen text,correct boolean,created_at timestamptz default now());
create index on practice_history(user_id,correct);
create table profile_requests(id uuid primary key default gen_random_uuid(),user_id uuid not null references profiles on delete cascade,school_id uuid references schools,grade smallint check(grade in(10,11,12)),status text not null default 'pending' check(status in('pending','approved','rejected')),created_at timestamptz default now());
alter table platform_settings enable row level security; alter table exam_assignments enable row level security; alter table notifications enable row level security;
alter table bookmarks enable row level security; alter table collections enable row level security; alter table collection_items enable row level security;
alter table practice_history enable row level security; alter table profile_requests enable row level security;
create policy ps_read on platform_settings for select using(true);
create policy ea_read on exam_assignments for select using(true);
create policy n_own on notifications for select using(user_id=auth.uid());
create policy bm_own on bookmarks for all using(user_id=auth.uid()) with check(user_id=auth.uid() and exists(select 1 from questions q where q.id=question_id));
create policy col_own on collections for all using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy ci_own on collection_items for all using(exists(select 1 from collections c where c.id=collection_id and c.user_id=auth.uid())) with check(exists(select 1 from collections c where c.id=collection_id and c.user_id=auth.uid()) and exists(select 1 from questions q where q.id=question_id));
create policy ph_own on practice_history for select using(user_id=auth.uid());
create policy pr_read on profile_requests for select using(user_id=auth.uid() or is_admin('{super_admin,admin}'));
drop policy if exists schools_admin on schools; -- school edits now go through audited RPCs
-- exams/questions visible only if assigned (no assignment rows = all schools of that grade)
drop policy if exists exams_read on exams;
create policy exams_read on exams for select using((published and grade=(select grade from profiles where id=auth.uid()) and (not exists(select 1 from exam_assignments x where x.exam_id=id) or exists(select 1 from exam_assignments x where x.exam_id=id and x.school_id=(select school_id from profiles where id=auth.uid())))) or is_admin('{super_admin,admin,exam_manager,results_manager}'));
drop policy if exists q_student on questions;
create policy q_student on questions for select using(exists(select 1 from exam_questions eq join exams e on e.id=eq.exam_id where eq.question_id=questions.id));
create or replace function start_attempt(p_exam uuid) returns uuid language plpgsql security definer as $$
declare a uuid; begin
 if not exists(select 1 from exams e join profiles p on p.id=auth.uid() where e.id=p_exam and e.published and e.grade=p.grade and (not exists(select 1 from exam_assignments x where x.exam_id=e.id) or exists(select 1 from exam_assignments x where x.exam_id=e.id and x.school_id=p.school_id))) then raise exception 'not allowed'; end if;
 select id into a from exam_attempts where user_id=auth.uid() and exam_id=p_exam and status='in_progress';
 if a is null then
  if exists(select 1 from exam_attempts where user_id=auth.uid() and exam_id=p_exam and status='submitted') and not (select allow_retakes from exams where id=p_exam) then raise exception 'retakes disabled'; end if;
  insert into exam_attempts(user_id,exam_id) values(auth.uid(),p_exam) returning id into a; end if;
 return a; end $$;
-- 3. Helpers
create or replace function notify_grade(g smallint,t text,b text) returns void language sql security definer as $$insert into notifications(user_id,title,body) select id,t,b from profiles where grade=g$$;
revoke all on function notify_grade from public,anon,authenticated;
create or replace function set_published(p_exam uuid,p_pub boolean) returns void language plpgsql security definer as $$
declare e exams; begin
 if not is_admin('{super_admin,admin,exam_manager}') then raise exception 'forbidden'; end if;
 if p_pub and not exists(select 1 from exam_questions where exam_id=p_exam) then raise exception 'exam has no questions'; end if;
 update exams set published=p_pub where id=p_exam returning * into e;
 if p_pub then perform notify_grade(e.grade,'New exam published',e.title); end if;
 insert into admin_audit_logs(admin_id,action,detail) values(auth.uid(),case when p_pub then 'publish_exam' else 'unpublish_exam' end,jsonb_build_object('exam_id',p_exam)); end $$;
create or replace function audit(a text,d jsonb) returns void language sql security definer as $$insert into admin_audit_logs(admin_id,action,detail) values(auth.uid(),a,d)$$;
revoke all on function audit from public,anon,authenticated;
create view attempt_pct as select a.id,a.user_id,a.exam_id,a.elapsed_seconds,a.submitted_at,a.score/nullif(t.total,0)*100 as pct from exam_attempts a join (select eq.exam_id,sum(q.marks) total from exam_questions eq join questions q on q.id=eq.question_id group by 1) t on t.exam_id=a.exam_id where a.status='submitted';
revoke all on attempt_pct from public,anon,authenticated;
-- 4. Student functions
create or replace function mark_read(p_id uuid default null) returns void language sql security definer as $$update notifications set read=true where user_id=auth.uid() and (p_id is null or id=p_id)$$;
create or replace function update_profile(p_name text,p_phone text) returns void language plpgsql security definer as $$
begin if array_length(regexp_split_to_array(trim(p_name),'\s+'),1)<4 then raise exception 'enter four names'; end if;
 if p_phone !~ '^(\+20|0)1[0125][0-9]{8}$' then raise exception 'invalid Egyptian phone'; end if;
 update profiles set full_name=trim(p_name),phone=p_phone where id=auth.uid(); end $$;
create or replace function request_change(p_school uuid,p_grade smallint) returns void language plpgsql security definer as $$
begin delete from profile_requests where user_id=auth.uid() and status='pending';
 insert into profile_requests(user_id,school_id,grade) values(auth.uid(),p_school,p_grade); end $$;
create or replace function practice_set(p_subject uuid,p_topic text,p_wrong boolean,p_limit int default 10) returns jsonb language sql security definer as $$
select coalesce(jsonb_agg(x),'[]'::jsonb) from (select jsonb_build_object('id',q.id,'text',q.text,'image_path',q.image_path,'topic',q.topic,'options',(select jsonb_agg(jsonb_build_object('opt_id',o.opt_id,'text',o.text) order by o.opt_id) from question_options o where o.question_id=q.id)) as x
 from questions q where q.id in(select eq.question_id from exam_questions eq join exams e on e.id=eq.exam_id where e.published and e.practice_enabled and e.grade=(select grade from profiles where id=auth.uid()) and (p_subject is null or e.subject_id=p_subject))
 and (p_topic is null or p_topic='' or q.topic=p_topic) and (not coalesce(p_wrong,false) or q.id in(select question_id from practice_history where user_id=auth.uid() and not correct))
 order by random() limit least(coalesce(p_limit,10),50)) s $$;
create or replace function practice_check(p_q uuid,p_opt text) returns jsonb language plpgsql security definer as $$
declare k text; ex text; begin
 if not exists(select 1 from exam_questions eq join exams e on e.id=eq.exam_id where eq.question_id=p_q and e.published and e.practice_enabled and e.grade=(select grade from profiles where id=auth.uid())) then raise exception 'not allowed'; end if;
 select correct_opt into k from question_keys where question_id=p_q; select explanation into ex from questions where id=p_q;
 insert into practice_history(user_id,question_id,chosen,correct) values(auth.uid(),p_q,p_opt,p_opt=k);
 return jsonb_build_object('correct',p_opt=k,'correct_opt',k,'explanation',ex); end $$;
create or replace function student_stats() returns jsonb language sql security definer as $$
select jsonb_build_object('avg',(select round(avg(pct),1) from attempt_pct where user_id=auth.uid()),'completed',(select count(*) from attempt_pct where user_id=auth.uid()),
 'total_secs',(select coalesce(sum(elapsed_seconds),0) from attempt_pct where user_id=auth.uid()),'avg_secs',(select round(avg(elapsed_seconds)) from attempt_pct where user_id=auth.uid()),
 'practice',(select count(*) from practice_history where user_id=auth.uid()),
 'by_subject',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select jsonb_build_object('label',s.name,'avg',round(avg(v.pct),1)) x from attempt_pct v join exams e on e.id=v.exam_id join subjects s on s.id=e.subject_id where v.user_id=auth.uid() group by s.name) q),
 'by_topic',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select jsonb_build_object('label',q.topic,'pct',round(100*avg((sa.chosen_opt=k.correct_opt)::int),0),'n',count(*)) x from student_answers sa join exam_attempts a on a.id=sa.attempt_id and a.status='submitted' and a.user_id=auth.uid() join questions q on q.id=sa.question_id join question_keys k on k.question_id=q.id where q.topic is not null group by q.topic having count(*)>=3) t),
 'history',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select jsonb_build_object('title',e.title,'pct',round(v.pct,1),'at',v.submitted_at) x from attempt_pct v join exams e on e.id=v.exam_id where v.user_id=auth.uid() order by v.submitted_at desc limit 20) h)) $$;
create or replace function leaderboard(p_scope text,p_exam uuid) returns jsonb language plpgsql security definer as $$
declare me profiles; begin
 if not coalesce((select (value)::boolean from platform_settings where key='leaderboards_enabled'),false) then return jsonb_build_object('disabled',true); end if;
 select * into me from profiles where id=auth.uid();
 if (select grade from exams where id=p_exam) is distinct from me.grade then raise exception 'not allowed'; end if;
 return jsonb_build_object('rows',coalesce((select jsonb_agg(r) from(
  select trim(split_part(p.full_name,' ',1)||' '||left(split_part(p.full_name,' ',2),1)||'.') as name,s.name as school,round(b.pct,1) as pct,b.secs,(b.user_id=auth.uid()) as me
  from(select distinct on(v.user_id) v.user_id,v.pct,v.elapsed_seconds secs from attempt_pct v where v.exam_id=p_exam order by v.user_id,v.pct desc,v.elapsed_seconds) b
  join profiles p on p.id=b.user_id left join schools s on s.id=p.school_id
  where p_scope='national' or(p_scope='grade' and p.grade=me.grade) or(p_scope='school' and p.school_id=me.school_id)
  order by b.pct desc,b.secs limit 50) r),'[]'::jsonb)); end $$;
-- 5. Admin functions
create or replace function decide_request(p_id uuid,p_ok boolean) returns void language plpgsql security definer as $$
declare r profile_requests; begin
 if not is_admin('{super_admin,admin}') then raise exception 'forbidden'; end if;
 update profile_requests set status=case when p_ok then 'approved' else 'rejected' end where id=p_id and status='pending' returning * into r;
 if not found then raise exception 'request not pending'; end if;
 if p_ok then update profiles set school_id=coalesce(r.school_id,school_id),grade=coalesce(r.grade,grade) where id=r.user_id; end if;
 insert into notifications(user_id,title) values(r.user_id,case when p_ok then 'Your school/grade change was approved' else 'Your school/grade change was rejected' end);
 perform audit('decide_request',jsonb_build_object('request',p_id,'approved',p_ok)); end $$;
create or replace function upsert_school(p_id uuid,p_name text,p_active boolean) returns uuid language plpgsql security definer as $$
declare i uuid:=p_id; begin
 if not is_admin('{super_admin,admin}') then raise exception 'forbidden'; end if;
 if coalesce(trim(p_name),'')='' then raise exception 'name required'; end if;
 if i is null then insert into schools(name,active) values(trim(p_name),coalesce(p_active,true)) returning id into i; else update schools set name=trim(p_name),active=coalesce(p_active,active) where id=i; end if;
 perform audit('upsert_school',jsonb_build_object('school',i,'name',p_name,'active',p_active)); return i; end $$;
create or replace function add_domain(p_school uuid,p_domain text) returns void language plpgsql security definer as $$
begin if not is_admin('{super_admin,admin}') then raise exception 'forbidden'; end if;
 if lower(trim(p_domain)) !~ '^[a-z0-9.-]+\.[a-z]{2,}$' then raise exception 'invalid domain'; end if;
 insert into school_domains(school_id,domain) values(p_school,lower(trim(p_domain))); perform audit('add_domain',jsonb_build_object('school',p_school,'domain',p_domain)); end $$;
create or replace function remove_domain(p_id uuid) returns void language plpgsql security definer as $$
begin if not is_admin('{super_admin,admin}') then raise exception 'forbidden'; end if; delete from school_domains where id=p_id; perform audit('remove_domain',jsonb_build_object('id',p_id)); end $$;
create or replace function set_exam_flags(p_exam uuid,p_practice boolean,p_show boolean,p_mode text,p_retakes boolean) returns void language plpgsql security definer as $$
begin if not is_admin('{super_admin,admin,exam_manager}') then raise exception 'forbidden'; end if;
 if p_mode not in('immediate','hidden') then raise exception 'bad results_mode'; end if;
 update exams set practice_enabled=p_practice,show_answers=p_show,results_mode=p_mode,allow_retakes=p_retakes where id=p_exam;
 perform audit('set_exam_flags',jsonb_build_object('exam',p_exam,'practice',p_practice,'show',p_show,'mode',p_mode,'retakes',p_retakes)); end $$;
create or replace function set_exam_meta(p_exam uuid,p_title text,p_instructions text) returns void language plpgsql security definer as $$
begin if not is_admin('{super_admin,admin,exam_manager}') then raise exception 'forbidden'; end if;
 if coalesce(trim(p_title),'')='' then raise exception 'title required'; end if;
 update exams set title=trim(p_title),instructions=p_instructions where id=p_exam; perform audit('edit_exam',jsonb_build_object('exam',p_exam)); end $$;
create or replace function set_assignments(p_exam uuid,p_schools uuid[]) returns void language plpgsql security definer as $$
begin if not is_admin('{super_admin,admin,exam_manager}') then raise exception 'forbidden'; end if;
 delete from exam_assignments where exam_id=p_exam; insert into exam_assignments select p_exam,unnest(p_schools);
 perform audit('set_assignments',jsonb_build_object('exam',p_exam,'schools',p_schools)); end $$;
create or replace function duplicate_exam(p_exam uuid) returns uuid language plpgsql security definer as $$
declare n uuid; begin if not is_admin('{super_admin,admin,exam_manager}') then raise exception 'forbidden'; end if;
 insert into exams(title,description,grade,subject_id,academic_year,semester,difficulty,total_marks,suggested_minutes,instructions) select title||' (copy)',description,grade,subject_id,academic_year,semester,difficulty,total_marks,suggested_minutes,instructions from exams where id=p_exam returning id into n;
 if n is null then raise exception 'exam not found'; end if;
 insert into exam_questions select n,question_id,position from exam_questions where exam_id=p_exam; perform audit('duplicate_exam',jsonb_build_object('from',p_exam,'to',n)); return n; end $$;
create or replace function delete_exam(p_exam uuid) returns void language plpgsql security definer as $$
begin if not is_admin('{super_admin,admin,exam_manager}') then raise exception 'forbidden'; end if;
 if exists(select 1 from exam_attempts where exam_id=p_exam) then raise exception 'exam has attempts - unpublish it instead'; end if;
 delete from exams where id=p_exam; perform audit('delete_exam',jsonb_build_object('exam',p_exam)); end $$;
create or replace function create_question(p_text text,p_options jsonb,p_correct text,p_marks numeric,p_topic text,p_diff text,p_expl text,p_image text,p_exam uuid) returns uuid language plpgsql security definer as $$
declare ids text[]; q uuid; o jsonb; pos int; begin
 if not is_admin('{super_admin,admin,exam_manager}') then raise exception 'forbidden'; end if;
 if coalesce(trim(p_text),'')='' then raise exception 'question text required'; end if;
 if coalesce((p_marks),0)<=0 then raise exception 'marks must be positive'; end if;
 select array_agg(x->>'id') into ids from jsonb_array_elements(p_options) x;
 if coalesce(array_length(ids,1),0)<2 or array_position(ids,null) is not null or (select count(distinct v) from unnest(ids) v)<>array_length(ids,1) then raise exception 'need >=2 options with unique ids'; end if;
 if exists(select 1 from jsonb_array_elements(p_options) x where coalesce(trim(x->>'text'),'')='') then raise exception 'empty option text'; end if;
 if not coalesce(p_correct,'')=any(ids) then raise exception 'correct answer must be one option'; end if;
 insert into questions(text,image_path,explanation,marks,difficulty,topic) values(p_text,nullif(p_image,''),p_expl,p_marks,p_diff,p_topic) returning id into q;
 for o in select * from jsonb_array_elements(p_options) loop insert into question_options values(q,o->>'id',o->>'text'); end loop;
 insert into question_keys values(q,p_correct);
 if p_exam is not null then select coalesce(max(position),0)+1 into pos from exam_questions where exam_id=p_exam; insert into exam_questions values(p_exam,q,pos);
  update exams set total_marks=(select sum(x.marks) from exam_questions eq join questions x on x.id=eq.question_id where eq.exam_id=p_exam) where id=p_exam; end if;
 perform audit('create_question',jsonb_build_object('question',q,'exam',p_exam)); return q; end $$;
create or replace function admin_update_question(p_q uuid,p_text text,p_expl text,p_marks numeric,p_topic text,p_diff text,p_image text,p_correct text) returns void language plpgsql security definer as $$
begin if not is_admin('{super_admin,admin,exam_manager}') then raise exception 'forbidden'; end if;
 if coalesce(trim(p_text),'')='' or coalesce(p_marks,0)<=0 then raise exception 'text and positive marks required'; end if;
 if not exists(select 1 from question_options where question_id=p_q and opt_id=p_correct) then raise exception 'correct answer must be an existing option'; end if;
 update questions set text=p_text,explanation=p_expl,marks=p_marks,topic=p_topic,difficulty=p_diff,image_path=nullif(p_image,'') where id=p_q;
 update question_keys set correct_opt=p_correct where question_id=p_q; perform audit('edit_question',jsonb_build_object('question',p_q)); end $$;
create or replace function delete_question(p_q uuid) returns void language plpgsql security definer as $$
begin if not is_admin('{super_admin,admin,exam_manager}') then raise exception 'forbidden'; end if;
 if exists(select 1 from exam_questions eq join exams e on e.id=eq.exam_id where eq.question_id=p_q and e.published) then raise exception 'question is in a published exam'; end if;
 if exists(select 1 from student_answers where question_id=p_q) then raise exception 'question has student answers'; end if;
 delete from questions where id=p_q; perform audit('delete_question',jsonb_build_object('question',p_q)); end $$;
create or replace function admin_analytics() returns jsonb language plpgsql security definer as $$
begin if not is_admin('{super_admin,admin,exam_manager,results_manager}') then raise exception 'forbidden'; end if;
 return jsonb_build_object(
 'by_grade',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select jsonb_build_object('label','Grade '||e.grade,'avg',round(avg(v.pct),1),'n',count(*)) x from attempt_pct v join exams e on e.id=v.exam_id group by e.grade) s),
 'by_school',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select jsonb_build_object('label',coalesce(sc.name,'-'),'avg',round(avg(v.pct),1),'n',count(*)) x from attempt_pct v join profiles p on p.id=v.user_id left join schools sc on sc.id=p.school_id group by sc.name) s),
 'by_subject',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select jsonb_build_object('label',su.name,'avg',round(avg(v.pct),1),'n',count(*)) x from attempt_pct v join exams e on e.id=v.exam_id join subjects su on su.id=e.subject_id group by su.name) s),
 'by_exam',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select jsonb_build_object('label',e.title,'attempts',count(a.id),'submitted',count(v.id),'avg',round(avg(v.pct),1),'avg_secs',round(avg(v.elapsed_seconds))) x from exams e left join exam_attempts a on a.exam_id=e.id left join attempt_pct v on v.id=a.id group by e.id,e.title) s),
 'hard_questions',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select jsonb_build_object('label',left(q.text,80),'pct_correct',round(100*avg((sa.chosen_opt=k.correct_opt)::int),1),'n',count(*)) x from student_answers sa join exam_attempts a on a.id=sa.attempt_id and a.status='submitted' join questions q on q.id=sa.question_id join question_keys k on k.question_id=q.id group by q.id,q.text having count(*)>=5 order by avg((sa.chosen_opt=k.correct_opt)::int) limit 10) s)); end $$;
create or replace function set_setting(p_key text,p_value jsonb) returns void language plpgsql security definer as $$
begin if not is_admin('{super_admin,admin}') then raise exception 'forbidden'; end if;
 if p_key<>'leaderboards_enabled' then raise exception 'unknown setting'; end if;
 insert into platform_settings values(p_key,p_value) on conflict(key) do update set value=excluded.value; perform audit('set_setting',jsonb_build_object('key',p_key,'value',p_value)); end $$;
create or replace function send_announcement(p_title text,p_body text,p_grade smallint) returns void language plpgsql security definer as $$
begin if not is_admin('{super_admin,admin}') then raise exception 'forbidden'; end if;
 if coalesce(trim(p_title),'')='' then raise exception 'title required'; end if;
 insert into notifications(user_id,title,body) select id,p_title,p_body from profiles where p_grade is null or grade=p_grade; perform audit('announcement',jsonb_build_object('title',p_title,'grade',p_grade)); end $$;
create or replace function list_admins() returns jsonb language plpgsql security definer as $$
begin if not is_admin('{super_admin}') then raise exception 'forbidden'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('user_id',r.user_id,'email',u.email,'role',r.role)) from user_roles r join auth.users u on u.id=r.user_id),'[]'::jsonb); end $$;
create or replace function grant_role(p_email text,p_role text) returns void language plpgsql security definer as $$
declare u uuid; begin if not is_admin('{super_admin}') then raise exception 'forbidden'; end if;
 select id into u from auth.users where lower(email)=lower(trim(p_email)); if u is null then raise exception 'no such user'; end if;
 insert into user_roles values(u,p_role) on conflict do nothing; perform audit('grant_role',jsonb_build_object('user',u,'role',p_role)); end $$;
create or replace function revoke_role(p_user uuid,p_role text) returns void language plpgsql security definer as $$
begin if not is_admin('{super_admin}') then raise exception 'forbidden'; end if;
 if p_role='super_admin' and (select count(*) from user_roles where role='super_admin')<=1 then raise exception 'cannot remove the last super admin'; end if;
 delete from user_roles where user_id=p_user and role=p_role; perform audit('revoke_role',jsonb_build_object('user',p_user,'role',p_role)); end $$;
revoke all on function mark_read,update_profile,request_change,practice_set,practice_check,student_stats,leaderboard,decide_request,upsert_school,add_domain,remove_domain,set_exam_flags,set_exam_meta,set_assignments,duplicate_exam,delete_exam,create_question,admin_update_question,delete_question,admin_analytics,set_setting,send_announcement,list_admins,grant_role,revoke_role,set_published,start_attempt from public,anon;
grant execute on function mark_read,update_profile,request_change,practice_set,practice_check,student_stats,leaderboard,decide_request,upsert_school,add_domain,remove_domain,set_exam_flags,set_exam_meta,set_assignments,duplicate_exam,delete_exam,create_question,admin_update_question,delete_question,admin_analytics,set_setting,send_announcement,list_admins,grant_role,revoke_role,set_published,start_attempt to authenticated;
-- 6. Storage: private bucket, 2 MB, raster images only (SVG excluded: can embed scripts). Reads need a signed-in user; writes need an exam role.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('question-images','question-images',false,2097152,array['image/png','image/jpeg','image/webp']) on conflict(id) do nothing;
create policy qi_read on storage.objects for select to authenticated using(bucket_id='question-images');
create policy qi_ins on storage.objects for insert to authenticated with check(bucket_id='question-images' and is_admin('{super_admin,admin,exam_manager}'));
create policy qi_upd on storage.objects for update to authenticated using(bucket_id='question-images' and is_admin('{super_admin,admin,exam_manager}'));
create policy qi_del on storage.objects for delete to authenticated using(bucket_id='question-images' and is_admin('{super_admin,admin,exam_manager}'));

-- ===== 005_completion.sql =====
alter table exams add column if not exists shuffle_questions boolean not null default false;
alter table exams add column if not exists shuffle_options boolean not null default false;
alter table exams add column if not exists results_release_at timestamptz;
alter table question_options add column if not exists image_path text;
create or replace function set_exam_options(p_exam uuid,p_shuf_q boolean,p_shuf_o boolean,p_release timestamptz) returns void language plpgsql security definer as $$
begin if not is_admin('{super_admin,admin,exam_manager}') then raise exception 'forbidden'; end if;
 update exams set shuffle_questions=p_shuf_q,shuffle_options=p_shuf_o,results_release_at=p_release where id=p_exam;
 perform audit('set_exam_options',jsonb_build_object('exam',p_exam,'shuffle_q',p_shuf_q,'shuffle_o',p_shuf_o,'release',p_release)); end $$;
create or replace function set_option(p_q uuid,p_opt text,p_text text,p_image text) returns void language plpgsql security definer as $$
begin if not is_admin('{super_admin,admin,exam_manager}') then raise exception 'forbidden'; end if;
 if coalesce(trim(p_text),'')='' then raise exception 'option text required'; end if;
 update question_options set text=p_text,image_path=nullif(p_image,'') where question_id=p_q and opt_id=p_opt;
 if not found then raise exception 'option not found'; end if; perform audit('edit_option',jsonb_build_object('question',p_q,'option',p_opt)); end $$;
-- results: honour scheduled release; review carries option texts (needed when options are shuffled)
create or replace function get_result(p_attempt uuid) returns jsonb language plpgsql security definer as $$
declare a exam_attempts; e exams; t numeric; n int; c int; w int; rev jsonb; begin
 select * into a from exam_attempts where id=p_attempt and user_id=auth.uid() and status='submitted'; if not found then raise exception 'not available'; end if;
 select * into e from exams where id=a.exam_id;
 if e.results_mode='hidden' or (e.results_release_at is not null and e.results_release_at>now()) then return jsonb_build_object('hidden',true,'release_at',e.results_release_at,'time_seconds',a.elapsed_seconds); end if;
 select coalesce(sum(q.marks),0),count(*) into t,n from exam_questions eq join questions q on q.id=eq.question_id where eq.exam_id=e.id;
 select count(*) filter(where k.correct_opt=sa.chosen_opt),count(*) filter(where k.correct_opt<>sa.chosen_opt) into c,w
  from student_answers sa join exam_questions eq on eq.question_id=sa.question_id and eq.exam_id=e.id join question_keys k on k.question_id=sa.question_id where sa.attempt_id=p_attempt;
 if e.show_answers then
  select jsonb_agg(jsonb_build_object('question_id',q.id,'text',q.text,'chosen',sa.chosen_opt,'chosen_text',oc.text,'correct',k.correct_opt,'correct_text',ok.text,'explanation',q.explanation) order by eq.position) into rev
  from exam_questions eq join questions q on q.id=eq.question_id join question_keys k on k.question_id=q.id join question_options ok on ok.question_id=q.id and ok.opt_id=k.correct_opt
  left join student_answers sa on sa.question_id=q.id and sa.attempt_id=p_attempt left join question_options oc on oc.question_id=q.id and oc.opt_id=sa.chosen_opt where eq.exam_id=e.id; end if;
 return jsonb_build_object('score',a.score,'total',t,'percentage',case when t>0 then round(a.score/t*100,1) else 0 end,'correct',c,'incorrect',w,'unanswered',n-c-w,'time_seconds',a.elapsed_seconds,'review',rev); end $$;
-- leaderboard must not leak scores of exams whose results are hidden/unreleased
create or replace function leaderboard(p_scope text,p_exam uuid) returns jsonb language plpgsql security definer as $$
declare me profiles; ex exams; begin
 if not coalesce((select (value)::boolean from platform_settings where key='leaderboards_enabled'),false) then return jsonb_build_object('disabled',true); end if;
 select * into me from profiles where id=auth.uid(); select * into ex from exams where id=p_exam;
 if ex.grade is distinct from me.grade then raise exception 'not allowed'; end if;
 if ex.results_mode='hidden' or (ex.results_release_at is not null and ex.results_release_at>now()) then return jsonb_build_object('hidden',true); end if;
 return jsonb_build_object('rows',coalesce((select jsonb_agg(r) from(
  select trim(split_part(p.full_name,' ',1)||' '||left(split_part(p.full_name,' ',2),1)||'.') as name,s.name as school,round(b.pct,1) as pct,b.secs,(b.user_id=auth.uid()) as me
  from(select distinct on(v.user_id) v.user_id,v.pct,v.elapsed_seconds secs from attempt_pct v where v.exam_id=p_exam order by v.user_id,v.pct desc,v.elapsed_seconds) b
  join profiles p on p.id=b.user_id left join schools s on s.id=p.school_id
  where p_scope='national' or(p_scope='grade' and p.grade=me.grade) or(p_scope='school' and p.school_id=me.school_id)
  order by b.pct desc,b.secs limit 50) r),'[]'::jsonb)); end $$;
-- practice from a personal collection (still limited to practice-enabled exams of the student's grade)
drop function if exists practice_set(uuid,text,boolean,int);
create or replace function practice_set(p_subject uuid,p_topic text,p_wrong boolean,p_collection uuid default null,p_limit int default 10) returns jsonb language sql security definer as $$
select coalesce(jsonb_agg(x),'[]'::jsonb) from (select jsonb_build_object('id',q.id,'text',q.text,'image_path',q.image_path,'topic',q.topic,'options',(select jsonb_agg(jsonb_build_object('opt_id',o.opt_id,'text',o.text,'image_path',o.image_path) order by o.opt_id) from question_options o where o.question_id=q.id)) as x
 from questions q where q.id in(select eq.question_id from exam_questions eq join exams e on e.id=eq.exam_id where e.published and e.practice_enabled and e.grade=(select grade from profiles where id=auth.uid()) and (p_subject is null or e.subject_id=p_subject))
 and (p_topic is null or p_topic='' or q.topic=p_topic) and (not coalesce(p_wrong,false) or q.id in(select question_id from practice_history where user_id=auth.uid() and not correct))
 and (p_collection is null or q.id in(select ci.question_id from collection_items ci join collections c on c.id=ci.collection_id where c.id=p_collection and c.user_id=auth.uid()))
 order by random() limit least(coalesce(p_limit,10),50)) s $$;
-- analytics with filters
drop function if exists admin_analytics();
create or replace function admin_analytics(p_from date default null,p_to date default null,p_school uuid default null,p_grade smallint default null,p_year text default null) returns jsonb language plpgsql security definer as $$
begin if not is_admin('{super_admin,admin,exam_manager,results_manager}') then raise exception 'forbidden'; end if;
 return(with v as(select ap.id,ap.exam_id,ap.elapsed_seconds,ap.pct,p.school_id,e.grade,e.subject_id from attempt_pct ap join profiles p on p.id=ap.user_id join exams e on e.id=ap.exam_id
   where(p_from is null or ap.submitted_at>=p_from) and(p_to is null or ap.submitted_at<p_to+1) and(p_school is null or p.school_id=p_school) and(p_grade is null or e.grade=p_grade) and(p_year is null or e.academic_year=p_year))
 select jsonb_build_object(
 'by_grade',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select jsonb_build_object('label','Grade '||grade,'avg',round(avg(pct),1),'n',count(*)) x from v group by grade) s),
 'by_school',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select jsonb_build_object('label',coalesce(sc.name,'-'),'avg',round(avg(pct),1),'n',count(*)) x from v left join schools sc on sc.id=v.school_id group by sc.name) s),
 'by_subject',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select jsonb_build_object('label',su.name,'avg',round(avg(pct),1),'n',count(*)) x from v join subjects su on su.id=v.subject_id group by su.name) s),
 'by_exam',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select jsonb_build_object('label',e.title,'attempts',count(a.id),'submitted',count(v.id),'avg',round(avg(v.pct),1),'avg_secs',round(avg(v.elapsed_seconds))) x from exams e left join exam_attempts a on a.exam_id=e.id left join v on v.id=a.id where(p_grade is null or e.grade=p_grade) and(p_year is null or e.academic_year=p_year) group by e.id,e.title) s),
 'hard_questions',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select jsonb_build_object('label',left(q.text,80),'pct_correct',round(100*avg((sa.chosen_opt=k.correct_opt)::int),1),'n',count(*)) x from student_answers sa join v on v.id=sa.attempt_id join questions q on q.id=sa.question_id join question_keys k on k.question_id=q.id group by q.id,q.text having count(*)>=5 order by avg((sa.chosen_opt=k.correct_opt)::int) limit 10) s))); end $$;
-- storage: images readable only if attached to a question/option the user may see (admins: all)
drop policy if exists qi_read on storage.objects;
create policy qi_read on storage.objects for select to authenticated using(bucket_id='question-images' and(is_admin('{super_admin,admin,exam_manager}') or exists(select 1 from questions q where q.image_path=name) or exists(select 1 from question_options o join questions q on q.id=o.question_id where o.image_path=name)));
revoke all on function set_exam_options,set_option,get_result,leaderboard,practice_set,admin_analytics from public,anon;
grant execute on function set_exam_options,set_option,get_result,leaderboard,practice_set,admin_analytics to authenticated;

-- delete_question must also detach the question from unpublished exams (exam_questions has no cascade) and refresh their totals
create or replace function delete_question(p_q uuid) returns void language plpgsql security definer as $$
declare ex uuid[]; begin
 if not is_admin('{super_admin,admin,exam_manager}') then raise exception 'forbidden'; end if;
 if exists(select 1 from exam_questions eq join exams e on e.id=eq.exam_id where eq.question_id=p_q and e.published) then raise exception 'question is in a published exam'; end if;
 if exists(select 1 from student_answers where question_id=p_q) then raise exception 'question has student answers'; end if;
 select array_agg(exam_id) into ex from exam_questions where question_id=p_q;
 delete from exam_questions where question_id=p_q; delete from questions where id=p_q;
 update exams set total_marks=(select coalesce(sum(q.marks),0) from exam_questions eq join questions q on q.id=eq.question_id where eq.exam_id=exams.id) where id=any(coalesce(ex,'{}'));
 perform audit('delete_question',jsonb_build_object('question',p_q)); end $$;
revoke all on function delete_question from public,anon; grant execute on function delete_question to authenticated;
