# Admin guide
1. Create your user in Supabase Auth with a password you choose, then run: `insert into user_roles values('<user uuid>','super_admin');`
2. Sign in at `/admin/login`. Roles: super_admin (all + audit), admin, exam_manager (exams/import), results_manager (overview only).
3. Import: Import tab → download a template → paste/upload → Validate → Import. The exam is created as a draft; publish from the Exams tab.
4. Before students can register, add school email domains: `insert into school_domains(school_id,domain) select id,'<domain>' from schools where name='<school>';`
