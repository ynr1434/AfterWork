-- The pre-Auth connection probe needs only the non-sensitive category catalog.
-- Apply after 001. Keep RLS enabled and all private tables authenticated-only.
begin;
grant usage on schema public to anon;
grant select on public.categories to anon;
create policy categories_read_anon on public.categories
    for select to anon using (true);
-- No write grants or policies are added.
commit;
