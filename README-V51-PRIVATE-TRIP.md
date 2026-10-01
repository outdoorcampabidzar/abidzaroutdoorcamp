# AOC V51 — Private Trip

Fitur baru:
- Kategori Travel: `Travel` dan `Private Trip`.
- Private Trip hanya dibuat/dikelola melalui Admin Panel > Travel.
- Admin Travel tetap wajib memiliki izin `travel.manage` dan verifikasi PIN Admin untuk membuat/mengubah/menghapus paket.
- Halaman customer Travel memiliki filter Semua / Travel / Private Trip.
- Harga tetap dihitung dan ditampilkan per paket, bukan per orang.

## Database
Jalankan `PRIVATE-TRIP-MIGRATION.sql` jika database belum menerima migration `add_private_trip_category`.
