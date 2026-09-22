-- PATCH-EXPENSES-TRACKING.sql
-- Fitur: Pencatatan Biaya/Pengeluaran + Laba Bersih pada tab Omzet & Keuangan.
-- Jalankan sekali setelah AOC-ULTIMATE-FINAL.sql. Aman dijalankan ulang (idempotent).

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  location_id uuid references public.aoc_locations(id) on delete set null,
  category text not null default 'Operasional',
  description text,
  amount numeric(14,2) not null check (amount >= 0),
  expense_date date not null default current_date,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists expenses_date_idx on public.expenses(expense_date);
create index if not exists expenses_location_idx on public.expenses(location_id);

alter table public.expenses enable row level security;

drop policy if exists expenses_read on public.expenses;
create policy expenses_read on public.expenses for select
  using (public.has_permission('finance.manage') or public.has_permission('*'));

drop policy if exists expenses_write on public.expenses;
create policy expenses_write on public.expenses for all
  using (public.has_permission('finance.manage') or public.has_permission('*'))
  with check (public.has_permission('finance.manage') or public.has_permission('*'));

grant select, insert, update, delete on public.expenses to authenticated;

-- Hanya boleh dicatat/dihapus lewat RPC ini supaya permission dicek di server,
-- bukan cuma mengandalkan RLS di client (pola yang sama dengan secure_admin_manage_order).
create or replace function public.secure_add_expense(
  p_location_id uuid,
  p_category text,
  p_description text,
  p_amount numeric,
  p_expense_date date default current_date
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if not (public.has_permission('finance.manage') or public.has_permission('*')) then
    raise exception 'Izin keuangan diperlukan';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Nominal pengeluaran tidak valid';
  end if;
  insert into public.expenses(location_id, category, description, amount, expense_date, created_by)
  values (
    p_location_id,
    coalesce(nullif(trim(p_category), ''), 'Operasional'),
    nullif(trim(coalesce(p_description, '')), ''),
    p_amount,
    coalesce(p_expense_date, current_date),
    auth.uid()
  )
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.secure_add_expense(uuid, text, text, numeric, date) from public;
grant execute on function public.secure_add_expense(uuid, text, text, numeric, date) to authenticated;

create or replace function public.secure_delete_expense(p_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not (public.has_permission('finance.manage') or public.has_permission('*')) then
    raise exception 'Izin keuangan diperlukan';
  end if;
  delete from public.expenses where id = p_id;
end $$;
revoke all on function public.secure_delete_expense(uuid) from public;
grant execute on function public.secure_delete_expense(uuid) to authenticated;

-- Ikutkan expenses ke sistem audit log yang sudah ada (tab 🛡️ Log Aktivitas),
-- supaya penambahan/penghapusan pengeluaran juga tercatat seperti refund/return.
-- Dibungkus pengecekan supaya aman dijalankan meski access-security.sql belum/baru jalan.
do $$ begin
  if exists (select 1 from pg_proc where proname = 'audit_admin_change' and pronamespace = 'public'::regnamespace) then
    drop trigger if exists audit_admin_change_trigger on public.expenses;
    create trigger audit_admin_change_trigger
      after insert or update or delete on public.expenses
      for each row execute function public.audit_admin_change();
  end if;
end $$;
