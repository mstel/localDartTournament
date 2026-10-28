-- Run this in the SQL Editor of the app's Supabase project.
-- Never put a service role or sb_secret key into the Flutter app.

create table if not exists public.player_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  country text not null default '',
  city text not null default '',
  darts_setup_json text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_active boolean not null default true,
  constraint player_profiles_user_id_unique unique (user_id)
);

create table if not exists public.tournaments (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  community_id uuid,
  client_tournament_id text,
  name text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false
);

create table if not exists public.communities (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 80),
  description text not null default '',
  invite_code text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.community_members (
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id uuid not null references public.player_profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at timestamptz not null default now(),
  primary key (community_id, user_id)
);

alter table public.tournaments
  add column if not exists community_id uuid references public.communities(id) on delete set null;
alter table public.tournaments
  add column if not exists client_tournament_id text;
create unique index if not exists tournaments_client_tournament_id_key
  on public.tournaments(client_tournament_id);
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'tournaments_community_id_fkey'
  ) then
    alter table public.tournaments
      add constraint tournaments_community_id_fkey
      foreign key (community_id) references public.communities(id) on delete set null;
  end if;
end;
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_player_profiles_updated_at on public.player_profiles;
create trigger set_player_profiles_updated_at
before update on public.player_profiles
for each row execute function public.set_updated_at();

drop trigger if exists set_tournaments_updated_at on public.tournaments;
create trigger set_tournaments_updated_at
before update on public.tournaments
for each row execute function public.set_updated_at();

drop trigger if exists set_communities_updated_at on public.communities;
create trigger set_communities_updated_at
before update on public.communities
for each row execute function public.set_updated_at();

alter table public.player_profiles enable row level security;
alter table public.tournaments enable row level security;
alter table public.communities enable row level security;
alter table public.community_members enable row level security;

create or replace function public.is_community_member(requested_community_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.community_members
    where community_id = requested_community_id and user_id = auth.uid()
  );
$$;

drop policy if exists "Users can read their own profile" on public.player_profiles;
create policy "Users can read their own profile"
on public.player_profiles
for select
using (auth.uid() = user_id);
-- Community members need names for the shared member list.
drop policy if exists "Community members can read member profiles" on public.player_profiles;
create policy "Community members can read member profiles"
on public.player_profiles for select
using (
  exists (
    select 1 from public.community_members mine
    join public.community_members theirs
      on theirs.community_id = mine.community_id
    where mine.user_id = auth.uid() and theirs.user_id = player_profiles.id
  )
);

drop policy if exists "Users can insert their own profile" on public.player_profiles;
create policy "Users can insert their own profile"
on public.player_profiles
for insert
with check (auth.uid() = user_id and auth.uid() = id);

drop policy if exists "Users can update their own profile" on public.player_profiles;
create policy "Users can update their own profile"
on public.player_profiles
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id and auth.uid() = id);

drop policy if exists "Users can read their own tournaments" on public.tournaments;
create policy "Users can read their own tournaments"
on public.tournaments
for select
using (
  auth.uid() = owner_user_id
  or (community_id is not null and public.is_community_member(community_id))
);

drop policy if exists "Users can insert their own tournaments" on public.tournaments;
create policy "Users can insert their own tournaments"
on public.tournaments
for insert
with check (
  auth.uid() = owner_user_id
  and (community_id is null or public.is_community_member(community_id))
);

drop policy if exists "Users can update their own tournaments" on public.tournaments;
create policy "Users can update their own tournaments"
on public.tournaments
for update
using (auth.uid() = owner_user_id)
with check (
  auth.uid() = owner_user_id
  and (community_id is null or public.is_community_member(community_id))
);

drop policy if exists "Members can read communities" on public.communities;
create policy "Members can read communities"
on public.communities for select
using (public.is_community_member(id) or auth.uid() = owner_user_id);

drop policy if exists "Users can create communities" on public.communities;
create policy "Users can create communities"
on public.communities for insert
with check (auth.uid() = owner_user_id);

