# Scan Member QR

Fitur ini menambahkan tombol **📷 Scan Member** pada Admin Panel > Pelanggan.

## Cara kerja
1. Admin buka tab **Pelanggan**.
2. Tekan **Scan Member**.
3. Izinkan akses kamera HP.
4. Arahkan kamera ke QR kartu member.
5. QR dapat berisi nomor kartu seperti `AOC-XXXXXXXX`, UUID `membership_cards.id`, atau `user_id`. URL dengan parameter `card`, `member`, atau `token` juga didukung.
6. Sistem mencari kartu/member dan menampilkan profil + riwayat rental.

## Prasyarat
- Jalankan `PATCH-MEMBERSHIP-CARD.sql` di Supabase agar tabel `membership_cards` tersedia.
- Admin harus memiliki permission `customers.view` dan akses kartu membership.
- Kamera browser memerlukan **HTTPS atau localhost**.
- Scanner menggunakan `BarcodeDetector` bawaan browser; gunakan Chrome/Edge Android terbaru.

Tidak ada data pribadi yang disimpan di dalam QR scanner. QR hanya dibaca lalu dicocokkan dengan data member yang sudah ada di Supabase.
