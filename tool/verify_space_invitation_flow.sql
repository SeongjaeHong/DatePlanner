-- Rollback-only Supabase integration check. Run only against the isolated local DB:
-- Get-Content -Raw tool/verify_space_invitation_flow.sql | docker exec -i supabase_db_Date_Planner psql -q -v ON_ERROR_STOP=1 -U postgres -d postgres
\set ON_ERROR_STOP on
\set QUIET on
begin;

create function pg_temp.assert_true(p_ok boolean, p_message text)
returns void language plpgsql as $$
begin
  if p_ok is distinct from true then raise exception '%', p_message; end if;
end;
$$;

select gen_random_uuid()::text as owner_id \gset
select gen_random_uuid()::text as partner_id \gset
select gen_random_uuid()::text as outsider_id \gset
select gen_random_uuid()::text as fresh_inviter_id \gset
select gen_random_uuid()::text as fresh_joiner_id \gset
select gen_random_uuid()::text as revoker_id \gset
select gen_random_uuid()::text as probe_id \gset
insert into auth.users(id, email, raw_user_meta_data) values
  (:'owner_id'::uuid, 's3-owner@local.invalid', '{"display_name":"Local owner"}'),
  (:'partner_id'::uuid, 's3-partner@local.invalid', '{"display_name":"Local partner"}'),
  (:'outsider_id'::uuid, 's3-outsider@local.invalid', '{"display_name":"Local outsider"}'),
  (:'fresh_inviter_id'::uuid, 's3-inviter@local.invalid', '{"display_name":"Local inviter"}'),
  (:'fresh_joiner_id'::uuid, 's3-joiner@local.invalid', '{"display_name":"Local joiner"}'),
  (:'revoker_id'::uuid, 's3-revoker@local.invalid', '{"display_name":"Local revoker"}'),
  (:'probe_id'::uuid, 's3-probe@local.invalid', '{"display_name":"Local probe"}');

set local role authenticated;
select set_config('request.jwt.claim.sub', :'owner_id', true) as _claim \gset
select public.create_personal_space()::text as target_space \gset
select public.create_date_plan(:'target_space'::uuid, 'Synthetic plan A', '2026-12-01', '2026-12-01')::text as plan_a \gset
select id::text as day_a from public.plan_days where plan_id = :'plan_a'::uuid \gset
select public.create_activity_card(:'day_a'::uuid, 'activity', 'Synthetic activity A', '')::text as card_a \gset

select set_config('request.jwt.claim.sub', :'partner_id', true) as _claim \gset
select public.create_personal_space()::text as source_space \gset
select public.create_date_plan(:'source_space'::uuid, 'Synthetic plan B', '2026-12-02', '2026-12-02')::text as plan_b \gset
select id::text as day_b from public.plan_days where plan_id = :'plan_b'::uuid \gset
select public.create_activity_card(:'day_b'::uuid, 'note', 'Synthetic activity B', '')::text as card_b \gset

select set_config('request.jwt.claim.sub', :'owner_id', true) as _claim \gset
select public.create_space_invitation(true)->>'code' as invite_code \gset
select length(:'invite_code') as code_length \gset
select pg_temp.assert_true(:'code_length' = '20', 'invitation code format was invalid');
select pg_temp.assert_true(not exists (
  select 1 from information_schema.columns where table_schema = 'public'
    and table_name = 'space_invitations' and column_name = 'code'
), 'raw invitation code has a database column');

