import os
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
import pgserver,psycopg2,sys,glob,shutil,os
shutil.rmtree('/tmp/pgdata',ignore_errors=True)
srv=pgserver.get_server('/tmp/pgdata');uri=srv.get_uri()
def conn():
    c=psycopg2.connect(uri);c.autocommit=True;return c
STUB="""
create role anon nologin; create role authenticated nologin; create role service_role nologin;
create schema auth; create table auth.users(id uuid primary key default gen_random_uuid(),email text,raw_user_meta_data jsonb);
create function auth.uid() returns uuid language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub'))::uuid $$;
create schema storage; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text); alter table storage.objects enable row level security;
grant usage on schema public,auth,storage to anon,authenticated;
alter default privileges in schema public grant all on tables to anon,authenticated;
alter default privileges in schema public grant all on sequences to anon,authenticated;
grant select on auth.users to authenticated; grant all on storage.objects,storage.buckets to authenticated;
"""
c=conn();cur=c.cursor();cur.execute(STUB)
files=sorted(glob.glob(ROOT+'/SUPABASE/migrations/*.sql'))
ok=True
for f in files:
    try: cur.execute(open(f).read());print('OK ',os.path.basename(f))
    except Exception as e: print('ERR',os.path.basename(f),str(e).strip()[:400]);ok=False;break
print('MIGRATIONS_OK' if ok else 'MIGRATIONS_FAILED')
