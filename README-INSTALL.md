INSTALASI RINGKAS

1. Upload semua file website ke hosting.
2. Pastikan config.js berisi URL dan anon key Supabase yang benar.
3. Jalankan SQL yang diperlukan di Supabase, terutama:
   - order-management.sql
   - stock-lifecycle.sql
   - rental-calendar.sql
   - PATCH-BULK-RETURN-INSPECTION.sql
   - PATCH-RENTAL-ADMIN-WORKFLOW.sql
   - PATCH-RENTAL-REMINDER-28H-4H-FEE100.sql
   - access-security.sql
4. Untuk otomatis setiap menit, aktifkan pg_cron dan schedule fungsi reminder sesuai patch.
5. Login sebagai admin lalu refresh.
