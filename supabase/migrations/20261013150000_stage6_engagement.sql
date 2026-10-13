-- Stage 6 engagement state. Apply after the existing Stage 4 migration.
begin;

create table public.activity_user_actions (
    id uuid primary key default gen_random_uuid(),
    activity_id uuid not null references public.activities(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    is_saved boolean not null default false,
    is_skipped boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (activity_id, user_id)
);

create index activity_user_actions_user_idx
    on public.activity_user_actions (user_id, updated_at desc);

alter table public.activity_user_actions enable row level security;
revoke all on public.activity_user_actions from public, anon, authenticated;
grant select, insert, update, delete on public.activity_user_actions to authenticated;

create policy activity_user_actions_read_own on public.activity_user_actions
    for select to authenticated using ((select auth.uid()) = user_id);
create policy activity_user_actions_insert_own on public.activity_user_actions
    for insert to authenticated with check ((select auth.uid()) = user_id);
create policy activity_user_actions_update_own on public.activity_user_actions
    for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);
create policy activity_user_actions_delete_own on public.activity_user_actions
    for delete to authenticated using ((select auth.uid()) = user_id);

create trigger activity_user_actions_updated_at before update
    on public.activity_user_actions for each row execute function public.set_updated_at();

-- Every organizer is an attendee. The trigger is invoker-security and can only
-- insert a participant when the authenticated caller owns the new activity.
create function public.ensure_activity_organizer_going()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
    if (select auth.uid()) = new.author_id then
        insert into public.activity_participants (activity_id, user_id, status)
        values (new.id, new.author_id, 'going')
        on conflict (activity_id, user_id) do update set status = 'going';
    end if;
    return new;
end;
$$;
revoke all on function public.ensure_activity_organizer_going() from public, anon;
grant execute on function public.ensure_activity_organizer_going() to authenticated;

create trigger activities_organizer_going after insert on public.activities
    for each row execute function public.ensure_activity_organizer_going();

-- The row lock makes the capacity check and participant transition atomic.
create function public.join_activity(p_activity_id uuid)
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

    select a.max_participants into activity_capacity
    from public.activities a
    where a.id = p_activity_id
    for update;
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
    on conflict (activity_id, user_id) do update set status = 'going';

    select count(*) into current_count
    from public.activity_participants p
    where p.activity_id = p_activity_id and p.status = 'going';
    return query select p_activity_id, current_count;
end;
$$;
revoke all on function public.join_activity(uuid) from public, anon;
grant execute on function public.join_activity(uuid) to authenticated;

commit;
