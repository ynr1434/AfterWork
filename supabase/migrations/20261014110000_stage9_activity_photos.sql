begin;

-- Private bucket: clients receive short-lived signed read URLs only after RLS checks.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('activity-photos', 'activity-photos', false, 5242880, array['image/jpeg'])
on conflict (id) do update
set name = excluded.name,
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

alter table public.activity_photos
    add constraint activity_photos_storage_path_unique unique (storage_path);

-- Clients supply the photo UUID so the object path and metadata row share one identity.
grant insert (id) on public.activity_photos to authenticated;

drop policy photos_read on public.activity_photos;
drop policy photos_insert_own on public.activity_photos;
drop policy photos_delete_own on public.activity_photos;

create policy photos_read on public.activity_photos
for select to authenticated
using (exists (
    select 1 from public.activities a where a.id = activity_photos.activity_id
));

create policy photos_insert_going on public.activity_photos
for insert to authenticated
with check (
    uploader_id = (select auth.uid())
    and (storage.foldername(storage_path))[1] = 'activities'
    and (storage.foldername(storage_path))[2] = activity_id::text
    and (storage.foldername(storage_path))[3] = uploader_id::text
    and storage.filename(storage_path) = id::text || '.jpg'
    and exists (
        select 1 from public.activities a
        where a.id = activity_photos.activity_id
          and (a.author_id = (select auth.uid()) or exists (
              select 1 from public.activity_participants p
              where p.activity_id = a.id
                and p.user_id = (select auth.uid())
                and p.status = 'going'
          ))
    )
);

create or replace function public.can_upload_activity_photo(
    p_activity_id uuid,
    p_uploader_id uuid
) returns boolean
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
    object_count bigint;
begin
    if auth.uid() is null or p_uploader_id is distinct from auth.uid() then
        return false;
    end if;

    -- Serialize uploads for this activity while the Storage object row is inserted.
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('activity-photos:' || p_activity_id::text, 0)
    );

    if not exists (
        select 1 from public.activities a
        where a.id = p_activity_id
          and (a.author_id = auth.uid() or exists (
              select 1 from public.activity_participants p
              where p.activity_id = a.id
                and p.user_id = auth.uid()
                and p.status = 'going'
          ))
    ) then
        return false;
    end if;

    select count(*) into object_count
    from storage.objects o
    where o.bucket_id = 'activity-photos'
      and (storage.foldername(o.name))[1] = 'activities'
      and (storage.foldername(o.name))[2] = p_activity_id::text;

    return object_count < 10;
end;
$$;

create or replace function public.can_delete_activity_photo(
    p_activity_id uuid,
    p_uploader_id uuid
) returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
    select auth.uid() is not null and (
        auth.uid() = p_uploader_id
        or exists (
            select 1 from public.activities a
            where a.id = p_activity_id and a.author_id = auth.uid()
        )
    );
$$;

revoke all on function public.can_upload_activity_photo(uuid, uuid) from public, anon, authenticated;
grant execute on function public.can_upload_activity_photo(uuid, uuid) to authenticated;
revoke all on function public.can_delete_activity_photo(uuid, uuid) from public, anon, authenticated;
grant execute on function public.can_delete_activity_photo(uuid, uuid) to authenticated;

create policy photos_delete_uploader_or_organizer on public.activity_photos
for delete to authenticated
using (public.can_delete_activity_photo(activity_id, uploader_id));

create or replace function public.enforce_activity_photo_limit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
    photo_count bigint;
begin
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('activity-photos:' || new.activity_id::text, 0)
    );
    select count(*) into photo_count
    from public.activity_photos p
    where p.activity_id = new.activity_id;
    if photo_count >= 10 then
        raise exception 'An activity can have at most 10 photos.' using errcode = '23514';
    end if;
    return new;
end;
$$;
revoke all on function public.enforce_activity_photo_limit() from public, anon, authenticated;
create trigger activity_photos_limit_before_insert
before insert on public.activity_photos
for each row execute function public.enforce_activity_photo_limit();

create policy activity_photos_objects_read on storage.objects
for select to authenticated
using (
    bucket_id = 'activity-photos'
    and exists (
        select 1 from public.activity_photos p
        where p.storage_path = storage.objects.name
    )
);

create policy activity_photos_objects_insert on storage.objects
for insert to authenticated
with check (
    bucket_id = 'activity-photos'
    and array_length(storage.foldername(name), 1) = 3
    and (storage.foldername(name))[1] = 'activities'
    and (storage.foldername(name))[3] = (select auth.uid())::text
    and storage.filename(name) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'
    and public.can_upload_activity_photo((storage.foldername(name))[2]::uuid, (select auth.uid()))
);

create policy activity_photos_objects_delete on storage.objects
for delete to authenticated
using (
    bucket_id = 'activity-photos'
    and array_length(storage.foldername(name), 1) = 3
    and (storage.foldername(name))[1] = 'activities'
    and storage.filename(name) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'
    and public.can_delete_activity_photo(
        (storage.foldername(name))[2]::uuid,
        (storage.foldername(name))[3]::uuid
    )
);

commit;
