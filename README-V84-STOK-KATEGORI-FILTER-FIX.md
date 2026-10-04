# AOC V84 — Stok Lokasi Auto Kategori

Perbaikan pada **Stok Lokasi → Daftar Item**:

- Filter kategori sekarang mencocokkan **ID kategori, slug, dan nama kategori**.
- Pencarian `Cari nama / kategori...` otomatis mengenali nama/slug kategori.
- Jika pengguna mengetik nama kategori secara tepat, dropdown kategori otomatis memilih kategori tersebut.
- Pencarian nama item tetap berjalan bersamaan dengan filter kategori.
- Reset mengembalikan filter ke semua kategori.
- Tidak mengubah sistem stok, toko, atau penyimpanan stok.


V84: memperbaiki filter Stok Lokasi agar kategori yang dipilih benar-benar menyaring kartu item berdasarkan nama/slug/ID kategori. Search kategori juga otomatis memilih kategori hanya ketika input cocok dengan kategori.
