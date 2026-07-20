-- Manajemen voucher AbidzarOutdoorcamp
-- Jalankan sekali melalui Supabase SQL Editor.

alter table public.vouchers
  add column if not exists applies_to text not null default 'all',
  add column if not exists once_per_customer boolean not null default false;

alter table public.vouchers drop constraint if exists vouchers_applies_to_check;
alter table public.vouchers add constraint vouchers_applies_to_check
  check (applies_to in ('all', 'rental', 'trip', 'products'));

create table if not exists public.voucher_items (
  voucher_id uuid not null references public.vouchers(id) on delete cascade,
  item_id uuid not null references public.items(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (voucher_id, item_id)
);

create table if not exists public.voucher_usages (
  id uuid primary key default gen_random_uuid(),
  voucher_id uuid not null references public.vouchers(id) on delete restrict,
  order_id uuid not null references public.orders(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  voucher_code text not null,
  discount numeric(14,2) not null default 0,
  status text not null default 'used' check (status in ('used', 'reversed')),
  used_at timestamptz not null default now(),
  reversed_at timestamptz,
  unique(order_id)
);

create index if not exists voucher_usages_voucher_used_idx
  on public.voucher_usages(voucher_id, used_at desc);
create index if not exists voucher_usages_user_idx
  on public.voucher_usages(user_id, used_at desc);

alter table public.voucher_items enable row level security;
alter table public.voucher_usages enable row level security;

drop policy if exists "voucher items admin all" on public.voucher_items;
create policy "voucher items admin all" on public.voucher_items
for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "voucher usages admin read" on public.voucher_usages;
create policy "voucher usages admin read" on public.voucher_usages
for select to authenticated using (public.is_admin());

drop policy if exists "voucher usages own read" on public.voucher_usages;
create policy "voucher usages own read" on public.voucher_usages
for select to authenticated using (user_id = auth.uid());

create or replace function public.voucher_scope_matches(
  p_voucher public.vouchers,
  p_items jsonb
) returns boolean
language sql stable security definer set search_path = public
as $$
  select case p_voucher.applies_to
    when 'all' then true
    when 'rental' then exists (
      select 1 from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) line
      join public.items i on i.id = (line->>'item_id')::uuid
      where i.type = 'product'
    )
    when 'trip' then exists (
      select 1 from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) line
      join public.items i on i.id = (line->>'item_id')::uuid
      where i.type = 'trip'
    )
    when 'products' then exists (
      select 1 from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) line
      join public.voucher_items vi
        on vi.voucher_id = p_voucher.id
       and vi.item_id = (line->>'item_id')::uuid
    )
    else false
  end;
$$;

drop function if exists public.preview_voucher(text, numeric);
drop function if exists public.preview_voucher(text, numeric, jsonb);
create function public.preview_voucher(
  p_code text,
  p_subtotal numeric,
  p_items jsonb default '[]'::jsonb
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v public.vouchers%rowtype;
  v_discount numeric := 0;
  v_code text := upper(trim(coalesce(p_code, '')));
begin
  if auth.uid() is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if p_subtotal is null or p_subtotal < 0 then raise exception 'Subtotal tidak valid'; end if;

  select * into v from public.vouchers
  where code = v_code and is_active = true
    and now() between starts_at and expires_at
    and used_count < quota;
  if not found then raise exception 'Voucher tidak valid, belum aktif, berakhir, atau kuota habis'; end if;
  if p_subtotal < v.min_purchase then
    raise exception 'Minimal transaksi voucher adalah %', v.min_purchase;
  end if;
  if not public.voucher_scope_matches(v, p_items) then
    raise exception 'Voucher tidak berlaku untuk isi keranjang ini';
  end if;
  if v.once_per_customer and exists (
    select 1 from public.orders o
    where o.user_id = auth.uid() and o.voucher_code = v.code
      and o.status not in ('cancelled', 'failed', 'refunded')
  ) then raise exception 'Voucher hanya dapat digunakan satu kali per pelanggan'; end if;

  v_discount := case when v.discount_type = 'percent'
    then p_subtotal * (v.discount_value / 100) else v.discount_value end;
  if v.max_discount is not null then v_discount := least(v_discount, v.max_discount); end if;
  v_discount := least(v_discount, p_subtotal);

  return jsonb_build_object(
    'id', v.id, 'code', v.code, 'discount_type', v.discount_type,
    'discount_value', v.discount_value, 'discount', v_discount,
    'applies_to', v.applies_to, 'expires_at', v.expires_at
  );
end;
$$;
grant execute on function public.preview_voucher(text, numeric, jsonb) to authenticated;

create or replace function public.track_voucher_usage()
returns trigger language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if new.voucher_code is null then return new; end if;
  select id into v_id from public.vouchers where code = new.voucher_code;
  if v_id is null then return new; end if;

  if new.status in ('confirmed', 'paid', 'completed')
     and old.status not in ('confirmed', 'paid', 'completed') then
    insert into public.voucher_usages(
      voucher_id, order_id, user_id, voucher_code, discount, status
    ) values (v_id, new.id, new.user_id, new.voucher_code, new.discount, 'used')
    on conflict (order_id) do update set
      status = 'used', used_at = now(), reversed_at = null;
  elsif old.status in ('confirmed', 'paid', 'completed')
        and new.status in ('cancelled', 'failed', 'refunded') then
    update public.voucher_usages set status = 'reversed', reversed_at = now()
    where order_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists orders_track_voucher_usage on public.orders;
create trigger orders_track_voucher_usage
after update of status on public.orders
for each row execute function public.track_voucher_usage();

grant select, insert, update, delete on public.vouchers to authenticated;
grant select, insert, update, delete on public.voucher_items to authenticated;
grant select on public.voucher_usages to authenticated;
