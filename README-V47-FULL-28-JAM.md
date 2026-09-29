# AOC V47 — Full Fix Rental 28 Jam

## Perbaikan
- Status `rented`/`Disewa` sekarang diizinkan oleh database.
- Tombol `📦 Barang Diambil / Mulai Sewa` mengubah pesanan dari `paid` menjadi `rented`.
- Waktu mulai dicatat oleh server pada saat barang benar-benar diambil.
- Durasi 1 hari = 28 jam penuh sejak waktu pengambilan.
- `rental_due_at` tidak dihitung dari tanggal jam 00:00.
- Pesanan yang belum diambil tidak memiliki countdown palsu/terlambat.
- Stok/unit rental mengikuti status `rented`.
- PIN Admin tetap diminta sebelum perubahan status rental.

## Contoh
Jika barang diambil 29/09 pukul 17:00:

`17:00 + 28 jam = 30/09 pukul 21:00`

## Upload
Upload seluruh isi ZIP ke hosting/GitHub Pages, termasuk `admin-bundle-v46.js` dan file lainnya.

Database project AOC yang digunakan pada pekerjaan ini juga sudah diperbaiki. File SQL `DATABASE-V47-28-JAM-RENTAL-FULL-FIX.sql` disertakan sebagai backup/migrasi untuk project yang sama atau deployment baru.
