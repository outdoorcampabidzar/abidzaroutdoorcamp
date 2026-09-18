# AOC — UPGRADE EVERYTHING V2

Bundle ini berbasis build terakhir AOC dan memprioritaskan keamanan, kestabilan Admin Panel, serta alur rental.

## Yang sudah di-upgrade

### 1. Keamanan akun
- Login memakai Supabase Auth.
- Setelah password benar, wajib verifikasi kode 6 digit acak.
- Kode login/aktivasi sekali pakai.
- Kode punya masa berlaku.
- Maksimal 5 percobaan kode.
- Request kode baru dibatasi 60 detik.
- Verifikasi admin disimpan server-side selama 12 jam; localStorage tidak dianggap sebagai bukti admin.
- Admin Panel melakukan pengecekan keamanan server-side dan heartbeat berkala.

### 2. Admin Panel
- Akses role/permission tetap server-side melalui RPC + RLS.
- Audit log tetap aktif dari `access-security.sql`.
- Jika verifikasi admin kedaluwarsa, Admin Panel meminta login + kode ulang.
- Proteksi timeout tetap dipertahankan agar panel tidak menggantung di “Memeriksa akses admin…”.

### 3. Operasional rental
- Pesanan rental dipisahkan dari Sewa Item.
- Pengingat Customer terpisah.
- Pengembalian Barang memakai checklist semua item dan finalisasi sekaligus.
- Monitor countdown berjalan setiap detik.
- Aturan 1 hari = 28 jam.
- Status H-4 jam = SEGERA KEMBALI.
- Status lewat waktu = TERLAMBAT.
- Denda keterlambatan = 100% dari total harga sewa dan diproses server-side oleh patch rental.

### 4. Multi-toko
- Nama toko ditampilkan, bukan UUID.
- Filter kategori toko pada monitor rental tetap dipertahankan.
- Stok per toko tetap memakai fungsi database yang sudah ada.

### 5. Stabilitas
- `auth.js` dan `admin.js` sudah lolos `node --check`.
- File SQL auth tidak mengubah return type signature fungsi yang sudah ada.

## Urutan SQL yang disarankan
1. `JUAL-SEWA-INVENTORY-FINAL.sql`
2. `MULTI-LOKASI-STOCK.sql`
3. `order-management.sql`
4. `stock-lifecycle.sql`
5. `PATCH-RENTAL-REMINDER-28H-4H-FEE100.sql`
6. `PATCH-BULK-RETURN-INSPECTION.sql`
7. `PATCH-RENTAL-ADMIN-WORKFLOW.sql`
8. `access-security.sql` — jalankan setelah SQL fitur lain.
9. `PATCH-AUTH-LOGIN-DAN-AKTIVASI-KODE-6-DIGIT.sql` — **jalankan paling akhir untuk auth security V2**.

Setelah SQL selesai: Supabase → refresh schema/reload jika diperlukan → logout → login ulang → masukkan kode 6 digit → buka Admin Panel.

## Catatan penting
Kode 6 digit yang ditampilkan di halaman adalah mekanisme verifikasi yang diminta pada alur AOC saat ini. Untuk OTP produksi yang dikirim ke perangkat customer/admin, tahap berikutnya adalah menghubungkan generator server-side ke provider WhatsApp/SMS/email sehingga kode tidak ditampilkan di browser.


## FINAL V4 PATCH

Setelah semua SQL di atas selesai, jalankan `AOC-FINAL-FIX.sql` sebagai langkah terakhir. Patch ini memperbaiki konflik trigger stok, membuat availability benar-benar per toko, mengunci pemotongan stok sale agar tidak double-deduct, dan menolak order yang mencampur Jual + Sewa di level database.
