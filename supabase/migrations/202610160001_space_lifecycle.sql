-- S10: leave a Space and delete an account with server-enforced safeguards.
-- This migration only adds lifecycle metadata/functions; it does not mutate existing user data.
begin;

create table if not exists public.file_deletion_queue (
  id uuid primary key default gen_random_uuid(),
  bucket_id text not null,
  object_path text not null,
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  queued_at timestamptz not null default now(),
  unique (bucket_id, object_path)
);
alter table public.file_deletion_queue enable row level security;
revoke all on public.file_deletion_queue from public, anon, authenticated;
grant all on public.file_deletion_queue to service_role;

create table if not exists public.space_leave_operations (
  id uuid primary key,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  result text not null check (result in ('completed', 'reconfirm_required', 'no_space')),
  last_member boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.space_leave_operations enable row level security;
revoke all on public.space_leave_operations from public, anon, authenticated;

-- Keep historical references valid when an account is deleted while the other
-- Space member retains the shared plans and files.
alter table public.spaces alter column created_by drop not null;
alter table public.spaces drop constraint if exists spaces_created_by_fkey;
alter table public.spaces add constraint spaces_created_by_fkey
  foreign key (created_by) references auth.users(id) on delete set null;
alter table public.space_invitations alter column created_by drop not null;
alter table public.space_invitations drop constraint if exists space_invitations_created_by_fkey;
alter table public.space_invitations add constraint space_invitations_created_by_fkey
  foreign key (created_by) references auth.users(id) on delete set null;
alter table public.space_invitations drop constraint if exists space_invitations_accepted_by_fkey;
alter table public.space_invitations add constraint space_invitations_accepted_by_fkey
  foreign key (accepted_by) references auth.users(id) on delete set null;
alter table public.space_merge_operations alter column actor_user_id drop not null;
alter table public.space_merge_operations drop constraint if exists space_merge_operations_actor_user_id_fkey;
alter table public.space_merge_operations add constraint space_merge_operations_actor_user_id_fkey
  foreign key (actor_user_id) references auth.users(id) on delete set null;

create or replace function public.space_deletion_preview()
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public as $$
declare
  v_user uuid := auth.uid();
  v_space uuid;
begin
  if v_user is null then return jsonb_build_object('error_code', 'NOT_AUTHENTICATED'); end if;
  select m.space_id into v_space from public.space_members m where m.user_id = v_user;
  if v_space is null then return jsonb_build_object('error_code', 'NO_SPACE'); end if;
  return jsonb_build_object(
    'member_count', (select count(*) from public.space_members m where m.space_id = v_space),
    'plan_count', (select count(*) from public.date_plans p where p.space_id = v_space),
    'file_count', (select count(*) from public.attachments a where a.space_id = v_space)
  );
end;
$$;
revoke all on function public.space_deletion_preview() from public, anon;
grant execute on function public.space_deletion_preview() to authenticated;

create or replace function public.leave_space(
  p_operation_id uuid,
  p_expected_member_count integer,
  p_confirmation_word text default null
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public as $$
declare
  v_user uuid := auth.uid();
  v_space uuid;
  v_member_count integer;
  v_remaining_user uuid;
  v_operation public.space_leave_operations%rowtype;
  v_delete_spaces uuid[];
  v_deleted_space uuid;
begin
  if v_user is null then return jsonb_build_object('error_code', 'NOT_AUTHENTICATED'); end if;
  if p_operation_id is null or p_expected_member_count is null
      or p_expected_member_count not between 1 and 2 then
    return jsonb_build_object('error_code', 'INVALID_REQUEST');
  end if;

  select * into v_operation from public.space_leave_operations o where o.id = p_operation_id;
  if found then
    if v_operation.actor_user_id <> v_user then
      return jsonb_build_object('error_code', 'OPERATION_MISMATCH');
    end if;
    return jsonb_build_object('result', v_operation.result, 'last_member', v_operation.last_member);
  end if;

  select m.space_id into v_space from public.space_members m where m.user_id = v_user;
  if v_space is null then
    insert into public.space_leave_operations(id, actor_user_id, result)
    values (p_operation_id, v_user, 'no_space');
    return jsonb_build_object('result', 'no_space', 'last_member', false);
  end if;

  perform 1 from public.spaces s where s.id = v_space and s.status = 'active' for update;
  if not found then return jsonb_build_object('error_code', 'SPACE_NOT_ACTIVE'); end if;
  -- A second request from the same user may have waited on this Space lock.
  -- Recheck membership after acquiring it so a stale request cannot delete
  -- the Space that the other member now owns.
  if not exists (
    select 1 from public.space_members m where m.space_id = v_space and m.user_id = v_user
  ) then
    insert into public.space_leave_operations(id, actor_user_id, result)
    values (p_operation_id, v_user, 'no_space');
    return jsonb_build_object('result', 'no_space', 'last_member', false);
  end if;
  select count(*) into v_member_count from public.space_members m where m.space_id = v_space;
  if v_member_count <> p_expected_member_count then
    insert into public.space_leave_operations(id, actor_user_id, result)
    values (p_operation_id, v_user, 'reconfirm_required');
    return jsonb_build_object(
      'result', 'reconfirm_required', 'last_member', false,
      'current_member_count', v_member_count
    );
  end if;
  if v_member_count = 1 and upper(coalesce(p_confirmation_word, '')) <> 'DELETE' then
    return jsonb_build_object('error_code', 'CONFIRMATION_REQUIRED');
  end if;

  if v_member_count = 2 then
    select m.user_id into v_remaining_user from public.space_members m
      where m.space_id = v_space and m.user_id <> v_user;
    update public.spaces set created_by = v_remaining_user where id = v_space;
    update public.space_members set role = 'owner'
      where space_id = v_space and user_id = v_remaining_user;
    update public.space_invitations set status = 'revoked', revoked_at = now()
      where space_id = v_space and status = 'pending';
    update public.date_plans set created_by = null
      where space_id = v_space and created_by = v_user;
    update public.activity_cards set created_by = null
      where space_id = v_space and created_by = v_user;
    update public.transport_bookings set created_by = null
      where space_id = v_space and created_by = v_user;
    update public.accommodation_bookings set created_by = null
      where space_id = v_space and created_by = v_user;
    update public.attachments set created_by = null
      where space_id = v_space and created_by = v_user;
    delete from public.space_members where space_id = v_space and user_id = v_user;
    insert into public.space_leave_operations(id, actor_user_id, result, last_member)
      values (p_operation_id, v_user, 'completed', false);
    return jsonb_build_object('result', 'completed', 'last_member', false);
  end if;

  -- A final member's Space and all merged tombstones below it are removed.
  with recursive descendants(id, depth) as (
    select s.id, 0 from public.spaces s where s.id = v_space
    union all
    select child.id, parent.depth + 1 from public.spaces child
      join descendants parent on child.merged_into = parent.id
  )
  select array_agg(id) into v_delete_spaces from descendants;

  insert into public.file_deletion_queue(bucket_id, object_path)
    select distinct 'space-attachments', a.storage_path
    from public.attachments a
    where a.space_id = any(v_delete_spaces)
    on conflict (bucket_id, object_path) do nothing;

  delete from public.space_merge_operations o
    where o.source_space_id = any(v_delete_spaces) or o.target_space_id = any(v_delete_spaces);
  delete from public.space_invitations i where i.space_id = any(v_delete_spaces);

  for v_deleted_space in
    with recursive descendants(id, depth) as (
      select s.id, 0 from public.spaces s where s.id = v_space
      union all
      select child.id, parent.depth + 1 from public.spaces child
        join descendants parent on child.merged_into = parent.id
    )
    select id from descendants order by depth desc
  loop
    delete from public.spaces where id = v_deleted_space;
  end loop;

  insert into public.space_leave_operations(id, actor_user_id, result, last_member)
    values (p_operation_id, v_user, 'completed', true);
  return jsonb_build_object('result', 'completed', 'last_member', true);
end;
$$;
revoke all on function public.leave_space(uuid, integer, text) from public, anon;
grant execute on function public.leave_space(uuid, integer, text) to authenticated;

commit;
