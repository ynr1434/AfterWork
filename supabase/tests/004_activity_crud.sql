-- Stage 5 ownership/CRUD verification. Run after all existing migrations in a
-- disposable Supabase database as postgres. No Stage 5 schema change is required.
begin;
create function pg_temp.assert_true(ok boolean, label text) returns void language plpgsql as $$ begin
    if ok is distinct from true then raise exception 'Assertion failed: %', label; end if;
end $$;
create function pg_temp.expect_error(statement text, expected_state text) returns void language plpgsql as $$ begin
    begin execute statement;
    exception when others then
        if sqlstate = expected_state then return; end if;
        raise exception 'Expected %, got %: %', expected_state, sqlstate, sqlerrm;
    end;
    raise exception 'Expected error % for %', expected_state, statement;
end $$;
insert into auth.users(id) values ('80000000-0000-0000-0000-000000000001'),('80000000-0000-0000-0000-000000000002');
insert into public.profiles(id,display_name) values ('80000000-0000-0000-0000-000000000001','Organizer'),('80000000-0000-0000-0000-000000000002','Other');
select set_config('request.jwt.claim.sub','80000000-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into public.activities(author_id, category_id,title,start_at,end_at,location_name,max_participants)
select auth.uid(),id,'Stage 5 disposable test',now()+interval '1 day',now()+interval '1 day 2 hours','Test Hall',12
from public.categories where slug='sports';
select pg_temp.assert_true((select count(*)=1 from public.activities where author_id=auth.uid()),'own create');
select pg_temp.assert_true((select count(*)=1 from public.activities a join public.profiles p on p.id=a.author_id join public.categories c on c.id=a.category_id where p.display_name='Organizer' and c.slug='sports'),'organizer/category joins');
select pg_temp.expect_error('insert into public.activities(author_id,category_id,title,start_at,location_name) select ''80000000-0000-0000-0000-000000000002'',id,''Spoof'',now(),''Hall'' from public.categories limit 1','42501');
select pg_temp.expect_error('update public.activities set author_id=''80000000-0000-0000-0000-000000000002'' where author_id=auth.uid()','42501');
select pg_temp.expect_error('update public.activities set max_participants=0 where author_id=auth.uid()','23514');
select pg_temp.expect_error('update public.activities set end_at=start_at where author_id=auth.uid()','23514');
update public.activities set title='Edited test', description='Edited', location_address='Test address',end_at=null,max_participants=null where author_id=auth.uid();
select pg_temp.assert_true((select title='Edited test' and end_at is null and max_participants is null from public.activities where author_id=auth.uid()),'own update and clearing fields');
insert into public.activity_participants(activity_id,user_id,status) select id,auth.uid(),'interested' from public.activities where author_id=auth.uid();
select pg_temp.assert_true((select count(*)=0 from public.activity_participants where status='going'),'interested is not going');
update public.activity_participants set status='going' where user_id=auth.uid();
select pg_temp.assert_true((select count(*)=1 from public.activity_participants where status='going'),'going count');
update public.activity_participants set status='declined' where user_id=auth.uid();
select pg_temp.assert_true((select count(*)=0 from public.activity_participants where status='going'),'declined is not going');
reset role;
select set_config('request.jwt.claim.sub','80000000-0000-0000-0000-000000000002',true);
set local role authenticated;
update public.activities set title='Forbidden' where author_id<>auth.uid();
delete from public.activities where author_id<>auth.uid();
select pg_temp.assert_true((select count(*)=1 from public.activities where title='Edited test'),'other user update/delete blocked');
reset role;
set local role anon;
select pg_temp.expect_error('select * from public.activities','42501');
select pg_temp.expect_error('delete from public.activities','42501');
reset role;
select set_config('request.jwt.claim.sub','80000000-0000-0000-0000-000000000001',true);
set local role authenticated;
delete from public.activities where author_id=auth.uid();
select pg_temp.assert_true((select count(*)=0 from public.activities where author_id=auth.uid()),'own delete');
select pg_temp.assert_true((select count(*)=0 from public.activity_participants where user_id=auth.uid()),'test attendance cascade');
reset role;
select pg_temp.assert_true((select relrowsecurity from pg_class where oid='public.activities'::regclass),'RLS enabled');
rollback;
