AOC V50 — MULTI ADMIN TRAVEL FIX

Perbaikan pada V50:
- Hak akses Administrator sekarang memisahkan 4 MODUL USAHA: Persewaan, Jual, Open Trip, Travel.
- Modul Travel ditampilkan sebagai divisi mandiri, bukan sekadar kategori katalog.
- Fitur pendukung dipindahkan ke bagian collapsible agar tidak bercampur dengan modul usaha.
- Preset Admin Travel tetap memberikan travel.manage + akses pesanan yang diperlukan.
- Halaman Travel customer tetap tersedia di travel.html dan menu Travel beranda.
- Backend Supabase Travel + permission travel.manage sudah diterapkan.
- admin-bundle-v50.js dan admin-security-v50.js digunakan oleh admin.html.

Upload seluruh isi ZIP ke hosting/GitHub Pages dengan mempertahankan struktur file.


FIX TERBARU: Tab 🚐 Travel sekarang benar-benar membuka halaman pengisian paket Travel. Sebelumnya dispatcher renderActiveTab tidak memiliki cabang travel sehingga Travel jatuh ke halaman Hak Akses/Administrator. Tab 🛒 Jual juga dipetakan eksplisit ke renderSaleTab.
