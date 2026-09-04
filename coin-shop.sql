-- SISTEM COIN + SHOP REWARD + VOUCHER RANDOM
-- Jalankan setelah schema utama / voucher-management.sql.

create table if not exists public.coin_settings (
  id boolean primary key default true,
  coin_value_rupiah bigint not null default 1000 check (coin_value_rupiah > 0),
  updated_at timestamptz not null default now()
);
-- Versi lama memakai coin_per_order. Jika kolom tersebut masih ada, nilainya
-- tidak lagi dipakai: coin sekarang dihitung dari nilai transaksi sewa/jual.
alter table public.coin_settings
  add column if not exists coin_value_rupiah bigint;
alter table public.coin_settings
  add column if not exists coin_min_percent numeric(5,2);
alter table public.coin_settings
  add column if not exists coin_max_percent numeric(5,2);
update public.coin_settings
set coin_value_rupiah=1000
where coin_value_rupiah is null or coin_value_rupiah<=0;
update public.coin_settings
set coin_min_percent=10
where coin_min_percent is null or coin_min_percent<0;
update public.coin_settings
set coin_max_percent=100
where coin_max_percent is null or coin_max_percent<=0;
alter table public.coin_settings
  alter column coin_min_percent set default 10;
alter table public.coin_settings
  alter column coin_max_percent set default 100;
do $$
begin
  if not exists (select 1 from pg_constraint where conrelid='public.coin_settings'::regclass and conname='coin_settings_percent_range_check') then
    alter table public.coin_settings
      add constraint coin_settings_percent_range_check
      check (coin_min_percent >= 0 and coin_max_percent >= coin_min_percent and coin_max_percent <= 100);
  end if;
end $$;
alter table public.coin_settings
  alter column coin_value_rupiah set default 1000;
insert into public.coin_settings(id, coin_value_rupiah, coin_min_percent, coin_max_percent)
values (true, 1000, 10, 100)
on conflict (id) do update set
  coin_min_percent=coalesce(public.coin_settings.coin_min_percent,10),
  coin_max_percent=coalesce(public.coin_settings.coin_max_percent,100);

alter table public.vouchers
  add column if not exists owner_user_id uuid references auth.users(id) on delete cascade,
  add column if not exists source_voucher_id uuid references public.vouchers(id) on delete set null;

-- Probabilitas Gacha per voucher. Jika kosong/0, sistem memakai bobot 1.
alter table public.vouchers
  add column if not exists gacha_rarity text not null default 'common',
  add column if not exists gacha_probability numeric(7,4) not null default 60;
alter table public.vouchers drop constraint if exists vouchers_gacha_rarity_check;
alter table public.vouchers add constraint vouchers_gacha_rarity_check check (gacha_rarity in ('common','uncommon','rare','epic','legendary'));
alter table public.vouchers drop constraint if exists vouchers_gacha_probability_check;
alter table public.vouchers add constraint vouchers_gacha_probability_check check (gacha_probability >= 0 and gacha_probability <= 100);
update public.vouchers set gacha_rarity = case
  when discount_type='percent' and discount_value >= 50 then 'legendary'
  when discount_type='percent' and discount_value >= 30 then 'epic'
  when discount_type='percent' and discount_value >= 20 then 'rare'
  when discount_type='percent' and discount_value >= 10 then 'uncommon'
  else 'common' end
where gacha_rarity='common' and gacha_probability=60;
update public.vouchers set gacha_probability = case gacha_rarity
  when 'common' then 60 when 'uncommon' then 25 when 'rare' then 10 when 'epic' then 4 when 'legendary' then 1 else 60 end
where gacha_probability=60;

create index if not exists vouchers_owner_idx on public.vouchers(owner_user_id);

create table if not exists public.customer_coins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance bigint not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.shop_rewards (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  image_url text,
  coin_cost bigint not null default 1 check (coin_cost > 0),
  reward_type text not null default 'voucher_random'
    check (reward_type in ('voucher_random')),
  is_active boolean not null default true,
  stock integer not null default 0 check (stock >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.coin_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount bigint not null check (amount <> 0),
  type text not null check (type in ('order_reward','redeem','adjustment')),
  order_id uuid references public.orders(id) on delete set null,
  shop_reward_id uuid references public.shop_rewards(id) on delete set null,
  description text,
  reward_percent numeric(5,2),
  created_at timestamptz not null default now()
);
alter table public.coin_transactions add column if not exists reward_percent numeric(5,2);
create unique index if not exists coin_tx_order_reward_unique
  on public.coin_transactions(order_id) where type='order_reward' and order_id is not null;
create index if not exists coin_tx_user_idx on public.coin_transactions(user_id, created_at desc);

create table if not exists public.shop_redemptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  shop_reward_id uuid not null references public.shop_rewards(id) on delete restrict,
  coin_cost bigint not null check (coin_cost > 0),
  voucher_id uuid references public.vouchers(id) on delete set null,
  voucher_code text,
  created_at timestamptz not null default now()
);
create index if not exists shop_redemptions_user_idx
  on public.shop_redemptions(user_id, created_at desc);

