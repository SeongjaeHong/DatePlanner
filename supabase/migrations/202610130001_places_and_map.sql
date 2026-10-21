-- S5: private place details on member-only activity cards.
begin;

alter table public.activity_cards
  add column place_name text,
  add column place_address text,
  add column place_latitude double precision,
  add column place_longitude double precision,
  add constraint activity_cards_place_name_length check (place_name is null or char_length(place_name) <= 160),
  add constraint activity_cards_place_address_length check (place_address is null or char_length(place_address) <= 500),
  add constraint activity_cards_place_coordinates_pair check
    ((place_latitude is null and place_longitude is null) or
     (place_latitude is not null and place_longitude is not null and
      place_latitude between -90 and 90 and place_longitude between -180 and 180));

drop function public.create_activity_card(uuid, text, text, text);
drop function public.update_activity_card(uuid, bigint, text, text, text);

create or replace function public.bump_card_version()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  if row(new.day_id, new.kind, new.title, new.body, new.place_name,
      new.place_address, new.place_latitude, new.place_longitude, new.deleted_at)
       is distinct from row(old.day_id, old.kind, old.title, old.body, old.place_name,
      old.place_address, old.place_latitude, old.place_longitude, old.deleted_at) then
    new.version := old.version + 1;
    new.updated_at := now();
  end if;
  return new;
end;
$$;

create or replace function public.create_activity_card(
  p_day_id uuid, p_kind text, p_title text, p_body text,
  p_place_name text default null, p_place_address text default null,
  p_place_latitude double precision default null, p_place_longitude double precision default null
) returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_day public.plan_days%rowtype; v_id uuid; v_position bigint;
begin
  select * into v_day from public.plan_days where id = p_day_id;
  if not found or not public.is_space_member(v_day.space_id) then raise exception 'NOT_AUTHORIZED'; end if;
  perform 1 from public.spaces where id = v_day.space_id and status = 'active' for update;
  if not found then raise exception 'SPACE_NOT_ACTIVE'; end if;
  select * into v_day from public.plan_days where id = p_day_id for update;
  if not exists (select 1 from public.date_plans p where p.id = v_day.plan_id and p.space_id = v_day.space_id and p.deleted_at is null) then raise exception 'PLAN_NOT_AVAILABLE'; end if;
  if p_kind not in ('note', 'activity', 'travel') or char_length(p_title) > 120 or char_length(p_body) > 4000
    or char_length(p_place_name) > 160 or char_length(p_place_address) > 500
    or ((p_place_latitude is null) <> (p_place_longitude is null))
    or (p_place_latitude is not null and (p_place_latitude not between -90 and 90 or p_place_longitude not between -180 and 180))
    or ((p_place_name is null or trim(p_place_name) = '') and (p_place_address is null or trim(p_place_address) = '')
        and (p_place_latitude is not null or p_place_longitude is not null)) then
    raise exception 'INVALID_CARD';
  end if;
  select coalesce(max(position::bigint), 0) + 1000000 into v_position from public.activity_cards where day_id = p_day_id and deleted_at is null;
  insert into public.activity_cards(plan_id, day_id, space_id, kind, position, title, body, place_name, place_address, place_latitude, place_longitude, created_by)
    values (v_day.plan_id, v_day.id, v_day.space_id, p_kind, lpad(v_position::text, 20, '0'), coalesce(p_title, ''), coalesce(p_body, ''), nullif(trim(p_place_name), ''), nullif(trim(p_place_address), ''), p_place_latitude, p_place_longitude, auth.uid())
    returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.update_activity_card(
  p_card_id uuid, p_expected_version bigint, p_kind text, p_title text, p_body text,
  p_place_name text default null, p_place_address text default null, p_place_latitude double precision default null, p_place_longitude double precision default null
) returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_card public.activity_cards%rowtype; v_space_id uuid;
begin
  select space_id into v_space_id from public.activity_cards where id = p_card_id;
  if not found or not public.is_space_member(v_space_id) then return jsonb_build_object('error_code', 'NOT_FOUND'); end if;
  perform 1 from public.spaces where id = v_space_id and status = 'active' for update;
  if not found then return jsonb_build_object('error_code', 'NOT_FOUND'); end if;
  select * into v_card from public.activity_cards where id = p_card_id for update;
  if v_card.deleted_at is not null or not exists (select 1 from public.date_plans p where p.id = v_card.plan_id and p.space_id = v_card.space_id and p.deleted_at is null) then return jsonb_build_object('error_code', 'NOT_FOUND'); end if;
  if v_card.version <> p_expected_version then return jsonb_build_object('error_code', 'CONFLICT', 'latest', to_jsonb(v_card)); end if;
  if p_kind not in ('note', 'activity', 'travel') or char_length(p_title) > 120 or char_length(p_body) > 4000
    or char_length(p_place_name) > 160 or char_length(p_place_address) > 500
    or ((p_place_latitude is null) <> (p_place_longitude is null))
    or (p_place_latitude is not null and (p_place_latitude not between -90 and 90 or p_place_longitude not between -180 and 180))
    or ((p_place_name is null or trim(p_place_name) = '') and (p_place_address is null or trim(p_place_address) = '')
        and (p_place_latitude is not null or p_place_longitude is not null)) then
    return jsonb_build_object('error_code', 'INVALID_CARD');
  end if;
  update public.activity_cards set kind = p_kind, title = coalesce(p_title, ''), body = coalesce(p_body, ''), place_name = nullif(trim(p_place_name), ''), place_address = nullif(trim(p_place_address), ''), place_latitude = p_place_latitude, place_longitude = p_place_longitude where id = p_card_id returning * into v_card;
  return jsonb_build_object('card', to_jsonb(v_card));
end;
$$;

revoke all on function public.create_activity_card(uuid,text,text,text,text,text,double precision,double precision) from public, anon;
revoke all on function public.update_activity_card(uuid,bigint,text,text,text,text,text,double precision,double precision) from public, anon;
grant execute on function public.create_activity_card(uuid,text,text,text,text,text,double precision,double precision) to authenticated;
grant execute on function public.update_activity_card(uuid,bigint,text,text,text,text,text,double precision,double precision) to authenticated;

commit;
