-- Fresh Supabase setup for the single-operator, local-first app.
-- Run once in the SQL Editor of the fresh project rbcsrqisbuutnnxpmcvp.
-- The private Storage object is a verified full-app backup, not player accounts.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'dart-app-backups',
  'dart-app-backups',
  false,
  134217728,
  array['application/octet-stream']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Dart backup owner can read own backup" on storage.objects;
create policy "Dart backup owner can read own backup"
on storage.objects for select to authenticated
using (
  bucket_id = 'dart-app-backups'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Dart backup owner can upload own backup" on storage.objects;
create policy "Dart backup owner can upload own backup"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'dart-app-backups'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Dart backup owner can replace own backup" on storage.objects;
create policy "Dart backup owner can replace own backup"
on storage.objects for update to authenticated
using (
  bucket_id = 'dart-app-backups'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'dart-app-backups'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Dart backup owner can delete own backup" on storage.objects;
create policy "Dart backup owner can delete own backup"
on storage.objects for delete to authenticated
using (
  bucket_id = 'dart-app-backups'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
