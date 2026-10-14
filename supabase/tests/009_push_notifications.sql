-- Run as postgres in a disposable Supabase test database after Stage 10. Rolls back.
begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$ begin
    if ok is distinct from true then raise exception 'Assertion failed: %',label; end if;
end $$;
create function pg_temp.expect_error(statement text,expected_state text) returns void language plpgsql as $$ begin
    begin execute statement;
    exception when others then
        if sqlstate=expected_state then return; end if;
        raise exception 'Expected %, got %: %',expected_state,sqlstate,sqlerrm;
    end;
    raise exception 'Expected error % for %',expected_state,statement;
end $$;
insert into auth.users(id) values('a0000000-0000-0000-0000-000000000001'),('a0000000-0000-0000-0000-000000000002');
insert into auth.sessions(id,user_id) values
('a1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001'),
('a1000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002');
insert into public.profiles(id,display_name) values
('a0000000-0000-0000-0000-000000000001','Recipient'),('a0000000-0000-0000-0000-000000000002','Actor');
insert into public.activities(id,author_id,category_id,title,start_at,location_name)
select 'a2000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',id,'Push test',now()+interval '1 day','Hall'
from public.categories where slug='sports';
insert into public.notifications(id,user_id,type,title,body,activity_id,actor_user_id) values
('a3000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','mention','Mention','Open',
'a2000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000002');
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"a0000000-0000-0000-0000-000000000001","session_id":"a1000000-0000-0000-0000-000000000001"}',true);
set local role authenticated;
select public.register_push_device('a4000000-0000-0000-0000-000000000001',repeat('a',64),repeat('aa',32),'sandbox');
select public.register_push_device('a4000000-0000-0000-0000-000000000001',repeat('a',64),repeat('aa',32),'sandbox');
select public.register_push_device('a4000000-0000-0000-0000-000000000002',repeat('b',64),repeat('bb',32),'production');
select pg_temp.assert_true((select count(*)=2 from public.push_device_tokens),'idempotent and multiple devices');
select pg_temp.expect_error('select device_token from public.push_device_tokens','42501');
select pg_temp.expect_error('select installation_secret_hash from public.push_device_tokens','42501');
select pg_temp.expect_error('insert into public.push_device_tokens(user_id,session_id,installation_id,installation_secret_hash,device_token,environment) values (auth.uid(),''a1000000-0000-0000-0000-000000000001'',''a4000000-0000-0000-0000-000000000004'',decode(''aa'',''hex''),repeat(''dd'',32),''sandbox'')','42501');
select pg_temp.expect_error('update public.push_device_tokens set user_id=''a0000000-0000-0000-0000-000000000002''','42501');
select pg_temp.expect_error('delete from public.push_device_tokens','42501');
select pg_temp.expect_error('select * from public.push_recipient_devices(''a3000000-0000-0000-0000-000000000001'')','42501');
select pg_temp.expect_error('select * from public.push_deliveries','42501');
select pg_temp.expect_error('select public.register_push_device(''a4000000-0000-0000-0000-000000000003'',repeat(''c'',64),repeat(''aa'',32),''sandbox'')','23505');
select pg_temp.expect_error('select public.register_push_device(''a4000000-0000-0000-0000-000000000001'',repeat(''c'',64),repeat(''cc'',32),''sandbox'')','42501');
select pg_temp.expect_error('select public.register_push_device(''a4000000-0000-0000-0000-000000000001'',repeat(''a'',64),repeat(''cc'',32),''unknown'')','23514');
select public.register_push_device('a4000000-0000-0000-0000-000000000001',repeat('a',64),repeat('cc',32),'sandbox');
reset role;
select pg_temp.assert_true((select count(*)=0 from public.push_device_tokens where device_token=repeat('aa',32)),'token rotation replaces old token');
set local role service_role;
select pg_temp.assert_true((select count(*)=2 from public.push_recipient_devices('a3000000-0000-0000-0000-000000000001')),'server recipient lookup includes both environments');
select pg_temp.assert_true((select public.claim_push_delivery('a3000000-0000-0000-0000-000000000001',id,version) is not null
from public.push_device_tokens where installation_id='a4000000-0000-0000-0000-000000000001'),'first claim');
select pg_temp.assert_true((select public.claim_push_delivery('a3000000-0000-0000-0000-000000000001',id,version) is null
from public.push_device_tokens where installation_id='a4000000-0000-0000-0000-000000000001'),'active lease dedup');
update public.push_deliveries set status='sent';
select pg_temp.assert_true((select public.claim_push_delivery('a3000000-0000-0000-0000-000000000001',id,version) is null
from public.push_device_tokens where installation_id='a4000000-0000-0000-0000-000000000001'),'accepted delivery not replayed');
update public.push_deliveries set status='retry',lease_until=now()-interval '1 second';
select pg_temp.assert_true((select public.claim_push_delivery('a3000000-0000-0000-0000-000000000001',id,version) is not null
from public.push_device_tokens where installation_id='a4000000-0000-0000-0000-000000000001'),'transient failure can retry');
update public.push_deliveries set status='retry',attempts=3,lease_until=now()-interval '1 second';
select pg_temp.assert_true((select public.claim_push_delivery('a3000000-0000-0000-0000-000000000001',id,version) is null
from public.push_device_tokens where installation_id='a4000000-0000-0000-0000-000000000001'),'retry bounded');
update public.push_deliveries set status='sent';
reset role;
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"a0000000-0000-0000-0000-000000000002","session_id":"a1000000-0000-0000-0000-000000000002"}',true);
set local role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.push_device_tokens),'cross-user row isolation');
select pg_temp.expect_error('select public.unregister_push_device(''a4000000-0000-0000-0000-000000000001'',repeat(''c'',64))','42501');
-- Same installation may transfer only when its Keychain-held proof matches.
select public.register_push_device('a4000000-0000-0000-0000-000000000001',repeat('a',64),repeat('cc',32),'sandbox');
select pg_temp.assert_true((select count(*)=1 from public.push_device_tokens),'proven installation transferred');
reset role;
set local role service_role;
select pg_temp.assert_true((select count(*)=1 from public.push_recipient_devices('a3000000-0000-0000-0000-000000000001')),'previous account cannot push to transferred device');
reset role;
update auth.sessions set not_after=now()-interval '1 second' where id='a1000000-0000-0000-0000-000000000001';
set local role service_role;
select pg_temp.assert_true((select count(*)=0 from public.push_recipient_devices('a3000000-0000-0000-0000-000000000001')),'expired auth sessions excluded');
reset role;
set local role authenticated;
select public.unregister_push_device('a4000000-0000-0000-0000-000000000001',repeat('a',64));
reset role;
select pg_temp.assert_true((select count(*)=1 from public.push_device_tokens),'logout removes only current installation');
select pg_temp.assert_true((select count(*)=1 and bool_and(device_id is null) from public.push_deliveries),'delivery history survives token removal');
update auth.sessions set not_after=null where id='a1000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"a0000000-0000-0000-0000-000000000001","session_id":"a1000000-0000-0000-0000-000000000001"}',true);
set local role authenticated;
select public.register_push_device('a4000000-0000-0000-0000-000000000001',repeat('a',64),repeat('cc',32),'sandbox');
reset role;
set local role service_role;
select pg_temp.assert_true((select public.claim_push_delivery('a3000000-0000-0000-0000-000000000001',id,version) is null
from public.push_device_tokens where installation_id='a4000000-0000-0000-0000-000000000001'),'logout/re-login does not replay accepted delivery');
reset role;
update public.notifications set is_read=true where id='a3000000-0000-0000-0000-000000000001';
set local role service_role;
select pg_temp.assert_true((select count(*)=0 from public.push_recipient_devices('a3000000-0000-0000-0000-000000000001')),'read notification not pushed');
reset role;
set local role anon;
select pg_temp.expect_error('select * from public.push_device_tokens','42501');
select pg_temp.expect_error('select public.register_push_device(''a4000000-0000-0000-0000-000000000001'',repeat(''a'',64),repeat(''cc'',32),''sandbox'')','42501');
reset role;
delete from auth.sessions where id='a1000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select count(*)=0 from public.push_device_tokens),'session revocation cascades orphan token cleanup');
select pg_temp.assert_true((select relrowsecurity from pg_class where oid='public.push_device_tokens'::regclass),'token RLS enabled');
select pg_temp.assert_true((select relrowsecurity from pg_class where oid='public.push_deliveries'::regclass),'delivery RLS enabled');
rollback;
