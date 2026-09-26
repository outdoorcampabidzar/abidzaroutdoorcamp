-- AOC - RESET OMZET PERMANEN 2 LANGKAH
-- PERINGATAN: reset ini benar-benar menghapus pesanan yang membentuk omzet
-- pada rentang/toko yang dipilih. Riwayat order tersebut ikut hilang karena
-- tabel anak menggunakan ON DELETE CASCADE. Voucher usage dihapus lebih dulu
-- karena relasinya ON DELETE RESTRICT.

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
  on public.finance_reset_challenges for all to authenticated
  using (public.has_permission('finance.manage') or public.has_permission('*'))
  with check (public.has_permission('finance.manage') or public.has_permission('*'));

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
  on public.finance_reset_audit for select to authenticated
  using (public.has_permission('finance.manage') or public.has_permission('*'));

grant select on public.finance_reset_audit to authenticated;

create or replace function public.begin_finance_reset(
  p_range_key text,
  p_location_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
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
  if v_user is null then raise exception 'Login admin diperlukan'; end if;
  if not (public.has_permission('finance.manage') or public.has_permission('*')) then
    raise exception 'Izin keuangan diperlukan';
  end if;
  if p_range_key not in ('today','7d','month','30d','all') then
    raise exception 'Rentang reset tidak valid';
  end if;

  if p_range_key = 'today' then
    v_start := date_trunc('day', now());
  elsif p_range_key = '7d' then
    v_start := date_trunc('day', now()) - interval '6 days';
  elsif p_range_key = 'month' then
    v_start := date_trunc('month', now());
  elsif p_range_key = '30d' then
    v_start := date_trunc('day', now()) - interval '29 days';
  else
    v_start := '2000-01-01'::timestamptz;
  end if;

  select count(*)::integer,
         coalesce(sum(o.total + coalesce(o.late_fee,0) - coalesce((select sum(r.amount) from public.order_refunds r where r.order_id=o.id and r.status <> 'failed'),0)),0)::numeric(14,2)
    into v_count, v_net
  from public.orders o
  where o.status in ('paid','returned','completed')
    and (p_location_id is null or o.location_id = p_location_id)
    and coalesce(o.paid_at,o.created_at) >= v_start
    and coalesce(o.paid_at,o.created_at) <= v_end;

  insert into public.finance_reset_challenges(id,user_id,range_key,location_id,code,order_count,net_amount,expires_at)
  values(v_id,v_user,p_range_key,p_location_id,v_code,v_count,v_net,now()+interval '5 minutes');

  return jsonb_build_object(
    'challenge_id', v_id,
    'code', v_code,
    'order_count', v_count,
    'net_amount', v_net,
    'expires_at', now()+interval '5 minutes'
  );
end;
$$;

create or replace function public.execute_finance_reset(
  p_challenge_id uuid,
  p_code text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ch public.finance_reset_challenges%rowtype;
  v_ids uuid[];
  v_deleted integer := 0;
  v_amount numeric(14,2) := 0;
  v_start timestamptz;
  v_end timestamptz := now();
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Login admin diperlukan'; end if;
  if not (public.has_permission('finance.manage') or public.has_permission('*')) then
    raise exception 'Izin keuangan diperlukan';
  end if;

  select * into v_ch
  from public.finance_reset_challenges
  where id=p_challenge_id and user_id=v_user
  for update;
  if not found then raise exception 'Verifikasi reset tidak ditemukan'; end if;
  if v_ch.used_at is not null then raise exception 'Kode reset sudah digunakan'; end if;
  if v_ch.expires_at < now() then raise exception 'Kode reset sudah kedaluwarsa'; end if;
  if v_ch.code <> trim(coalesce(p_code,'')) then raise exception 'Kode verifikasi salah'; end if;

  if v_ch.range_key = 'today' then
    v_start := date_trunc('day', now());
  elsif v_ch.range_key = '7d' then
    v_start := date_trunc('day', now()) - interval '6 days';
  elsif v_ch.range_key = 'month' then
    v_start := date_trunc('month', now());
  elsif v_ch.range_key = '30d' then
    v_start := date_trunc('day', now()) - interval '29 days';
  else
    v_start := '2000-01-01'::timestamptz;
  end if;

  select array_agg(o.id), count(*)::integer,
         coalesce(sum(o.total + coalesce(o.late_fee,0) - coalesce((select sum(r.amount) from public.order_refunds r where r.order_id=o.id and r.status <> 'failed'),0)),0)::numeric(14,2)
    into v_ids, v_deleted, v_amount
  from public.orders o
  where o.status in ('paid','returned','completed')
    and (v_ch.location_id is null or o.location_id = v_ch.location_id)
    and coalesce(o.paid_at,o.created_at) >= v_start
    and coalesce(o.paid_at,o.created_at) <= v_end;

  if coalesce(array_length(v_ids,1),0) > 0 then
    delete from public.voucher_usages where order_id = any(v_ids);
    delete from public.orders where id = any(v_ids);
  end if;

  update public.finance_reset_challenges set used_at=now() where id=v_ch.id;

  insert into public.finance_reset_audit(user_id,range_key,location_id,deleted_order_count,deleted_net_amount)
  values(v_user,v_ch.range_key,v_ch.location_id,coalesce(v_deleted,0),coalesce(v_amount,0));

  return jsonb_build_object('deleted_order_count',coalesce(v_deleted,0),'deleted_net_amount',coalesce(v_amount,0));
end;
$$;

revoke all on function public.begin_finance_reset(text,uuid) from public;
revoke all on function public.execute_finance_reset(uuid,text) from public;
grant execute on function public.begin_finance_reset(text,uuid) to authenticated;
grant execute on function public.execute_finance_reset(uuid,text) to authenticated;

notify pgrst, 'reload schema';