select set_config('request.jwt.claim.sub', :'partner_id', true) as _claim \gset
select public.prepare_join(:'invite_code', gen_random_uuid()) as preview \gset
select (:'preview'::jsonb->>'operation_id') as join_operation \gset
select pg_temp.assert_true((:'preview'::jsonb->>'status') = 'prepared'
  and (:'preview'::jsonb#>>'{counts,their_plans}')::int = 1
  and not (:'preview'::jsonb ? 'title'), 'join review exposed titles or missed counts');
select public.confirm_join(:'join_operation'::uuid, 2) as joined \gset
select public.confirm_join(:'join_operation'::uuid, 2) as joined_again \gset
select pg_temp.assert_true((:'joined'::jsonb->>'status') = 'completed'
  and (:'joined_again'::jsonb->>'status') = 'completed', 'join was not idempotent');
select pg_temp.assert_true((select count(*) = 2 and bool_and(space_id = :'target_space'::uuid)
  and bool_and(id in (:'plan_a'::uuid, :'plan_b'::uuid)) from public.date_plans),
  'plans did not merge with stable ids');
select pg_temp.assert_true((select count(*) = 2 and bool_and(space_id = :'target_space'::uuid)
  and bool_and(id in (:'day_a'::uuid, :'day_b'::uuid)) from public.plan_days),
  'days did not merge with stable ids');
select pg_temp.assert_true((select count(*) = 2 and bool_and(space_id = :'target_space'::uuid)
  and bool_and(id in (:'card_a'::uuid, :'card_b'::uuid)) from public.activity_cards),
  'activity cards did not merge with stable ids');
select pg_temp.assert_true((select count(*) = 2 from public.space_members where space_id = :'target_space'::uuid),
  'merged Space does not have exactly two members');

select set_config('request.jwt.claim.sub', :'owner_id', true) as _claim \gset
select pg_temp.assert_true((select count(*) = 2 from public.date_plans), 'inviter cannot see both plans after joining');
select set_config('request.jwt.claim.sub', :'outsider_id', true) as _claim \gset
select pg_temp.assert_true((select count(*) = 0 from public.date_plans), 'unrelated account can read a private plan');
select pg_temp.assert_true((select count(*) = 0 from public.plan_days), 'unrelated account can read private plan days');
select pg_temp.assert_true((select count(*) = 0 from public.activity_cards), 'unrelated account can read private cards');
select pg_temp.assert_true(not has_table_privilege('authenticated', 'public.space_members', 'INSERT')
  and not has_table_privilege('anon', 'public.date_plans', 'SELECT'),
  'direct membership writes or anonymous plan reads are enabled');

select set_config('request.jwt.claim.sub', :'fresh_inviter_id', true) as _claim \gset
select public.create_personal_space() as fresh_space \gset
select public.create_space_invitation(true)->>'code' as fresh_code \gset
select set_config('request.jwt.claim.sub', :'fresh_joiner_id', true) as _claim \gset
select public.prepare_join(:'fresh_code', gen_random_uuid()) as fresh_review \gset
select (:'fresh_review'::jsonb->>'operation_id') as fresh_operation \gset
select public.cancel_join(:'fresh_operation'::uuid) as cancelled \gset
select public.prepare_join(:'fresh_code', gen_random_uuid()) as retry_review \gset
select (:'retry_review'::jsonb->>'operation_id') as retry_operation \gset
select public.confirm_join(:'retry_operation'::uuid, 2) as fresh_joined \gset
select pg_temp.assert_true((:'fresh_joined'::jsonb->>'status') = 'completed', 'cancel/retry join did not complete');

select set_config('request.jwt.claim.sub', :'revoker_id', true) as _claim \gset
select public.create_personal_space() as revoke_space \gset
select public.create_space_invitation(true)->>'code' as revoked_code \gset
select public.list_my_space_invitations() as invitations \gset
select public.revoke_space_invitation((:'invitations'::jsonb->0->>'id')::uuid) as revoked \gset
select pg_temp.assert_true(:'revoked'::jsonb->>'status' = 'revoked', 'pending invitation could not be revoked');
select set_config('request.jwt.claim.sub', :'probe_id', true) as _claim \gset
select pg_temp.assert_true((public.prepare_join(:'revoked_code', gen_random_uuid())->>'error_code') = 'INVITE_INVALID',
  'revoked invitation was accepted');
do $$
declare i integer; v_result jsonb;
begin
  for i in 1..9 loop
    v_result := public.prepare_join('00000000000000000000', gen_random_uuid());
    if v_result->>'error_code' <> 'INVITE_INVALID' then raise exception 'invalid code attempt % was not handled', i; end if;
  end loop;
  v_result := public.prepare_join('00000000000000000000', gen_random_uuid());
  if v_result->>'error_code' <> 'RATE_LIMITED' then raise exception 'invalid code attempts were not rate limited'; end if;
end;
$$;

rollback;
\echo 'PASS: Space invitation joins preserve plan/day/card ids and grant both members access.'
\echo 'PASS: counts-only review, idempotent confirm, outsider RLS, and no direct membership writes.'
\echo 'PASS: no-Space invitee cancel/retry, revocation, and invalid-code rate limiting.'
