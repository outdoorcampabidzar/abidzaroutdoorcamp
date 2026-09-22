-- PATCH-MEMBERSHIP-CARD.sql
-- Fitur: Admin bisa membuat/menaikkan Kartu Membership untuk pelanggan
-- (Bronze/Silver/Gold/Platinum), lewat tab Pelanggan.
-- Jalankan sekali setelah access-security.sql. Aman dijalankan ulang.

create table if not exists public.membership_cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  card_number text not null unique,
  tier text not null default 'Bronze' check (tier in ('Bronze','Silver','Gold','Platinum')),
  status text not null default 'active' check (status in ('active','inactive')),
  issued_by uuid references auth.users(id) on delete set null,
  issued_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists membership_cards_tier_idx on public.membership_cards(tier);

alter table public.membership_cards enable row level security;

drop policy if exists membership_cards_read on public.membership_cards;
create policy membership_cards_read on public.membership_cards for select
  using (user_id = auth.uid() or public.has_permission('customers.view') or public.has_permission('*'));

drop policy if exists membership_cards_write on public.membership_cards;
create policy membership_cards_write on public.membership_cards for all
  using (public.has_permission('customers.manage') or public.has_permission('*'))
  with check (public.has_permission('customers.manage') or public.has_permission('*'));

grant select on public.membership_cards to authenticated;

-- Buat kartu baru (kalau pelanggan belum punya), atau naikkan/turunkan tier
-- kartu yang sudah ada (nomor kartu tidak berubah supaya konsisten dipakai pelanggan).
create or replace function public.secure_issue_membership_card(p_user_id uuid, p_tier text)
returns public.membership_cards
language plpgsql security definer set search_path = public as $$
declare
  v_row public.membership_cards;
  v_number text;
begin
  if not (public.has_permission('customers.manage') or public.has_permission('*')) then
    raise exception 'Izin mengelola pelanggan diperlukan';
  end if;
  if p_tier not in ('Bronze','Silver','Gold','Platinum') then
    raise exception 'Tier tidak valid';
  end if;
  if not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'Pelanggan tidak ditemukan';
  end if;

  select * into v_row from public.membership_cards where user_id = p_user_id;

  if v_row.id is not null then
    update public.membership_cards
      set tier = p_tier, status = 'active', updated_at = now()
      where user_id = p_user_id
      returning * into v_row;
    return v_row;
  end if;

  -- Generate nomor kartu unik format AOC-XXXXXXXX, retry kalau tabrakan (sangat jarang).
  loop
    v_number := 'AOC-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    exit when not exists (select 1 from public.membership_cards where card_number = v_number);
  end loop;

  insert into public.membership_cards(user_id, card_number, tier, issued_by)
  values (p_user_id, v_number, p_tier, auth.uid())
  returning * into v_row;
  return v_row;
end $$;
revoke all on function public.secure_issue_membership_card(uuid, text) from public;
grant execute on function public.secure_issue_membership_card(uuid, text) to authenticated;

-- Ikutkan ke audit log (tab Log Aktivitas) kalau fungsinya sudah ada.
do $$ begin
  if exists (select 1 from pg_proc where proname = 'audit_admin_change' and pronamespace = 'public'::regnamespace) then
    drop trigger if exists audit_admin_change_trigger on public.membership_cards;
    create trigger audit_admin_change_trigger
      after insert or update or delete on public.membership_cards
      for each row execute function public.audit_admin_change();
  end if;
end $$;
