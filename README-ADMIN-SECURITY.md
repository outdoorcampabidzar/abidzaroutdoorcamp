# AOC Admin Security — PIN Admin

Versi ini menggunakan **PIN Admin 8 digit** tanpa membutuhkan RPC/SQL tambahan.

## Membuat PIN
Admin Panel → Pengaturan → Keamanan → PIN Admin → Buat / Ubah PIN Admin.

Hanya SUPERADMIN yang boleh membuat/mengubah PIN.

## Penyimpanan
PIN tidak disimpan sebagai teks biasa. Browser menyimpan salt + SHA-256 digest di localStorage perangkat tersebut.

## Penggunaan
PIN hanya diminta saat aksi perubahan penting yang memanggil `window.aocAdminSecurity.ensure()`.
Membuka dashboard, melihat order, laporan, stok, dan data tidak otomatis meminta PIN.

## Catatan keamanan
Karena versi ini sengaja tidak memakai SQL/RPC tambahan, PIN Admin merupakan proteksi sisi aplikasi/perangkat. Untuk proteksi yang benar-benar tidak dapat dilewati melalui API/database, diperlukan enforcement di Supabase/RPC/RLS.
