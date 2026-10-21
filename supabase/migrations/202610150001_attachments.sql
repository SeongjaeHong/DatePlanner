-- S7: private file attachments for itinerary cards, plans, and bookings.
begin;

create table if not exists public.attachments (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  plan_id uuid not null references public.date_plans(id) on delete cascade,
  activity_card_id uuid references public.activity_cards(id) on delete cascade,
  transport_booking_id uuid references public.transport_bookings(id) on delete cascade,
  accommodation_booking_id uuid references public.accommodation_bookings(id) on delete cascade,
  kind text not null check (kind in ('pdf', 'photo')),
  original_name text not null check (char_length(original_name) between 1 and 255),
  storage_path text not null unique,
  content_type text not null check (content_type in ('application/pdf', 'image/jpeg')),
  size_bytes bigint not null check (size_bytes between 1 and 3145728),
  status text not null default 'uploading'
    check (status in ('uploading', 'ready', 'failed', 'deleting')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (num_nonnulls(activity_card_id, transport_booking_id, accommodation_booking_id) <= 1),
  check ((kind = 'photo' and activity_card_id is not null
          and transport_booking_id is null and accommodation_booking_id is null
          and content_type = 'image/jpeg')
      or (kind = 'pdf' and activity_card_id is null and content_type = 'application/pdf')),
  check (storage_path = lower(id::text))
);

create index if not exists attachments_plan_created_idx on public.attachments(plan_id, created_at);
create index if not exists attachments_space_idx on public.attachments(space_id);
alter table public.attachments enable row level security;
drop policy if exists attachments_member_read on public.attachments;
create policy attachments_member_read on public.attachments
  for select to authenticated using (public.is_space_member(space_id));
revoke all on public.attachments from anon, authenticated;
grant select on public.attachments to authenticated;

drop trigger if exists lock_active_space_before_write on public.attachments;
create trigger lock_active_space_before_write before insert or update or delete on public.attachments
  for each row execute function public.lock_active_space_for_owned_row();

create or replace function public.validate_attachment_parent()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public as $$
declare
  v_parent_space uuid;
  v_parent_plan uuid;
  v_deleted timestamptz;
  v_spaces_match boolean;
begin
  select p.space_id, p.deleted_at into v_parent_space, v_deleted
    from public.date_plans p where p.id = new.plan_id;
  v_spaces_match := v_parent_space = new.space_id or exists (
    select 1 from public.space_merge_operations o
    where o.status = 'prepared'
      and ((o.source_space_id = v_parent_space and o.target_space_id = new.space_id)
        or (o.target_space_id = v_parent_space and o.source_space_id = new.space_id))
  );
  if not found or not v_spaces_match or v_deleted is not null then
    raise exception 'ATTACHMENT_PARENT_INVALID';
  end if;
  if new.activity_card_id is not null then
    select c.space_id, c.plan_id, c.deleted_at into v_parent_space, v_parent_plan, v_deleted
      from public.activity_cards c where c.id = new.activity_card_id;
    v_spaces_match := v_parent_space = new.space_id or exists (
      select 1 from public.space_merge_operations o
      where o.status = 'prepared'
        and ((o.source_space_id = v_parent_space and o.target_space_id = new.space_id)
          or (o.target_space_id = v_parent_space and o.source_space_id = new.space_id))
    );
    if not found or not v_spaces_match or v_parent_plan <> new.plan_id or v_deleted is not null then
      raise exception 'ATTACHMENT_PARENT_INVALID';
    end if;
  elsif new.transport_booking_id is not null then
    select b.space_id, b.plan_id, b.deleted_at into v_parent_space, v_parent_plan, v_deleted
      from public.transport_bookings b where b.id = new.transport_booking_id;
    v_spaces_match := v_parent_space = new.space_id or exists (
      select 1 from public.space_merge_operations o
      where o.status = 'prepared'
        and ((o.source_space_id = v_parent_space and o.target_space_id = new.space_id)
          or (o.target_space_id = v_parent_space and o.source_space_id = new.space_id))
    );
    if not found or not v_spaces_match or v_parent_plan <> new.plan_id or v_deleted is not null then
      raise exception 'ATTACHMENT_PARENT_INVALID';
    end if;
  elsif new.accommodation_booking_id is not null then
    select b.space_id, b.plan_id, b.deleted_at into v_parent_space, v_parent_plan, v_deleted
      from public.accommodation_bookings b where b.id = new.accommodation_booking_id;
    v_spaces_match := v_parent_space = new.space_id or exists (
      select 1 from public.space_merge_operations o
      where o.status = 'prepared'
        and ((o.source_space_id = v_parent_space and o.target_space_id = new.space_id)
          or (o.target_space_id = v_parent_space and o.source_space_id = new.space_id))
    );
    if not found or not v_spaces_match or v_parent_plan <> new.plan_id or v_deleted is not null then
      raise exception 'ATTACHMENT_PARENT_INVALID';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.validate_attachment_parent() from public, anon, authenticated;
drop trigger if exists attachment_parent_valid on public.attachments;
create trigger attachment_parent_valid before insert or update on public.attachments
  for each row execute function public.validate_attachment_parent();

-- The object bucket remains private. Storage enforces size and the final stored MIME type.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('space-attachments', 'space-attachments', false, 3145728,
  array['application/pdf', 'image/jpeg']::text[])
on conflict (id) do update set
  name = excluded.name,
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists space_attachments_member_read on storage.objects;
create policy space_attachments_member_read on storage.objects
  for select to authenticated using (
    bucket_id = 'space-attachments' and exists (
      select 1 from public.attachments a
      where a.storage_path = name and a.status = 'ready'
        and public.is_space_member(a.space_id)
    )
  );

drop policy if exists space_attachments_member_upload on storage.objects;
create policy space_attachments_member_upload on storage.objects
  for insert to authenticated with check (
    bucket_id = 'space-attachments' and exists (
      select 1 from public.attachments a
      where a.storage_path = name and a.status in ('uploading', 'failed')
        and public.is_space_member(a.space_id)
    )
  );

drop policy if exists space_attachments_member_delete on storage.objects;
create policy space_attachments_member_delete on storage.objects
  for delete to authenticated using (
    bucket_id = 'space-attachments' and exists (
      select 1 from public.attachments a
      where a.storage_path = name and a.status in ('uploading', 'failed', 'deleting')
        and public.is_space_member(a.space_id)
    )
  );

create or replace function public.begin_space_attachment_upload(
  p_plan_id uuid, p_activity_card_id uuid, p_transport_booking_id uuid,
  p_accommodation_booking_id uuid, p_kind text, p_original_name text,
  p_content_type text, p_size_bytes bigint, p_attachment_id uuid default null
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public as $$
declare v_plan public.date_plans%rowtype; v_id uuid; v_row public.attachments%rowtype;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into v_plan from public.date_plans where id = p_plan_id and deleted_at is null;
  if not found or not public.is_space_member(v_plan.space_id) then raise exception 'NOT_AUTHORIZED'; end if;
  if p_size_bytes is null or p_size_bytes < 1 or p_size_bytes > 3145728 then
    raise exception 'ATTACHMENT_TOO_LARGE';
  end if;
  if p_kind not in ('pdf', 'photo') or
     (p_kind = 'pdf' and (p_content_type <> 'application/pdf' or p_activity_card_id is not null)) or
     (p_kind = 'photo' and (p_content_type <> 'image/jpeg' or p_activity_card_id is null or
       p_transport_booking_id is not null or p_accommodation_booking_id is not null)) or
     num_nonnulls(p_activity_card_id, p_transport_booking_id, p_accommodation_booking_id) > 1 then
    raise exception 'ATTACHMENT_INVALID';
  end if;
  if p_original_name is null or char_length(trim(p_original_name)) < 1 or char_length(p_original_name) > 255 or
     p_original_name ~ '[[:cntrl:]]' then raise exception 'ATTACHMENT_INVALID'; end if;
  perform 1 from public.spaces where id = v_plan.space_id and status = 'active' for update;
  if not found then raise exception 'SPACE_NOT_ACTIVE'; end if;

  v_id := coalesce(p_attachment_id, gen_random_uuid());
  select * into v_row from public.attachments where id = v_id for update;
  if found then
    if v_row.status <> 'failed' or v_row.space_id <> v_plan.space_id or v_row.plan_id <> p_plan_id or
       v_row.activity_card_id is distinct from p_activity_card_id or
       v_row.transport_booking_id is distinct from p_transport_booking_id or
       v_row.accommodation_booking_id is distinct from p_accommodation_booking_id or
       v_row.kind <> p_kind or v_row.content_type <> p_content_type or v_row.size_bytes <> p_size_bytes or
       v_row.original_name <> p_original_name then raise exception 'ATTACHMENT_RETRY_INVALID'; end if;
    update public.attachments set status = 'uploading' where id = v_id returning * into v_row;
  else
    insert into public.attachments(id, space_id, plan_id, activity_card_id,
      transport_booking_id, accommodation_booking_id, kind, original_name,
      storage_path, content_type, size_bytes, created_by)
    values (v_id, v_plan.space_id, p_plan_id, p_activity_card_id,
      p_transport_booking_id, p_accommodation_booking_id, p_kind, trim(p_original_name),
      v_id::text, p_content_type, p_size_bytes, auth.uid()) returning * into v_row;
  end if;
  return to_jsonb(v_row);
end;
$$;

create or replace function public.finish_space_attachment_upload(p_attachment_id uuid)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, storage as $$
declare v_attachment public.attachments%rowtype; v_size bigint; v_mime text;
begin
  select * into v_attachment from public.attachments where id = p_attachment_id for update;
  if not found or not public.is_space_member(v_attachment.space_id) or v_attachment.status <> 'uploading' then
    raise exception 'ATTACHMENT_NOT_AVAILABLE';
  end if;
  select nullif(o.metadata->>'size','')::bigint, o.metadata->>'mimetype'
    into v_size, v_mime from storage.objects o
    where o.bucket_id = 'space-attachments' and o.name = v_attachment.storage_path;
  if not found or v_size is null or v_size <> v_attachment.size_bytes or
     v_mime <> v_attachment.content_type then raise exception 'ATTACHMENT_OBJECT_INVALID'; end if;
  update public.attachments set status = 'ready' where id = p_attachment_id returning * into v_attachment;
  return to_jsonb(v_attachment);
end;
$$;

create or replace function public.fail_space_attachment_upload(p_attachment_id uuid)
returns void language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  update public.attachments set status = 'failed'
    where id = p_attachment_id and status = 'uploading' and public.is_space_member(space_id);
  if not found then raise exception 'ATTACHMENT_NOT_AVAILABLE'; end if;
end;
$$;

create or replace function public.mark_space_attachment_deleting(p_attachment_id uuid)
returns void language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  update public.attachments set status = 'deleting'
    where id = p_attachment_id and status in ('ready', 'failed', 'deleting') and public.is_space_member(space_id);
  if not found then raise exception 'ATTACHMENT_NOT_AVAILABLE'; end if;
end;
$$;

create or replace function public.finish_space_attachment_delete(p_attachment_id uuid)
returns void language plpgsql security definer set search_path = pg_catalog, public, storage as $$
declare v_attachment public.attachments%rowtype;
begin
  select * into v_attachment from public.attachments where id = p_attachment_id for update;
  if not found or v_attachment.status <> 'deleting' or not public.is_space_member(v_attachment.space_id) then
    raise exception 'ATTACHMENT_NOT_AVAILABLE';
  end if;
  if exists (select 1 from storage.objects o where o.bucket_id = 'space-attachments'
      and o.name = v_attachment.storage_path) then raise exception 'ATTACHMENT_OBJECT_REMAINS'; end if;
  delete from public.attachments where id = p_attachment_id;
end;
$$;

revoke all on function public.begin_space_attachment_upload(uuid,uuid,uuid,uuid,text,text,text,bigint,uuid),
  public.finish_space_attachment_upload(uuid), public.fail_space_attachment_upload(uuid),
  public.mark_space_attachment_deleting(uuid), public.finish_space_attachment_delete(uuid)
  from public, anon;
grant execute on function public.begin_space_attachment_upload(uuid,uuid,uuid,uuid,text,text,text,bigint,uuid),
  public.finish_space_attachment_upload(uuid), public.fail_space_attachment_upload(uuid),
  public.mark_space_attachment_deleting(uuid), public.finish_space_attachment_delete(uuid)
  to authenticated;

commit;
