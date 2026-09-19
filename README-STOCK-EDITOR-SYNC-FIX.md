AOC STOCK EDITOR SYNC FIX

File ini adalah patch untuk AOC-ULTIMATE-FINAL-CLEAN-NOTIFY-HAPUS.
Masalah: stok yang diedit pada Admin > Sewa Item masuk ke items.stock / item_variants.stock, tetapi sistem stok lokasi membaca item_location_stock sehingga stok terlihat 0.

Perbaikan:
1. Edit stok item tanpa varian -> otomatis masuk ke lokasi aktif pertama.
2. Edit stok varian -> otomatis masuk ke stok lokasi varian.
3. Data lama yang belum punya stok lokasi diisi dari stok yang sudah ada.
4. Saat stok lokasi diubah dari menu Lokasi, sinkronisasi balik tetap berjalan.
5. pg_trigger_depth mencegah loop antara items/item_variants dan item_location_stock.

SQL: src/PATCH-STOCK-EDITOR-SYNC.sql
Patch ini sudah diterapkan pada database AOC yang sedang diperbaiki.
Lokasi aktif pertama berdasarkan sort_order menjadi lokasi default untuk stok yang diedit dari form Sewa Item. Untuk pembagian stok antar beberapa lokasi, gunakan menu Stok Toko/Lokasi.
