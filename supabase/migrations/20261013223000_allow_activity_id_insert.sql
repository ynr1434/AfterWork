-- Allow authenticated clients to provide an activity UUID for idempotent
-- creation retries. Existing column-level grants and RLS remain unchanged.
grant insert (id) on public.activities to authenticated;
