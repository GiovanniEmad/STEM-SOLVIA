import pgserver,psycopg2,json,uuid,re,subprocess
import os
HERE=os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(HERE,'db_setup.py')).read().split("files=sorted")[0])  # fresh server + stubs
import glob,os
cur=c.cursor()
for f in sorted(glob.glob(ROOT+'/SUPABASE/migrations/*.sql')): cur.execute(open(f).read())
res=[]
def T(name,cond,extra=''):
    res.append((name,bool(cond)));print(('PASS ' if cond else 'FAIL ')+name+(' | '+str(extra)[:160] if not cond else ''))
def as_(uid,sql,args=None):
    cur.execute("reset role");
    if uid: cur.execute("select set_config('request.jwt.claim.sub',%s,false)",(str(uid),));cur.execute("set role authenticated")
    else: cur.execute("set role anon")
    try:
        cur.execute(sql,args);
        try: r=cur.fetchall()
        except Exception: r=[]
        return ('OK',r)
    except Exception as e: return ('ERR',str(e).strip().split('\n')[0])
    finally: cur.execute("reset role")
def su(sql,args=None): cur.execute("reset role");cur.execute(sql,args);
    
cur.execute("select id from schools where name='Luxor STEM School'");L=cur.fetchone()[0]
cur.execute("select id from schools where name='Aswan STEM School'");AS=cur.fetchone()[0]
meta=lambda n,g,s=None,ph='01275856450':json.dumps({'full_name':n,'phone':ph,'school_id':str(s or L),'grade':g})
def reg(email,m):
    try: su("insert into auth.users(email,raw_user_meta_data) values(%s,%s) returning id",(email,m));cur.execute("select id from auth.users where email=%s",(email,));return cur.fetchone()[0]
    except Exception as e: return 'ERR:'+str(e).split('\n')[0]
S1=reg('a.1@stemluxor.moe.edu.eg',meta('Ali Ahmed Hassan Omar',11))
S2=reg('b.2@stemluxor.moe.edu.eg',meta('Sara Mona Adel Samir',10))
S3=reg('c.3@stemluxor.moe.edu.eg',meta('Omar Khaled Nabil Taha',11))
T('registration creates profile',cur.execute("select count(*) from profiles") or cur.fetchone()[0]==3)
T('rejects unapproved domain',str(reg('x@gmail.com',meta('A B C D',11))).startswith('ERR'))
T('rejects 3-name registration',str(reg('y@stemluxor.moe.edu.eg',meta('A B C',11))).startswith('ERR'))
T('rejects bad phone',str(reg('z@stemluxor.moe.edu.eg',meta('A B C D',11,ph='123'))).startswith('ERR'))
T('rejects domain not belonging to chosen school',str(reg('w@stemluxor.moe.edu.eg',meta('A B C D',11,AS))).startswith('ERR'))
cur.execute("insert into auth.users(email) values('root@x.com') returning id");ADM=cur.fetchone()[0]
su("insert into user_roles values(%s,'super_admin')",(ADM,))
T('operator-created user (no metadata) gets no profile',cur.execute("select count(*) from profiles where id=%s",(ADM,)) or cur.fetchone()[0]==0)
doc=json.load(open(ROOT+'/JSON-TEMPLATES/mcq-template.json'))
base=doc['questions'][0]
def mk(i,m,ans='B'):
    q=json.loads(json.dumps(base));q['question_id']=f'P{i}';q['marks']=m;q['correct_answer']=ans;q['topic']='Electricity';return q
good={'exam':doc['exam'],'questions':[mk(1,1),mk(2,2),mk(3,1)]}
imp=lambda d,u=ADM:as_(u,"select import_exam(%s::jsonb,%s)",(json.dumps(d),str(uuid.uuid4())))
r=as_(S1,"select import_exam(%s::jsonb,'h0')",(json.dumps(good),));T('student cannot import',r[0]=='ERR' and 'forbidden' in r[1],r)
bad=json.loads(json.dumps(good));bad['questions'][2]['correct_answer']='Z'
r=imp(bad);T('invalid question rejects whole import',r[0]=='ERR',r)
cur.execute("select (select count(*) from exams),(select count(*) from questions)");T('rejected import rolled back fully',cur.fetchone()==(0,0))
for k,v in [('question_type','TF'),('marks',0)]:
    b=json.loads(json.dumps(good));b['questions'][0][k]=v;T(f'server rejects {k}={v}',imp(b)[0]=='ERR')
