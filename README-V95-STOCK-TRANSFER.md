# AOC V95 — Peminjaman Antar Store

Fitur baru: pengajuan peminjaman barang antar store melalui Admin Panel.

Alur: Pending → Disetujui & stok berpindah → Sedang Dipinjam → Pengembalian Diajukan → Selesai & stok kembali ke store asal.

Stok hanya berubah pada saat persetujuan dan penyelesaian pengembalian. Jumlah store dinamis mengikuti tabel aoc_locations.

Database migration diterapkan langsung ke project Supabase. Deployment ZIP ini berisi file runtime website; SQL migration tidak dimasukkan agar paket tetap ringkas.