alter table public.customer_coins enable row level security;
alter table public.coin_transactions enable row level security;
alter table public.shop_rewards enable row level security;
alter table public.shop_redemptions enable row level security;
alter table public.coin_settings enable row level security;

drop policy if exists "coins own read" on public.customer_coins;
create policy "coins own read" on public.customer_coins for select to authenticated
using (user_id=auth.uid() or public.has_permission('coinshop.manage') or public.has_permission('*'));

drop policy if exists "coin tx own read" on public.coin_transactions;
create policy "coin tx own read" on public.coin_transactions for select to authenticated
using (user_id=auth.uid() or public.has_permission('coinshop.manage') or public.has_permission('*'));

drop policy if exists "shop rewards public read" on public.shop_rewards;
create policy "shop rewards public read" on public.shop_rewards for select to authenticated
using (is_active=true or public.has_permission('coinshop.manage') or public.has_permission('*'));

drop policy if exists "shop rewards admin all" on public.shop_rewards;
create policy "shop rewards admin all" on public.shop_rewards for all to authenticated
using (public.has_permission('coinshop.manage') or public.has_permission('*')) with check (public.has_permission('coinshop.manage') or public.has_permission('*'));

drop policy if exists "shop redemptions own read" on public.shop_redemptions;
create policy "shop redemptions own read" on public.shop_redemptions for select to authenticated
using (user_id=auth.uid() or public.has_permission('coinshop.manage') or public.has_permission('*'));

drop policy if exists "coin settings admin" on public.coin_settings;
create policy "coin settings admin" on public.coin_settings for all to authenticated
using (public.has_permission('coinshop.manage') or public.has_permission('*')) with check (public.has_permission('coinshop.manage') or public.has_permission('*'));

grant select on public.customer_coins, public.coin_transactions, public.shop_rewards, public.shop_redemptions, public.coin_settings to authenticated;

create or replace function public.award_order_coins(p_order_id uuid)
returns bigint language plpgsql security definer set search_path=public,auth as $$
declare
  v_order public.orders%rowtype;
  v_coin_value bigint := 1000;
  v_eligible_total numeric := 0;
  v_coin_base numeric := 0;
  v_coins bigint := 0;
  v_min_percent numeric := 10;
  v_max_percent numeric := 100;
  v_reward_percent numeric := 10;
  v_user uuid;
  v_inserted boolean := false;
begin
  select * into v_order from public.orders where id=p_order_id;
  if not found then return 0; end if;
  if v_order.status not in ('paid','completed') and coalesce(v_order.payment_status,'') <> 'paid' then return 0; end if;
  v_user := v_order.user_id;
  if v_user is null then return 0; end if;

  select coin_value_rupiah, coin_min_percent, coin_max_percent
    into v_coin_value, v_min_percent, v_max_percent
  from public.coin_settings where id=true;
  v_coin_value := greatest(1,coalesce(v_coin_value,1000));
  v_min_percent := greatest(0,least(100,coalesce(v_min_percent,10)));
  v_max_percent := greatest(v_min_percent,least(100,coalesce(v_max_percent,100)));
  -- Random persentase dibuat di database, bukan di browser. Inclusive: min..max.
  -- Random integer inclusive agar mudah dipahami: 10..100 berarti tepat salah satu angka 10 sampai 100.
  v_reward_percent := floor(v_min_percent + random() * (v_max_percent - v_min_percent + 1));

  -- Coin hanya dihitung dari item SEWA dan JUAL, bukan Open Trip.
  select coalesce(sum(oi.line_total),0) into v_eligible_total
  from public.order_items oi
  where oi.order_id=p_order_id
    and lower(coalesce(oi.fulfillment_type,'')) in ('rental','sale');

  if v_eligible_total <= 0 then return 0; end if;

  -- Diskon voucher ikut mengurangi nilai transaksi yang menghasilkan coin.
  -- Dialokasikan proporsional terhadap subtotal order.
  if coalesce(v_order.subtotal,0) > 0 then
    v_coin_base := least(v_eligible_total,
      greatest(0, v_eligible_total * (coalesce(v_order.total,0) / v_order.subtotal)));
  else
    v_coin_base := v_eligible_total;
  end if;

  -- Reward coin = nilai transaksi eligible × persentase acak / nilai 1 coin.
  v_coin_base := v_coin_base * (v_reward_percent / 100.0);
  v_coins := floor(v_coin_base / v_coin_value)::bigint;
  if v_coins <= 0 then return 0; end if;

  insert into public.coin_transactions(user_id,amount,type,order_id,description,reward_percent)
  values(v_user,v_coins,'order_reward',p_order_id,
         'Coin pesanan sewa/jual '||coalesce(v_order.order_number,p_order_id::text)||
         ' · Reward '||to_char(v_reward_percent,'FM990D00')||'% · Rp'||to_char(v_coin_base,'FM999G999G999G990D00'),
         v_reward_percent)
  on conflict (order_id) where type='order_reward' and order_id is not null do nothing;
  v_inserted := found;
  if not v_inserted then return 0; end if;

  insert into public.customer_coins(user_id,balance)
  values(v_user,v_coins)
  on conflict(user_id) do update
    set balance=public.customer_coins.balance+excluded.balance, updated_at=now();

  return v_coins;
