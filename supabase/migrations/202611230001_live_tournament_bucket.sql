-- Public, read-only spectator channel for the current tournament.
-- This bucket is deliberately separate from dart-app-backups, which stays private.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'live-tournament',
  'live-tournament',
  true,
  262144,
  array['application/json', 'text/html', 'text/html; charset=utf-8']
)
on conflict (id) do update
set public = true,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Live tournament public read" on storage.objects;
create policy "Live tournament public read"
on storage.objects for select to anon, authenticated
using (bucket_id = 'live-tournament');

drop policy if exists "Live tournament operator insert" on storage.objects;
create policy "Live tournament operator insert"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'live-tournament'
  and (storage.foldername(name))[1] = 'verein-live'
);

drop policy if exists "Live tournament operator update" on storage.objects;
create policy "Live tournament operator update"
on storage.objects for update to authenticated
using (
  bucket_id = 'live-tournament'
  and (storage.foldername(name))[1] = 'verein-live'
)
with check (
  bucket_id = 'live-tournament'
  and (storage.foldername(name))[1] = 'verein-live'
);

drop policy if exists "Live tournament operator delete" on storage.objects;
create policy "Live tournament operator delete"
on storage.objects for delete to authenticated
using (
  bucket_id = 'live-tournament'
  and (storage.foldername(name))[1] = 'verein-live'
);
