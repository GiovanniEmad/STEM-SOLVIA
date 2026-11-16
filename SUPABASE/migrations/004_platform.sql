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
