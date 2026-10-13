-- Run after the migration in an isolated Supabase test project as postgres.
-- All fixtures and changes roll back. No extension required.
begin;
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$ begin
    if ok is distinct from true then raise exception 'Assertion failed: %', label; end if;
end $$;
create function pg_temp.expect_error(statement text, expected_state text) returns void
language plpgsql as $$ begin
    begin
        execute statement;
    exception when others then
        if sqlstate = expected_state then return; end if;
        raise;
    end;
    raise exception 'Expected SQLSTATE %, statement succeeded: %', expected_state, statement;
end $$;

insert into auth.users (id) values
('10000000-0000-0000-0000-000000000001'),
('10000000-0000-0000-0000-000000000002'),
('10000000-0000-0000-0000-000000000003');
insert into public.profiles (id, display_name) values
('10000000-0000-0000-0000-000000000001', 'Owner'),
('10000000-0000-0000-0000-000000000002', 'Coworker'),
('10000000-0000-0000-0000-000000000003', 'Unrelated');
insert into public.activities (id, author_id, category_id, title, start_at, location_name, updated_at)
select '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', id, 'Owner activity', now(), 'Court', '2000-01-01' from public.categories where slug = 'sports';
insert into public.activities (id, author_id, category_id, title, start_at, location_name)
select '20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', id, 'Other activity', now(), 'Cafe' from public.categories where slug = 'food';
insert into public.comments (id, activity_id, author_id, body) values
('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Owner comment'),
('30000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','Other comment');
insert into public.notifications (user_id, type, title) values
('10000000-0000-0000-0000-000000000001','test','Owner notification'),
('10000000-0000-0000-0000-000000000002','test','Other notification');

set local role anon;
select pg_temp.expect_error('select * from public.activities', '42501');
select pg_temp.expect_error('select * from public.profiles', '42501');
select pg_temp.expect_error('select * from public.notifications', '42501');
reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.assert_true((select count(*) = 12 from public.categories), 'category seeds');
select pg_temp.assert_true((select count(*) = 3 from public.profiles), 'authenticated profile read');
update public.profiles set display_name = 'Updated owner' where id = auth.uid();
update public.profiles set display_name = 'Forbidden' where id <> auth.uid();
select pg_temp.assert_true(not exists(select 1 from public.profiles where display_name = 'Forbidden'), 'profile ownership');
select pg_temp.expect_error('update public.profiles set email = ''spoofed''', '42501');
select pg_temp.expect_error('insert into public.categories(slug,name,sf_symbol) values (''bad'',''bad'',''bad'')', '42501');

update public.activities set title = 'Updated activity' where author_id = auth.uid();
select pg_temp.assert_true((select updated_at > '2000-01-01' from public.activities where author_id = auth.uid()), 'updated_at trigger');
update public.activities set title = 'Forbidden' where author_id <> auth.uid();
select pg_temp.assert_true(not exists(select 1 from public.activities where title = 'Forbidden'), 'activity update ownership');
select pg_temp.expect_error('update public.activities set author_id = ''10000000-0000-0000-0000-000000000002''', '42501');
insert into public.activities(author_id,category_id,title,start_at,location_name)
select auth.uid(),id,'New own activity',now(),'Court' from public.categories where slug = 'sports';
select pg_temp.expect_error('insert into public.activities(author_id,category_id,title,start_at,location_name) select ''10000000-0000-0000-0000-000000000002'',id,''Spoofed'',now(),''Court'' from public.categories limit 1', '42501');
select pg_temp.expect_error('update public.activities set max_participants = 0 where author_id = auth.uid()', '23514');
select pg_temp.expect_error('update public.activities set end_at = start_at - interval ''1 hour'' where author_id = auth.uid()', '23514');

