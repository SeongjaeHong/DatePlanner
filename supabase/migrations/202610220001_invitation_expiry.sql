-- Seven-day, single-use Space invitation expiry. Existing rows are not rewritten:
-- legacy invitations use created_at + 7 days until expires_at is populated for new codes.
begin;

alter table public.space_invitations add column if not exists expires_at timestamptz;
alter table public.space_invitations drop constraint if exists space_invitations_status_check;
alter table public.space_invitations add constraint space_invitations_status_check
  check (status in ('pending', 'accepted', 'revoked', 'expired'));

create or replace function public.space_invitation_is_expired(
  p_created_at timestamptz, p_expires_at timestamptz
)
returns boolean
language sql
stable
set search_path = pg_catalog
as $$
  select coalesce(p_expires_at <= statement_timestamp(),
    p_created_at <= statement_timestamp() - interval '7 days')
$$;
revoke all on function public.space_invitation_is_expired(timestamptz, timestamptz)
  from public, anon, authenticated;

create or replace function public.create_space_invitation(p_disclosure_acknowledged boolean)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_user uuid := auth.uid();
  v_space uuid;
  v_members integer;
  v_code text;
  v_id uuid;
begin
  if v_user is null then return jsonb_build_object('error_code', 'NOT_AUTHORIZED'); end if;
  if p_disclosure_acknowledged is distinct from true then
    return jsonb_build_object('error_code', 'DISCLOSURE_REQUIRED');
  end if;
  select m.space_id into v_space from public.space_members m where m.user_id = v_user;
  if v_space is null then return jsonb_build_object('error_code', 'SPACE_REQUIRED'); end if;
  perform 1 from public.spaces s where s.id = v_space and s.status = 'active' for update;
  if not found then return jsonb_build_object('error_code', 'SPACE_FULL'); end if;
  select count(*) into v_members from public.space_members m where m.space_id = v_space;
  if v_members <> 1 then return jsonb_build_object('error_code', 'SPACE_FULL'); end if;
  update public.space_invitations i set status = 'expired'
    where i.space_id = v_space and i.status = 'pending'
      and public.space_invitation_is_expired(i.created_at, i.expires_at);
  if exists (select 1 from public.space_invitations i
      where i.space_id = v_space and i.status = 'pending') then
    return jsonb_build_object('error_code', 'INVITE_PENDING');
  end if;

  -- gen_random_uuid is backed by PostgreSQL's CSPRNG. The code is returned once only.
  v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 20));
  insert into public.space_invitations(space_id, created_by, code_hash, expires_at)
  values (v_space, v_user, extensions.digest(convert_to(v_code, 'UTF8'), 'sha256'), now() + interval '7 days')
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'code', v_code, 'expires_at', now() + interval '7 days');
end;
$$;

create or replace function public.list_my_space_invitations()
returns jsonb
language sql
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', i.id, 'status', case when i.status = 'pending'
      and public.space_invitation_is_expired(i.created_at, i.expires_at) then 'expired' else i.status end,
    'created_at', i.created_at, 'expires_at', coalesce(i.expires_at, i.created_at + interval '7 days'),
    'accepted_at', i.accepted_at
  ) order by i.created_at desc), '[]'::jsonb)
  from public.space_invitations i
  join public.space_members m on m.space_id = i.space_id
  where m.user_id = auth.uid() and i.created_by = auth.uid()
$$;

