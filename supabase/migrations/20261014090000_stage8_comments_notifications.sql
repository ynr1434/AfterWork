-- Stage 8: server-created in-app notifications for comments and mentions.
-- Apply after the existing comments, mentions, and notifications schema.
begin;

create or replace function public.create_comment_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
    activity_owner uuid;
    activity_title text;
    actor_name text;
begin
    select a.author_id, a.title into activity_owner, activity_title
    from public.activities a where a.id = new.activity_id;
    if activity_owner is null or activity_owner = new.author_id then
        return new;
    end if;
    select p.display_name into actor_name from public.profiles p where p.id = new.author_id;
    insert into public.notifications (user_id, type, title, body, activity_id, actor_user_id)
    values (activity_owner, 'activityComment', 'New comment on ' || activity_title,
            coalesce(actor_name, 'Someone') || ': ' || new.body, new.activity_id, new.author_id);
    return new;
end;
$$;
revoke all on function public.create_comment_notification() from public, anon, authenticated;

create or replace function public.create_mention_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
    actor_name text;
    comment_body text;
begin
    select p.display_name into actor_name from public.profiles p where p.id = new.mentioned_by_user_id;
    select c.body into comment_body from public.comments c where c.id = new.comment_id;
    if new.mentioned_user_id = new.mentioned_by_user_id then
        return new;
    end if;
    insert into public.notifications (user_id, type, title, body, activity_id, actor_user_id)
    values (new.mentioned_user_id, 'mention', coalesce(actor_name, 'Someone') || ' mentioned you',
            coalesce(comment_body, 'You were mentioned in an activity.'), new.activity_id, new.mentioned_by_user_id);
    return new;
end;
$$;
revoke all on function public.create_mention_notification() from public, anon, authenticated;

drop trigger if exists comments_create_owner_notification on public.comments;
create trigger comments_create_owner_notification
after insert on public.comments for each row
execute function public.create_comment_notification();

drop trigger if exists mentions_create_notification on public.activity_mentions;
create trigger mentions_create_notification
after insert on public.activity_mentions for each row
execute function public.create_mention_notification();

commit;
