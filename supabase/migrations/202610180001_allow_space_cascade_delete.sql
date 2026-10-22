-- Permit FK cascades after the parent Space row has been deleted. Direct
-- client writes remain restricted; an existing non-active Space still blocks
-- edits and deletes as before.
begin;

create or replace function public.lock_active_space_for_owned_row()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_space_id uuid;
  v_status text;
begin
  if tg_op = 'DELETE' then
    select s.status into v_status
      from public.spaces s where s.id = old.space_id for update;
    -- A missing parent means this delete is part of the parent's FK cascade.
    if not found then return old; end if;
    if v_status is distinct from 'active' then raise exception 'SPACE_NOT_ACTIVE'; end if;
    return old;
  end if;

  if tg_op = 'UPDATE' and old.space_id is distinct from new.space_id then
    perform 1 from public.spaces s
      where s.id in (old.space_id, new.space_id) order by s.id for update;
  else
    v_space_id := new.space_id;
    perform 1 from public.spaces s where s.id = v_space_id for update;
  end if;

  select s.status into v_status from public.spaces s where s.id = new.space_id;
  if v_status is distinct from 'active' then raise exception 'SPACE_NOT_ACTIVE'; end if;
  return new;
end;
$$;

revoke all on function public.lock_active_space_for_owned_row() from public, anon, authenticated;

commit;
