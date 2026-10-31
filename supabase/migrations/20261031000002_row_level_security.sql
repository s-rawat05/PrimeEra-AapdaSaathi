-- Row-level security: least privilege for any direct client access (Supabase anon/authenticated
-- keys, Realtime). The FastAPI backend connects with a privileged role and enforces the same rules
-- in code; these policies are defence in depth so a leaked anon key cannot read the registry.
--
-- Identity: auth.uid() (Supabase) → users.auth_user_id → users.id / users.role.

create schema if not exists app;

create or replace function app.current_user_id() returns varchar
language sql stable security definer set search_path = public as $$
  select u.id from users u where u.auth_user_id = auth.uid()::text and u.is_active
$$;

create or replace function app.current_role() returns varchar
language sql stable security definer set search_path = public as $$
  select u.role from users u where u.auth_user_id = auth.uid()::text and u.is_active
$$;

create or replace function app.is_ops() returns boolean
language sql stable as $$ select coalesce(app.current_role() in ('admin','operator'), false) $$;

create or replace function app.is_admin() returns boolean
language sql stable as $$ select coalesce(app.current_role() = 'admin', false) $$;

-- Resident ids the current user may see as a responder: open task in an active incident.
create or replace function app.assigned_resident_ids() returns setof varchar
language sql stable security definer set search_path = public as $$
  select t.resident_id from tasks t join incidents i on i.id = t.incident_id
  where t.assignee_user_id = app.current_user_id()
    and t.status in ('ASSIGNED','ACCEPTED') and i.status = 'active'
$$;

create or replace function app.caregiver_resident_ids() returns setof varchar
language sql stable security definer set search_path = public as $$
  select resident_id from caregiver_links where caregiver_user_id = app.current_user_id()
$$;

create or replace function app.own_resident_id() returns varchar
language sql stable security definer set search_path = public as $$
  select id from residents where user_id = app.current_user_id()
$$;

-- Policies run as the querying role, so client roles must be able to call the helpers
-- (security definer functions; they only reveal the caller's own id/role/assignments).
grant usage on schema app to anon, authenticated;
grant execute on all functions in schema app to anon, authenticated;

-- Enable RLS everywhere. No policy = no access for anon/authenticated.
do $$
declare t text;
begin
  foreach t in array array['users','otp_challenges','wards','shelters','residents','resident_locations',
    'consent_records','caregiver_links','neighbour_links','volunteers','pre_assigned_helpers','feed_state',
    'cap_messages','demo_sessions','incidents','incident_wards','deliveries','tasks','notification_attempts',
    'incident_timeline','audit_log','device_registrations','alert_templates','sms_inbound','idempotency_keys',
    'worker_heartbeats']
  loop
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

-- users: yourself; operations staff see everyone.
create policy users_self on users for select using (id = app.current_user_id() or app.is_ops());

-- Reference data readable by any signed-in user.
create policy wards_read on wards for select to authenticated using (true);
create policy shelters_read on shelters for select to authenticated using (true);

-- Registry: own profile, linked caregivers, operations staff. Responders use the audited API instead.
create policy residents_read on residents for select using (
  id = app.own_resident_id() or id in (select app.caregiver_resident_ids()) or app.is_ops()
);
create policy consent_read on consent_records for select using (
  resident_id = app.own_resident_id() or app.is_admin()
);

-- Exact location: the resident, consented caregivers, responders on an ACTIVE task, admins.
create policy locations_read on resident_locations for select using (
  resident_id = app.own_resident_id()
  or resident_id in (select app.assigned_resident_ids())
  or app.is_admin()
  or exists (select 1 from caregiver_links c where c.resident_id = resident_locations.resident_id
             and c.caregiver_user_id = app.current_user_id() and c.can_view_location)
);

create policy caregiver_links_read on caregiver_links for select using (
  caregiver_user_id = app.current_user_id() or resident_id = app.own_resident_id() or app.is_admin()
);
create policy neighbour_links_read on neighbour_links for select using (
  neighbour_user_id = app.current_user_id() or app.is_admin()
);
create policy volunteers_read on volunteers for select using (user_id = app.current_user_id() or app.is_ops());

-- Incidents: operations staff; residents/responders only for incidents that involve them.
create policy incidents_read on incidents for select using (
  app.is_ops()
  or exists (select 1 from deliveries d where d.incident_id = incidents.id and d.resident_id = app.own_resident_id())
  or exists (select 1 from tasks t where t.incident_id = incidents.id and t.assignee_user_id = app.current_user_id())
);
create policy incident_wards_read on incident_wards for select using (app.is_ops());

create policy deliveries_read on deliveries for select using (
  resident_id = app.own_resident_id() or resident_id in (select app.caregiver_resident_ids()) or app.is_ops()
);
create policy tasks_read on tasks for select using (assignee_user_id = app.current_user_id() or app.is_ops());
create policy timeline_read on incident_timeline for select using (app.is_ops());
create policy notifications_read on notification_attempts for select using (
  recipient_user_id = app.current_user_id() or app.is_ops()
);

-- Operations-only tables.
create policy cap_read on cap_messages for select using (app.is_ops());
create policy feed_read on feed_state for select using (app.is_ops());
create policy audit_read on audit_log for select using (app.is_ops());
create policy templates_read on alert_templates for select using (app.is_admin());
create policy devices_own on device_registrations for select using (user_id = app.current_user_id());

-- No insert/update/delete policies: every write goes through the authorised backend, which
-- validates, runs in a transaction and writes the audit log.

-- Audit log is append-only. The only permitted UPDATE is ON DELETE SET NULL of the actor.
create or replace function app.audit_log_append_only() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'audit_log is append-only';
  end if;
  if (new.actor_user_id is null and old.actor_user_id is not null)
     and (new.action, new.entity_type, new.entity_id, new.reason, new.before, new.after, new.created_at)
         is not distinct from
         (old.action, old.entity_type, old.entity_id, old.reason, old.before, old.after, old.created_at) then
    return new;
  end if;
  raise exception 'audit_log is append-only';
end $$;

create trigger audit_log_append_only before update or delete on audit_log
  for each row execute function app.audit_log_append_only();

-- Realtime: publish only the tables operators subscribe to (RLS still applies to subscribers).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table incidents, deliveries, tasks, feed_state;
  end if;
end $$;
