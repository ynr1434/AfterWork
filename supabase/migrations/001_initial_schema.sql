-- Apply once to a fresh Supabase project. No remote changes are made by the app.
begin;

create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    email text,
    display_name text not null check (length(btrim(display_name)) between 1 and 100),
    avatar_url text,
    department text,
    job_title text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.categories (
    id uuid primary key default gen_random_uuid(),
    slug text not null unique,
    name text not null,
    sf_symbol text not null,
    created_at timestamptz not null default now()
);

create table public.activities (
    id uuid primary key default gen_random_uuid(),
    author_id uuid not null references public.profiles(id) on delete cascade,
    category_id uuid not null references public.categories(id) on delete restrict,
    title text not null check (length(btrim(title)) between 1 and 160),
    description text not null default '' check (length(description) <= 10000),
    start_at timestamptz not null,
    end_at timestamptz,
    location_name text not null check (length(btrim(location_name)) between 1 and 200),
    location_address text,
    latitude double precision check (latitude between -90 and 90),
    longitude double precision check (longitude between -180 and 180),
    max_participants integer check (max_participants > 0),
    cover_image_url text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint valid_activity_dates check (end_at is null or end_at > start_at),
    constraint coordinate_pair check ((latitude is null) = (longitude is null))
);

create table public.activity_participants (
    id uuid primary key default gen_random_uuid(),
    activity_id uuid not null references public.activities(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    status text not null check (status in ('interested', 'going', 'declined')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (activity_id, user_id)
);

create table public.comments (
    id uuid primary key default gen_random_uuid(),
    activity_id uuid not null references public.activities(id) on delete cascade,
    author_id uuid not null references public.profiles(id) on delete cascade,
    body text not null check (length(btrim(body)) between 1 and 5000),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (id, activity_id) -- Target of the mention's composite foreign key.
);

create table public.activity_photos (
    id uuid primary key default gen_random_uuid(),
    activity_id uuid not null references public.activities(id) on delete cascade,
    uploader_id uuid not null references public.profiles(id) on delete cascade,
    storage_path text not null check (length(btrim(storage_path)) > 0),
    created_at timestamptz not null default now()
);

create table public.activity_mentions (
    id uuid primary key default gen_random_uuid(),
    activity_id uuid not null references public.activities(id) on delete cascade,
    comment_id uuid,
    mentioned_user_id uuid not null references public.profiles(id) on delete cascade,
    mentioned_by_user_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    -- A comment mention must belong to the same activity, never an unrelated one.
    foreign key (comment_id, activity_id) references public.comments(id, activity_id) on delete cascade
);
create unique index activity_mentions_activity_unique
    on public.activity_mentions (activity_id, mentioned_user_id) where comment_id is null;
create unique index activity_mentions_comment_unique
    on public.activity_mentions (comment_id, mentioned_user_id) where comment_id is not null;

create table public.notifications (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    type text not null check (length(btrim(type)) > 0),
    title text not null check (length(btrim(title)) > 0),
    body text not null default '',
    activity_id uuid references public.activities(id) on delete set null,
    actor_user_id uuid references public.profiles(id) on delete set null,
    is_read boolean not null default false,
    created_at timestamptz not null default now()
);

create index activities_start_at_idx on public.activities (start_at);
create index activities_category_idx on public.activities (category_id, start_at);
create index activities_author_idx on public.activities (author_id);
-- The unique (activity_id, user_id) index already supports activity participant lookups.
create index participants_user_idx on public.activity_participants (user_id);
create index comments_activity_idx on public.comments (activity_id, created_at);
create index comments_author_idx on public.comments (author_id);
create index photos_activity_idx on public.activity_photos (activity_id);
create index photos_uploader_idx on public.activity_photos (uploader_id);
create index mentions_recipient_idx on public.activity_mentions (mentioned_user_id);
create index mentions_sender_idx on public.activity_mentions (mentioned_by_user_id);
create index notifications_user_created_idx on public.notifications (user_id, created_at desc);
create index notifications_activity_idx on public.notifications (activity_id);
create index notifications_actor_idx on public.notifications (actor_user_id);

create function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
    new.updated_at = now();
    return new;
end;
$$;
revoke all on function public.set_updated_at() from public, anon, authenticated;

create trigger profiles_updated_at before update on public.profiles
    for each row execute function public.set_updated_at();
create trigger activities_updated_at before update on public.activities
    for each row execute function public.set_updated_at();
create trigger participants_updated_at before update on public.activity_participants
    for each row execute function public.set_updated_at();
create trigger comments_updated_at before update on public.comments
    for each row execute function public.set_updated_at();

insert into public.categories (slug, name, sf_symbol) values
    ('sports', 'Sports', 'figure.volleyball'),
    ('games', 'Games', 'gamecontroller.fill'),
    ('food', 'Food', 'fork.knife'),
    ('drinks', 'Drinks', 'cup.and.saucer.fill'),
    ('movies', 'Movies', 'film.fill'),
    ('music', 'Music', 'music.note'),
    ('walking', 'Walking', 'figure.walk'),
    ('creative', 'Creative', 'paintpalette.fill'),
    ('learning', 'Learning', 'book.fill'),
    ('board_games', 'Board Games', 'dice.fill'),
    ('party', 'Party', 'party.popper.fill'),
    ('other', 'Other', 'sparkles');

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.activities enable row level security;
alter table public.activity_participants enable row level security;
alter table public.comments enable row level security;
alter table public.activity_photos enable row level security;
alter table public.activity_mentions enable row level security;
alter table public.notifications enable row level security;

-- Remove Supabase default grants; grant only the required operations/columns.
revoke all on public.profiles, public.categories, public.activities,
    public.activity_participants, public.comments, public.activity_photos,
    public.activity_mentions, public.notifications from public, anon, authenticated;
grant usage on schema public to authenticated;
grant select on public.profiles, public.categories, public.activities,
    public.activity_participants, public.comments, public.activity_photos,
    public.activity_mentions, public.notifications to authenticated;
-- Profiles are provisioned by trusted server code in a future Auth stage.
-- Email is informational, server-managed, and never an authorization signal.
grant update (display_name, avatar_url, department, job_title) on public.profiles to authenticated;
grant insert (author_id, category_id, title, description, start_at, end_at,
    location_name, location_address, latitude, longitude, max_participants, cover_image_url)
    on public.activities to authenticated;
grant update (category_id, title, description, start_at, end_at, location_name,
    location_address, latitude, longitude, max_participants, cover_image_url)
    on public.activities to authenticated;
grant delete on public.activities to authenticated;
grant insert (activity_id, user_id, status) on public.activity_participants to authenticated;
grant update (status) on public.activity_participants to authenticated;
grant delete on public.activity_participants to authenticated;
grant insert (activity_id, author_id, body) on public.comments to authenticated;
grant update (body) on public.comments to authenticated;
grant delete on public.comments to authenticated;
grant insert (activity_id, uploader_id, storage_path) on public.activity_photos to authenticated;
grant delete on public.activity_photos to authenticated;
grant insert (activity_id, comment_id, mentioned_user_id, mentioned_by_user_id)
    on public.activity_mentions to authenticated;
grant delete on public.activity_mentions to authenticated;
grant update (is_read) on public.notifications to authenticated;
grant all on public.profiles, public.categories, public.activities,
    public.activity_participants, public.comments, public.activity_photos,
    public.activity_mentions, public.notifications to service_role;

create policy profiles_read on public.profiles for select to authenticated using (true);
create policy profiles_update_own on public.profiles for update to authenticated
    using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy categories_read on public.categories for select to authenticated using (true);
create policy activities_read on public.activities for select to authenticated using (true);
create policy activities_insert_own on public.activities for insert to authenticated
    with check ((select auth.uid()) = author_id);
create policy activities_update_own on public.activities for update to authenticated
    using ((select auth.uid()) = author_id) with check ((select auth.uid()) = author_id);
create policy activities_delete_own on public.activities for delete to authenticated
    using ((select auth.uid()) = author_id);
create policy participants_read on public.activity_participants for select to authenticated using (true);
create policy participants_insert_own on public.activity_participants for insert to authenticated
    with check ((select auth.uid()) = user_id);
create policy participants_update_own on public.activity_participants for update to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy participants_delete_own on public.activity_participants for delete to authenticated
    using ((select auth.uid()) = user_id);
create policy comments_read on public.comments for select to authenticated using (true);
create policy comments_insert_own on public.comments for insert to authenticated
    with check ((select auth.uid()) = author_id);
create policy comments_update_own on public.comments for update to authenticated
    using ((select auth.uid()) = author_id) with check ((select auth.uid()) = author_id);
create policy comments_delete_own on public.comments for delete to authenticated
    using ((select auth.uid()) = author_id);
create policy photos_read on public.activity_photos for select to authenticated using (true);
create policy photos_insert_own on public.activity_photos for insert to authenticated
    with check ((select auth.uid()) = uploader_id
        and split_part(storage_path, '/', 1) = (select auth.uid())::text);
create policy photos_delete_own on public.activity_photos for delete to authenticated
    using ((select auth.uid()) = uploader_id);

create policy mentions_read_relevant on public.activity_mentions for select to authenticated
    using ((select auth.uid()) = mentioned_user_id or (select auth.uid()) = mentioned_by_user_id);
create policy mentions_insert_from_owned_source on public.activity_mentions for insert to authenticated
    with check (
        (select auth.uid()) = mentioned_by_user_id and (
            (comment_id is null and exists (
                select 1 from public.activities a
                where a.id = activity_id and a.author_id = (select auth.uid())
            )) or (comment_id is not null and exists (
                select 1 from public.comments c
                where c.id = comment_id and c.activity_id = activity_mentions.activity_id
                    and c.author_id = (select auth.uid())
            ))
        )
    );
create policy mentions_delete_own on public.activity_mentions for delete to authenticated
    using ((select auth.uid()) = mentioned_by_user_id);
create policy notifications_read_own on public.notifications for select to authenticated
    using ((select auth.uid()) = user_id);
create policy notifications_mark_own on public.notifications for update to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
-- No client notification insert/delete policy; trusted server creation only.
-- No Storage buckets, uploads, push delivery, or automatic Auth provisioning yet.
commit;
