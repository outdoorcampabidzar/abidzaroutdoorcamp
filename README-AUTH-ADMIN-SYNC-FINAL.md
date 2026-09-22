# AOC — AUTH + ADMIN SYNC FINAL

Perbaikan ini menyatukan login Supabase Auth, role `profiles`, permission admin, verifikasi kode 6 digit, dan tampilan Admin Panel.

## File utama yang diperbaiki
- `auth.js`
- `admin.js`
- `app.js`
- `profile.js`
- `admin.html`
- `PATCH-AUTH-ADMIN-SYNC-FINAL.sql`

## Urutan SQL
Jalankan di Supabase SQL Editor:
1. `access-security.sql`
2. `PATCH-AUTH-LOGIN-DAN-AKTIVASI-KODE-6-DIGIT.sql`
3. `PATCH-AUTH-ADMIN-SYNC-FINAL.sql` (TERAKHIR)

Jangan menjalankan `admin-management.sql` lama setelah patch ini karena file lama masih memakai role `admin` dan dapat mengembalikan struktur role lama.

## Role yang didukung
- `super_admin`
- `order_admin`
- `catalog_admin`
- `finance_admin`
- `warehouse_staff`

Role lama `admin` / `superadmin` dinormalisasi menjadi `super_admin` oleh patch.

## Alur login admin
Supabase Auth login -> kode login 6 digit -> `verify_login_code()` -> server mencatat `admin_security_verifications` -> Admin Panel memeriksa `admin_security_check()` -> role/permission dibaca -> panel tampil.

Setelah upload file, lakukan hard refresh browser.
