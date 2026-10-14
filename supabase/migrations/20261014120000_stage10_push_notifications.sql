-- Generated with `supabase migration new stage10_push_notifications`, then ordered
-- after the repository's pre-dated Stage 9 migration. No webhook secrets/deployment.
begin;
create table public.push_device_tokens (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    session_id uuid not null references auth.sessions(id) on delete cascade,
    installation_id uuid not null unique,
    installation_secret_hash bytea not null,
    device_token text not null check (device_token ~ '^[0-9a-f]+$' and length(device_token) between 2 and 512 and length(device_token) % 2 = 0),
    environment text not null check (environment in ('sandbox','production')),
    platform text not null default 'ios' check (platform = 'ios'),
    version uuid not null default gen_random_uuid(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    last_seen_at timestamptz not null default now(),
    unique (device_token, environment)
);
create index push_tokens_recipient on public.push_device_tokens(user_id);
create index push_tokens_session on public.push_device_tokens(session_id);
alter table public.push_device_tokens enable row level security;
revoke all on public.push_device_tokens from public, anon, authenticated;
-- Secrets/hashes/tokens are not included in any profile response or cross-user SELECT.
grant select (id,user_id,installation_id,environment,platform,created_at,updated_at,last_seen_at)
    on public.push_device_tokens to authenticated;
create policy push_tokens_read_own on public.push_device_tokens for select to authenticated
    using (user_id = (select auth.uid()));
-- All writes go through the narrow functions below; direct reassignment is forbidden.
grant all on public.push_device_tokens to service_role;

create function public.register_push_device(p_installation_id uuid, p_installation_secret text,
    p_device_token text, p_environment text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
    caller uuid := auth.uid();
    caller_session uuid := nullif(auth.jwt()->>'session_id','')::uuid;
    result uuid;
    hashed bytea;
begin
    if caller is null or caller_session is null or not exists (
        select 1 from auth.sessions s where s.id = caller_session and s.user_id = caller
            and (s.not_after is null or s.not_after > now())
    ) then raise exception 'Authentication required' using errcode='42501'; end if;
    if p_installation_id is null or p_installation_secret is null or
       p_installation_secret !~ '^[0-9a-f]{64}$' then
        raise exception 'Invalid installation' using errcode='22023';
    end if;
    hashed := sha256(convert_to(p_installation_secret,'UTF8'));
    -- Serializes first registration/account transfers on one installation.
    perform pg_advisory_xact_lock(hashtextextended(p_installation_id::text, 10));
    if exists (select 1 from public.push_device_tokens t where t.installation_id=p_installation_id
        and t.installation_secret_hash <> hashed) then
        raise exception 'Installation proof required' using errcode='42501';
    end if;
    insert into public.push_device_tokens as t
        (user_id,session_id,installation_id,installation_secret_hash,device_token,environment)
    values (caller,caller_session,p_installation_id,hashed,p_device_token,p_environment)
    on conflict (installation_id) do update set
        user_id=excluded.user_id, session_id=excluded.session_id,
        device_token=excluded.device_token, environment=excluded.environment,
        version=case when (t.user_id,t.session_id,t.device_token,t.environment)
            is distinct from (excluded.user_id,excluded.session_id,excluded.device_token,excluded.environment)
            then gen_random_uuid() else t.version end,
        updated_at=now(), last_seen_at=now()
    returning id into result;
    return result;
end;
$$;
revoke all on function public.register_push_device(uuid,text,text,text) from public, anon;
grant execute on function public.register_push_device(uuid,text,text,text) to authenticated;

create function public.unregister_push_device(p_installation_id uuid,p_installation_secret text) returns void
language plpgsql security definer set search_path = '' as $$
begin
    if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
    delete from public.push_device_tokens t where t.installation_id=p_installation_id
        and t.installation_secret_hash=sha256(convert_to(p_installation_secret,'UTF8'));
    if exists(select 1 from public.push_device_tokens t where t.installation_id=p_installation_id) then
        raise exception 'Installation proof required' using errcode='42501';
    end if;
end;
$$;
revoke all on function public.unregister_push_device(uuid,text) from public, anon;
grant execute on function public.unregister_push_device(uuid,text) to authenticated;

create table public.push_deliveries (
    notification_id uuid not null references public.notifications(id) on delete cascade,
    installation_id uuid not null,
    device_id uuid references public.push_device_tokens(id) on delete set null,
    registration_version uuid not null,
    attempt_id uuid not null,
    status text not null check (status in ('sending','sent','retry','failed')),
    attempts integer not null default 1 check (attempts between 1 and 3),
    lease_until timestamptz not null,
    apns_status integer,
    reason text,
    updated_at timestamptz not null default now(),
    primary key(notification_id,installation_id)
);
create index push_delivery_device on public.push_deliveries(device_id);
alter table public.push_deliveries enable row level security;
revoke all on public.push_deliveries from public,anon,authenticated;
grant all on public.push_deliveries to service_role;

-- Server-only lookup: revoked/expired sessions and dormant installations are excluded.
create function public.push_recipient_devices(p_notification_id uuid)
returns table(id uuid,user_id uuid,device_token text,environment text,version uuid,last_seen_at timestamptz)
language sql security definer set search_path = '' as $$
    select t.id,t.user_id,t.device_token,t.environment,t.version,t.last_seen_at
    from public.push_device_tokens t join auth.sessions s on s.id=t.session_id and s.user_id=t.user_id
    join public.notifications n on n.user_id=t.user_id
    where n.id=p_notification_id and n.type in ('mention','activityComment') and not n.is_read
        and n.activity_id is not null and n.actor_user_id is distinct from n.user_id
        and (s.not_after is null or s.not_after>now()) and t.last_seen_at>now()-interval '30 days';
$$;
revoke all on function public.push_recipient_devices(uuid) from public,anon,authenticated;
grant execute on function public.push_recipient_devices(uuid) to service_role;

-- Atomic per-notification/installation claim; accepted delivery history survives logout. Lease permits bounded manual/webhook retries;
-- it is not an exactly-once delivery guarantee if a worker crashes after APNs accepts.
create function public.claim_push_delivery(p_notification_id uuid,p_device_id uuid,p_version uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare attempt uuid := gen_random_uuid(); result uuid; installation uuid;
begin
    if not exists(select 1 from public.push_recipient_devices(p_notification_id) d
                  where d.id=p_device_id and d.version=p_version) then return null; end if;
    select t.installation_id into installation from public.push_device_tokens t where t.id=p_device_id;
    insert into public.push_deliveries as d
        (notification_id,installation_id,device_id,registration_version,attempt_id,status,lease_until)
    values(p_notification_id,installation,p_device_id,p_version,attempt,'sending',now()+interval '60 seconds')
    on conflict(notification_id,installation_id) do update set
        device_id=excluded.device_id, attempt_id=excluded.attempt_id, registration_version=excluded.registration_version,
        status='sending',attempts=d.attempts+1,lease_until=excluded.lease_until,updated_at=now()
    where d.attempts<3 and d.registration_version=excluded.registration_version
        and ((d.status='retry' and d.lease_until<now()) or (d.status='sending' and d.lease_until<now()))
    returning attempt_id into result;
    return result;
end;
$$;
revoke all on function public.claim_push_delivery(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.claim_push_delivery(uuid,uuid,uuid) to service_role;
commit;
