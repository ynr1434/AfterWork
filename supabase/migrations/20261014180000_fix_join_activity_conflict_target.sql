-- The RETURNS TABLE output column activity_id conflicts with the unqualified
-- ON CONFLICT column list in the prior join_activity definition.
begin;

create or replace function public.join_activity(p_activity_id uuid)
returns table (activity_id uuid, participant_count bigint)
language plpgsql security invoker set search_path = '' as $$
declare
    activity_capacity integer;
    current_count bigint;
    current_status text;
begin
    if (select auth.uid()) is null then
        raise exception 'Authentication required' using errcode = '42501';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('afterwork.join_activity:' || p_activity_id::text, 0)
    );

    select a.max_participants into activity_capacity
    from public.activities a
    where a.id = p_activity_id;
    if not found then
        raise exception 'Activity not found' using errcode = 'P0002';
    end if;

    select p.status into current_status
    from public.activity_participants p
    where p.activity_id = p_activity_id and p.user_id = (select auth.uid());

    if current_status = 'going' then
        select count(*) into current_count
        from public.activity_participants p
        where p.activity_id = p_activity_id and p.status = 'going';
        return query select p_activity_id, current_count;
        return;
    end if;

    select count(*) into current_count
    from public.activity_participants p
    where p.activity_id = p_activity_id and p.status = 'going';
    if activity_capacity is not null and current_count >= activity_capacity then
        raise exception 'This activity is full.' using errcode = 'P0001';
    end if;

    insert into public.activity_participants (activity_id, user_id, status)
    values (p_activity_id, (select auth.uid()), 'going')
    on conflict on constraint activity_participants_activity_id_user_id_key
    do update set status = 'going';

    select count(*) into current_count
    from public.activity_participants p
    where p.activity_id = p_activity_id and p.status = 'going';
    return query select p_activity_id, current_count;
end;
$$;

commit;
