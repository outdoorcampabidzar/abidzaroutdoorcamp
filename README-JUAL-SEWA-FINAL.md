# AbidzarOutdoorcamp — Jual + Sewa (Final)

Paket ini sudah dirapikan untuk deployment.

## Struktur utama
- `index.html` — beranda
- `rental.html` — katalog sewa
- `sale.html` — katalog jual
- `item.html` — detail item + pilihan mode
- `cart.html` — keranjang + checkout
- `payment.html` — pembayaran
- `admin.html` — panel admin
- `supabase/` — konfigurasi dan Edge Function pembayaran

## SQL
Gunakan `sql/BACKUP-SELURUH-DATABASE.sql` sebagai backup/recovery database yang sudah ada.

Untuk perubahan sistem JUAL + SEWA, jalankan:
1. `rental-calendar.sql`
2. `order-management.sql`
3. `btzpay-payment.sql`
4. `JUAL-SEWA-INVENTORY-FINAL.sql`
5. `access-security.sql`

File SQL lain yang merupakan salinan lama/backup dihapus dari paket deployment agar tidak salah dijalankan dua kali.

## Perbaikan utama
- Ketersediaan rental memakai **peak overlap**, bukan menjumlahkan semua booking yang tidak selalu bentrok.
- Pembayaran SALE melakukan **re-check stok + komitmen rental** sebelum stok dipotong.
- Order `pending` baru mendapat masa reservasi 30 menit untuk perhitungan ketersediaan.
- Harga invoice rental mengikuti **paket durasi/price tier** yang sama dengan server.
- Mode **Jual dan Sewa memakai harga, fulfillment, dan gateway pembayaran yang terpisah**. Keranjang menolak campuran Jual + Sewa agar gateway tidak ambigu.
- Payment gateway dapat memakai API key BTZPay berbeda: `BTZPAY_API_KEY_SALE` dan `BTZPAY_API_KEY_RENTAL`, dengan `BTZPAY_API_KEY` sebagai fallback.
- SQL duplikat dan arsip ZIP bertingkat dihapus dari paket deployment.
