# AOC V39 - Per-Account Admin PIN

Perubahan utama:
- PIN Admin tidak lagi disimpan di localStorage.
- Setiap akun admin mempunyai PIN Admin sendiri.
- PIN disimpan di Supabase sebagai bcrypt hash melalui RPC security-definer.
- PIN akun A tidak dapat dipakai untuk akun B.
- Membuat PIN pertama kali tidak membutuhkan PIN lama.
- Mengganti PIN membutuhkan PIN lama.
- 5 percobaan PIN salah mengunci PIN selama 30 menit.
- Session verifikasi admin tetap hanya 10 menit pada tab/perangkat tersebut.
- PIN Admin tetap hanya diminta untuk perubahan penting; melihat dashboard/data tidak meminta PIN.

## WAJIB: pasang SQL
Buka Supabase Dashboard -> SQL Editor, lalu jalankan:
`DATABASE-V39-PER-ACCOUNT-ADMIN-PIN.sql`

Setelah SQL berhasil, upload file website hasil ZIP.

## Catatan
PIN asli tidak disimpan di database. Database menyimpan bcrypt hash.
PIN juga tidak disimpan di localStorage.
