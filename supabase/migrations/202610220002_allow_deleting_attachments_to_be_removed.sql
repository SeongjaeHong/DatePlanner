-- Storage's delete endpoint must be able to select an object before deleting it.
-- Keep deleting attachments readable to current Space members so removal can
-- finish after mark_space_attachment_deleting changes the attachment status.
begin;

drop policy if exists space_attachments_member_read on storage.objects;
create policy space_attachments_member_read on storage.objects
  for select to authenticated using (
    bucket_id = 'space-attachments' and exists (
      select 1 from public.attachments a
      where a.storage_path = name and a.status in ('ready', 'deleting')
        and public.is_space_member(a.space_id)
    )
  );

commit;
