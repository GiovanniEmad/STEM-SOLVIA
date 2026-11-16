"""Starts embedded Postgres + PostgREST (Supabase's REST layer) with all migrations, seeds fixtures and writes /tmp/fixtures.json.
Auth (GoTrue) is replaced by locally minted HS256 JWTs. Needs: pip install pgserver psycopg2-binary; PostgREST binary at $POSTGREST (default /tmp/postgrest_bin)."""
import os,sys,json,time,hmac,hashlib,base64,subprocess,urllib.request,glob
HERE=os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(HERE,'db_setup.py')).read().split("files=sorted")[0])
for f in sorted(glob.glob(ROOT+'/SUPABASE/migrations/*.sql')): cur.execute(open(f).read())
SECRET='test-secret-test-secret-test-secret-123456'
def jwt(claims):
    b=lambda x:base64.urlsafe_b64encode(x).rstrip(b'=')
    h=b(json.dumps({'alg':'HS256','typ':'JWT'}).encode());p=b(json.dumps({**claims,'exp':4102444800}).encode())
    return (h+b'.'+p+b'.'+b(hmac.new(SECRET.encode(),h+b'.'+p,hashlib.sha256).digest())).decode()
def as_(uid,sql,args=None):
    cur.execute("reset role");cur.execute("select set_config('request.jwt.claim.sub',%s,false)",(str(uid),));cur.execute("set role authenticated")
    try: cur.execute(sql,args);r=cur.fetchall() if cur.description else []
    finally: cur.execute("reset role")
    return r
cur.execute("select id from schools where name='Luxor STEM School'");L=cur.fetchone()[0]
meta=lambda n,g:json.dumps({'full_name':n,'phone':'01275856450','school_id':str(L),'grade':g})
def reg(email,m):
    cur.execute("insert into auth.users(email,raw_user_meta_data) values(%s,%s) returning id",(email,m));return str(cur.fetchone()[0])
S1=reg('a.1@stemluxor.moe.edu.eg',meta('Ali Ahmed Hassan Omar',11));S2=reg('b.2@stemluxor.moe.edu.eg',meta('Sara Mona Adel Samir',10));S3=reg('c.3@stemluxor.moe.edu.eg',meta('Omar Khaled Nabil Taha',11))
ADM=reg('root@x.com','{}');cur.execute("insert into user_roles values(%s,'super_admin')",(ADM,))
doc=json.load(open(ROOT+'/JSON-TEMPLATES/mcq-template.json'));base=doc['questions'][0];qs=[]
for i,(m,topic) in enumerate([(1,'Electricity'),(2,'Electricity'),(1,'Optics')],1):
    q=json.loads(json.dumps(base));q.update(question_id=f'P{i}',marks=m,topic=topic,question_text=f'Question {i}: what is $V=IR$?');qs.append(q)
EID=as_(ADM,"select import_exam(%s::jsonb,'seed1')",(json.dumps({'exam':doc['exam'],'questions':qs}),))[0][0]['exam_id']
as_(ADM,"select set_published(%s,true)",(EID,));as_(ADM,"select set_exam_flags(%s,true,true,'immediate',true)",(EID,))
cur.execute("select external_id,id from questions");Q={a:str(b) for a,b in cur.fetchall()}
cur.execute("create role authenticator noinherit login;grant anon,authenticated to authenticator;notify pgrst, 'reload schema'")
env=dict(os.environ,PGRST_DB_URI='postgresql://authenticator:@/postgres?host=/tmp/pgdata',PGRST_DB_SCHEMAS='public',PGRST_DB_ANON_ROLE='anon',PGRST_JWT_SECRET=SECRET,PGRST_SERVER_PORT='3000',PGRST_DB_POOL='5')
pr=subprocess.Popen([os.environ.get('POSTGREST','/tmp/postgrest_bin')],env=env,stdout=open('/tmp/postgrest.log','w'),stderr=subprocess.STDOUT);open('/tmp/postgrest.pid','w').write(str(pr.pid))
for _ in range(60):
    try: urllib.request.urlopen('http://127.0.0.1:3000/',timeout=1);break
    except urllib.error.HTTPError: break
    except Exception: time.sleep(0.5)

