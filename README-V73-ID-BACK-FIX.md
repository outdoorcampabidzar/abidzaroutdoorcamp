# AOC V73 — Data Anggota Back Card Fix

Memperbaiki layout sisi BELAKANG ID Card agar tidak overflow pada preview maupun export SUPER HD.

Perubahan:
- grid belakang memakai `minmax(0,1fr)` agar kolom tengah dapat menyusut.
- teks dipaksa membungkus dengan aman.
- area barcode memiliki batas lebar.
- copy belakang dipadatkan agar tetap rapi di mobile.
- DEPAN, BELAKANG, QR, barcode, logo header, dan export 2 sisi tetap dipertahankan.
