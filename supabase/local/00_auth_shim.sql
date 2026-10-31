-- LOCAL VERIFICATION ONLY — never apply to Supabase (which already provides these objects).
-- Recreates the minimal Supabase auth surface (roles + auth.uid()) on vanilla PostgreSQL so the
-- RLS migration can be applied and tested with scripts/apply_migrations.py --local-shim.

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;

create schema if not exists auth;

create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

grant usage on schema public, auth to anon, authenticated, service_role;
alter default privileges in schema public grant select on tables to anon, authenticated;
