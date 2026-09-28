# AbidzarOutdoorcamp V36 — Clean Update

Paket ini merapikan V35 tanpa mengubah konsep utama.

## Konsep tetap
- Register: email + password.
- Setelah register/login pertama: buat **Home Security PIN 6 digit**.
- Lengkapi identitas.
- Setiap masuk/refresh Beranda: **Home Security PIN wajib lagi**.
- Home PIN berbeda dari Transaction PIN.
- Transaction PIN hanya dipakai untuk transaksi/checkout.
- Admin Panel tidak meminta Transaction PIN.
- Hak akses Admin tetap per akun/checkbox.
- Reset Omzet tetap melalui alur aman dan tidak meminta Transaction PIN.
- Galeri: semua akun terdaftar yang login dapat upload; semua pengunjung dapat melihat; hanya pemilik yang dapat menghapus.
- Pengumuman Beranda tetap tampil meskipun belum ada pengumuman aktif; tidak menghilang diam-diam karena query kosong/error.

## Database
Jalankan **DATABASE-V36-FINAL-PATCH.sql** satu kali di Supabase SQL Editor.

Patch ini ditujukan untuk database AOC yang sudah ada dari versi sebelumnya. Jangan menghapus data lama.

## Deployment
Upload isi ZIP ke GitHub Pages dan timpa file versi lama.

File legacy/duplikat dan dokumentasi build lama sengaja dikeluarkan agar paket lebih kecil dan lebih mudah dirawat.
