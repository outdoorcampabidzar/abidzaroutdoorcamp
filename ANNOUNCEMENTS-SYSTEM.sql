-- AOC: Pengumuman Beranda
create table if not exists public.site_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  content text not null,
  category text not null default 'info' check (category in ('info','promo','warning','event','new')),
  image_url text,
  action_label text,
  action_url text,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint announcement_dates check (ends_at is null or ends_at > starts_at)
);
alter table public.site_announcements enable row level security;
drop policy if exists announcements_public_read on public.site_announcements;
create policy announcements_public_read on public.site_announcements
for select using (is_active = true and starts_at <= now() and (ends_at is null or ends_at > now()));
drop policy if exists announcements_admin_read on public.site_announcements;
create policy announcements_admin_read on public.site_announcements
for select using (public.has_permission('site.announcements.manage') or public.has_permission('*'));
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
create index if not exists site_announcements_active_idx on public.site_announcements(is_active, starts_at, ends_at, sort_order);
