# FIX Pengingat Rental

Perbaikan utama:
- Menyesuaikan nama field Admin Panel dengan RPC `admin_list_rental_reminders()`:
  - `rental_due_at` (bukan `due_at`)
  - `status` (bukan `order_status`)
- Countdown tidak lagi menampilkan `Invalid Date` / `NaNj`.
- Total sewa memakai nilai order, lalu fallback ke data RPC.
- Filter order cancelled/completed diperbaiki.
- Sorting dan deteksi overdue memakai field waktu yang benar.

SQL database tidak perlu diganti untuk bug JavaScript ini. Jika patch reminder belum dijalankan, jalankan `PATCH-RENTAL-REMINDER-28H-4H-FEE10.sql`.
