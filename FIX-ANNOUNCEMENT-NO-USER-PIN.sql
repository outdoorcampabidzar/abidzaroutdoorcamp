-- AOC: Announcement admin management must not require customer transaction PIN.
-- Existing RLS policies on site_announcements continue to enforce admin permissions.

drop trigger if exists aoc_pin_gate_site_announcements on public.site_announcements;

-- Reassert the intended admin-only mutation policies.
alter table public.site_announcements enable row level security;

drop policy if exists announcements_admin_insert on public.site_announcements;
create policy announcements_admin_insert on public.site_announcements
for insert with check (public.has_permission('site.announcements.manage') or public.has_permission('*'));

drop policy if exists announcements_admin_update on public.site_announcements;
create policy announcements_admin_update on public.site_announcements
for update using (public.has_permission('site.announcements.manage') or public.has_permission('*'))
with check (public.has_permission('site.announcements.manage') or public.has_permission('*'));

drop policy if exists announcements_admin_delete on public.site_announcements;
create policy announcements_admin_delete on public.site_announcements
for delete using (public.has_permission('site.announcements.manage') or public.has_permission('*'));