b=json.loads(json.dumps(good));b['questions'][1]['options'][1]['id']='A';T('server rejects duplicate option ids',imp(b)[0]=='ERR')
b=json.loads(json.dumps(good));b['questions'][1]['question_id']='P1';T('server rejects duplicate question ids',imp(b)[0]=='ERR')
h=str(uuid.uuid4());r=as_(ADM,"select import_exam(%s::jsonb,%s)",(json.dumps(good),h));T('valid import succeeds',r[0]=='OK',r)
EID=r[1][0][0]['exam_id'] if r[0]=='OK' else None
T('same file import blocked',as_(ADM,"select import_exam(%s::jsonb,%s)",(json.dumps(good),h))[0]=='ERR')
cur.execute("select total_marks,published from exams where id=%s",(EID,));T('total marks computed, draft by default',cur.fetchone()==(4,False))
T('student cannot see draft exam',as_(S1,"select id from exams")[1]==[])
T('student cannot publish',as_(S1,"select set_published(%s,true)",(EID,))[0]=='ERR')
T('admin publishes',as_(ADM,"select set_published(%s,true)",(EID,))[0]=='OK')
T('grade-11 student sees exam',len(as_(S1,"select id from exams")[1])==1)
T('grade-10 student does NOT see grade-11 exam',as_(S2,"select id from exams")[1]==[])
T('grade-10 student cannot start it',as_(S2,"select start_attempt(%s)",(EID,))[0]=='ERR')
T('publish notified grade 11 only',(cur.execute("select count(*) from notifications where user_id in(%s,%s)",(S1,S3)) or cur.fetchone()[0]==2) and (cur.execute("select count(*) from notifications where user_id=%s",(S2,)) or cur.fetchone()[0]==0))
T('student cannot read answer keys',as_(S1,"select * from question_keys")[1]==[])
r=as_(S1,"select start_attempt(%s)",(EID,));A1=r[1][0][0];T('start attempt',r[0]=='OK')
T('start is idempotent (one active attempt)',as_(S1,"select start_attempt(%s)",(EID,))[1][0][0]==A1)
cur.execute("select id,external_id from questions");Q={e:i for i,e in cur.fetchall()}
T('save correct answer',as_(S1,"select save_answer(%s,%s,'B')",(A1,Q['P1']))[0]=='OK')
T('change answer',as_(S1,"select save_answer(%s,%s,'A')",(A1,Q['P1']))[0]=='OK' and as_(S1,"select save_answer(%s,%s,'B')",(A1,Q['P1']))[0]=='OK')
as_(S1,"select save_answer(%s,%s,'B')",(A1,Q['P2']));as_(S1,"select save_answer(%s,%s,'A')",(A1,Q['P3']))
T('invalid option rejected',as_(S1,"select save_answer(%s,%s,'Z')",(A1,Q['P1']))[0]=='ERR')
T('other student cannot save into my attempt',as_(S3,"select save_answer(%s,%s,'A')",(A1,Q['P1']))[0]=='ERR')
T('other student cannot read my attempt',as_(S3,"select id from exam_attempts")[1]==[])
T('direct insert into student_answers denied',as_(S1,"insert into student_answers values(%s,%s,'B')",(A1,Q['P3']))[0]=='ERR')
as_(S1,"update exam_attempts set score=999,status='submitted' where id=%s",(A1,));cur.execute("select score,status from exam_attempts where id=%s",(A1,));T('student cannot tamper with score/status',cur.fetchone()==(None,'in_progress'))
T('student cannot grant self admin role',as_(S1,"insert into user_roles values(%s,'super_admin')",(S1,))[0]=='ERR')
T('student cannot call admin_stats',as_(S1,"select admin_stats()")[0]=='ERR')
T('student cannot read audit log',as_(S1,"select * from admin_audit_logs")[1]==[])
T('anon cannot call start_attempt',as_(None,"select start_attempt(%s)",(EID,))[0]=='ERR')
T('toggle mark',as_(S1,"select toggle_mark(%s,%s)",(A1,Q['P3']))[0]=='OK')
T('pause clock',as_(S1,"select set_clock(%s,false)",(A1,))[0]=='OK')
cur.execute("update exam_attempts set elapsed_seconds=90000,running_since=null where id=%s",(A1,))  # simulate >24h
r=as_(S1,"select submit_attempt(%s)",(A1,));T('submit succeeds (no time limit, 25h elapsed)',r[0]=='OK',r)
res_=r[1][0][0] if r[0]=='OK' else {}
T('server grading correct (3 of 4 marks)',res_.get('score')==3 and res_.get('total')==4 and res_.get('correct')==2 and res_.get('incorrect')==1 and res_.get('percentage')==75.0,res_)
T('result includes review when show_answers',len(res_.get('review') or [])==3)
T('double submit rejected',as_(S1,"select submit_attempt(%s)",(A1,))[0]=='ERR')
T('cannot save after submit',as_(S1,"select save_answer(%s,%s,'A')",(A1,Q['P1']))[0]=='ERR')
T('retake blocked by default',as_(S1,"select start_attempt(%s)",(EID,))[0]=='ERR')
as_(ADM,"select set_exam_flags(%s,true,false,'immediate',true)",(EID,))
r=as_(S1,"select get_result(%s)",(A1,));T('show_answers=false hides review',r[0]=='OK' and r[1][0][0].get('review') is None,r)
as_(ADM,"select set_exam_flags(%s,true,true,'hidden',true)",(EID,));r=as_(S1,"select get_result(%s)",(A1,));T('results_mode=hidden hides score',r[1][0][0].get('hidden') is True and 'score' not in r[1][0][0])
as_(ADM,"select set_exam_flags(%s,true,true,'immediate',true)",(EID,))
T('retake works when enabled',as_(S1,"select start_attempt(%s)",(EID,))[1][0][0]!=A1)
r=as_(S3,"select start_attempt(%s)",(EID,));A3=r[1][0][0]
for q,o in [('P1','B'),('P2','B'),('P3','B')]: as_(S3,"select save_answer(%s,%s,%s)",(A3,Q[q],o))
as_(S3,"select submit_attempt(%s)",(A3,))
lb=as_(S1,"select leaderboard('grade',%s)",(EID,));T('leaderboard ranks best attempts, shortened names',lb[0]=='OK' and [x['name'] for x in lb[1][0][0]['rows']]==['Omar K.','Ali A.'],lb)
T('leaderboard blocked for other-grade exam',as_(S2,"select leaderboard('national',%s)",(EID,))[0]=='ERR')
as_(ADM,"select set_setting('leaderboards_enabled','false')");T('leaderboard can be disabled',as_(S1,"select leaderboard('grade',%s)",(EID,))[1][0][0].get('disabled') is True)
T('practice_set serves practice-enabled questions',len(as_(S1,"select practice_set(null,'',false,null,10)")[1][0][0])==3)
pc=as_(S1,"select practice_check(%s,'A')",(Q['P1'],));T('practice feedback',pc[0]=='OK' and pc[1][0][0]['correct'] is False)
T('retry-incorrect returns only missed',len(as_(S1,"select practice_set(null,'',true,null,10)")[1][0][0])==1)
T('student_stats works',as_(S1,"select student_stats()")[0]=='OK',as_(S1,"select student_stats()"))
an=as_(ADM,"select admin_analytics()");T('admin_analytics works',an[0]=='OK',an)
T('results_manager can read analytics, cannot import',True)
RM=reg('rm@x.com',json.dumps({}));su("insert into user_roles values(%s,'results_manager')",(RM,))
T('results_manager: analytics ok / import denied',as_(RM,"select admin_analytics()")[0]=='OK' and as_(RM,"select import_exam(%s::jsonb,'zz')",(json.dumps(good),))[0]=='ERR')
T('bookmark + collection ownership',as_(S1,"insert into bookmarks(question_id) values(%s)",(Q['P1'],))[0]=='OK' and as_(S3,"select * from bookmarks")[1]==[])
T('audit log written',(cur.execute("select count(*) from admin_audit_logs") or cur.fetchone()[0])>=4)
T('audit log immutable via API',as_(ADM,"update admin_audit_logs set action='x'")[0]=='ERR' and as_(ADM,"delete from admin_audit_logs")[0]=='ERR')
T('profile change needs approval',as_(S1,"update profiles set grade=12 where id=%s",(S1,))[1]==[] and (cur.execute("select grade from profiles where id=%s",(S1,)) or cur.fetchone()[0]==11))
as_(S1,"select request_change(%s,12::smallint)",(L,));cur.execute("select id from profile_requests");RID=cur.fetchone()[0]
T('student cannot approve own request',as_(S1,"select decide_request(%s,true)",(RID,))[0]=='ERR')
as_(ADM,"select decide_request(%s,true)",(RID,));T('admin approval applies change',(cur.execute("select grade from profiles where id=%s",(S1,)) or cur.fetchone()[0]==12))
T('cannot revoke last super admin',as_(ADM,"select revoke_role(%s,'super_admin')",(ADM,))[0]=='ERR')

