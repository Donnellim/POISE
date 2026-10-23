-- Event outbox only: intentionally no foreign key to the online sessions table.
create table public.device_posture_events (
 user_id uuid not null references auth.users(id) on delete cascade,
 device_id text not null, event_id text not null, schema_version integer not null check(schema_version = 1),
 session_id text not null, start_time_ms bigint, end_time_ms bigint,
 timestamp_status text not null check(timestamp_status in ('synced','unknown')),
 mode_id integer not null check(mode_id between 1 and 4),
 peak_deviation_deg double precision not null,
 vibration_count integer not null check(vibration_count >= 0),
 correction_status text not null check(correction_status in ('corrected','interrupted')),
 end_reason text not null,
 primary key(user_id, device_id, event_id)
);
alter table public.device_posture_events enable row level security;
create policy "Read own imported events" on public.device_posture_events for select to authenticated using (auth.uid() = user_id);
create policy "Insert own imported events" on public.device_posture_events for insert to authenticated with check (auth.uid() = user_id);
create policy "Delete own imported events" on public.device_posture_events for delete to authenticated using (auth.uid() = user_id);
