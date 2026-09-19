# AOC Clean Final — 18 September 2026

Paket ini adalah versi runtime yang sudah dibersihkan dari file lama/duplikat yang tidak direferensikan oleh website.

## Perubahan utama
- Konfirmasi hapus pesanan memakai modal modern, bukan `window.confirm()`.
- Menampilkan kode order, customer, dan status.
- Tombol `Hapus Pesanan` berwarna merah dan khusus aksi berbahaya.
- Semua pesanan dapat dihapus melalui RPC `admin_delete_order` sesuai permission Super Admin.
- Tombol hapus rental memakai modal yang sama.
- Cache `admin.js` dinaikkan ke versi 202609181600.

## SQL hapus pesanan
Jalankan sekali:

`PATCH-HAPUS-SEMUA-JENIS-PESANAN.sql`

Patch lama `PATCH-HAPUS-PESANAN-RENTAL.sql` sudah dihapus dari paket karena digantikan oleh patch semua jenis.

## Instalasi website
1. Backup database dan folder website.
2. Upload isi folder `src` ke website.
3. Pertahankan `config.js` milik project jika URL/anon key Supabase sudah benar.
4. Jalankan SQL yang memang diperlukan oleh instalasi project. Untuk fitur hapus, jalankan `PATCH-HAPUS-SEMUA-JENIS-PESANAN.sql`.
5. Logout/login kembali dan lakukan hard refresh untuk memastikan `admin.js?v=202609181600` termuat.

## File yang sengaja dibersihkan
- Script lama yang tidak direferensikan: `script0.js`, `test.js`, `simple-cart-direct.js`.
- Patch finalisasi lama dan patch hapus rental lama yang sudah superseded.
- README/patch dokumentasi historis yang hanya merujuk ke versi lama.

File SQL fitur aktif lainnya tetap dipertahankan agar instalasi fitur AOC yang sudah ada tidak kehilangan dependensi.


--- STOCK EDITOR SYNC FIX ---
Stok pada form Edit Sewa Item kini disinkronkan ke stok lokasi melalui PATCH-STOCK-EDITOR-SYNC.sql.