insert into public.activity_participants(activity_id,user_id,status) values
('20000000-0000-0000-0000-000000000001',auth.uid(),'going');
select pg_temp.expect_error('insert into public.activity_participants(activity_id,user_id,status) values (''20000000-0000-0000-0000-000000000001'',auth.uid(),''going'')', '23505');
select pg_temp.expect_error('insert into public.activity_participants(activity_id,user_id,status) values (''20000000-0000-0000-0000-000000000001'',''10000000-0000-0000-0000-000000000002'',''going'')', '42501');
update public.activity_participants set status = 'interested' where user_id = auth.uid();
select pg_temp.assert_true((select status = 'interested' from public.activity_participants where user_id = auth.uid()), 'own participant update');
select pg_temp.expect_error('update public.activity_participants set status = ''invalid''', '23514');
select pg_temp.expect_error('update public.activity_participants set activity_id = ''20000000-0000-0000-0000-000000000002''', '42501');

insert into public.comments(activity_id,author_id,body) values ('20000000-0000-0000-0000-000000000001',auth.uid(),'New comment');
select pg_temp.expect_error('insert into public.comments(activity_id,author_id,body) values (''20000000-0000-0000-0000-000000000001'',''10000000-0000-0000-0000-000000000002'',''Spoofed'')', '42501');
update public.comments set body = 'Forbidden' where author_id <> auth.uid();
select pg_temp.assert_true(not exists(select 1 from public.comments where body = 'Forbidden'), 'comment ownership');
insert into public.activity_photos(activity_id,uploader_id,storage_path) values
('20000000-0000-0000-0000-000000000001',auth.uid(),auth.uid()::text || '/photo.jpg');
select pg_temp.expect_error('insert into public.activity_photos(activity_id,uploader_id,storage_path) values (''20000000-0000-0000-0000-000000000001'',auth.uid(),''someone-else/photo.jpg'')', '42501');

insert into public.activity_mentions(activity_id,mentioned_user_id,mentioned_by_user_id) values
('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002',auth.uid());
insert into public.activity_mentions(activity_id,comment_id,mentioned_user_id,mentioned_by_user_id) values
('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002',auth.uid());
select pg_temp.expect_error('insert into public.activity_mentions(activity_id,mentioned_user_id,mentioned_by_user_id) values (''20000000-0000-0000-0000-000000000002'',''10000000-0000-0000-0000-000000000003'',auth.uid())', '42501');
select pg_temp.expect_error('insert into public.activity_mentions(activity_id,comment_id,mentioned_user_id,mentioned_by_user_id) values (''20000000-0000-0000-0000-000000000002'',''30000000-0000-0000-0000-000000000001'',''10000000-0000-0000-0000-000000000003'',auth.uid())', '42501');

select pg_temp.assert_true((select count(*) = 1 from public.notifications), 'notification isolation');
update public.notifications set is_read = true;
select pg_temp.assert_true((select bool_and(is_read) from public.notifications), 'mark own notification read');
select pg_temp.expect_error('update public.notifications set title = ''Spoofed''', '42501');
select pg_temp.expect_error('insert into public.notifications(user_id,type,title) values (auth.uid(),''test'',''Spoofed'')', '42501');
select pg_temp.expect_error('delete from public.notifications', '42501');

reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.assert_true((select count(*) = 0 from public.activity_mentions), 'unrelated mentions hidden');
delete from public.activities;
delete from public.comments;
delete from public.activity_photos;
delete from public.activity_participants;
delete from public.activity_mentions;
select pg_temp.assert_true((select count(*) = 3 from public.activities), 'non-owner activity delete blocked');
select pg_temp.assert_true((select count(*) = 3 from public.comments), 'non-owner comment delete blocked');
select pg_temp.assert_true((select count(*) = 1 from public.activity_photos), 'non-owner photo delete blocked');
select pg_temp.assert_true((select count(*) = 1 from public.activity_participants), 'non-owner participant delete blocked');
reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.assert_true((select count(*) = 2 from public.activity_mentions), 'recipient reads mentions');
select pg_temp.assert_true((select not is_read from public.notifications), 'other notification unchanged');
reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
delete from public.activities where id = '20000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select count(*) = 0 from public.activity_participants), 'participant cascade');
select pg_temp.assert_true((select count(*) = 0 from public.activity_photos), 'photo cascade');
select pg_temp.assert_true((select count(*) = 0 from public.activity_mentions), 'mention cascade');
rollback;
