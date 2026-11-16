-- Step 1: Supabase Dashboard -> Authentication -> Users -> "Add user" -> your email + a strong password you choose (tick "Auto Confirm User").
-- Step 2: run this in the SQL Editor, replacing the e-mail:
insert into user_roles(user_id, role)
select id, 'super_admin' from auth.users where lower(email) = lower('YOUR-EMAIL@example.com');
-- Step 3 (check): should return 1 row
select u.email, r.role from user_roles r join auth.users u on u.id = r.user_id;
-- School email domains must exist before students can register (or add them in /admin -> schools):
-- insert into school_domains(school_id, domain) select id, 'stemluxor.moe.edu.eg' from schools where name = 'Luxor STEM School'; (already seeded for Luxor)
