-- AOC V47 - FULL FIX RENTAL 28 JAM
-- 1) Allow status 'rented'
-- 2) Start 28-hour timer only when goods are actually picked up
-- 3) Clear invalid due times for rentals that have not started

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_status_check
CHECK (status = ANY (ARRAY[
  'pending'::text,
  'confirmed'::text,
  'paid'::text,
  'rented'::text,
  'completed'::text,
  'returned'::text,
  'cancelled'::text
]));

CREATE OR REPLACE FUNCTION public.aoc_set_rental_due_at()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare
  v_days integer;
  v_start timestamptz;
begin
  -- 28 jam hanya dimulai ketika status sudah DISEWA dan waktu pickup tercatat.
  if new.status <> 'rented' OR new.rental_start_at IS NULL then
    new.rental_due_at := NULL;
    new.rental_end_at := NULL;
    return new;
  end if;

  v_days := greatest(coalesce(new.rental_days,1),1);
  v_start := new.rental_start_at;
  new.rental_due_at := v_start + (v_days * interval '28 hours');
  new.rental_end_at := new.rental_due_at;
  new.rental_start := (v_start AT TIME ZONE 'Asia/Jakarta')::date;
  new.rental_end := (new.rental_due_at AT TIME ZONE 'Asia/Jakarta')::date;
  return new;
end;
$$;

UPDATE public.orders
SET rental_due_at = NULL,
    rental_end_at = NULL
WHERE status <> 'rented';

DROP TRIGGER IF EXISTS orders_rental_due_at_trigger ON public.orders;
CREATE TRIGGER orders_rental_due_at_trigger
BEFORE INSERT OR UPDATE OF status, rental_days, rental_start_at, rental_end_at
ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.aoc_set_rental_due_at();

-- Verifikasi cepat:
-- select order_number,status,rental_start_at,rental_due_at from public.orders order by created_at desc limit 10;