end;
$$;

revoke all on function public.award_order_coins(uuid) from public;
grant execute on function public.award_order_coins(uuid) to service_role;

create or replace function public.coin_award_order_trigger()
returns trigger language plpgsql security definer set search_path=public,auth as $$
begin
  if tg_op='INSERT' then
    if new.status in ('paid','completed') or coalesce(new.payment_status,'')='paid' then
      perform public.award_order_coins(new.id);
    end if;
  elsif (new.status in ('paid','completed') or coalesce(new.payment_status,'')='paid')
        and (old.status is distinct from new.status or old.payment_status is distinct from new.payment_status) then
    perform public.award_order_coins(new.id);
  end if;
  return new;
end;
$$;
drop trigger if exists orders_coin_reward_trigger on public.orders;
create trigger orders_coin_reward_trigger after insert or update of status,payment_status on public.orders
for each row execute function public.coin_award_order_trigger();

-- Gacha: seluruh proses memilih voucher dilakukan di server dalam satu transaksi.
-- Ini membuat hasil roda selalu sama dengan voucher yang benar-benar diberikan.
drop function if exists public.get_shop_gacha_options(uuid);
create or replace function public.get_shop_gacha_options(p_reward_id uuid)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare
  v_reward public.shop_rewards%rowtype;
  v_options jsonb;
begin
  if auth.uid() is null then raise exception 'Silakan login terlebih dahulu'; end if;
  select * into v_reward from public.shop_rewards where id=p_reward_id and is_active=true;
  if not found then raise exception 'Hadiah shop tidak tersedia'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,
    'rarity',v.gacha_rarity,
    'probability',v.gacha_probability,
    'label',case when v.discount_type='percent' then trim(trailing '.' from trim(trailing '0' from to_char(v.discount_value,'FM999999990.00')))||'%' else 'Rp'||to_char(v.discount_value,'FM999G999G999G990') end
  ) order by random()),'[]'::jsonb)
  into v_options
  from (
    select v.* from public.vouchers v
    where v.is_active=true and v.owner_user_id is null
      and now() between v.starts_at and v.expires_at
      and coalesce(v.used_count,0) < v.quota
      and coalesce(v.gacha_probability,60) > 0
    order by random() limit 12
  ) v;
  if jsonb_array_length(v_options)=0 then raise exception 'Belum ada voucher aktif untuk Gacha. Buat/aktifkan voucher di Admin → Voucher.'; end if;
  return v_options;
end;
$$;
revoke all on function public.get_shop_gacha_options(uuid) from public;
grant execute on function public.get_shop_gacha_options(uuid) to authenticated;

drop function if exists public.redeem_shop_reward(uuid);
create or replace function public.redeem_shop_reward(p_reward_id uuid)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare
  v_user uuid := auth.uid();
  v_reward public.shop_rewards%rowtype;
  v_balance bigint;
  v_source public.vouchers%rowtype;
  v_voucher_id uuid;
  v_code text;
  v_expiry timestamptz;
  v_options jsonb := '[]'::jsonb;
  v_index integer := 0;
  v_found_index integer := -1;
  v_label text;
