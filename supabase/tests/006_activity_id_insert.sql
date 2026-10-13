-- Verify client-supplied activity IDs do not weaken activity ownership or the
-- Stage 6 organizer attendance trigger. Run after all migrations.
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
('91000000-0000-0000-0000-000000000001'), ('91000000-0000-0000-0000-000000000002');
insert into public.profiles(id, display_name) values
('91000000-0000-0000-0000-000000000001', 'ID Grant Organizer'),
('91000000-0000-0000-0000-000000000002', 'Other User');
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
set local role authenticated;

insert into public.activities(id, author_id, category_id, title, start_at, location_name)
select '92000000-0000-0000-0000-000000000001', auth.uid(), id,
       'Client ID disposable activity', now() + interval '1 day', 'Test Hall'
from public.categories limit 1;
select pg_temp.assert_true(
    (select count(*) = 1 from public.activities
     where id = '92000000-0000-0000-0000-000000000001'
       and author_id = auth.uid()),
    'client supplied activity id is accepted');
select pg_temp.assert_true(
    (select count(*) = 1 from public.activity_participants
     where activity_id = '92000000-0000-0000-0000-000000000001'
       and user_id = auth.uid() and status = 'going'),
    'organizer trigger inserts going participant');

select pg_temp.expect_error(
    'insert into public.activities(id, author_id, category_id, title, start_at, location_name)
      select ''92000000-0000-0000-0000-000000000002'',
             ''91000000-0000-0000-0000-000000000002'', id,
             ''Spoof disposable activity'', now() + interval ''1 day'', ''Test Hall''
      from public.categories limit 1',
    '42501');
select pg_temp.assert_true(
    (select relrowsecurity from pg_class where oid = 'public.activities'::regclass),
    'activities RLS remains enabled');
select pg_temp.assert_true(
    not (select p.prosecdef from pg_proc p
         join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'ensure_activity_organizer_going'),
    'organizer trigger remains security invoker');

reset role;
rollback;
