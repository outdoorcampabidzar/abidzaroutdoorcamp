-- OPTIONAL: data uji untuk memastikan perpindahan mode benar-benar terlihat.
-- Tidak perlu dijalankan pada production jika Anda tidak ingin mengubah item bernama "test".
-- Setelah dijalankan: mode Sewa = Rp1.000, mode Jual = Rp5.000.

update public.items
set
  price = 1000,
  sale_price = 5000,
  rental_enabled = true,
  sale_enabled = true
where lower(trim(title)) = 'test';

update public.site_settings
set settings = settings || jsonb_build_object(
  'payment_method_rental', 'qrisorkut',
  'payment_method_sale', 'qrisdana'
), updated_at = now()
where id = 'main';

-- Untuk gateway BTZPay yang benar-benar berbeda, gunakan secret Edge Function:
-- BTZPAY_API_KEY_RENTAL untuk mode Sewa
-- BTZPAY_API_KEY_SALE   untuk mode Jual
-- Jika keduanya kosong, BTZPAY_API_KEY dipakai sebagai fallback.
