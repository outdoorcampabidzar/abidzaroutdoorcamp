-- AOC RESET OMZET V28 - FINAL PIN TRIGGER FIX
--
-- Tujuan:
-- 1. PIN transaksi hanya berlaku ketika CUSTOMER membuat order (INSERT).
-- 2. PIN transaksi TIDAK BOLEH memblokir DELETE saat Admin melakukan Reset Omzet.
-- 3. Menghapus trigger DELETE lama yang function-nya berisi guard PIN transaksi,
--    termasuk trigger pada tabel terkait yang ikut terhapus saat order dihapus.
-- 4. Menyediakan RPC V28 yang dipanggil langsung oleh admin-bundle-v28.js.
--
-- Jalankan file ini SEKALI di Supabase SQL Editor.

create table if not exists public.finance_reset_challenges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  range_key text not null check (range_key in ('today','7d','month','30d','all')),
  location_id uuid,
  code text not null,
  order_count integer not null default 0,
  net_amount numeric(14,2) not null default 0,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '5 minutes'),
  used_at timestamptz
);

create index if not exists finance_reset_challenges_user_idx
  on public.finance_reset_challenges(user_id, created_at desc);

alter table public.finance_reset_challenges enable row level security;
drop policy if exists "finance reset challenge admin" on public.finance_reset_challenges;
create policy "finance reset challenge admin"
on public.finance_reset_challenges
for all to authenticated
using (public.is_admin() or public.has_permission('finance.manage') or public.has_permission('*'))
with check (public.is_admin() or public.has_permission('finance.manage') or public.has_permission('*'));

create table if not exists public.finance_reset_audit (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete set null,
  range_key text not null,
  location_id uuid,
  deleted_order_count integer not null default 0,
  deleted_net_amount numeric(14,2) not null default 0,
  created_at timestamptz not null default now()
);

alter table public.finance_reset_audit enable row level security;
drop policy if exists "finance reset audit admin read" on public.finance_reset_audit;
create policy "finance reset audit admin read"
on public.finance_reset_audit
for select to authenticated
using (public.is_admin() or public.has_permission('finance.manage') or public.has_permission('*'));
grant select on public.finance_reset_audit to authenticated;

-- ============================================================
-- 1) REMOVE LEGACY DELETE PIN GUARDS
-- ============================================================
-- Jangan hanya memeriksa public.orders. Error PIN bisa berasal dari trigger
-- pada tabel anak yang ikut diproses ketika order dihapus.
--
-- pg_trigger.tgtype bit 8 = DELETE event.
-- Hanya trigger DELETE yang function-nya secara eksplisit berisi guard PIN
-- transaksi yang dibuang. Trigger INSERT untuk customer akan dibuat ulang di
-- bawah sehingga checkout tetap terlindungi.

do $$
declare
  r record;
begin
  for r in
    select
      n.nspname as schema_name,
      c.relname as table_name,
      tg.tgname as trigger_name,
      p.oid as function_oid,
      p.proname as function_name,
      pg_get_functiondef(p.oid) as function_def
    from pg_trigger tg
    join pg_class c on c.oid = tg.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_proc p on p.oid = tg.tgfoid
    join pg_namespace pn on pn.oid = p.pronamespace
    where n.nspname = 'public'
      and pn.nspname = 'public'
      and not tg.tgisinternal
      and (tg.tgtype & 8) <> 0
      and (
        pg_get_functiondef(p.oid) ilike '%PIN transaksi wajib diverifikasi%'
        or p.proname ilike '%transaction%pin%'
        or tg.tgname ilike '%transaction%pin%'
        or tg.tgname ilike '%pin%'
      )
  loop
    raise notice 'Removing legacy DELETE PIN trigger: %.% on %.%',
      r.schema_name, r.trigger_name, r.schema_name, r.table_name;
    execute format(
      'drop trigger if exists %I on %I.%I',
      r.trigger_name, r.schema_name, r.table_name
    );
  end loop;
end $$;

-- ============================================================
-- 2) CORRECT CUSTOMER TRANSACTION-PIN FUNCTION
-- ============================================================
create or replace function public.aoc_require_transaction_pin_for_customer_order()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_user_id uuid := auth.uid();
  v_verified boolean := false;
