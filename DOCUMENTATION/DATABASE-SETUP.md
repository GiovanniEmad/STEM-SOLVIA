# Database
Run in order: 001_schema (tables, RLS, 25 schools, subjects, core RPCs) → 002_exam_engine (answer/mark/submit/result RPCs; closes direct answer inserts) → 003_admin (import_exam, publish, stats) → 004_platform (registration trigger, notifications, bookmarks, collections, practice, leaderboard, analytics, school/user/role RPCs, assignments, storage).
Every write by students/admins goes through SECURITY DEFINER functions that re-check roles. Add each school's email domain in the admin console (Schools → + domain) before students can register.
Known gaps: migrations have not been executed by the author; run them on a fresh project first and report errors. 004 redefines `start_attempt`, `set_published`, the `exams_read` and `q_student` policies.

## 005_completion
Adds shuffle flags, scheduled result release (`results_release_at`), option images + `set_option`, filtered `admin_analytics`, `practice_set` with collections, leaderboard that respects hidden/unreleased results, and a storage read policy limited to images attached to questions the user can see. Run 001→005 in order.
