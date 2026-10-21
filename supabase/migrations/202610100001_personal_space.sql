-- Authenticated users create their own private, one-member Space explicitly.
-- This migration does not provision or connect a Supabase project.
begin;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  locale text not null default 'en',
  created_at timestamptz not null default now()
);

create table if not exists public.spaces (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Our Space',
  status text not null default 'active' check (status in ('active', 'merged')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.space_members (
  space_id uuid not null references public.spaces(id) on delete cascade,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  role text not null default 'owner' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (space_id, user_id)
);

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, nullif(new.raw_user_meta_data ->> 'display_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function public.handle_new_auth_user() from public, anon, authenticated;
drop trigger if exists create_profile_for_auth_user on auth.users;
create trigger create_profile_for_auth_user after insert on auth.users
for each row execute function public.handle_new_auth_user();

create or replace function public.enforce_space_member_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform 1 from public.spaces where id = new.space_id and status = 'active' for update;
  if not found then raise exception 'SPACE_NOT_ACTIVE'; end if;
  if (select count(*) from public.space_members where space_id = new.space_id) >= 2 then
    raise exception 'SPACE_FULL';
  end if;
  return new;
end;
$$;

drop trigger if exists space_member_limit on public.space_members;
create trigger space_member_limit before insert on public.space_members
for each row execute function public.enforce_space_member_limit();

create or replace function public.create_personal_space()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_space uuid;
begin
  if v_user is null then raise exception 'NOT_AUTHENTICATED'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text, 0));
  select space_id into v_space from public.space_members where user_id = v_user;
  if v_space is not null then return v_space; end if;
  insert into public.spaces (created_by) values (v_user) returning id into v_space;
  insert into public.space_members (space_id, user_id, role) values (v_space, v_user, 'owner');
  return v_space;
end;
$$;

revoke all on function public.create_personal_space() from public, anon;
grant execute on function public.create_personal_space() to authenticated;

alter table public.profiles enable row level security;
alter table public.spaces enable row level security;
alter table public.space_members enable row level security;

drop policy if exists profile_self_read on public.profiles;
create policy profile_self_read on public.profiles for select to authenticated
using (id = (select auth.uid()));
drop policy if exists profile_self_update on public.profiles;
create policy profile_self_update on public.profiles for update to authenticated
using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy if exists space_member_read on public.spaces;
create policy space_member_read on public.spaces for select to authenticated
using (exists (select 1 from public.space_members m where m.space_id = id and m.user_id = (select auth.uid())));

drop policy if exists membership_self_read on public.space_members;
create policy membership_self_read on public.space_members for select to authenticated
using (user_id = (select auth.uid()));
revoke insert, update, delete on public.space_members from anon, authenticated;
revoke insert, update, delete on public.spaces from anon, authenticated;
revoke all on public.profiles from anon;
grant select, update on public.profiles to authenticated;
grant select on public.spaces, public.space_members to authenticated;

commit;
