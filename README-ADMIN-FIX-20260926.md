# AOC Admin Panel Fix — 26 September 2026

Perbaikan pada build ini menargetkan kondisi Admin Panel yang berhenti di **"Memeriksa akses admin..."**.

## Perubahan utama

1. `admin.html`
   - Menghapus boot cache/service-worker cleanup yang tidak diperlukan.
   - Menambahkan deteksi gagal-load module.
   - Menambahkan timeout boot 9 detik agar halaman tidak menggantung.
   - Jika belum login, tampil tombol **Login ke Admin**.

2. `admin-core-final-20260926.js`
   - `getSession()` dibatasi timeout.
   - Ditambahkan fallback `getUser()` dengan timeout.
   - Cache sesi lokal hanya menjadi fallback terakhir.
   - Admin Panel tidak memakai PIN 6 digit.

3. `PATCH-AUTH-ADMIN-SYNC-FINAL.sql`
   - `has_permission()` tidak lagi bergantung pada `admin_security_verifications`.
   - PIN 6 digit tetap untuk checkout sesuai build `2PIN-CHECKOUT-ONLY`.
   - Role/permission admin tetap menjadi pengaman Admin Panel.

## Setelah upload

1. Upload semua file hasil ZIP ke hosting/GitHub Pages.
2. Di Supabase SQL Editor, jalankan `PATCH-AUTH-ADMIN-SYNC-FINAL.sql` setelah `access-security.sql`.
3. Pastikan akun yang dipakai login memiliki role `super_admin` (atau role staff yang sesuai) di `profiles`.
4. Buka `admin.html` lalu login kembali jika sesi lama sudah hilang.
5. Jika browser masih menampilkan versi lama, lakukan hard refresh.


## V9 boot fix
Admin sekarang memuat `admin-core.js` sebagai nama file stabil agar tidak gagal karena file `admin-core-final-20260926.js` tidak ikut ter-upload/cache lama. `admin-core.js` adalah salinan build Admin terbaru.
