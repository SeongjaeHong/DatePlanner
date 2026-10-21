-- Rollback-only S4 integration check. Run only against the isolated local Supabase DB:
-- Get-Content -Raw tool/verify_date_plans_and_cards.sql | docker exec -i supabase_db_Date_Planner psql -q -v ON_ERROR_STOP=1 -U postgres -d postgres
\set ON_ERROR_STOP on
\set QUIET on
begin;

create function pg_temp.assert_true(p_ok boolean, p_message text)
returns void language plpgsql as $$
begin
  if p_ok is distinct from true then raise exception '%', p_message; end if;
end;
$$;
create function pg_temp.assert_plan_is_closed(p_day_id uuid)
returns void language plpgsql as $$
begin
  begin
    perform public.create_activity_card(p_day_id, 'note', 'blocked', '');
    raise exception 'Expected PLAN_NOT_AVAILABLE';
  exception when others then
    if sqlerrm <> 'PLAN_NOT_AVAILABLE' then raise; end if;
  end;
end;
$$;

select gen_random_uuid()::text as owner_id \gset
select gen_random_uuid()::text as outsider_id \gset
insert into auth.users(id, email, raw_user_meta_data) values
  (:'owner_id'::uuid, 's4-owner@local.invalid', '{"display_name":"S4 local owner"}'),
  (:'outsider_id'::uuid, 's4-outsider@local.invalid', '{"display_name":"S4 local outsider"}');

set local role authenticated;
select set_config('request.jwt.claim.sub', :'owner_id', true) as _claim \gset
select public.create_personal_space()::text as space_id \gset
select public.create_date_plan(:'space_id'::uuid, 'Local date test', '2026-12-01', '2026-12-03', '')::text as plan_id \gset
select id::text as first_day from public.plan_days where plan_id = :'plan_id'::uuid and day_date = '2026-12-01' \gset
select id::text as middle_day from public.plan_days where plan_id = :'plan_id'::uuid and day_date = '2026-12-02' \gset
select id::text as last_day from public.plan_days where plan_id = :'plan_id'::uuid and day_date = '2026-12-03' \gset
select pg_temp.assert_true((select count(*) = 3 and min(day_date) = '2026-12-01' and max(day_date) = '2026-12-03'
  from public.plan_days where plan_id = :'plan_id'::uuid), 'plan did not create one date-only day per calendar date');

select set_config('TimeZone', 'Pacific/Honolulu', true) as _tz \gset
select pg_temp.assert_true((select day_date::text = '2026-12-01' from public.plan_days where id = :'first_day'::uuid),
  'calendar date shifted in a westward viewer time zone');
select set_config('TimeZone', 'Pacific/Kiritimati', true) as _tz \gset
select pg_temp.assert_true((select day_date::text = '2026-12-01' from public.plan_days where id = :'first_day'::uuid),
  'calendar date shifted in an eastward viewer time zone');

select public.create_activity_card(:'first_day'::uuid, 'note', '', 'Text only')::text as card_one \gset
select public.create_activity_card(:'first_day'::uuid, 'activity', 'Second', '')::text as card_two \gset
select public.create_activity_card(:'first_day'::uuid, 'travel', '', '')::text as card_three \gset
select public.create_activity_card(:'last_day'::uuid, 'note', 'Move target', '')::text as card_four \gset
select pg_temp.assert_true((select count(*) = 4 from public.activity_cards where space_id = :'space_id'::uuid),
  'cards with text-only or no optional parts were not accepted');

select public.move_activity_card(:'card_three'::uuid, :'first_day'::uuid, 0) as move_to_top \gset
select pg_temp.assert_true((select array_agg(id order by position, id) = array[:'card_three'::uuid, :'card_one'::uuid, :'card_two'::uuid]
  from public.activity_cards where day_id = :'first_day'::uuid and deleted_at is null),
  'move-to-top produced an unstable or incorrect order');
select public.move_activity_card(:'card_two'::uuid, :'middle_day'::uuid, 0) as move_to_day \gset
select pg_temp.assert_true((select day_id = :'middle_day'::uuid from public.activity_cards where id = :'card_two'::uuid),
  'card could not move between days');

