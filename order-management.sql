-- AbidzarOutdoorcamp - Manajemen pesanan lanjutan
-- Jalankan setelah rental-calendar.sql dan btzpay-payment.sql.

alter table public.orders add column if not exists cancellation_reason text;
alter table public.orders add column if not exists cancelled_at timestamptz;
alter table public.orders add column if not exists late_fee numeric(14,2) not null default 0;
alter table public.orders add column if not exists deposit_amount numeric(14,2) not null default 0;
alter table public.orders add column if not exists deposit_status text not null default 'none'
  check (deposit_status in ('none','expected','received','partially_returned','returned','forfeited'));
alter table public.orders add column if not exists deposit_received_at timestamptz;
alter table public.orders add column if not exists deposit_returned_at timestamptz;
alter table public.orders add column if not exists returned_at timestamptz;
alter table public.orders add column if not exists return_condition text;
alter table public.orders add column if not exists inspection_notes text;

create table if not exists public.order_status_history (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  old_status text,
  new_status text not null,
  note text,
  changed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.order_refunds (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  payment_transaction_id uuid references public.payment_transactions(id) on delete set null,
  amount numeric(14,2) not null check (amount > 0),
  refund_type text not null check (refund_type in ('full','partial')),
  reason text not null,
  status text not null default 'recorded' check (status in ('recorded','processed','failed')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.order_returns (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  item_id uuid references public.items(id) on delete set null,
  quantity integer not null default 1 check (quantity > 0),
  condition text not null check (condition in ('good','dirty','damaged','lost')),
  fee numeric(14,2) not null default 0,
  notes text,
  inspected_by uuid references auth.users(id) on delete set null,
  inspected_at timestamptz not null default now()
);

create index if not exists order_history_order_idx on public.order_status_history(order_id, created_at desc);
create index if not exists order_refunds_order_idx on public.order_refunds(order_id, created_at desc);
create index if not exists order_returns_order_idx on public.order_returns(order_id, inspected_at desc);

alter table public.order_status_history enable row level security;
alter table public.order_refunds enable row level security;
alter table public.order_returns enable row level security;
drop policy if exists "order history admin read" on public.order_status_history;
create policy "order history admin read" on public.order_status_history for select using (public.is_admin());
drop policy if exists "refund admin read" on public.order_refunds;
create policy "refund admin read" on public.order_refunds for select using (public.is_admin());
drop policy if exists "return admin read" on public.order_returns;
create policy "return admin read" on public.order_returns for select using (public.is_admin());
grant select on public.order_status_history, public.order_refunds, public.order_returns to authenticated;

create or replace function public.log_order_status_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or old.status is distinct from new.status then
    insert into public.order_status_history(order_id,old_status,new_status,note,changed_by)
    values (new.id,case when tg_op='INSERT' then null else old.status end,new.status,new.admin_notes,auth.uid());
  end if;
  return new;
end; $$;
drop trigger if exists orders_status_history_trigger on public.orders;
create trigger orders_status_history_trigger after insert or update of status on public.orders
for each row execute function public.log_order_status_change();

insert into public.order_status_history(order_id,old_status,new_status,note,created_at)
select o.id,null,o.status,'Riwayat awal',o.created_at from public.orders o
where not exists (select 1 from public.order_status_history h where h.order_id=o.id);

create or replace function public.admin_manage_order(
  p_order_id uuid,
  p_action text,
  p_amount numeric default null,
  p_reason text default null,
  p_condition text default null,
  p_item_id uuid default null,
  p_quantity integer default 1
) returns void language plpgsql security definer set search_path=public as $$
declare v_order public.orders%rowtype; v_payment_id uuid; v_refunded numeric;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;
  if p_action='cancel' then
    if nullif(trim(p_reason),'') is null then raise exception 'Alasan pembatalan wajib diisi'; end if;
    update public.orders set status='cancelled',cancellation_reason=trim(p_reason),cancelled_at=now() where id=p_order_id;
  elsif p_action='refund' then
    if coalesce(p_amount,0)<=0 then raise exception 'Nominal refund harus lebih dari 0'; end if;
    select coalesce(sum(amount),0) into v_refunded from public.order_refunds where order_id=p_order_id and status<>'failed';
    if v_refunded+p_amount>v_order.total then raise exception 'Total refund melebihi nilai pesanan'; end if;
    select id into v_payment_id from public.payment_transactions where order_id=p_order_id order by created_at desc limit 1;
    insert into public.order_refunds(order_id,payment_transaction_id,amount,refund_type,reason,status,created_by)
    values(p_order_id,v_payment_id,p_amount,case when v_refunded+p_amount>=v_order.total then 'full' else 'partial' end,coalesce(nullif(trim(p_reason),''),'Refund admin'),'recorded',auth.uid());
    if v_refunded+p_amount>=v_order.total then update public.orders set payment_status='refunded',status='cancelled' where id=p_order_id; end if;
  elsif p_action='late_fee' then
    update public.orders set late_fee=greatest(coalesce(p_amount,0),0) where id=p_order_id;
  elsif p_action='deposit_received' then
    update public.orders set deposit_amount=greatest(coalesce(p_amount,0),0),deposit_status='received',deposit_received_at=now() where id=p_order_id;
  elsif p_action='deposit_returned' then
    update public.orders set deposit_status='returned',deposit_returned_at=now() where id=p_order_id;
  elsif p_action='return' then
    if p_condition not in ('good','dirty','damaged','lost') then raise exception 'Kondisi pengembalian tidak valid'; end if;
    insert into public.order_returns(order_id,item_id,quantity,condition,fee,notes,inspected_by)
    values(p_order_id,p_item_id,greatest(coalesce(p_quantity,1),1),p_condition,greatest(coalesce(p_amount,0),0),nullif(trim(p_reason),''),auth.uid());
    update public.orders set returned_at=now(),return_condition=p_condition,inspection_notes=nullif(trim(p_reason),''),late_fee=late_fee+greatest(coalesce(p_amount,0),0) where id=p_order_id;
  else raise exception 'Aksi tidak dikenal'; end if;
end; $$;
revoke all on function public.admin_manage_order(uuid,text,numeric,text,text,uuid,integer) from public;
grant execute on function public.admin_manage_order(uuid,text,numeric,text,text,uuid,integer) to authenticated;
