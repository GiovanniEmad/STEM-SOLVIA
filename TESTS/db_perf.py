"""Load check: 3000 students, 3000 submitted attempts, 120k saved answers. Prints timings of the heaviest queries."""
import os,time,json,glob
HERE=os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(HERE,'db_setup.py')).read().split("files=sorted")[0])
cur=c.cursor()
for f in sorted(glob.glob(ROOT+'/SUPABASE/migrations/*.sql')): cur.execute(open(f).read())
N=3000;Qn=40
t=time.time()
cur.execute("select id from schools order by name");S=[r[0] for r in cur.fetchall()]
cur.execute("insert into auth.users(email) select 'u'||g||'@x.com' from generate_series(1,%s) g",(N,))
cur.execute("insert into profiles(id,full_name,phone,school_id,grade) select id,'Student '||row_number() over()||' A B','01275856450',(%s::uuid[])[1+(row_number() over())%%25],11 from auth.users",(S,))
cur.execute("insert into auth.users(email) values('adm@x.com') returning id");ADM=cur.fetchone()[0];cur.execute("insert into user_roles values(%s,'super_admin')",(ADM,))
cur.execute("select id from subjects where name='Physics'");sub=cur.fetchone()[0]
cur.execute("insert into exams(title,grade,subject_id,published,allow_retakes,practice_enabled,academic_year) values('Load exam',11,%s,true,true,true,'2025-2026') returning id",(sub,));E=cur.fetchone()[0]
cur.execute("insert into questions(text,marks,topic) select 'Q'||g,1,'T'||(g%%5) from generate_series(1,%s) g",(Qn,))
cur.execute("insert into question_options select id,o,'opt '||o from questions,unnest(array['A','B','C','D']) o")
cur.execute("insert into question_keys select id,'B' from questions")
cur.execute("insert into exam_questions select %s,id,row_number() over() from questions",(E,))
cur.execute("update exams set total_marks=%s where id=%s",(Qn,E))
cur.execute("insert into exam_attempts(user_id,exam_id,status,elapsed_seconds,running_since,score,submitted_at) select id,%s,'submitted',1800+(random()*3000)::int,null,(random()*%s)::int,now()-(random()*30||' days')::interval from profiles",(E,Qn))
cur.execute("insert into student_answers select a.id,q.id,(array['A','B','C','D'])[1+(random()*3)::int] from exam_attempts a cross join questions q")
cur.execute("analyze")
print(f"seed {N} students / {N*Qn} answers: {time.time()-t:.1f}s")
cur.execute("select id from profiles limit 1");U=cur.fetchone()[0]
def timed(name,uid,sql,args=None,limit=500):
    cur.execute("reset role");cur.execute("select set_config('request.jwt.claim.sub',%s,false)",(str(uid),));cur.execute("set role authenticated")
    t=time.time();cur.execute(sql,args);cur.fetchall();ms=(time.time()-t)*1000;cur.execute("reset role")
    print(f"{'OK  ' if ms<limit else 'SLOW'} {name}: {ms:.0f} ms");return ms<limit
ok=True
ok&=timed('library list (student, RLS)',U,"select e.id,e.title,s.name,(select count(*) from exam_questions x where x.exam_id=e.id) from exams e join subjects s on s.id=e.subject_id where e.published")
ok&=timed('student_stats',U,"select student_stats()")
ok&=timed('leaderboard national top-50 (3000 attempts)',U,"select leaderboard('national',%s)",(E,))
ok&=timed('leaderboard school',U,"select leaderboard('school',%s)",(E,))
ok&=timed('admin_analytics (unfiltered)',ADM,"select admin_analytics()",limit=1500)
ok&=timed('admin_analytics (grade+school filter)',ADM,"select admin_analytics(null,null,%s,11::smallint,null)",(S[0],),limit=1500)
ok&=timed('admin_stats',ADM,"select admin_stats()")
cur.execute("insert into auth.users(email) values('new@x.com') returning id");NU=cur.fetchone()[0];cur.execute("insert into profiles(id,full_name,phone,school_id,grade) values(%s,'New A B C','01275856450',%s,11)",(NU,S[0]))
cur.execute("reset role");cur.execute("select set_config('request.jwt.claim.sub',%s,false)",(str(NU),));cur.execute("set role authenticated")
cur.execute("select start_attempt(%s)",(E,));A=cur.fetchone()[0];cur.execute("reset role");cur.execute("select id from questions");QS=[r[0] for r in cur.fetchall()]
cur.execute("set role authenticated")
t=time.time()
for q in QS: cur.execute("select save_answer(%s,%s,'B')",(A,q))
print(f"save_answer x{Qn}: {(time.time()-t)*1000/Qn:.1f} ms each")
ok&=timed('submit_attempt (grade 40 answers)',NU,"select submit_attempt(%s)",(A,))
print('PERF_OK' if ok else 'PERF_SLOW')