create or replace function public.prepare_join(p_code text, p_operation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_user uuid := auth.uid();
  v_code text := regexp_replace(upper(coalesce(p_code, '')), '[^0-9A-F]', '', 'g');
  v_hash bytea;
  v_invitation public.space_invitations%rowtype;
  v_existing public.space_merge_operations%rowtype;
  v_target_members integer;
  v_source uuid;
  v_source_members integer;
  v_inviter_name text;
  v_target_rows jsonb;
  v_source_rows jsonb;
  v_target_counts jsonb;
  v_source_counts jsonb;
  v_attempts integer;
begin
  if v_user is null or p_operation_id is null then
    return jsonb_build_object('error_code', 'NOT_AUTHORIZED');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text, 0));
  delete from public.invitation_attempts where attempted_at < now() - interval '1 day';
  select count(*) into v_attempts from public.invitation_attempts
    where user_id = v_user and attempted_at >= now() - interval '15 minutes';
  if v_attempts >= 10 then return jsonb_build_object('error_code', 'RATE_LIMITED'); end if;

  if length(v_code) <> 20 then
    insert into public.invitation_attempts(user_id) values (v_user);
    return jsonb_build_object('error_code', 'INVITE_INVALID');
  end if;
  v_hash := extensions.digest(convert_to(v_code, 'UTF8'), 'sha256');
  select i.* into v_invitation
  from public.space_invitations i
  where i.status = 'pending'
    and not public.space_invitation_is_expired(i.created_at, i.expires_at)
    and public._constant_time_hash_equal(i.code_hash, v_hash)
  limit 1;
  if not found then
    insert into public.invitation_attempts(user_id) values (v_user);
    return jsonb_build_object('error_code', 'INVITE_INVALID');
  end if;

  select o.* into v_existing from public.space_merge_operations o
    where o.invitation_id = v_invitation.id;
  if found then
    if v_existing.actor_user_id <> v_user or v_existing.status = 'rejected' then
      return jsonb_build_object('error_code', 'INVITE_INVALID');
    end if;
    if v_existing.status = 'completed' then
      return jsonb_build_object('operation_id', v_existing.id, 'status', 'completed',
        'disclosure_version', v_existing.disclosure_version,
        'counts', v_existing.counts_before->'display');
    end if;
    select coalesce(p.display_name, 'Your partner') into v_inviter_name
      from public.profiles p where p.id = v_invitation.created_by;
    return jsonb_build_object('operation_id', v_existing.id, 'status', 'prepared',
      'disclosure_version', v_existing.disclosure_version,
      'inviter_name', coalesce(v_inviter_name, 'Your partner'),
      'counts', v_existing.counts_before->'display');
  end if;

  if v_invitation.created_by = v_user then
    return jsonb_build_object('error_code', 'INVITE_INVALID');
  end if;
  select count(*) into v_target_members from public.space_members m
    where m.space_id = v_invitation.space_id;
  if not exists (select 1 from public.spaces s
      where s.id = v_invitation.space_id and s.status = 'active')
    or not exists (select 1 from public.space_members m
      where m.space_id = v_invitation.space_id and m.user_id = v_invitation.created_by) then
    return jsonb_build_object('error_code', 'INVITE_INVALID');
  end if;
  if v_target_members <> 1 then
    return jsonb_build_object('error_code', 'SPACE_FULL');
  end if;
  select m.space_id into v_source from public.space_members m where m.user_id = v_user;
  if v_source = v_invitation.space_id then
    return jsonb_build_object('error_code', 'SAME_SPACE');
  end if;
  if v_source is not null then
    select count(*) into v_source_members from public.space_members m where m.space_id = v_source;
    if v_source_members <> 1 then
      return jsonb_build_object('error_code', 'ALREADY_IN_TWO_PERSON_SPACE');
    end if;
    if not exists (select 1 from public.spaces s where s.id = v_source and s.status = 'active') then
      return jsonb_build_object('error_code', 'INVITE_INVALID');
    end if;
  end if;

  select coalesce(p.display_name, 'Your partner') into v_inviter_name
    from public.profiles p where p.id = v_invitation.created_by;
  v_target_rows := public._space_row_counts(v_invitation.space_id);
  v_source_rows := public._space_row_counts(v_source);
  v_target_counts := public._space_summary_counts(v_invitation.space_id);
  v_source_counts := public._space_summary_counts(v_source);
  insert into public.space_merge_operations(
    id, invitation_id, source_space_id, target_space_id, actor_user_id,
    status, disclosure_version, counts_before
  ) values (
    p_operation_id, v_invitation.id, v_source, v_invitation.space_id, v_user,
    'prepared', 2,
    jsonb_build_object('target_rows', v_target_rows, 'source_rows', v_source_rows,
      'display', jsonb_build_object('their_plans', (v_target_counts->>'plans')::integer,
        'their_files', (v_target_counts->>'files')::integer,
        'my_plans', (v_source_counts->>'plans')::integer,
        'my_files', (v_source_counts->>'files')::integer))
  );
  return jsonb_build_object(
    'operation_id', p_operation_id, 'status', 'prepared', 'disclosure_version', 2,
    'inviter_name', coalesce(v_inviter_name, 'Your partner'),
    'counts', jsonb_build_object('their_plans', (v_target_counts->>'plans')::integer,
      'their_files', (v_target_counts->>'files')::integer,
      'my_plans', (v_source_counts->>'plans')::integer,
      'my_files', (v_source_counts->>'files')::integer)
  );
