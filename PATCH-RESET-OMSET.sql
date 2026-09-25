-- AOC: Reset Omzet tanpa menghapus transaksi
-- Reset hanya menggeser titik awal laporan. Data pesanan/pembayaran tetap tersimpan.

create table if not exists public.finance_reset_points (
  id uuid primary key default gen_random_uuid(),
  location_id uuid references public.aoc_locations(id) on delete cascade,
  reset_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists finance_reset_points_lookup_idx
  on public.finance_reset_points(location_id, reset_at desc);

alter table public.finance_reset_points enable row level security;

drop policy if exists finance_reset_points_admin_read on public.finance_reset_points;
create policy finance_reset_points_admin_read
on public.finance_reset_points for select
using (public.has_permission('finance.manage') or public.has_permission('*'));

-- Titik reset terbaru: reset global berlaku untuk semua toko,
-- reset toko berlaku khusus toko tersebut. Yang paling baru dipakai.
drop function if exists public.get_finance_reset_at(uuid);
create or replace function public.get_finance_reset_at(p_location_id uuid default null)
returns timestamptz
language sql
security definer
set search_path = public
as $$
  select max(reset_at)
  from public.finance_reset_points
  where location_id is null or location_id = p_location_id;
$$;

revoke all on function public.get_finance_reset_at(uuid) from public;
grant execute on function public.get_finance_reset_at(uuid) to authenticated;

-- Membuat titik reset baru. Tidak menghapus order, pembayaran, refund,
-- atau data keuangan apa pun.
drop function if exists public.admin_reset_omzet(uuid);
create or replace function public.admin_reset_omzet(p_location_id uuid default null)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
begin
  if not (public.has_permission('finance.manage') or public.has_permission('*')) then
    raise exception 'Tidak memiliki izin untuk mereset omzet';
  end if;

  insert into public.finance_reset_points(location_id, reset_at, created_by)
  values (p_location_id, v_now, auth.uid());

  return v_now;
end;
$$;

revoke all on function public.admin_reset_omzet(uuid) from public;
grant execute on function public.admin_reset_omzet(uuid) to authenticated;
