-- Stage 6 engagement checks. Run after all migrations in a disposable project.
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

insert into auth.users(id) values
('90000000-0000-0000-0000-000000000001'), ('90000000-0000-0000-0000-000000000002');
insert into public.profiles(id, display_name) values
('90000000-0000-0000-0000-000000000001', 'Organizer'),
('90000000-0000-0000-0000-000000000002', 'Guest');
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into public.activities(author_id, category_id, title, start_at, location_name, max_participants)
select auth.uid(), id, 'Stage 6 disposable activity', now() + interval '1 day', 'Test Hall', 1
from public.categories limit 1;
select pg_temp.assert_true((select count(*) = 1 from public.activity_participants
    where activity_id = (select id from public.activities where title = 'Stage 6 disposable activity')
      and user_id = auth.uid() and status = 'going'), 'organizer is going');
select * from public.join_activity((select id from public.activities where title = 'Stage 6 disposable activity'));
select pg_temp.assert_true((select count(*) = 1 from public.activity_participants
    where status = 'going'), 'joining twice is idempotent');
insert into public.activity_user_actions(activity_id, user_id, is_saved)
select id, auth.uid(), true from public.activities where title = 'Stage 6 disposable activity';
update public.activity_user_actions set is_skipped = true where user_id = auth.uid();
select pg_temp.assert_true((select is_saved and is_skipped from public.activity_user_actions where user_id = auth.uid()), 'own save/skip state');
reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.expect_error('update public.activity_user_actions set is_saved = false', '42501');
select pg_temp.expect_error('select * from public.join_activity((select id from public.activities where title = ''Stage 6 disposable activity''))', 'P0001');
select pg_temp.assert_true((select relrowsecurity from pg_class where oid = 'public.activity_user_actions'::regclass), 'engagement RLS enabled');
rollback;
