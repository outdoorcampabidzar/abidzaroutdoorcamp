# AOC — Hapus Semua Jenis Pesanan

Patch ini menambahkan tombol **🗑️ Hapus Pesanan** pada pesanan rental di menu **Pengembalian Barang** untuk **semua status**, termasuk Operasional, Menunggu, Dibayar, Dikembalikan, Selesai, dan status rental lain yang tampil.

## Instalasi

1. Buka Supabase → SQL Editor.
2. Jalankan `PATCH-HAPUS-SEMUA-JENIS-PESANAN.sql` satu kali.
3. Deploy/ganti file website dengan isi folder `src` dari ZIP ini.
4. Logout → login kembali → refresh.

## Perilaku

- Hanya Super Admin dengan permission `*` yang dapat menghapus.
- Pesanan dapat dihapus dari tab **Operasional**, **Pesanan Selesai**, maupun **Semua**.
- Sebelum penghapusan, server mengunci order dan mengembalikan stok produk/kuota yang masih tercatat terpotong.
- Data anak yang menggunakan `ON DELETE CASCADE` ikut terhapus.
- `voucher_usages` dan log webhook terkait dibersihkan lebih dahulu sesuai constraint skema.
- Penghapusan permanen tidak dapat dibatalkan.