begin
  if v_user is null then raise exception 'Silakan login terlebih dahulu'; end if;

  select * into v_reward from public.shop_rewards
  where id=p_reward_id and is_active=true
  for update;
  if not found then raise exception 'Hadiah shop tidak tersedia'; end if;
  
  insert into public.customer_coins(user_id,balance) values(v_user,0)
  on conflict(user_id) do nothing;
  select balance into v_balance from public.customer_coins where user_id=v_user for update;
  if v_balance < v_reward.coin_cost then
    raise exception 'Coin tidak cukup. Anda memiliki % coin.',v_balance;
  end if;

  -- Ambil maksimal 12 voucher aktif sebagai isi papan.
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',x.id,
    'rarity',x.gacha_rarity,
    'probability',x.gacha_probability,
    'label',case when x.discount_type='percent'
      then trim(trailing '.' from trim(trailing '0' from to_char(x.discount_value,'FM999999990.00')))||'%'
      else 'Rp'||to_char(x.discount_value,'FM999G999G999G990') end
  ) order by x.sort_no),'[]'::jsonb)
  into v_options
  from (
    select v.id,v.discount_type,v.discount_value,v.gacha_rarity,v.gacha_probability,
           row_number() over(order by random()) as sort_no
    from public.vouchers v
    where v.is_active=true and v.owner_user_id is null
      and now() between v.starts_at and v.expires_at
      and coalesce(v.used_count,0) < v.quota
      and coalesce(v.gacha_probability,60) > 0
    order by random() limit 12
  ) x;

  if jsonb_array_length(v_options)=0 then
    raise exception 'Belum ada voucher aktif untuk Gacha. Buat/aktifkan voucher di Admin → Voucher.';
  end if;

  -- Pilih satu voucher dari papan yang sama dengan yang ditampilkan ke customer.
  -- Pilih pemenang berdasarkan bobot/probabilitas masing-masing voucher.
  -- Bobot dinormalisasi hanya di antara voucher yang tampil di papan.
  with board as (
    select v.*, greatest(0,coalesce(v.gacha_probability,60)) as weight
    from public.vouchers v
    where v.id in (select (e->>'id')::uuid from jsonb_array_elements(v_options) e)
      and v.is_active=true and now() between v.starts_at and v.expires_at
      and coalesce(v.used_count,0) < v.quota
  ), weighted as (
    select board.*, sum(weight) over () total_weight,
           sum(weight) over (order by random()) cumulative_weight
    from board
  ), pick as (
    select * from weighted where cumulative_weight >= random()*nullif(total_weight,0) order by cumulative_weight limit 1
  )
  select * into v_source from public.vouchers v where v.id=(select id from pick) for update;
  if not found then raise exception 'Voucher Gacha tidak tersedia'; end if;

  -- Cari posisi voucher pemenang di papan.
  v_index := 0;
  for v_label in select value->>'id' from jsonb_array_elements(v_options)
  loop
    if v_label = v_source.id::text then v_found_index := v_index; exit; end if;
    v_index := v_index + 1;
  end loop;
  if v_found_index < 0 then v_found_index := 0; end if;

  -- Kuota voucher sumber juga menjadi batas jumlah voucher yang dapat dimenangkan
  -- lewat Gacha. Kunci baris sumber sudah diambil FOR UPDATE, sehingga dua
  -- penukaran bersamaan tidak dapat melewati kuota.
  update public.vouchers
  set used_count = coalesce(used_count,0) + 1
  where id = v_source.id
    and coalesce(used_count,0) < quota;
  if not found then
    raise exception 'Kuota voucher Gacha sudah habis';
  end if;

  v_code := 'AOC-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  v_expiry := least(v_source.expires_at, now()+interval '30 days');

  insert into public.vouchers(
    code,discount_type,discount_value,min_purchase,max_discount,quota,used_count,
    starts_at,expires_at,is_active,applies_to,once_per_customer,owner_user_id,source_voucher_id,gacha_rarity,gacha_probability
  )
  values(
    v_code,v_source.discount_type,v_source.discount_value,v_source.min_purchase,v_source.max_discount,
    1,0,now(),v_expiry,true,v_source.applies_to,true,v_user,v_source.id,v_source.gacha_rarity,v_source.gacha_probability
  ) returning id into v_voucher_id;

  if v_source.applies_to='products' then
    insert into public.voucher_items(voucher_id,item_id)
    select v_voucher_id,item_id from public.voucher_items where voucher_id=v_source.id;
  end if;

  -- Voucher sumber Gacha adalah stok/template. Jika seluruh kuotanya sudah
  -- terpakai, hapus otomatis setelah voucher pemenang berhasil dibuat.
  -- Untuk voucher 1/1, sumber langsung terhapus pada penukaran yang berhasil.
  if coalesce(v_source.used_count,0) + 1 >= v_source.quota then
    delete from public.vouchers
    where id = v_source.id
      and coalesce(used_count,0) >= quota;
  end if;

  update public.customer_coins
  set balance=balance-v_reward.coin_cost, updated_at=now()
  where user_id=v_user;

  insert into public.coin_transactions(user_id,amount,type,shop_reward_id,description)
  values(v_user,-v_reward.coin_cost,'redeem',v_reward.id,'Tukar coin: '||v_reward.title);

  insert into public.shop_redemptions(user_id,shop_reward_id,coin_cost,voucher_id,voucher_code)
  values(v_user,v_reward.id,v_reward.coin_cost,v_voucher_id,v_code);

  if v_reward.stock > 0 then
    update public.shop_rewards
    set stock=greatest(stock-1,0),updated_at=now()
    where id=v_reward.id;
  end if;

  return jsonb_build_object(
    'voucher_code',v_code,
    'voucher_id',v_voucher_id,
    'coin_cost',v_reward.coin_cost,
    'remaining_coins',v_balance-v_reward.coin_cost,
    'discount_type',v_source.discount_type,
    'discount_value',v_source.discount_value,'rarity',v_source.gacha_rarity,'probability',v_source.gacha_probability,
    'source_voucher_id',v_source.id,
    'gacha_options',v_options,
    'gacha_index',v_found_index,
    'expires_at',v_expiry
  );
