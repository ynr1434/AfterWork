-- Run after migrations 001 and 002 in a development project as postgres.
begin;
set local role anon;
do $$
declare row_count integer;
begin
    select count(*) into row_count from public.categories;
    if row_count <> 12 then raise exception 'Expected 12 seeded categories, got %', row_count; end if;
end $$;
-- Catalog remains read-only; every private table remains inaccessible.
do $$
declare table_name text;
begin
    begin
        insert into public.categories(slug, name, sf_symbol) values ('forbidden', 'Forbidden', 'xmark');
        raise exception 'Anonymous category insert was allowed';
    exception when insufficient_privilege then null;
    end;
    begin
        update public.categories set name = 'Forbidden';
        raise exception 'Anonymous category update was allowed';
    exception when insufficient_privilege then null;
    end;
    begin
        delete from public.categories;
        raise exception 'Anonymous category delete was allowed';
    exception when insufficient_privilege then null;
    end;
    foreach table_name in array array['profiles', 'activities', 'activity_participants', 'comments', 'activity_photos', 'activity_mentions', 'notifications'] loop
        begin
            execute format('select * from public.%I', table_name);
            raise exception 'Anonymous read was allowed on %', table_name;
        exception when insufficient_privilege then null;
        end;
    end loop;
end $$;
rollback;
