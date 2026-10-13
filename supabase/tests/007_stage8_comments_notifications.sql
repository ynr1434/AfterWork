-- Stage 8 SQL checks. Run in a test database with authenticated test users.
-- These assertions document the security contract for the additive trigger migration.
do $$ begin
    if not (select relrowsecurity from pg_class where oid = 'public.comments'::regclass) then
        raise exception 'comments RLS must remain enabled';
    end if;
    if not has_column_privilege('authenticated', 'public.comments', 'body', 'UPDATE') then
        raise exception 'authenticated is missing the body UPDATE privilege';
    end if;
    if not has_table_privilege('authenticated', 'public.comments', 'DELETE') then
        raise exception 'authenticated is missing the comments DELETE privilege';
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'public'
        and tablename = 'comments' and policyname = 'comments_update_own'
        and cmd = 'UPDATE' and qual like '%auth.uid()%author_id%'
        and with_check like '%auth.uid()%author_id%') then
        raise exception 'comments UPDATE ownership policy is missing or too broad';
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'public'
        and tablename = 'comments' and policyname = 'comments_delete_own'
        and cmd = 'DELETE' and qual like '%auth.uid()%author_id%') then
        raise exception 'comments DELETE ownership policy is missing or too broad';
    end if;
    if not exists (select 1 from pg_trigger where tgname = 'comments_create_owner_notification') then
        raise exception 'comment notification trigger is missing';
    end if;
    if not exists (select 1 from pg_trigger where tgname = 'mentions_create_notification') then
        raise exception 'mention notification trigger is missing';
    end if;
    if has_table_privilege('authenticated', 'public.notifications', 'INSERT') then
        raise exception 'authenticated must not insert notifications directly';
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'public'
        and tablename = 'comments' and policyname = 'comments_insert_own') then
        raise exception 'comments ownership policy is missing';
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'public'
        and tablename = 'activity_mentions' and policyname = 'mentions_insert_from_owned_source') then
        raise exception 'mention ownership policy is missing';
    end if;
    if not exists (select 1 from pg_indexes where schemaname = 'public'
        and tablename = 'activity_mentions' and indexname = 'activity_mentions_comment_unique') then
        raise exception 'comment mention deduplication index is missing';
    end if;
end $$;
