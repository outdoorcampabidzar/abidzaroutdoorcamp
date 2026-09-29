-- V46: 28 jam dihitung hanya dari waktu barang benar-benar diambil.
CREATE OR REPLACE FUNCTION public.aoc_set_rental_due_at()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare v_days integer; v_start timestamptz;
begin
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
UPDATE public.orders SET rental_due_at=NULL, rental_end_at=NULL WHERE status <> 'rented';
DROP TRIGGER IF EXISTS orders_rental_due_at_trigger ON public.orders;
CREATE TRIGGER orders_rental_due_at_trigger
BEFORE INSERT OR UPDATE OF status, rental_days, rental_start_at, rental_end_at
ON public.orders FOR EACH ROW EXECUTE FUNCTION public.aoc_set_rental_due_at();
