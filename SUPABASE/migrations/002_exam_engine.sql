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
