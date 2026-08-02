import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const output = resolve(root, "BACKUP-SELURUH-DATABASE.sql");

const sources = [
  "backup.txt",
  "site-settings.sql",
  "catalog-management.sql",
  "voucher-management.sql",
  "open-trip-management.sql",
  "rental-calendar.sql",
  "btzpay-payment.sql",
  "order-management.sql",
  "customer-review-notification.sql",
  "admin-management.sql",
  "stock-lifecycle.sql",
  "fix-rental-price-constraint.sql",
  "order-cleanup.sql",
  "preserve-rating-comment.sql",
  "website-comment-rpc-v2.sql",
  "profile-avatar.sql",
  "access-security.sql",
];

const sections = [];
sections.push(`-- ============================================================================
-- BACKUP SELURUH DATABASE ABIDZAR OUTDOORCAMP
-- Dibuat otomatis dari seluruh file SQL proyek.
--
-- CARA RESTORE:
-- 1. Buat project Supabase baru.
-- 2. Buka SQL Editor.
-- 3. Salin seluruh isi file ini dan klik Run.
-- 4. Buat akun pengguna pertama, lalu tetapkan Super Admin sesuai petunjuk.
--
-- File ini berisi skema, tabel, indeks, trigger, fungsi/RPC, RLS, Storage bucket,
-- voucher, katalog, open trip, kalender sewa, pembayaran, pesanan, pelanggan,
-- ulasan, notifikasi, stok, penghapusan pesanan, avatar, dan hak akses.
-- ============================================================================`);

for (const name of sources) {
  const content = await readFile(resolve(root, name), "utf8");
  sections.push(`-- ============================================================================
-- BEGIN SOURCE: ${name}
-- ============================================================================\n\n${content.trim()}\n\n-- ============================================================================
-- END SOURCE: ${name}
-- ============================================================================`);
}

sections.push(`-- Paksa PostgREST membaca skema terbaru setelah seluruh restore selesai.
notify pgrst, 'reload schema';

-- Ringkasan tabel publik hasil restore.
select table_name
from information_schema.tables
where table_schema = 'public'
order by table_name;`);

await writeFile(output, `${sections.join("\n\n")}\n`, "utf8");
console.log(output);
