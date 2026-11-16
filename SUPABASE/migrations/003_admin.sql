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
