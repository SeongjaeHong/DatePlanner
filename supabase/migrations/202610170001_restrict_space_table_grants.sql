-- Keep membership reads behind RLS and prevent direct table-wide operations.
-- Space creation and membership changes remain available only through audited RPCs.
begin;

revoke all privileges on table public.spaces, public.space_members
  from public, anon, authenticated;
grant select on table public.spaces, public.space_members to authenticated;

-- Trigger functions are invoked by their triggers and need no client execute grant.
revoke all on function public.enforce_space_member_limit() from public, anon, authenticated;

commit;