end;
$$;
revoke all on function public.redeem_shop_reward(uuid) from public;
grant execute on function public.redeem_shop_reward(uuid) to authenticated;

-- owner voucher: hanya pemilik voucher random yang boleh memakainya.
drop function if exists public.preview_voucher(text,numeric,jsonb);
create or replace function public.preview_voucher(
  p_code text,p_subtotal numeric,p_items jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v public.vouchers%rowtype; v_discount numeric:=0; v_code text:=upper(trim(coalesce(p_code,'')));
begin
  if auth.uid() is null then raise exception 'Silakan login terlebih dahulu'; end if;
  select * into v from public.vouchers where code=v_code and is_active=true
    and (owner_user_id is null or owner_user_id=auth.uid())
    and now() between starts_at and expires_at and used_count<quota;
  if not found then raise exception 'Voucher tidak valid, belum aktif, berakhir, atau kuota habis'; end if;
  if p_subtotal is null or p_subtotal<0 then raise exception 'Subtotal tidak valid'; end if;
  if p_subtotal<v.min_purchase then raise exception 'Minimal transaksi voucher adalah %',v.min_purchase; end if;
  if not public.voucher_scope_matches(v,p_items) then raise exception 'Voucher tidak berlaku untuk isi keranjang ini'; end if;
  if v.once_per_customer and exists(select 1 from public.orders o where o.user_id=auth.uid() and o.voucher_code=v.code and o.status not in ('cancelled','failed','refunded')) then
    raise exception 'Voucher hanya dapat digunakan satu kali per pelanggan';
  end if;
  v_discount:=case when v.discount_type='percent' then p_subtotal*(v.discount_value/100) else v.discount_value end;
  if v.max_discount is not null then v_discount:=least(v_discount,v.max_discount); end if;
  v_discount:=least(v_discount,p_subtotal);
  return jsonb_build_object('id',v.id,'code',v.code,'discount_type',v.discount_type,'discount_value',v.discount_value,'discount',v_discount,'total',p_subtotal-v_discount);
end;
$$;
revoke all on function public.preview_voucher(text,numeric,jsonb) from public;
grant execute on function public.preview_voucher(text,numeric,jsonb) to authenticated;

-- Validasi owner voucher juga di checkout final.
-- Jalankan ulang fungsi create_order dari JUAL-SEWA-INVENTORY-FINAL.sql setelah
-- menambahkan kondisi owner_user_id, atau gunakan patch berikut pada database:
-- update voucher validation query agar memakai:
-- and (owner_user_id is null or owner_user_id=auth.uid());

-- Backfill order lama yang sudah berhasil tetapi belum pernah mendapat reward coin.
-- Coin dihitung dari order_items fulfillment rental/sale dengan persentase acak sesuai coin_settings (default 10%..100%) dan 1 coin = Rp1.000.
do $$
declare r record; begin
  for r in select id from public.orders o
    where (o.status in ('paid','completed') or coalesce(o.payment_status,'')='paid')
      and not exists(select 1 from public.coin_transactions ct where ct.order_id=o.id and ct.type='order_reward')
  loop
    perform public.award_order_coins(r.id);
  end loop;
end $$;
notify pgrst,'reload schema';
