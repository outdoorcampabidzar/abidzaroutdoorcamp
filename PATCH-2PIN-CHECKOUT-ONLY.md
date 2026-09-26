# AOC — 2 PIN / Checkout Only

- Admin Panel tidak lagi meminta kode keamanan 6 digit/login code.
- Akses Admin tetap dilindungi session Supabase + role/permission server-side.
- Login email/password tidak lagi meminta kode 6 digit.
- PIN pengguna (PIN Transaksi 6 digit) tetap menjadi verifikasi khusus checkout.
- PIN transaksi tetap diverifikasi melalui `verify_transaction_pin` dan gate database pada pembuatan order.
- Fitur buat/ganti PIN tetap berada di Profil Saya.
