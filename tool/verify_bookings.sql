-- Rollback-only S6 test against local Supabase only.
\set ON_ERROR_STOP on
\set QUIET on
begin;
create function pg_temp.assert_true(p_ok boolean,p_message text) returns void language plpgsql as $$ begin if p_ok is distinct from true then raise exception '%',p_message; end if; end; $$;
select gen_random_uuid()::text as owner_id \gset
select gen_random_uuid()::text as outsider_id \gset
insert into auth.users(id,email,raw_user_meta_data) values
  (:'owner_id'::uuid,'s6-owner@local.invalid','{}'),(:'outsider_id'::uuid,'s6-outsider@local.invalid','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub', :'owner_id', true) \gset
select public.create_personal_space()::text as space_id \gset
select public.create_date_plan(:'space_id'::uuid,'Booking date test','2026-12-20','2026-12-22','')::text as plan_id \gset
select public.save_transport_booking(:'plan_id'::uuid,null,null,
  '{"mode":"train","provider_name":"Synthetic Rail","booking_reference":"FAKE-123","segments":[{"origin_text":"Seoul","destination_text":"Berlin","departs_at":"2026-12-20T00:00:00+09:00","departs_tz":"Asia/Seoul","arrives_at":"2026-12-20T12:00:00Z","arrives_tz":"Europe/Berlin"}]}'::jsonb) as saved_transport \gset
select (:'saved_transport'::jsonb#>>'{booking,id}')::uuid as booking_id \gset
select pg_temp.assert_true((select mode='train' and booking_reference='FAKE-123' from public.transport_bookings where id=:'booking_id'::uuid),'transport booking fields not saved');
select pg_temp.assert_true((select departs_tz='Asia/Seoul' and arrives_tz='Europe/Berlin' and departs_at='2026-12-19 15:00:00+00'::timestamptz and arrives_at='2026-12-20 12:00:00+00'::timestamptz from public.transport_segments where booking_id=:'booking_id'::uuid),'segment instants or IANA zone labels changed');
select public.save_accommodation_booking(:'plan_id'::uuid,null,null,
  '{"name":"Synthetic Hotel","address_text":"Berlin","check_in_date":"2026-12-20","check_out_date":"2026-12-22","check_in_local_time":"15:30:00","booking_reference":"FAKE-STAY","notes":"fixture"}'::jsonb) as saved_stay \gset
select (:'saved_stay'::jsonb#>>'{booking,id}')::uuid as stay_id \gset
select pg_temp.assert_true((select check_in_date='2026-12-20' and check_out_date='2026-12-22' and check_in_local_time='15:30'::time from public.accommodation_bookings where id=:'stay_id'::uuid),'date-only accommodation values shifted');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'outsider_id', true) \gset
select pg_temp.assert_true((select count(*)=0 from public.transport_bookings where id=:'booking_id'::uuid),'outsider can read a transport booking');
select pg_temp.assert_true((select count(*)=0 from public.transport_segments where booking_id=:'booking_id'::uuid),'outsider can read transport segment times');
select pg_temp.assert_true((select count(*)=0 from public.accommodation_bookings where id=:'stay_id'::uuid),'outsider can read accommodation details');
rollback;
\echo 'PASS: booking RPCs persist zone-aware segments and date-only stays; outsiders are denied.'