exception when unique_violation then
  return jsonb_build_object('error_code', 'INVITE_INVALID');
end;
$$;

create or replace function public.confirm_join(p_operation_id uuid, p_disclosure_version integer)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user uuid := auth.uid();
  v_operation public.space_merge_operations%rowtype;
  v_invitation public.space_invitations%rowtype;
  v_space uuid;
  v_record record;
  v_target_before bigint;
  v_source_before bigint;
  v_target_after bigint;
  v_source_after bigint;
  v_result jsonb := '{}'::jsonb;
  v_current_target_rows jsonb;
  v_current_source_rows jsonb;
begin
  if v_user is null then return jsonb_build_object('error_code', 'NOT_AUTHORIZED'); end if;
  select o.* into v_operation from public.space_merge_operations o
    where o.id = p_operation_id and o.actor_user_id = v_user;
  if not found then return jsonb_build_object('error_code', 'NOT_AUTHORIZED'); end if;
  if v_operation.status = 'completed' then
    return jsonb_build_object('status', 'completed', 'space_id', v_operation.target_space_id);
  end if;
  if v_operation.status <> 'prepared' then
    return jsonb_build_object('error_code', coalesce(v_operation.error_code, 'INVITE_INVALID'));
  end if;
  if p_disclosure_version is distinct from v_operation.disclosure_version then
    return jsonb_build_object('error_code', 'DISCLOSURE_CHANGED');
  end if;

  -- Lock both Spaces in a globally consistent order before locking the invitation.
  for v_space in
    select s.id from public.spaces s
    where s.id = v_operation.target_space_id or s.id = v_operation.source_space_id
    order by s.id for update
  loop null; end loop;
  select i.* into v_invitation from public.space_invitations i
    where i.id = v_operation.invitation_id for update;
  if not found or v_invitation.status <> 'pending' then
    update public.space_merge_operations set status = 'rejected', error_code = 'INVITE_INVALID'
      where id = v_operation.id;
    return jsonb_build_object('error_code', 'INVITE_INVALID');
  end if;
  if public.space_invitation_is_expired(v_invitation.created_at, v_invitation.expires_at) then
    update public.space_invitations set status = 'expired' where id = v_invitation.id;
    update public.space_merge_operations set status = 'rejected', error_code = 'INVITE_INVALID'
      where id = v_operation.id;
    return jsonb_build_object('error_code', 'INVITE_INVALID');
  end if;
  if not exists (select 1 from public.spaces s where s.id = v_operation.target_space_id and s.status = 'active')
    or (select count(*) from public.space_members m where m.space_id = v_operation.target_space_id) <> 1
    or not exists (select 1 from public.space_members m where m.space_id = v_operation.target_space_id and m.user_id = v_invitation.created_by)
    or v_invitation.created_by = v_user then
    update public.space_merge_operations set status = 'rejected', error_code = 'SPACE_FULL'
      where id = v_operation.id;
    return jsonb_build_object('error_code', 'SPACE_FULL');
  end if;
  if v_operation.source_space_id is not null then
    if not exists (select 1 from public.spaces s where s.id = v_operation.source_space_id and s.status = 'active')
      or (select count(*) from public.space_members m where m.space_id = v_operation.source_space_id) <> 1
      or not exists (select 1 from public.space_members m where m.space_id = v_operation.source_space_id and m.user_id = v_user) then
      update public.space_merge_operations set status = 'rejected', error_code = 'ALREADY_IN_TWO_PERSON_SPACE'
        where id = v_operation.id;
      return jsonb_build_object('error_code', 'ALREADY_IN_TWO_PERSON_SPACE');
    end if;
  elsif exists (select 1 from public.space_members m where m.user_id = v_user) then
    update public.space_merge_operations set status = 'rejected', error_code = 'ALREADY_IN_TWO_PERSON_SPACE'
      where id = v_operation.id;
    return jsonb_build_object('error_code', 'ALREADY_IN_TWO_PERSON_SPACE');
  end if;

  v_current_target_rows := public._space_row_counts(v_operation.target_space_id);
  v_current_source_rows := public._space_row_counts(v_operation.source_space_id);
  if v_current_target_rows is distinct from v_operation.counts_before->'target_rows'
    or v_current_source_rows is distinct from v_operation.counts_before->'source_rows' then
    return jsonb_build_object('error_code', 'DISCLOSURE_CHANGED');
  end if;

  set constraints all deferred;
  for v_record in
    select c.table_schema, c.table_name
    from information_schema.columns c
    where c.table_schema = 'public' and c.column_name = 'space_id'
      and c.table_name not in ('spaces', 'space_members', 'space_invitations', 'space_merge_operations', 'invitation_attempts')
    order by c.table_name
  loop
    v_target_before := coalesce((v_operation.counts_before->'target_rows'->>v_record.table_name)::bigint, 0);
    v_source_before := coalesce((v_operation.counts_before->'source_rows'->>v_record.table_name)::bigint, 0);
    if v_operation.source_space_id is not null then
      execute format('update %I.%I set space_id = $1 where space_id = $2', v_record.table_schema, v_record.table_name)
        using v_operation.target_space_id, v_operation.source_space_id;
    end if;
    execute format('select count(*) from %I.%I where space_id = $1', v_record.table_schema, v_record.table_name)
      into v_target_after using v_operation.target_space_id;
    execute format('select count(*) from %I.%I where space_id = $1', v_record.table_schema, v_record.table_name)
      into v_source_after using v_operation.source_space_id;
    if v_target_after <> v_target_before + v_source_before or v_source_after <> 0 then
      raise exception 'SPACE_MERGE_INVARIANT_FAILED';
    end if;
    v_result := v_result || jsonb_build_object(v_record.table_name, v_source_before);
  end loop;

  delete from public.space_members where space_id = v_operation.source_space_id and user_id = v_user;
  insert into public.space_members(space_id, user_id, role)
    values (v_operation.target_space_id, v_user, 'member');
  if v_operation.source_space_id is not null then
    update public.spaces set status = 'merged', merged_into = v_operation.target_space_id
      where id = v_operation.source_space_id;
    update public.space_invitations set status = 'revoked', revoked_at = now()
      where space_id = v_operation.source_space_id and status = 'pending';
  end if;
  update public.space_invitations set status = 'accepted', accepted_by = v_user, accepted_at = now()
    where id = v_invitation.id;
  update public.space_merge_operations set status = 'completed', counts_moved = v_result, completed_at = now()
    where id = v_operation.id;
  return jsonb_build_object('status', 'completed', 'space_id', v_operation.target_space_id);
end;
$$;

commit;
