-- Run as postgres in an isolated Supabase test project after all migrations.
-- Fixtures roll back. This also runs in the documented PGlite harness.
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
('40000000-0000-0000-0000-000000000001'), ('40000000-0000-0000-0000-000000000002');
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"40000000-0000-0000-0000-000000000001","email":"owner@example.invalid"}', true);
set local role authenticated;
select * from public.save_my_profile(' Owner ', 'Engineering', null, array['sports','board_games']);
select pg_temp.assert_true((select count(*) = 1 from public.profiles where id = auth.uid()), 'own profile created');
select pg_temp.assert_true((select email = 'owner@example.invalid' and display_name = 'Owner' and interests = array['sports','board_games'] from public.profiles where id = auth.uid()), 'email and interests persisted');
select * from public.save_my_profile('Edited', null, 'Engineer', array['food']);
select * from public.save_my_profile('Edited', null, 'Engineer', array['food']);
select pg_temp.assert_true((select count(*) = 1 from public.profiles where id = auth.uid()), 'idempotent upsert');
select pg_temp.assert_true((select department is null and job_title = 'Engineer' and interests = array['food'] from public.profiles where id = auth.uid()), 'atomic editing and clearing fields');
select pg_temp.expect_error('select * from public.save_my_profile('' '',null,null,array[]::text[])', '23514');
select pg_temp.expect_error('select * from public.save_my_profile(''Bad'',null,null,array[''boardGames''])', '23514');
select pg_temp.expect_error('select * from public.save_my_profile(''Bad'',null,null,array[null]::text[])', '23514');
select pg_temp.assert_true((select display_name = 'Edited' and interests = array['food'] from public.profiles where id = auth.uid()), 'failed save rolls back entire update');
select pg_temp.expect_error('insert into public.profiles(id,display_name,interests) values (''40000000-0000-0000-0000-000000000002'',''Spoofed'',array[''sports''])', '42501');
select pg_temp.expect_error('update public.profiles set id = ''40000000-0000-0000-0000-000000000002''', '42501');
select pg_temp.expect_error('update public.profiles set email = ''spoofed@example.invalid''', '42501');
reset role;
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"40000000-0000-0000-0000-000000000002"}', true);
set local role authenticated;
select * from public.save_my_profile('Second',null,null,array[]::text[]);
select pg_temp.assert_true((select email is null and interests = '{}'::text[] from public.profiles where id = auth.uid()), 'missing email and optional interests');
update public.profiles set interests = array['party'], display_name = 'Forbidden'
where id = '40000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select display_name = 'Edited' and interests = array['food'] from public.profiles where id = '40000000-0000-0000-0000-000000000001'), 'other user interests and profile protected');
reset role;
set local role anon;
select pg_temp.expect_error('select * from public.save_my_profile(''Anon'',null,null,array[]::text[])', '42501');
select pg_temp.expect_error('select interests from public.profiles', '42501');
reset role;
select pg_temp.assert_true((select prosecdef = false from pg_proc where oid = 'public.save_my_profile(text,text,text,text[])'::regprocedure), 'RPC respects RLS');
select pg_temp.assert_true((select relrowsecurity from pg_class where oid = 'public.profiles'::regclass), 'RLS stays enabled');
rollback;
