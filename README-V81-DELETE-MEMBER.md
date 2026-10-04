# V81 — Hapus Data Anggota

Admin dapat menghapus Data Anggota / ID Card dari tab Data Anggota.

- Tombol: 🗑️ Hapus Anggota
- Konfirmasi sebelum hapus
- RPC SECURITY DEFINER memeriksa `is_admin()`
- Menghapus record `member_id_cards`
- Mencoba membersihkan foto dari bucket `member-photos` jika URL foto berasal dari bucket tersebut
- Tidak menghapus akun login pelanggan / `auth.users`

Jalankan `MEMBER-ID-CARD-DELETE-V81.sql` pada Supabase sebelum memakai tombol hapus jika RPC belum ada.
