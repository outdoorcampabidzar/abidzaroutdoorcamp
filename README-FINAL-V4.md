# AbidzarOutdoorcamp — FINAL V4

Bundle ini merapikan fondasi sistem **Jual + Sewa + Multi Toko**.

## Perbaikan utama

### 1. Mode Jual / Sewa
- `fulfillment_type` menjadi sumber kebenaran server-side.
- Harga jual memakai `items.sale_price`.
- Harga sewa memakai `item_price_tiers` bila tersedia, lalu fallback ke harga sewa × hari.
- Checkout tidak mempercayai harga dari browser; harga dihitung ulang di database.
- Satu order **tidak boleh mencampur produk Jual dan Sewa**. Open Trip tetap dapat digabung sesuai alur sebelumnya.

### 2. Stok Multi Toko
- Ketersediaan katalog dan checkout menggunakan stok toko yang dipilih.
- Reservation rental hanya mengurangi ketersediaan rental pada toko yang sama.
- Sale hanya memotong stok lokasi pesanan saat status `paid`.
- Pembatalan sale setelah `paid` mengembalikan stok ke lokasi asal.
- Rental **tidak mengurangi stok fisik**.
- `items.stock` dan `item_variants.stock` hanya menjadi total agregat seluruh toko.

### 3. Mencegah double stock deduction
- Trigger stok rental lama dinonaktifkan.
- Trigger sale lama yang berpotensi bertabrakan dinonaktifkan.
- Hanya `aoc_final_sale_stock_trigger` yang menangani stok fisik sale.
- Baris stok lokasi dikunci saat pembayaran untuk mencegah dua pembayaran bersamaan mengurangi stok yang sama.

### 4. Checkout
- Validasi stok server-side tetap dilakukan.
- Lokasi checkout disinkronkan sebelum `create_order`.
- Harga snapshot dibuat oleh server.
- Mode pembayaran mengikuti mode transaksi.

## Urutan SQL FINAL

Jalankan di Supabase SQL Editor **berurutan**:

1. `order-management.sql`
2. `rental-calendar.sql`
3. `stock-lifecycle.sql`
4. `MULTI-LOKASI-STOCK.sql`
5. `JUAL-SEWA-INVENTORY-FINAL.sql`
6. Patch fitur lain yang memang digunakan:
   - `voucher-management.sql`
   - `PATCH-KODE-VOUCHER-AOC.sql`
   - `btzpay-payment.sql`
   - `PATCH-PHASE-2-BTZPAY.sql`
   - `PATCH-RENTAL-REMINDER-28H-4H-FEE100.sql`
   - `PATCH-BULK-RETURN-INSPECTION.sql`
   - `PATCH-RENTAL-ADMIN-WORKFLOW.sql`
   - `catalog-management.sql`
   - `site-settings.sql`
   - `profile-avatar.sql`
   - `site-logo-storage.sql`
   - `customer-review-notification.sql`
   - `website-comment-rpc-v2.sql`
   - `preserve-rating-comment.sql`
   - `coin-shop.sql`
   - `SECURITY-HARDENING-COIN.sql`
   - `PATCH-GACHA-QUOTA.sql`
   - `PATCH-GACHA-AUTO-DELETE-USED.sql`
   - `open-trip-management.sql`
   - `order-cleanup.sql`
7. `access-security.sql`
8. `PATCH-AUTH-LOGIN-DAN-AKTIVASI-KODE-6-DIGIT.sql`
9. **Terakhir:** `AOC-FINAL-FIX.sql`

> `AOC-FINAL-FIX.sql` wajib dijalankan paling akhir karena mengunci fungsi stok final dan menonaktifkan trigger stok lama yang bertabrakan.

## Setelah SQL

1. Supabase → refresh/reload schema.
2. Logout dari website.
3. Login ulang.
4. Pilih Toko 1 / Toko 2.
5. Tes item yang mempunyai **Sewa + Jual**.
6. Tes perubahan mode di halaman detail item.
7. Tes rental dengan tanggal yang bentrok.
8. Tes sale sampai `paid`.
9. Tes pembatalan sale setelah `paid`.
10. Tes return rental dan pastikan stok fisik tidak bertambah dua kali.

## Catatan

SQL ini tidak dapat mengubah data Supabase yang sedang berjalan hanya dengan mengganti ZIP. Setelah ZIP diunggah ke hosting, SQL di atas tetap harus dijalankan pada project Supabase yang digunakan website.
