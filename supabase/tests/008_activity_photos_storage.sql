-- Run after migrations 001-008. Exercises photo metadata RLS and storage rules
-- in a rollback-only transaction; it creates no persistent test data.
begin;
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$ begin
    if ok is distinct from true then raise exception 'Assertion failed: %', label; end if;
end $$;
create function pg_temp.expect_error(statement text, expected_state text) returns void
language plpgsql as $$ begin
    begin execute statement;
    exception when others then
        if sqlstate = expected_state then return; end if;
        raise exception 'Expected %, got %: %', expected_state, sqlstate, sqlerrm;
    end;
    raise exception 'Expected error % for %', expected_state, statement;
end $$;

select pg_temp.assert_true(
    (select public = false from storage.buckets where id = 'activity-photos'),
    'activity photo bucket exists and is private');
select pg_temp.assert_true(
    (select relrowsecurity from pg_class where oid = 'public.activity_photos'::regclass),
    'photo metadata RLS remains enabled');
select pg_temp.assert_true(
    (select relrowsecurity from pg_class where oid = 'storage.objects'::regclass),
    'Storage object RLS remains enabled');
select pg_temp.assert_true(
    has_column_privilege('authenticated', 'public.activity_photos', 'id', 'INSERT'),
    'authenticated can supply metadata id while preserving existing column grants');
select pg_temp.assert_true(
    not has_table_privilege('authenticated', 'public.activity_photos', 'UPDATE'),
    'authenticated cannot update photo metadata');

insert into auth.users(id) values
('91000000-0000-0000-0000-000000000091'),
('91000000-0000-0000-0000-000000000092'),
('91000000-0000-0000-0000-000000000093');
insert into public.profiles(id, display_name) values
('91000000-0000-0000-0000-000000000091', 'Photo Organizer'),
('91000000-0000-0000-0000-000000000092', 'Photo Participant'),
('91000000-0000-0000-0000-000000000093', 'Photo Outsider');

select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000091', true);
set local role authenticated;
insert into public.activities(id, author_id, category_id, title, start_at, location_name)
select '92000000-0000-0000-0000-000000000091', auth.uid(), id,
       'Photo policy test activity', now() + interval '1 day', 'Test Hall'
from public.categories limit 1;
reset role;

select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000092', true);
set local role authenticated;
insert into public.activity_participants(activity_id, user_id, status)
values ('92000000-0000-0000-0000-000000000091', auth.uid(), 'going');
insert into storage.objects(bucket_id, name)
values ('activity-photos', 'activities/92000000-0000-0000-0000-000000000091/91000000-0000-0000-0000-000000000092/93000000-0000-0000-0000-000000000091.jpg');
insert into public.activity_photos(id, activity_id, uploader_id, storage_path)
values ('93000000-0000-0000-0000-000000000091',
        '92000000-0000-0000-0000-000000000091', auth.uid(),
        'activities/92000000-0000-0000-0000-000000000091/91000000-0000-0000-0000-000000000092/93000000-0000-0000-0000-000000000091.jpg');
select pg_temp.assert_true(
    (select count(*) = 1 from public.activity_photos where id = '93000000-0000-0000-0000-000000000091'),
    'going participant can upload a photo and read metadata');
select pg_temp.expect_error(
    'insert into public.activity_photos(id, activity_id, uploader_id, storage_path) values (''93000000-0000-0000-0000-000000000094'', ''92000000-0000-0000-0000-000000000091'', auth.uid(), ''activities/92000000-0000-0000-0000-000000000091/91000000-0000-0000-0000-000000000092/93000000-0000-0000-0000-000000000091.jpg'')',
    '23505');
reset role;

select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000093', true);
set local role authenticated;
select pg_temp.expect_error(
    'insert into storage.objects(bucket_id, name) values (''activity-photos'', ''activities/92000000-0000-0000-0000-000000000091/91000000-0000-0000-0000-000000000093/93000000-0000-0000-0000-000000000093.jpg'')',
    '42501');
