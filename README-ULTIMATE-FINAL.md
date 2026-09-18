# AOC Ultimate Final

## Instalasi SQL

Jalankan seluruh SQL fitur dasar/patch yang memang diperlukan terlebih dahulu, kemudian **jalankan `AOC-ULTIMATE-FINAL.sql` PALING TERAKHIR**.

### Penting: error `42P13`
Versi lama pernah membuat:
`secure_admin_finalize_rental(uuid,text) RETURNS void`

Versi Ultimate memakai:
`secure_admin_finalize_rental(uuid,text) RETURNS jsonb`

PostgreSQL tidak mengizinkan `CREATE OR REPLACE FUNCTION` mengubah return type. Karena itu `AOC-ULTIMATE-FINAL.sql` sekarang otomatis menjalankan:

`DROP FUNCTION IF EXISTS public.secure_admin_finalize_rental(uuid,text);`

sebelum membuat fungsi final.

## Jangan jalankan patch finalisasi lama
`PATCH-FINALISASI-TANPA-VOUCHER.sql` sekarang hanya menjadi compatibility notice dan tidak lagi mengganti fungsi final. Ini mencegah fungsi final JSONB tertimpa kembali oleh implementasi lama yang `RETURNS void`.

## Finalisasi
- `returned` -> `completed`
- idempotent / aman jika tombol ditekan dua kali
- denda 100% dihitung server-side
- tidak membaca atau mengubah voucher pada proses finalisasi
- audit finalisasi disimpan
- order yang sudah terkunci tidak dapat dikembalikan ke status operasional
