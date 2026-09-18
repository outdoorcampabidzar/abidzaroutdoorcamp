AOC FINAL ADMIN - ORDER, REMINDER, RETURN

MENU ADMIN:
- Sewa Item: hanya katalog/stok item rental.
- Pesanan Sewa: hanya order rental aktif/menunggu.
- Pengingat Rental: terpisah dari Sewa Item; monitor H-4 jam dan overdue.
- Pengembalian Barang: terpisah; checklist semua item dan simpan sekaligus.

ATURAN RENTAL:
- 1 hari = 28 jam.
- Pengingat H-4 jam.
- Denda terlambat = 100% dari total harga sewa, diterapkan sekali oleh database.

WAJIB:
1. Jalankan SQL utama sesuai kebutuhan.
2. Jalankan PATCH-RENTAL-REMINDER-28H-4H-FEE100.sql.
3. Jika memakai pg_cron, jadwalkan aoc_process_rental_reminders() setiap menit.
4. Refresh Admin Panel.

Catatan: menu Pengingat Rental memanggil RPC admin_process_rental_reminders dan admin_list_rental_reminders. Jika SQL belum dipasang, panel akan menampilkan pesan yang jelas.