select pg_temp.expect_error(
    'insert into storage.objects(bucket_id, name) values (''activity-photos'', ''activities/92000000-0000-0000-0000-000000000091/91000000-0000-0000-0000-000000000092/93000000-0000-0000-0000-000000000093.jpg'')',
    '42501');
select pg_temp.expect_error(
    'insert into public.activity_photos(id, activity_id, uploader_id, storage_path) values (''93000000-0000-0000-0000-000000000093'', ''92000000-0000-0000-0000-000000000091'', auth.uid(), ''activities/92000000-0000-0000-0000-000000000091/91000000-0000-0000-0000-000000000093/93000000-0000-0000-0000-000000000093.jpg'')',
    '42501');
select pg_temp.assert_true(
    (select count(*) = 1 from public.activity_photos where id = '93000000-0000-0000-0000-000000000091'),
    'authenticated coworker can read photos for a visible activity');
select pg_temp.assert_true(
    (select count(*) = 0 from public.activity_photos where id = '93000000-0000-0000-0000-000000000091'
      and public.can_delete_activity_photo(activity_id, uploader_id)),
    'unrelated coworker cannot satisfy photo delete authorization');
delete from public.activity_photos where id = '93000000-0000-0000-0000-000000000091';
select pg_temp.assert_true(exists (
    select 1 from public.activity_photos where id = '93000000-0000-0000-0000-000000000091'
), 'unrelated coworker delete is filtered by RLS');
reset role;

select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000092', true);
set local role authenticated;
delete from storage.objects where bucket_id = 'activity-photos'
  and name = 'activities/92000000-0000-0000-0000-000000000091/91000000-0000-0000-0000-000000000092/93000000-0000-0000-0000-000000000091.jpg';
delete from public.activity_photos where id = '93000000-0000-0000-0000-000000000091';
select pg_temp.assert_true(not exists (
    select 1 from public.activity_photos where id = '93000000-0000-0000-0000-000000000091'
), 'uploader can delete own photo');

-- Recreate one row to verify organizer cleanup independently of uploader rights.
insert into storage.objects(bucket_id, name)
values ('activity-photos', 'activities/92000000-0000-0000-0000-000000000091/91000000-0000-0000-0000-000000000092/93000000-0000-0000-0000-000000000092.jpg');
insert into public.activity_photos(id, activity_id, uploader_id, storage_path)
values ('93000000-0000-0000-0000-000000000092',
        '92000000-0000-0000-0000-000000000091', auth.uid(),
        'activities/92000000-0000-0000-0000-000000000091/91000000-0000-0000-0000-000000000092/93000000-0000-0000-0000-000000000092.jpg');
reset role;

select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000091', true);
set local role authenticated;
delete from storage.objects where bucket_id = 'activity-photos'
  and name = 'activities/92000000-0000-0000-0000-000000000091/91000000-0000-0000-0000-000000000092/93000000-0000-0000-0000-000000000092.jpg';
delete from public.activity_photos where id = '93000000-0000-0000-0000-000000000092';
select pg_temp.assert_true(not exists (
    select 1 from public.activity_photos where id = '93000000-0000-0000-0000-000000000092'
), 'activity organizer can delete a participant photo');
reset role;

-- Verify the immutable path uniqueness constraint and server-side row count cap.
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000091', true);
set local role authenticated;
do $$
declare i integer;
begin
    for i in 1..10 loop
        insert into public.activity_photos(id, activity_id, uploader_id, storage_path)
        values (('94000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
                '92000000-0000-0000-0000-000000000091', auth.uid(),
                'activities/92000000-0000-0000-0000-000000000091/91000000-0000-0000-0000-000000000091/'
                || ('94000000-0000-0000-0000-' || lpad(i::text, 12, '0')) || '.jpg');
    end loop;
end $$;
select pg_temp.expect_error(
    'insert into public.activity_photos(id, activity_id, uploader_id, storage_path) values (''94000000-0000-0000-0000-000000000011'', ''92000000-0000-0000-0000-000000000091'', auth.uid(), ''activities/92000000-0000-0000-0000-000000000091/91000000-0000-0000-0000-000000000091/94000000-0000-0000-0000-000000000011.jpg'')',
    '23514');
reset role;
rollback;
