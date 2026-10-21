-- S6: private transport bookings/segments and accommodation records.
begin;

create table if not exists public.transport_bookings (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.date_plans(id) on delete cascade deferrable initially deferred,
  space_id uuid not null references public.spaces(id) on delete cascade deferrable initially deferred,
  mode text not null check (mode in ('train','flight','bus','other')),
  provider_name text not null default '' check (char_length(provider_name) <= 160),
  booking_reference text not null default '' check (char_length(booking_reference) <= 160),
  notes text not null default '' check (char_length(notes) <= 4000),
  version bigint not null default 1,
  deleted_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.transport_segments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.transport_bookings(id) on delete cascade deferrable initially deferred,
  space_id uuid not null references public.spaces(id) on delete cascade deferrable initially deferred,
  origin_text text not null check (char_length(origin_text) between 1 and 240),
  destination_text text not null check (char_length(destination_text) between 1 and 240),
  departs_at timestamptz not null,
  departs_tz text not null,
  arrives_at timestamptz not null,
  arrives_tz text not null,
  sequence integer not null check (sequence >= 0),
  created_at timestamptz not null default now(),
  check (arrives_at > departs_at),
  unique (booking_id, sequence)
);

create table if not exists public.accommodation_bookings (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.date_plans(id) on delete cascade deferrable initially deferred,
  space_id uuid not null references public.spaces(id) on delete cascade deferrable initially deferred,
  name text not null check (char_length(trim(name)) between 1 and 160),
  address_text text not null default '' check (char_length(address_text) <= 500),
  check_in_date date not null,
  check_out_date date not null,
  check_in_local_time time,
  booking_reference text not null default '' check (char_length(booking_reference) <= 160),
  notes text not null default '' check (char_length(notes) <= 4000),
  version bigint not null default 1,
  deleted_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (check_out_date >= check_in_date)
);

create index if not exists transport_bookings_plan_idx on public.transport_bookings(plan_id) where deleted_at is null;
create index if not exists accommodation_bookings_plan_idx on public.accommodation_bookings(plan_id) where deleted_at is null;
create index if not exists transport_segments_booking_idx on public.transport_segments(booking_id, sequence);
alter table public.transport_bookings enable row level security;
alter table public.transport_segments enable row level security;
alter table public.accommodation_bookings enable row level security;
drop policy if exists transport_bookings_member_read on public.transport_bookings;
create policy transport_bookings_member_read on public.transport_bookings for select to authenticated using (public.is_space_member(space_id));
drop policy if exists transport_segments_member_read on public.transport_segments;
create policy transport_segments_member_read on public.transport_segments for select to authenticated using (public.is_space_member(space_id));
drop policy if exists accommodation_member_read on public.accommodation_bookings;
create policy accommodation_member_read on public.accommodation_bookings for select to authenticated using (public.is_space_member(space_id));
revoke all on public.transport_bookings, public.transport_segments, public.accommodation_bookings from anon, authenticated;
grant select on public.transport_bookings, public.transport_segments, public.accommodation_bookings to authenticated;

drop trigger if exists lock_active_space_before_write on public.transport_bookings;
create trigger lock_active_space_before_write before insert or update or delete on public.transport_bookings for each row execute function public.lock_active_space_for_owned_row();
drop trigger if exists lock_active_space_before_write on public.transport_segments;
create trigger lock_active_space_before_write before insert or update or delete on public.transport_segments for each row execute function public.lock_active_space_for_owned_row();
drop trigger if exists lock_active_space_before_write on public.accommodation_bookings;
create trigger lock_active_space_before_write before insert or update or delete on public.accommodation_bookings for each row execute function public.lock_active_space_for_owned_row();

create or replace function public.bump_booking_version()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  if to_jsonb(new) - array['version','updated_at'] is distinct from to_jsonb(old) - array['version','updated_at'] then
    new.version := old.version + 1;
    new.updated_at := now();
  end if;
  return new;
end; $$;
drop trigger if exists transport_booking_version on public.transport_bookings;
create trigger transport_booking_version before update on public.transport_bookings for each row execute function public.bump_booking_version();
drop trigger if exists accommodation_booking_version on public.accommodation_bookings;
create trigger accommodation_booking_version before update on public.accommodation_bookings for each row execute function public.bump_booking_version();

