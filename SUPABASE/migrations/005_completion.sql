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
