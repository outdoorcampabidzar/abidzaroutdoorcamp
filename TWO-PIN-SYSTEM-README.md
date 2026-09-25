# AOC — Sistem 2 PIN

## 1. PIN Keamanan Beranda
- Dibuat acak oleh sistem (6 digit) setiap kali halaman Beranda dibuka/dikunjungi kembali.
- User hanya memasukkan PIN yang tampil pada challenge untuk membuka Beranda.
- Tidak disimpan sebagai PIN akun dan tidak menggantikan autentikasi/RLS.

## 2. PIN User / PIN Transaksi
- Dibuat sendiri oleh user, 6 digit.
- Dipakai untuk checkout/tindakan transaksi yang dilindungi.
- Disimpan sebagai hash di server dan tidak dapat dilihat admin.
- Ganti PIN hanya melalui user dengan PIN lama.
- Salah berkali-kali memicu lock sementara sesuai policy database.

## Perbedaan
PIN Keamanan Beranda = challenge akses halaman, dibuat sistem.
PIN User = PIN transaksi, dibuat dan dikelola user.
