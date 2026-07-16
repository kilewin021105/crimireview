# CrimiReview Admin + Supabase-only Questions - TODO

- [ ] Confirm/locate Supabase `questions` table definition (may not exist in current schema)
- [ ] Add `role` column to `public.user_profiles` (default 'user')
- [ ] Add RLS policies: admin-only write access for questions (and any other admin-managed tables)
- [ ] Add Supabase `questions` table schema (if missing)
- [ ] Update `lib/services/question_service.dart` to use Supabase-only questions (disable local fallback)
- [ ] Add role helper(s) to `lib/services/supabase_service.dart` to fetch current user role
- [ ] Create admin UI: `lib/screens/admin/admin_panel_screen.dart`
- [ ] Add Admin Panel button/entry on post-login flow (HomeScreen header)
- [ ] Add admin-only question CRUD methods in `lib/services/question_service.dart`
- [ ] Run `flutter analyze`
- [ ] Manual testing:
  - [ ] Sign in as non-admin: Admin Panel hidden / inaccessible
  - [ ] Sign in as admin: Admin Panel accessible
  - [ ] Load quiz: questions come from Supabase (no local fallback)
  - [ ] Daily challenge works
