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
