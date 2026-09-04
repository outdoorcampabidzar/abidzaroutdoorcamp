# AbidzarOutdoorcamp — FINAL FIX

Paket ini memperbaiki bagian-bagian utama yang sebelumnya saling bertabrakan.

## Yang diperbaiki

1. **Gacha Voucher memakai bobot/probabilitas per voucher**
   - Setiap voucher memiliki `gacha_rarity` dan `gacha_probability`.
   - Default contoh: Common 60%, Uncommon 25%, Rare 10%, Epic 4%, Legendary 1%.
   - Bobot dapat diubah admin pada menu Voucher.
   - Random ditentukan di database, bukan browser.

2. **Voucher sumber Gacha auto-delete ketika kuota habis**
   - Voucher 1/1 akan hilang setelah hadiah berhasil dibuat.
   - Riwayat penukaran tetap tersimpan melalui `voucher_code` dan `shop_redemptions`.
   - FK riwayat memakai `ON DELETE SET NULL`.

3. **Voucher hasil Gacha benar-benar milik pelanggan**
   - Kode menggunakan prefix `AOC-`.
   - Hanya akun pemilik voucher yang dapat menggunakannya.
   - Voucher hasil Gacha memiliki kuota 1.

4. **Stok Coin Shop diperbaiki**
   - `stock = 0` berarti unlimited, sesuai tampilan admin.
   - `stock > 0` berkurang satu setiap redemption.
   - Saldo coin dan redemption diproses atomik di database.

5. **Mode Jual vs Sewa tetap dipisahkan**
   - Harga jual memakai `sale_price`.
   - Harga sewa memakai harga harian/paket sewa.
   - Keranjang tidak boleh mencampur Jual + Sewa.
   - API key BTZPay dapat berbeda per mode.

6. **BTZPay Edge Function diperbaiki**
   - Sebelumnya frontend memakai `action=create/check/cancel/recreate`, sementara Edge Function membaca URL path yang berbeda.
   - Sekarang action frontend dan Edge Function konsisten.
   - Edge Function memakai tabel `payment_transactions` yang memang dibuat oleh SQL paket.
   - Total memakai `orders.total`, bukan kolom `total_amount` yang tidak tersedia di schema order.
   - Callback webhook tidak langsung dipercaya: status diverifikasi ulang ke BTZPay sebelum diterapkan.
   - Cron expiry diamankan dengan `x-cron-secret`.

7. **Keamanan Coin/Voucher**
   - Tetap jalankan `access-security.sql` PALING AKHIR.
   - Customer tidak boleh mengubah saldo coin, transaksi coin, atau voucher admin secara langsung.
   - Fungsi internal pemberian coin hanya untuk `service_role`.

## Urutan instalasi database

Jika database sudah memakai paket sebelumnya, **backup dahulu**.

1. Jalankan `voucher-management.sql`.
2. Jalankan `coin-shop.sql` versi dari paket FINAL ini.
3. Jalankan `rental-calendar.sql`.
4. Jalankan `JUAL-SEWA-INVENTORY-FINAL.sql`.
5. Jalankan `btzpay-payment.sql`.
6. Jalankan `order-management.sql` bila fitur tersebut dipakai pada instalasi Anda.
7. Jalankan `order-cleanup.sql` bila sebelumnya memang digunakan.
8. Jalankan `access-security.sql` **PALING AKHIR**.

`PATCH-GACHA-QUOTA.sql` di paket ini sudah dibuat kompatibel dan tidak lagi menimpa fungsi Gacha versi baru. Jika `coin-shop.sql` FINAL sudah dijalankan, patch tersebut tidak wajib dijalankan.

## Edge Function BTZPay

Deploy ulang:

```bash
supabase functions deploy btzpay --no-verify-jwt
```

Secrets:

- `BTZPAY_API_KEY`
- `BTZPAY_API_KEY_RENTAL` (opsional)
- `BTZPAY_API_KEY_SALE` (opsional)
- `PUBLIC_SITE_URL`
- `BTZPAY_CRON_SECRET`

Untuk gateway berbeda per mode:

- Sewa → `BTZPAY_API_KEY_RENTAL`
- Jual → `BTZPAY_API_KEY_SALE`
- Jika kosong → fallback `BTZPAY_API_KEY`

## Cron expiry

Panggil setiap menit:

```text
GET https://PROJECT_REF.supabase.co/functions/v1/btzpay/check-expiry
x-cron-secret: NILAI_BTZPAY_CRON_SECRET
```

## Pengaturan probabilitas

Contoh yang disediakan:

| Rarity | Bobot |
|---|---:|
| Common | 60% |
| Uncommon | 25% |
| Rare | 10% |
| Epic | 4% |
| Legendary | 1% |

Bobot adalah **per voucher yang tampil di papan Gacha**, sehingga hasil dihitung secara proporsional terhadap voucher yang tersedia di papan tersebut.

## Catatan penting

Setelah deploy, lakukan test kecil:

- Buat voucher template kuota `1`.
- Atur rarity/probabilitas.
- Tukar Coin Shop sekali.
- Pastikan voucher hasil berawalan `AOC-`.
- Pastikan template 1/1 hilang dari daftar voucher.
- Pastikan riwayat redemption masih terlihat.
- Coba gunakan voucher dari akun lain: harus ditolak.
- Test item Jual dan Sewa secara terpisah dan pastikan harga/gateway berbeda.
- Test pembayaran sandbox/nominal kecil sebelum produksi.