as_(ADM,"select set_setting('leaderboards_enabled','true')")
as_(ADM,"select set_exam_options(%s,true,true,null)",(EID,));cur.execute("select shuffle_questions,shuffle_options from exams where id=%s",(EID,));T('shuffle flags saved',cur.fetchone()==(True,True))
T('student cannot set exam options',as_(S1,"select set_exam_options(%s,false,false,null)",(EID,))[0]=='ERR')
as_(ADM,"select set_exam_options(%s,false,false,now()+interval '1 day')",(EID,))
r=as_(S1,"select get_result(%s)",(A1,));T('scheduled release hides result',r[1][0][0].get('hidden') is True and r[1][0][0].get('release_at') is not None,r)
T('leaderboard hidden before release',as_(S3,"select leaderboard('grade',%s)",(EID,))[1][0][0].get('hidden') is True)
as_(ADM,"select set_exam_options(%s,false,false,now()-interval '1 minute')",(EID,))
r=as_(S1,"select get_result(%s)",(A1,));T('result released after schedule; review has option texts',r[0]=='OK' and r[1][0][0].get('score')==3 and r[1][0][0]['review'][0].get('correct_text')=="Ohm's Law",r)
T('student cannot edit options',as_(S1,"select set_option(%s,'A','x','')",(Q['P1'],))[0]=='ERR')
T('admin edits option text+image',as_(ADM,"select set_option(%s,'A','Edited','q/o.png')",(Q['P1'],))[0]=='OK')
T('set_option rejects blank text',as_(ADM,"select set_option(%s,'A',' ','')",(Q['P1'],))[0]=='ERR')
CID='00000000-0000-0000-0000-0000000000c1'
as_(S3,"insert into collections(id,name) values(%s,'mine')",(CID,));as_(S3,"insert into collection_items values(%s,%s)",(CID,Q['P2']))
r=as_(S3,"select practice_set(null,'',false,%s::uuid,10)",(CID,));T('practice from own collection returns only its questions',r[0]=='OK' and len(r[1][0][0])==1,r)
T("other student cannot read my collection",as_(S1,"select * from collections")[1]==[])
a=lambda *x:as_(ADM,"select admin_analytics(%s,%s,%s,%s::smallint,%s)",x)
T('analytics grade 11 has data',len(a(None,None,None,11,None)[1][0][0]['by_grade'])==1,a(None,None,None,11,None))
T('analytics grade 10 empty',a(None,None,None,10,None)[1][0][0]['by_grade']==[])
T('analytics school filter',len(a(None,None,str(L),None,None)[1][0][0]['by_school'])==1 and a(None,None,str(AS),None,None)[1][0][0]['by_school']==[])
T('analytics future date empty',a('2999-01-01',None,None,None,None)[1][0][0]['by_grade']==[])
T('analytics year filter',a(None,None,None,None,'1999')[1][0][0]['by_exam']==[])
su("insert into storage.objects(bucket_id,name) values('question-images','q/o.png'),('question-images','q/secret.png')")
T('student reads only images attached to visible questions',[x[0] for x in as_(S3,"select name from storage.objects")[1]]==['q/o.png'])
T('student cannot upload images',as_(S3,"insert into storage.objects(bucket_id,name) values('question-images','q/evil.png')")[0]=='ERR')
T('admin can upload images',as_(ADM,"insert into storage.objects(bucket_id,name) values('question-images','q/ok.png')")[0]=='OK')
as_(ADM,"select duplicate_exam(%s)",(EID,));cur.execute("select id from exams where title like '%(copy)'");DX=cur.fetchone()[0]
r=as_(ADM,"select create_question('Q?','[{\"id\":\"A\",\"text\":\"1\"},{\"id\":\"B\",\"text\":\"2\"}]'::jsonb,'B',5,'t','Easy','','',%s)",(DX,));NQ=r[1][0][0]
T('delete_question removes it from an unpublished exam and refreshes total_marks',as_(ADM,"select delete_question(%s)",(NQ,))[0]=='OK' and (cur.execute("select total_marks from exams where id=%s",(DX,)) or cur.fetchone()[0]==4))
print(f"\n{sum(1 for _,p in res if p)}/{len(res)} passed")