create or replace function public.save_transport_booking(p_plan_id uuid, p_booking_id uuid, p_expected_version bigint, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_plan public.date_plans%rowtype; v_booking public.transport_bookings%rowtype; v_segment jsonb; v_seq integer := 0;
begin
  select * into v_plan from public.date_plans where id = p_plan_id;
  if not found or not public.is_space_member(v_plan.space_id) or v_plan.deleted_at is not null then return jsonb_build_object('error_code','NOT_FOUND'); end if;
  perform 1 from public.spaces where id = v_plan.space_id and status='active' for update;
  if not found then return jsonb_build_object('error_code','NOT_FOUND'); end if;
  if p_booking_id is null then
    insert into public.transport_bookings(plan_id,space_id,mode,provider_name,booking_reference,notes,created_by)
      values(p_plan_id,v_plan.space_id,p_data->>'mode',coalesce(p_data->>'provider_name',''),coalesce(p_data->>'booking_reference',''),coalesce(p_data->>'notes',''),auth.uid()) returning * into v_booking;
  else
    select * into v_booking from public.transport_bookings where id=p_booking_id and plan_id=p_plan_id and space_id=v_plan.space_id and deleted_at is null for update;
    if not found then return jsonb_build_object('error_code','NOT_FOUND'); end if;
    if v_booking.version <> p_expected_version then return jsonb_build_object('error_code','CONFLICT','latest',to_jsonb(v_booking)); end if;
    update public.transport_bookings set mode=p_data->>'mode',provider_name=coalesce(p_data->>'provider_name',''),booking_reference=coalesce(p_data->>'booking_reference',''),notes=coalesce(p_data->>'notes','') where id=p_booking_id returning * into v_booking;
    delete from public.transport_segments where booking_id=p_booking_id;
  end if;
  for v_segment in select value from jsonb_array_elements(coalesce(p_data->'segments','[]'::jsonb)) loop
    if not exists(select 1 from pg_catalog.pg_timezone_names where name=v_segment->>'departs_tz')
      or not exists(select 1 from pg_catalog.pg_timezone_names where name=v_segment->>'arrives_tz') then raise exception 'INVALID_TIME_ZONE'; end if;
    insert into public.transport_segments(booking_id,space_id,origin_text,destination_text,departs_at,departs_tz,arrives_at,arrives_tz,sequence)
      values(v_booking.id,v_plan.space_id,v_segment->>'origin_text',v_segment->>'destination_text',(v_segment->>'departs_at')::timestamptz,v_segment->>'departs_tz',(v_segment->>'arrives_at')::timestamptz,v_segment->>'arrives_tz',v_seq);
    v_seq := v_seq + 1;
  end loop;
  if v_seq=0 then raise exception 'SEGMENT_REQUIRED'; end if;
  return jsonb_build_object('booking',to_jsonb(v_booking),'segments',(select jsonb_agg(to_jsonb(s) order by sequence) from public.transport_segments s where s.booking_id=v_booking.id));
end; $$;

create or replace function public.set_transport_booking_deleted(p_booking_id uuid,p_expected_version bigint,p_deleted boolean)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_booking public.transport_bookings%rowtype;
begin
  select * into v_booking from public.transport_bookings where id=p_booking_id;
  if not found or not public.is_space_member(v_booking.space_id) then return jsonb_build_object('error_code','NOT_FOUND'); end if;
  perform 1 from public.spaces where id=v_booking.space_id and status='active' for update;
  select * into v_booking from public.transport_bookings where id=p_booking_id for update;
  if v_booking.version<>p_expected_version then return jsonb_build_object('error_code','CONFLICT','latest',to_jsonb(v_booking)); end if;
  update public.transport_bookings set deleted_at=case when p_deleted then now() else null end where id=p_booking_id returning * into v_booking;
  return jsonb_build_object('booking',to_jsonb(v_booking));
end; $$;

create or replace function public.save_accommodation_booking(p_plan_id uuid,p_booking_id uuid,p_expected_version bigint,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_plan public.date_plans%rowtype; v_booking public.accommodation_bookings%rowtype;
begin
  select * into v_plan from public.date_plans where id=p_plan_id;
  if not found or not public.is_space_member(v_plan.space_id) or v_plan.deleted_at is not null then return jsonb_build_object('error_code','NOT_FOUND'); end if;
  perform 1 from public.spaces where id=v_plan.space_id and status='active' for update;
  if not found then return jsonb_build_object('error_code','NOT_FOUND'); end if;
  if p_booking_id is null then
    insert into public.accommodation_bookings(plan_id,space_id,name,address_text,check_in_date,check_out_date,check_in_local_time,booking_reference,notes,created_by)
      values(p_plan_id,v_plan.space_id,p_data->>'name',coalesce(p_data->>'address_text',''),(p_data->>'check_in_date')::date,(p_data->>'check_out_date')::date,nullif(p_data->>'check_in_local_time','')::time,coalesce(p_data->>'booking_reference',''),coalesce(p_data->>'notes',''),auth.uid()) returning * into v_booking;
  else
    select * into v_booking from public.accommodation_bookings where id=p_booking_id and plan_id=p_plan_id and space_id=v_plan.space_id and deleted_at is null for update;
    if not found then return jsonb_build_object('error_code','NOT_FOUND'); end if;
    if v_booking.version<>p_expected_version then return jsonb_build_object('error_code','CONFLICT','latest',to_jsonb(v_booking)); end if;
    update public.accommodation_bookings set name=p_data->>'name',address_text=coalesce(p_data->>'address_text',''),check_in_date=(p_data->>'check_in_date')::date,check_out_date=(p_data->>'check_out_date')::date,check_in_local_time=nullif(p_data->>'check_in_local_time','')::time,booking_reference=coalesce(p_data->>'booking_reference',''),notes=coalesce(p_data->>'notes','') where id=p_booking_id returning * into v_booking;
  end if;
  return jsonb_build_object('booking',to_jsonb(v_booking));
end; $$;

revoke all on function public.bump_booking_version() from public,anon,authenticated;
revoke all on function public.save_transport_booking(uuid,uuid,bigint,jsonb), public.set_transport_booking_deleted(uuid,bigint,boolean), public.save_accommodation_booking(uuid,uuid,bigint,jsonb) from public,anon;
grant execute on function public.save_transport_booking(uuid,uuid,bigint,jsonb), public.set_transport_booking_deleted(uuid,bigint,boolean), public.save_accommodation_booking(uuid,uuid,bigint,jsonb) to authenticated;
commit;