# Supabase's gateway maps /rest/v1/* -> PostgREST /*; supabase-js expects that prefix.
import http.client,threading
EM={S1:'a.1@stemluxor.moe.edu.eg',S2:'b.2@stemluxor.moe.edu.eg',S3:'c.3@stemluxor.moe.edu.eg',ADM:'root@x.com'}
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
class H(BaseHTTPRequestHandler):
    def auth(self):
        path=self.path.split('?')[0];n=int(self.headers.get('Content-Length') or 0);body=json.loads(self.rfile.read(n) or b'{}') if n else {}
        def send(code,obj=None):
            data=json.dumps(obj).encode() if obj is not None else b''
            self.send_response(code);self.send_header('Access-Control-Allow-Origin','*');self.send_header('Access-Control-Allow-Headers',self.headers.get('Access-Control-Request-Headers') or '*');self.send_header('Access-Control-Allow-Methods','*')
            self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
        if self.command=='OPTIONS': return send(204)
        if path.endswith('/token'):
            ids=[k for k,v in EM.items() if v==body.get('email')]
            if not ids or body.get('password')!='pw': return send(400,{'code':400,'error_code':'invalid_credentials','msg':'Invalid login credentials','error_description':'Invalid login credentials'})
            u={'id':ids[0],'email':EM[ids[0]],'aud':'authenticated','role':'authenticated','app_metadata':{},'user_metadata':{},'created_at':'2026-01-01T00:00:00Z'}
            return send(200,{'access_token':jwt({'role':'authenticated','sub':ids[0]}),'token_type':'bearer','expires_in':3600,'expires_at':int(time.time())+3600,'refresh_token':'r','user':u})
        if path.endswith('/user'):
            tok=(self.headers.get('Authorization') or 'Bearer x').split()[1]
            try: sub=json.loads(base64.urlsafe_b64decode(tok.split('.')[1]+'=='))['sub']
            except Exception: return send(401,{'msg':'bad token'})
            return send(200,{'id':sub,'email':EM.get(sub),'aud':'authenticated','role':'authenticated','app_metadata':{},'user_metadata':{}})
        return send(204)
    protocol_version='HTTP/1.1'
    def log_message(self,*a): pass
    def do(self):
        if self.path.startswith('/auth/v1'): return self.auth()
        n=int(self.headers.get('Content-Length') or 0);body=self.rfile.read(n) if n else None
        hd={k:v for k,v in self.headers.items() if k.lower() not in('host','connection','content-length')}
        c=http.client.HTTPConnection('127.0.0.1',3000);c.request(self.command,self.path.replace('/rest/v1','',1),body,hd);r=c.getresponse();data=r.read()
        self.send_response(r.status)
        for k,v in r.getheaders():
            if k.lower() not in('transfer-encoding','connection','content-length'): self.send_header(k,v)
        self.send_header('Content-Length',str(len(data)));self.end_headers()
        if self.command!='HEAD': self.wfile.write(data)
    do_GET=do_POST=do_PATCH=do_DELETE=do_PUT=do_HEAD=do_OPTIONS=do
ThreadingHTTPServer.daemon_threads=True
threading.Thread(target=ThreadingHTTPServer(('127.0.0.1',3001),H).serve_forever,daemon=True).start()
U=lambda i:{'id':i,'jwt':jwt({'role':'authenticated','sub':i})}
json.dump({'url':'http://127.0.0.1:3001','anon':jwt({'role':'anon'}),'s1':U(S1),'s2':U(S2),'s3':U(S3),'admin':U(ADM),'exam':EID,'q':Q,'school':str(L)},open('/tmp/fixtures.json','w'))
print('READY',flush=True)
while True: time.sleep(3600)
