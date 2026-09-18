# FIX TAMBAH ITEM — AOC

Patch ini memperbaiki proses **Tambah Item Sewa** agar pembuatan item tidak dilakukan setengah-setengah. Untuk item BARU, browser memanggil RPC `secure_admin_create_rental_item`; PostgreSQL menyimpan item, kategori, galeri, varian, inventaris, harga paket, dan stok lokasi dalam satu transaksi. Jika salah satu langkah gagal, transaksi dibatalkan otomatis.

## Cara install

### 1. Backup database
Di Supabase buka **Database → Backups** atau buat backup sebelum menjalankan SQL.

### 2. Pastikan SQL AOC utama sudah pernah dijalankan
Patch ini bergantung pada tabel/fungsi katalog dan permission AOC. Jalankan SQL dasar/upgrade AOC sesuai README utama sampai `AOC-ULTIMATE-FINAL.sql` selesai.

### 3. Jalankan patch ini
Buka **Supabase → SQL Editor → New query**, buka file:

`src/FIX-TAMBAH-ITEM-TRANSACTIONAL.sql`

Copy seluruh isinya → Paste ke SQL Editor → **Run**.

### 4. Upload file website
Salin isi folder `src` ke hosting/htdocs sesuai struktur website AOC yang sekarang. File yang paling penting untuk patch ini adalah:

- `admin.js`
- `FIX-TAMBAH-ITEM-TRANSACTIONAL.sql`

Jangan menghapus `config.js`/`config.example.js` yang sudah berisi konfigurasi Supabase milik website.

### 5. Logout/login
Setelah SQL dan file website diperbarui:

1. Logout dari akun admin.
2. Login kembali.
3. Refresh paksa browser (atau hapus cache situs).
4. Masuk **Admin → Sewa Item → Tambah Item**.

## Test Tambah Item

Isi minimal:

- Nama item
- Slug
- Deskripsi
- Harga sewa
- Stok

Kategori, gambar, varian, inventaris, dan harga paket boleh dikosongkan untuk pengujian pertama. **Gambar utama sekarang opsional.**

Klik **Tambah Item**. Item harus langsung muncul di daftar.

## Jika masih gagal
Pesan error sekarang dibuat lebih jelas. Kirim **screenshot pesan error merah** yang muncul setelah tombol Tambah Item ditekan. Jangan hanya kirim halaman form, karena pesan error tersebut menentukan apakah masalahnya permission, constraint, slug duplikat, nomor inventaris duplikat, atau konfigurasi database.

## Catatan penting

- Untuk item baru, jangan kembali menggunakan kode `items.insert()` lama untuk proses Tambah Item; `admin.js` pada ZIP ini sudah memakai RPC transaksional.
- `PATCH-FINALISASI-TANPA-VOUCHER.sql` tetap mengikuti versi yang sudah disupersede pada ZIP sebelumnya; tidak perlu dijalankan ulang untuk memperbaiki Tambah Item.