begin
  -- PIN transaksi hanya untuk CUSTOMER ketika membuat order baru.
  -- UPDATE dan DELETE tidak pernah meminta PIN dari trigger ini.
  if TG_OP <> 'INSERT' then
    if TG_OP = 'DELETE' then
      return OLD;
    end if;
    return NEW;
  end if;

  -- Admin/staff tidak perlu PIN transaksi untuk operasi administratif.
  if public.is_admin()
     or public.has_permission('orders.manage')
     or public.has_permission('*') then
    return NEW;
  end if;

  if v_user_id is null then
    raise exception 'Silakan login terlebih dahulu.';
  end if;

  select exists (
    select 1
    from private.aoc_transaction_pin_sessions s
    where s.user_id = v_user_id
      and s.verified_until > now()
  ) into v_verified;

  if not v_verified then
    raise exception 'PIN transaksi wajib diverifikasi sebelum membuat pesanan.';
  end if;

  delete from private.aoc_transaction_pin_sessions
  where user_id = v_user_id;

  return NEW;
end;
$$;

drop trigger if exists aoc_require_transaction_pin on public.orders;
create trigger aoc_require_transaction_pin
before insert on public.orders
for each row
execute function public.aoc_require_transaction_pin_for_customer_order();

-- ============================================================
-- 3) RESET START RPC
-- ============================================================
create or replace function public.aoc_reset_omzet_v28_start(
  p_range_key text,
  p_location_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_user uuid := auth.uid();
  v_code text := lpad((floor(random()*1000000))::bigint::text, 6, '0');
  v_id uuid := gen_random_uuid();
  v_start timestamptz;
  v_end timestamptz := now();
  v_count integer;
  v_net numeric(14,2);
begin
  if v_user is null then
    raise exception 'Login admin diperlukan';
  end if;

  if not (public.is_admin() or public.has_permission('finance.manage') or public.has_permission('*')) then
    raise exception 'Izin keuangan diperlukan';
  end if;

  if p_range_key not in ('today','7d','month','30d','all') then
    raise exception 'Rentang reset tidak valid';
  end if;

  if p_range_key='today' then
    v_start := date_trunc('day', now());
  elsif p_range_key='7d' then
    v_start := date_trunc('day', now()) - interval '6 days';
  elsif p_range_key='month' then
    v_start := date_trunc('month', now());
  elsif p_range_key='30d' then
    v_start := date_trunc('day', now()) - interval '29 days';
  else
    v_start := '2000-01-01'::timestamptz;
  end if;

  select
    count(*)::integer,
    coalesce(sum(
      coalesce(o.total,0)
      + coalesce(o.late_fee,0)
      - coalesce((
          select sum(r.amount)
          from public.order_refunds r
          where r.order_id=o.id
            and r.status<>'failed'
        ),0)
    ),0)::numeric(14,2)
  into v_count, v_net
  from public.orders o
  where o.status in ('paid','returned','completed')
    and (p_location_id is null or o.location_id=p_location_id)
    and coalesce(o.paid_at,o.created_at)>=v_start
    and coalesce(o.paid_at,o.created_at)<=v_end;

  insert into public.finance_reset_challenges(
    id,user_id,range_key,location_id,code,order_count,net_amount,expires_at
  ) values (
    v_id,v_user,p_range_key,p_location_id,v_code,v_count,v_net,now()+interval '5 minutes'
  );

  return jsonb_build_object(
    'challenge_id',v_id,
    'code',v_code,
    'order_count',v_count,
    'net_amount',v_net,
    'expires_at',now()+interval '5 minutes'
  );
end;
$$;

-- ============================================================
-- 4) RESET EXECUTE RPC
-- ============================================================
create or replace function public.aoc_reset_omzet_v28_execute(
  p_challenge_id uuid,
  p_code text
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  c public.finance_reset_challenges%rowtype;
  ids uuid[];
  uid uuid := auth.uid();
  s timestamptz;
  e timestamptz := now();
  oid uuid;
  n integer := 0;
  amt numeric(14,2) := 0;
  deleted_ids jsonb := '[]'::jsonb;
  fk record;
  child_sql text;
begin
  if uid is null then
    raise exception 'Login admin diperlukan';
  end if;

  if not (public.is_admin() or public.has_permission('finance.manage') or public.has_permission('*')) then
    raise exception 'Izin keuangan diperlukan';
  end if;

  select * into c
  from public.finance_reset_challenges
  where id=p_challenge_id
    and user_id=uid
  for update;

  if not found then
    raise exception 'Verifikasi reset tidak ditemukan';
  end if;

  if c.used_at is not null then
    raise exception 'Kode reset sudah digunakan';
  end if;

  if c.expires_at<now() then
    raise exception 'Kode reset sudah kedaluwarsa';
  end if;

  if c.code<>trim(coalesce(p_code,'')) then
    raise exception 'Kode verifikasi salah';
  end if;

  if c.range_key='today' then
    s := date_trunc('day',now());
  elsif c.range_key='7d' then
    s := date_trunc('day',now())-interval '6 days';
  elsif c.range_key='month' then
    s := date_trunc('month',now());
  elsif c.range_key='30d' then
    s := date_trunc('day',now())-interval '29 days';
  else
    s := '2000-01-01'::timestamptz;
  end if;

  select
    coalesce(array_agg(o.id),'{}'::uuid[]),
    count(*)::integer,
    coalesce(sum(
      coalesce(o.total,0)+coalesce(o.late_fee,0)
      -coalesce((select sum(r.amount) from public.order_refunds r where r.order_id=o.id and r.status<>'failed'),0)
    ),0)::numeric(14,2)
  into ids,n,amt
  from public.orders o
  where o.status in ('paid','returned','completed')
    and (c.location_id is null or o.location_id=c.location_id)
    and coalesce(o.paid_at,o.created_at)>=s
    and coalesce(o.paid_at,o.created_at)<=e;

  -- Hapus child rows yang memakai FK RESTRICT/NO ACTION terhadap orders.
  -- Trigger DELETE PIN lama sudah dibersihkan pada bagian 1.
  if coalesce(array_length(ids,1),0)>0 then
    for fk in
      select
        n.nspname as schema_name,
        cl.relname as table_name,
        att.attname as column_name,
        con.conname as constraint_name
      from pg_constraint con
      join pg_class cl on cl.oid=con.conrelid
      join pg_namespace n on n.oid=cl.relnamespace
      join pg_class parent on parent.oid=con.confrelid
      join pg_namespace pn on pn.oid=parent.relnamespace
      join lateral unnest(con.conkey) with ordinality ck(attnum,ord) on true
      join pg_attribute att on att.attrelid=cl.oid and att.attnum=ck.attnum
      where con.contype='f'
        and pn.nspname='public'
        and parent.relname='orders'
        and array_length(con.conkey,1)=1
        and array_length(con.confkey,1)=1
        and con.confdeltype in ('a','r')
        and n.nspname='public'
        and cl.relname<>'orders'
      order by cl.relname, con.conname
    loop
      child_sql := format(
        'delete from %I.%I where %I = any($1)',
        fk.schema_name,fk.table_name,fk.column_name
      );
      begin
        execute child_sql using ids;
      exception when others then
        raise exception
          'Gagal membersihkan data terkait pesanan pada %: %',
          fk.table_name,sqlerrm;
      end;
    end loop;

    foreach oid in array ids loop
      begin
        delete from public.orders where id=oid;
        if not found then
          raise exception 'Pesanan tidak ditemukan: %',oid;
        end if;
      exception when others then
        raise exception
          'Pesanan % gagal dihapus. Constraint/data terkait masih menghalangi penghapusan: %',
          oid,sqlerrm;
      end;
      deleted_ids := deleted_ids || jsonb_build_array(oid);
    end loop;
  end if;

  update public.finance_reset_challenges
  set used_at=now()
  where id=c.id;

  insert into public.finance_reset_audit(
    user_id,range_key,location_id,deleted_order_count,deleted_net_amount
  ) values (
    uid,c.range_key,c.location_id,n,amt
  );

  return jsonb_build_object(
    'success',true,
    'deleted_order_count',n,
    'deleted_net_amount',amt,
    'deleted_order_ids',deleted_ids
  );
end;
$$;

revoke all on function public.aoc_reset_omzet_v28_start(text,uuid) from public;
revoke all on function public.aoc_reset_omzet_v28_execute(uuid,text) from public;
grant execute on function public.aoc_reset_omzet_v28_start(text,uuid) to authenticated;
grant execute on function public.aoc_reset_omzet_v28_execute(uuid,text) to authenticated;

notify pgrst,'reload schema';