select public.update_activity_card(:'card_one'::uuid, 1, 'activity', 'Updated', 'new text',
  'Berlin cafe', 'Berlin, Germany', 52.5200, 13.4050) as updated \gset
select pg_temp.assert_true((:'updated'::jsonb#>>'{card,version}')::int = 2
  and :'updated'::jsonb#>>'{card,place_name}' = 'Berlin cafe'
  and :'updated'::jsonb#>>'{card,place_address}' = 'Berlin, Germany'
  and (:'updated'::jsonb#>>'{card,place_latitude}')::numeric = 52.52
  and (:'updated'::jsonb#>>'{card,place_longitude}')::numeric = 13.405,
  'card edit did not save its place fields and coordinates');
select public.update_activity_card(:'card_one'::uuid, 1, 'activity', 'Stale', 'overwrite') as stale_edit \gset
select pg_temp.assert_true(:'stale_edit'::jsonb->>'error_code' = 'CONFLICT'
  and :'stale_edit'::jsonb#>>'{latest,title}' = 'Updated', 'stale card edit overwrote newer data');

select public.set_activity_card_deleted(:'card_one'::uuid, 2, true) as removed \gset
select pg_temp.assert_true(:'removed'::jsonb#>>'{card,deleted_at}' is not null, 'card removal was not recoverable/soft');
select public.set_activity_card_deleted(:'card_one'::uuid, 3, false) as restored \gset
select pg_temp.assert_true(:'restored'::jsonb#>>'{card,deleted_at}' is null, 'removed card could not be restored');
select public.set_activity_card_deleted(:'card_four'::uuid, 1, true) as removed_dropped_day \gset
select pg_temp.assert_true(:'removed_dropped_day'::jsonb#>>'{card,deleted_at}' is not null,
  'test fixture did not soft-remove a card on the day to be dropped');

select public.update_date_plan(:'plan_id'::uuid, 1, 'Shortened', '2026-12-01', '2026-12-02', '') as blocked \gset
select pg_temp.assert_true(:'blocked'::jsonb->>'error_code' = 'DAYS_CONTAIN_CARDS',
  'plan date shortening discarded a day containing active or removed cards');
select public.set_activity_card_deleted(:'card_four'::uuid, 2, false) as restored_dropped_day \gset
select public.update_date_plan(:'plan_id'::uuid, 1, 'Extended', '2026-12-01', '2026-12-04', 'edited') as extended \gset
select pg_temp.assert_true(:'extended'::jsonb->>'plan' is not null
  and (:'extended'::jsonb#>>'{plan,version}')::int = 2
  and (select count(*) = 4 from public.plan_days where plan_id = :'plan_id'::uuid),
  'valid plan edit did not retain and reconcile its days');
select public.set_date_plan_deleted(:'plan_id'::uuid, 2, true) as hidden_plan \gset
select pg_temp.assert_plan_is_closed(:'first_day'::uuid);
select public.set_date_plan_deleted(:'plan_id'::uuid, 3, false) as restored_plan \gset
select pg_temp.assert_true(:'restored_plan'::jsonb->>'plan' is not null,
  'soft-removed plan could not be restored');

select set_config('request.jwt.claim.sub', :'outsider_id', true) as _claim \gset
select pg_temp.assert_true((select count(*) = 0 from public.date_plans), 'unrelated account read a private plan');
select pg_temp.assert_true((select count(*) = 0 from public.plan_days), 'unrelated account read private plan days');
select pg_temp.assert_true((select count(*) = 0 from public.activity_cards), 'unrelated account read private cards');
select pg_temp.assert_true(not has_table_privilege('authenticated', 'public.date_plans', 'INSERT')
  and not has_table_privilege('authenticated', 'public.activity_cards', 'UPDATE')
  and not has_table_privilege('anon', 'public.activity_cards', 'SELECT'),
  'direct writes or anonymous reads are enabled');

rollback;
\echo 'PASS: date-only days persist unchanged under Pacific/Honolulu and Pacific/Kiritimati time zones.'
\echo 'PASS: optional card content, move/reorder, optimistic conflict handling, soft removal, restore and hidden-plan write protection.'
\echo 'PASS: date shortening with cards is blocked, allowed edits reconcile days, and outsider RLS denies reads.'
