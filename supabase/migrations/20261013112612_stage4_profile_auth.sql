-- Stage 4 only. Apply after 001 and 002; existing migrations remain unchanged.
begin;

-- A small bounded array is appropriate for this fixed, seeded category catalog.
-- Store database slugs (board_games), never the Swift case name (boardGames).
alter table public.profiles add column interests text[] not null default '{}';
alter table public.profiles add constraint profiles_valid_interests check (
    cardinality(interests) <= 12 and array_position(interests, null) is null
    and interests <@ array['sports','games','food','drinks','movies','music',
                          'walking','creative','learning','board_games','party','other']::text[]
);

-- Keep email server-derived and informational. Clients still cannot insert/update email.
create function public.set_profile_auth_email()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
    if current_user = 'authenticated' then
        new.email = auth.jwt() ->> 'email';
    end if;
    return new;
end;
$$;
revoke all on function public.set_profile_auth_email() from public, anon, authenticated;
create trigger profiles_auth_email before insert on public.profiles
    for each row execute function public.set_profile_auth_email();

grant insert (id, display_name, department, job_title, interests) on public.profiles to authenticated;
grant update (interests) on public.profiles to authenticated;
create policy profiles_insert_own on public.profiles for insert to authenticated
    with check ((select auth.uid()) = id);
-- The existing UPDATE policy already has USING and WITH CHECK on auth.uid() = id.

-- One transaction: identity from auth.uid(), email from trigger, no caller-supplied UUID.
-- SECURITY INVOKER retains column grants and ownership RLS for every operation.
create function public.save_my_profile(
    p_display_name text,
    p_department text,
    p_job_title text,
    p_interests text[]
) returns setof public.profiles
language plpgsql security invoker set search_path = '' as $$
begin
    if auth.uid() is null then
        raise exception 'Authentication required' using errcode = '42501';
    end if;
    return query
    insert into public.profiles as p (id, display_name, department, job_title, interests)
    values (auth.uid(), btrim(p_display_name), nullif(btrim(p_department), ''),
            nullif(btrim(p_job_title), ''), coalesce(p_interests, '{}'::text[]))
    on conflict (id) do update set
        display_name = excluded.display_name,
        department = excluded.department,
        job_title = excluded.job_title,
        interests = excluded.interests
    returning p.*;
end;
$$;
revoke all on function public.save_my_profile(text,text,text,text[]) from public, anon;
grant execute on function public.save_my_profile(text,text,text,text[]) to authenticated;
commit;
