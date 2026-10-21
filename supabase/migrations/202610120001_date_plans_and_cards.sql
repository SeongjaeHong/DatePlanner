-- S4: shared Date Plans, date-only days, optimistic card edits and serialized ordering.
begin;

create table public.date_plans (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 120),
  start_date date not null,
  end_date date not null,
  notes text not null default '' check (char_length(notes) <= 4000),
  version bigint not null default 1,
  deleted_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint date_plans_valid_range check (end_date >= start_date)
);

create table public.plan_days (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.date_plans(id) on delete cascade,
  space_id uuid not null references public.spaces(id) on delete cascade,
  day_date date not null,
  created_at timestamptz not null default now(),
  unique (plan_id, day_date),
  unique (id, plan_id, space_id)
);

create table public.activity_cards (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.date_plans(id) on delete cascade,
  day_id uuid not null,
  space_id uuid not null references public.spaces(id) on delete cascade,
  kind text not null check (kind in ('note', 'activity', 'travel')),
  position text not null,
  title text not null default '' check (char_length(title) <= 120),
  body text not null default '' check (char_length(body) <= 4000),
  version bigint not null default 1,
  deleted_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (day_id, plan_id, space_id)
    references public.plan_days(id, plan_id, space_id) on delete cascade
    deferrable initially deferred
);

create index date_plans_space_active_idx on public.date_plans(space_id, start_date)
  where deleted_at is null;
create index plan_days_plan_date_idx on public.plan_days(plan_id, day_date);
create index activity_cards_day_order_idx on public.activity_cards(day_id, position, id)
  where deleted_at is null;

alter table public.date_plans enable row level security;
alter table public.plan_days enable row level security;
alter table public.activity_cards enable row level security;