drop policy if exists "Owners can update communities" on public.communities;
create policy "Owners can update communities"
on public.communities for update
using (auth.uid() = owner_user_id)
with check (auth.uid() = owner_user_id);

drop policy if exists "Members can read memberships" on public.community_members;
create policy "Members can read memberships"
on public.community_members for select
using (public.is_community_member(community_id));

drop policy if exists "Owners can add initial membership" on public.community_members;
create policy "Owners can add initial membership"
on public.community_members for insert
with check (
  auth.uid() = user_id
  and exists (
    select 1 from public.communities
    where id = community_id and owner_user_id = auth.uid()
  )
);

create or replace function public.join_community_by_code(requested_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_community public.communities;
begin
  if auth.uid() is null then
    raise exception 'Anmeldung erforderlich';
  end if;

  select * into selected_community
  from public.communities
  where invite_code = upper(trim(requested_code));

  if selected_community.id is null then
    raise exception 'Einladungscode nicht gefunden';
  end if;

  insert into public.community_members (community_id, user_id, role)
  values (selected_community.id, auth.uid(), 'member')
  on conflict (community_id, user_id) do nothing;

  return to_jsonb(selected_community);
end;
$$;

revoke all on function public.join_community_by_code(text) from public;
grant execute on function public.join_community_by_code(text) to authenticated;
-- One replaceable scorer session per authenticated account. Undo updates the
-- same session; community summaries continue to use tournaments.payload.
create table if not exists public.player_match_statistics (
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  session_id text not null,
  payload jsonb not null,
  primary key (owner_user_id, session_id),
  constraint statistics_payload_owner check (payload ? 'accountId' and payload->>'accountId' is not null and payload->>'accountId' = owner_user_id::text),
  constraint statistics_payload_session check (payload ? 'id' and payload->>'id' is not null and payload->>'id' = session_id),
  constraint statistics_payload_version check (payload ? 'schemaVersion' and payload->>'schemaVersion' is not null and payload->>'schemaVersion' = '1')
);
alter table public.player_match_statistics enable row level security;
grant select, insert, update on public.player_match_statistics to authenticated;

drop policy if exists "Read own scorer statistics" on public.player_match_statistics;
create policy "Read own scorer statistics" on public.player_match_statistics
  for select to authenticated using (auth.uid() = owner_user_id);
drop policy if exists "Insert own scorer statistics" on public.player_match_statistics;
create policy "Insert own scorer statistics" on public.player_match_statistics
  for insert to authenticated with check (auth.uid() = owner_user_id);
drop policy if exists "Update own scorer statistics" on public.player_match_statistics;
create policy "Update own scorer statistics" on public.player_match_statistics
  for update to authenticated using (auth.uid() = owner_user_id)
  with check (auth.uid() = owner_user_id);
-- Private, versioned personal profile, including its resized image.
create table if not exists public.personal_profiles (
  owner_user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null,
  constraint personal_profile_version check (payload ? 'version' and payload->>'version' = '1'),
  constraint personal_profile_name check (jsonb_typeof(payload->'name') = 'string' and length(trim(payload->>'name')) between 1 and 100),
  constraint personal_profile_size check (octet_length(payload::text) <= 8388608)
);
alter table public.personal_profiles enable row level security;
grant select, insert, update on public.personal_profiles to authenticated;
drop policy if exists "Read own personal profile" on public.personal_profiles;
create policy "Read own personal profile" on public.personal_profiles for select to authenticated using (auth.uid() = owner_user_id);
drop policy if exists "Insert own personal profile" on public.personal_profiles;
create policy "Insert own personal profile" on public.personal_profiles for insert to authenticated with check (auth.uid() = owner_user_id);
drop policy if exists "Update own personal profile" on public.personal_profiles;
create policy "Update own personal profile" on public.personal_profiles for update to authenticated using (auth.uid() = owner_user_id) with check (auth.uid() = owner_user_id);

-- League invitation support
begin;
create table if not exists public.league_invitations (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references auth.users(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  match_id text not null,
  title text not null,
  team integer not null check(team in (0,1)),
  slot integer not null check(slot between 0 and 8),
  display_name text not null,
  status text not null default 'pending' check(status in ('pending','accepted','declined','cancelled')),
  closed boolean not null default false,
  expires_at timestamptz not null default now() + interval '2 days',
  unique(host_id,match_id,team,slot)
);
create index if not exists league_invitation_inbox on public.league_invitations(user_id,status);
alter table public.league_invitations enable row level security;
revoke all on public.league_invitations from anon, authenticated;
create or replace function public.league_invitation_action(action text, args jsonb default '{}')
returns jsonb language plpgsql security definer set search_path=public as $$
declare me uuid := auth.uid(); item public.league_invitations; target uuid; display text;
begin
  if me is null then raise exception 'Anmeldung erforderlich' using errcode='42501'; end if;
  if action='invite' then
    perform 1 from auth.users where id=me for update;
    target := (args->>'user')::uuid;
    if target=me or not exists(select 1 from public.community_members a join public.community_members b on a.community_id=b.community_id where a.user_id=me and b.user_id=target) then
      raise exception 'Keine gemeinsame Community' using errcode='42501';
    end if;
    if length(args->>'title') not between 1 and 200 or length(args->>'match') not between 1 and 100 then raise exception 'Ungültiges Ligaspiel'; end if;
    if exists(select 1 from public.league_invitations where host_id=me and match_id=args->>'match' and (closed or (user_id=target and status in ('pending','accepted')))) then raise exception 'Ligaspiel geschlossen oder Mitglied bereits eingeladen'; end if;
    select coalesce(nullif(display_name,''),'Mitglied') into display from public.player_profiles where id=target;
    insert into public.league_invitations(host_id,user_id,match_id,title,team,slot,display_name)
      values(me,target,args->>'match',args->>'title',(args->>'team')::int,(args->>'slot')::int,coalesce(display,'Mitglied'))
      on conflict(host_id,match_id,team,slot) do update set id=gen_random_uuid(),user_id=excluded.user_id, title=excluded.title, display_name=excluded.display_name,status='pending',expires_at=now()+interval '2 days'
      returning * into item;
    return to_jsonb(item);
  elsif action='inbox' then
    return coalesce((select jsonb_agg(to_jsonb(i)) from public.league_invitations i where user_id=me and status='pending' and not closed and expires_at>now()),'[]'::jsonb);
  elsif action='status' then
    return coalesce((select jsonb_agg(to_jsonb(i)) from public.league_invitations i where host_id=me and match_id=args->>'match'),'[]'::jsonb);
  elsif action='respond' then
    select * into item from public.league_invitations where id=(args->>'id')::uuid and user_id=me for update;
    if item.id is null or item.closed or item.expires_at<=now() or item.status<>'pending' then raise exception 'Einladung nicht mehr verfügbar'; end if;
    update public.league_invitations set status=case when (args->>'accept')::boolean then 'accepted' else 'declined' end where id=item.id;
  elsif action='cancel' then
    update public.league_invitations set status='cancelled' where id=(args->>'id')::uuid and host_id=me and not closed;
  elsif action='close' then
    perform 1 from auth.users where id=me for update;
    perform 1 from public.league_invitations where host_id=me and match_id=args->>'match' for update;
    if exists(select 1 from public.league_invitations where host_id=me and match_id=args->>'match' and status='pending') then raise exception 'Offene Einladungen zuerst beantworten oder zurückziehen'; end if;
    update public.league_invitations set closed=true where host_id=me and match_id=args->>'match';
  else raise exception 'Unbekannte Aktion';
  end if;
  return '{}'::jsonb;
end $$;
revoke all on function public.league_invitation_action(text,jsonb) from public,anon;
grant execute on function public.league_invitation_action(text,jsonb) to authenticated;
commit;