create or replace function public.is_space_member(p_space_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public as $$
  select exists (select 1 from public.space_members m
    where m.space_id = p_space_id and m.user_id = auth.uid())
$$;
revoke all on function public.is_space_member(uuid) from public, anon;
grant execute on function public.is_space_member(uuid) to authenticated;

create policy date_plans_member_read on public.date_plans for select to authenticated
  using (public.is_space_member(space_id));
create policy plan_days_member_read on public.plan_days for select to authenticated
  using (public.is_space_member(space_id));
create policy activity_cards_member_read on public.activity_cards for select to authenticated
  using (public.is_space_member(space_id));
revoke all on public.date_plans, public.plan_days, public.activity_cards from anon, authenticated;
grant select on public.date_plans, public.plan_days, public.activity_cards to authenticated;

-- Attach merge/write locks to these newly introduced Space-owned tables.
create trigger lock_active_space_before_write before insert or update or delete on public.date_plans
  for each row execute function public.lock_active_space_for_owned_row();
create trigger lock_active_space_before_write before insert or update or delete on public.plan_days
  for each row execute function public.lock_active_space_for_owned_row();
create trigger lock_active_space_before_write before insert or update or delete on public.activity_cards
  for each row execute function public.lock_active_space_for_owned_row();

create or replace function public.bump_planning_version()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  if row(new.title, new.start_date, new.end_date, new.notes, new.deleted_at)
       is distinct from row(old.title, old.start_date, old.end_date, old.notes, old.deleted_at) then
    new.version := old.version + 1;
    new.updated_at := now();
  end if;
  return new;
end;
$$;
create trigger date_plans_version before update on public.date_plans
  for each row execute function public.bump_planning_version();

create or replace function public.bump_card_version()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  if row(new.day_id, new.kind, new.title, new.body, new.deleted_at)
       is distinct from row(old.day_id, old.kind, old.title, old.body, old.deleted_at) then
    new.version := old.version + 1;
    new.updated_at := now();
  end if;
  return new;
end;
$$;
create trigger activity_cards_version before update on public.activity_cards
  for each row execute function public.bump_card_version();

create or replace function public.create_date_plan(
  p_space_id uuid, p_title text, p_start_date date, p_end_date date, p_notes text default ''
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_id uuid;
  v_day date;
begin
  if auth.uid() is null or not public.is_space_member(p_space_id) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_end_date < p_start_date then
    raise exception 'INVALID_DATE_RANGE';
  end if;
  if char_length(trim(p_title)) not between 1 and 120 or char_length(p_notes) > 4000 then
    raise exception 'INVALID_PLAN';
  end if;
  insert into public.date_plans(space_id, title, start_date, end_date, notes, created_by)
    values (p_space_id, trim(p_title), p_start_date, p_end_date, coalesce(p_notes, ''), auth.uid())
    returning id into v_id;
  for v_day in select d::date from generate_series(p_start_date, p_end_date, interval '1 day') d loop
    insert into public.plan_days(plan_id, space_id, day_date) values (v_id, p_space_id, v_day);
  end loop;
  return v_id;
end;
$$;

create or replace function public.update_date_plan(
  p_plan_id uuid, p_expected_version bigint, p_title text, p_start_date date,
  p_end_date date, p_notes text
) returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_plan public.date_plans%rowtype;
  v_day date;
  v_space_id uuid;
begin
  select space_id into v_space_id from public.date_plans where id = p_plan_id;
  if not found or not public.is_space_member(v_space_id) then
    return jsonb_build_object('error_code', 'NOT_FOUND');
  end if;
  perform 1 from public.spaces where id = v_space_id and status = 'active' for update;
  if not found then return jsonb_build_object('error_code', 'NOT_FOUND'); end if;
  select * into v_plan from public.date_plans where id = p_plan_id for update;
  if v_plan.version <> p_expected_version then
    return jsonb_build_object('error_code', 'CONFLICT', 'latest', to_jsonb(v_plan));
  end if;
  if v_plan.deleted_at is not null then return jsonb_build_object('error_code', 'NOT_FOUND'); end if;
  if p_end_date < p_start_date
     or char_length(trim(p_title)) not between 1 and 120 or char_length(p_notes) > 4000 then
    return jsonb_build_object('error_code', 'INVALID_PLAN');
  end if;
  if exists (
    select 1 from public.activity_cards c join public.plan_days d on d.id = c.day_id
    where d.plan_id = p_plan_id
      and (d.day_date < p_start_date or d.day_date > p_end_date)
  ) then return jsonb_build_object('error_code', 'DAYS_CONTAIN_CARDS'); end if;
  update public.date_plans set title = trim(p_title), start_date = p_start_date,
    end_date = p_end_date, notes = coalesce(p_notes, '') where id = p_plan_id
    returning * into v_plan;
  delete from public.plan_days where plan_id = p_plan_id
    and (day_date < p_start_date or day_date > p_end_date);
  for v_day in select d::date from generate_series(p_start_date, p_end_date, interval '1 day') d loop
    insert into public.plan_days(plan_id, space_id, day_date)
      values (p_plan_id, v_plan.space_id, v_day) on conflict (plan_id, day_date) do nothing;
  end loop;
  return jsonb_build_object('plan', to_jsonb(v_plan));
end;
$$;

create or replace function public.set_date_plan_deleted(
  p_plan_id uuid, p_expected_version bigint, p_deleted boolean
) returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_plan public.date_plans%rowtype; v_space_id uuid;
begin
  select space_id into v_space_id from public.date_plans where id = p_plan_id;
  if not found or not public.is_space_member(v_space_id) then
    return jsonb_build_object('error_code', 'NOT_FOUND');
  end if;
  perform 1 from public.spaces where id = v_space_id and status = 'active' for update;
  if not found then return jsonb_build_object('error_code', 'NOT_FOUND'); end if;
  select * into v_plan from public.date_plans where id = p_plan_id for update;
  if v_plan.version <> p_expected_version then
    return jsonb_build_object('error_code', 'CONFLICT', 'latest', to_jsonb(v_plan));
  end if;
  update public.date_plans set deleted_at = case when p_deleted then now() else null end
    where id = p_plan_id returning * into v_plan;
  return jsonb_build_object('plan', to_jsonb(v_plan));
end;
$$;

create or replace function public.create_activity_card(
  p_day_id uuid, p_kind text, p_title text, p_body text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_day public.plan_days%rowtype;
  v_id uuid;
  v_position bigint;
begin
  select * into v_day from public.plan_days where id = p_day_id;
  if not found or not public.is_space_member(v_day.space_id) then raise exception 'NOT_AUTHORIZED'; end if;
  perform 1 from public.spaces where id = v_day.space_id and status = 'active' for update;
  if not found then raise exception 'SPACE_NOT_ACTIVE'; end if;
  select * into v_day from public.plan_days where id = p_day_id for update;
  if not exists (select 1 from public.date_plans p where p.id = v_day.plan_id
      and p.space_id = v_day.space_id and p.deleted_at is null) then
    raise exception 'PLAN_NOT_AVAILABLE';
  end if;
  if p_kind not in ('note', 'activity', 'travel') or char_length(p_title) > 120 or char_length(p_body) > 4000 then
    raise exception 'INVALID_CARD';
  end if;
  select coalesce(max(position::bigint), 0) + 1000000 into v_position
    from public.activity_cards where day_id = p_day_id and deleted_at is null;
  insert into public.activity_cards(plan_id, day_id, space_id, kind, position, title, body, created_by)
    values (v_day.plan_id, v_day.id, v_day.space_id, p_kind,
      lpad(v_position::text, 20, '0'), coalesce(p_title, ''), coalesce(p_body, ''), auth.uid())
    returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.update_activity_card(
  p_card_id uuid, p_expected_version bigint, p_kind text, p_title text, p_body text
) returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_card public.activity_cards%rowtype; v_space_id uuid;
begin
  select space_id into v_space_id from public.activity_cards where id = p_card_id;
  if not found or not public.is_space_member(v_space_id) then
    return jsonb_build_object('error_code', 'NOT_FOUND');
  end if;
  perform 1 from public.spaces where id = v_space_id and status = 'active' for update;
  if not found then return jsonb_build_object('error_code', 'NOT_FOUND'); end if;
  select * into v_card from public.activity_cards where id = p_card_id for update;
  if v_card.deleted_at is not null then return jsonb_build_object('error_code', 'NOT_FOUND'); end if;
  if not exists (select 1 from public.date_plans p where p.id = v_card.plan_id
      and p.space_id = v_card.space_id and p.deleted_at is null) then
    return jsonb_build_object('error_code', 'NOT_FOUND');
  end if;
  if v_card.version <> p_expected_version then
    return jsonb_build_object('error_code', 'CONFLICT', 'latest', to_jsonb(v_card));
  end if;
  if p_kind not in ('note', 'activity', 'travel') or char_length(p_title) > 120 or char_length(p_body) > 4000 then
    return jsonb_build_object('error_code', 'INVALID_CARD');
  end if;
  update public.activity_cards set kind = p_kind, title = coalesce(p_title, ''), body = coalesce(p_body, '')
    where id = p_card_id returning * into v_card;
  return jsonb_build_object('card', to_jsonb(v_card));
end;
$$;

create or replace function public.set_activity_card_deleted(
  p_card_id uuid, p_expected_version bigint, p_deleted boolean
) returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_card public.activity_cards%rowtype; v_space_id uuid;
begin
  select space_id into v_space_id from public.activity_cards where id = p_card_id;
  if not found or not public.is_space_member(v_space_id) then
    return jsonb_build_object('error_code', 'NOT_FOUND');
  end if;
  perform 1 from public.spaces where id = v_space_id and status = 'active' for update;
  if not found then return jsonb_build_object('error_code', 'NOT_FOUND'); end if;
  select * into v_card from public.activity_cards where id = p_card_id for update;
  if not exists (select 1 from public.date_plans p where p.id = v_card.plan_id
      and p.space_id = v_card.space_id and p.deleted_at is null) then
    return jsonb_build_object('error_code', 'NOT_FOUND');
  end if;
  if v_card.version <> p_expected_version then
    return jsonb_build_object('error_code', 'CONFLICT', 'latest', to_jsonb(v_card));
  end if;
  update public.activity_cards set deleted_at = case when p_deleted then now() else null end
    where id = p_card_id returning * into v_card;
  return jsonb_build_object('card', to_jsonb(v_card));
end;
$$;

create or replace function public.move_activity_card(
  p_card_id uuid, p_target_day_id uuid, p_target_index integer
) returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_card public.activity_cards%rowtype;
  v_source public.plan_days%rowtype;
  v_target public.plan_days%rowtype;
  v_day uuid;
  v_ids uuid[];
  v_i integer;
  v_space_id uuid;
begin
  select * into v_card from public.activity_cards where id = p_card_id;
  if not found or not public.is_space_member(v_card.space_id) or v_card.deleted_at is not null then
    return jsonb_build_object('error_code', 'NOT_FOUND');
  end if;
  select * into v_source from public.plan_days where id = v_card.day_id;
  select * into v_target from public.plan_days where id = p_target_day_id;
  if not found or v_source.plan_id <> v_target.plan_id or v_source.space_id <> v_target.space_id then
    return jsonb_build_object('error_code', 'INVALID_TARGET');
  end if;
  if not public.is_space_member(v_target.space_id) then return jsonb_build_object('error_code', 'NOT_AUTHORIZED'); end if;
  -- Space lock comes first, matching the write trigger and merge transaction order.
  v_space_id := v_source.space_id;
  perform 1 from public.spaces where id = v_space_id and status = 'active' for update;
  if not found then return jsonb_build_object('error_code', 'NOT_FOUND'); end if;
  select * into v_card from public.activity_cards where id = p_card_id for update;
  if v_card.deleted_at is not null or v_card.day_id <> v_source.id then
    return jsonb_build_object('error_code', 'CONFLICT');
  end if;
  if not exists (select 1 from public.date_plans p where p.id = v_card.plan_id
      and p.space_id = v_card.space_id and p.deleted_at is null) then
    return jsonb_build_object('error_code', 'NOT_FOUND');
  end if;
  -- Lock source and target days in a global order. This serializes every reorder in the feed.
  perform 1 from public.plan_days where id in (v_source.id, v_target.id) order by id for update;
  for v_day in select distinct unnest(array[v_source.id, v_target.id]) order by 1 loop
    select array_agg(id order by position, id) into v_ids from public.activity_cards
      where day_id = v_day and deleted_at is null and id <> p_card_id;
    v_ids := coalesce(v_ids, array[]::uuid[]);
    if v_day = v_target.id then
      v_i := greatest(0, least(coalesce(p_target_index, cardinality(v_ids)), cardinality(v_ids)));
      v_ids := array_cat(array_cat(v_ids[1:v_i], array[p_card_id]), v_ids[v_i + 1:cardinality(v_ids)]);
      update public.activity_cards set day_id = v_target.id where id = p_card_id;
    end if;
    for v_i in 1..coalesce(cardinality(v_ids), 0) loop
      update public.activity_cards set position = lpad((v_i::bigint * 1000000)::text, 20, '0')
        where id = v_ids[v_i];
    end loop;
  end loop;
  return jsonb_build_object('status', 'moved');
end;
$$;

revoke all on function public.bump_planning_version() from public, anon, authenticated;
revoke all on function public.bump_card_version() from public, anon, authenticated;
revoke all on function public.create_date_plan(uuid,text,date,date,text) from public, anon;
revoke all on function public.update_date_plan(uuid,bigint,text,date,date,text) from public, anon;
revoke all on function public.set_date_plan_deleted(uuid,bigint,boolean) from public, anon;
revoke all on function public.create_activity_card(uuid,text,text,text) from public, anon;
revoke all on function public.update_activity_card(uuid,bigint,text,text,text) from public, anon;
revoke all on function public.set_activity_card_deleted(uuid,bigint,boolean) from public, anon;
revoke all on function public.move_activity_card(uuid,uuid,integer) from public, anon;
grant execute on function public.create_date_plan(uuid,text,date,date,text) to authenticated;
grant execute on function public.update_date_plan(uuid,bigint,text,date,date,text) to authenticated;
grant execute on function public.set_date_plan_deleted(uuid,bigint,boolean) to authenticated;
grant execute on function public.create_activity_card(uuid,text,text,text) to authenticated;
grant execute on function public.update_activity_card(uuid,bigint,text,text,text) to authenticated;
grant execute on function public.set_activity_card_deleted(uuid,bigint,boolean) to authenticated;
grant execute on function public.move_activity_card(uuid,uuid,integer) to authenticated;

commit;
