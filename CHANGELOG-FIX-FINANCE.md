# Fix Omzet & Keuangan — 20 Sep 2026

Perubahan pada `admin.js` (tab Omzet & Keuangan) dan cache-bust `admin.html`:

1. **Denda kini ikut dihitung ke Omzet Kotor/Bersih**
   - Fungsi baru `financeGrossAmount(o)` = subtotal/total order + `late_fee`.
   - Dipakai untuk kartu Omzet Kotor, Omzet Bersih, Omzet per Toko, dan grafik Omzet Harian.
   - Sebelumnya denda hanya tampil di kartu "Denda" tapi tidak menambah Omzet Bersih — sekarang konsisten dengan invoice yang sudah menjumlahkan `total + late_fee`.

2. **Kartu "Belum Dibayar" sekarang mengikuti filter rentang tanggal yang dipilih**
   - Sebelumnya menjumlahkan SEMUA order pending/confirmed tanpa peduli rentang tanggal (Hari ini/7 Hari/Bulan ini/dst), jadi angkanya selalu sama walau filter diganti.
   - Sekarang difilter berdasarkan `created_at` sesuai rentang yang aktif.

3. **Export CSV diperbarui**
   - Kolom "Total" diganti jadi "Subtotal" + kolom baru "Denda" (terpisah, transparan).
   - Kolom "Net" sekarang memakai Omzet Kotor (termasuk denda) dikurangi refund, konsisten dengan kartu di dashboard.

4. **Cache-busting**: `admin.js?v=202609181600` → `?v=202609201700` di `admin.html` supaya browser admin memuat ulang file yang sudah diperbaiki (bukan versi lama yang ter-cache).

## Belum dikerjakan (di luar scope perbaikan bug, perlu keputusan desain + skema DB baru)
- Tracking biaya/pengeluaran (HPP) dan laporan laba bersih — belum ada tabel/kolom biaya di database.
- Perbandingan omzet antar-periode (bulan ini vs bulan lalu).
- Laporan omzet per item/kategori terlaris.

Syntax admin.js sudah divalidasi (`node --check`) — tidak ada error.

---

# Fitur Baru — Batch 1: Pengeluaran & Laba Bersih (20 Sep 2026)

## Yang ditambahkan
1. **Tabel `expenses` baru** (SQL: `PATCH-EXPENSES-TRACKING.sql`) — kategori, keterangan, nominal, tanggal, toko (opsional), pencatat.
2. **RLS + RPC**: `secure_add_expense()` dan `secure_delete_expense()`, hanya bisa dipakai akun dengan permission `finance.manage` atau super_admin (`*`) — sama pola keamanannya dengan fitur order/refund yang sudah ada.
3. **UI di tab 💰 Omzet & Keuangan** (hanya tampil untuk akun `finance.manage`/super_admin):
   - Panel "📉 Pengeluaran" — daftar pengeluaran sesuai rentang tanggal & toko yang dipilih, tombol ➕ Tambah dan 🗑️ Hapus per baris.
   - Kartu baru **"Laba Bersih"** = Omzet Bersih − Total Pengeluaran pada rentang yang sama.

## Cara pasang
1. Jalankan `PATCH-EXPENSES-TRACKING.sql` di Supabase SQL editor (setelah `AOC-ULTIMATE-FINAL.sql`).
2. Upload ulang `src` ke hosting (isi `admin.js` & `admin.html` berubah, versi cache dinaikkan ke `?v=202609201900`).
3. Hard refresh, buka tab Omzet & Keuangan dengan akun `finance_admin` atau `super_admin`.

## Catatan
- Akun role `order_admin`/`catalog_admin` tidak akan melihat panel Pengeluaran/Laba Bersih (sesuai desain hak akses yang sudah ada).
- Belum ada export CSV khusus pengeluaran — baru tampil di panel, bisa ditambahkan berikutnya kalau dibutuhkan.
- Belum diuji ke database live (saya tidak punya akses ke Supabase project ini) — mohon dites di staging/lingkungan aman dulu sebelum dipakai di produksi.
- **Update:** `expenses` sekarang juga terhubung ke sistem audit log yang sudah ada (trigger `audit_admin_change_trigger`), jadi tambah/hapus pengeluaran ikut tercatat di tab 🛡️ Log Aktivitas — konsisten dengan refund/return. Tidak perlu perubahan lain di sisi CSS (class yang dipakai panel Pengeluaran sudah tersedia di `styles.css`), dan `gen_random_uuid()` sudah dipakai tabel lain di project ini jadi tidak perlu extension tambahan.

## Roadmap fitur lain yang diminta (belum dikerjakan)
Daftar ini sengaja dikerjakan bertahap, bukan sekaligus, karena masing-masing menyentuh skema database & alur produksi yang berbeda-beda dan berisiko kalau digabung jadi satu patch besar tanpa pengujian bertahap:
- Notifikasi stok menipis/habis
- Riwayat kondisi barang per unit (log kerusakan/servis)
- Jadwal maintenance alat
- Poin loyalitas otomatis dari transaksi (kartu membership dasarnya sudah ada — lihat Batch 2 di bawah)
- Riwayat sewa per pelanggan di profil + blacklist otomatis
- Notifikasi WhatsApp otomatis via WA Business API (perlu API key/akun WA Business dari kamu) — **ditunda, tidak diperlukan untuk saat ini**
- Dashboard okupansi alat
- Prediksi ketersediaan alat untuk booking jauh hari
- Two-factor authentication admin (kode verifikasi login saat ini masih tampil di layar sendiri, bukan 2FA sungguhan — perbaikan via Email OTP masih terbuka kalau suatu saat dibutuhkan)
- Filter Log Aktivitas per staff
- Wishlist pelanggan
- Estimasi kebutuhan alat untuk open trip

Kasih tahu urutan prioritas yang kamu mau, saya lanjutkan batch berikutnya dengan pola yang sama (SQL patch + perubahan admin.js/app.js + changelog + zip lengkap).

---

# Fitur Baru — Batch 2: Kartu Membership (20 Sep 2026)

## Yang ditambahkan
1. **Tabel `membership_cards` baru** (SQL: `PATCH-MEMBERSHIP-CARD.sql`) — satu kartu per pelanggan, nomor kartu unik format `AOC-XXXXXXXX`, tier `Bronze`/`Silver`/`Gold`/`Platinum`, status aktif/nonaktif, pencatat siapa yang menerbitkan.
2. **RPC `secure_issue_membership_card(user_id, tier)`** — hanya bisa dipakai akun dengan permission `customers.manage` atau super_admin. Kalau pelanggan belum punya kartu, dibuatkan baru dengan nomor unik. Kalau sudah punya, tier-nya di-update (nomor kartu tidak berubah).
3. **RLS**: pelanggan sendiri bisa lihat kartunya; admin dengan `customers.view`/`*` bisa lihat semua; hanya `customers.manage`/`*` yang bisa terbitkan/ubah.
4. **UI di tab 👤 Pelanggan**: setiap kartu pelanggan sekarang menampilkan badge tier (kalau sudah punya kartu) dan bagian "🎫 Kartu Membership" dengan tombol **Buat Kartu Membership** / **Ubah Tier**. Admin cukup ketik tier yang diinginkan lewat dialog, sistem yang generate nomor kartunya.
5. Terhubung ke audit log (tab 🛡️ Log Aktivitas) seperti fitur lain.

## Cara pasang
1. Jalankan `PATCH-MEMBERSHIP-CARD.sql` di Supabase SQL editor (setelah `access-security.sql`).
2. Upload ulang `src` ke hosting (versi cache `admin.js` naik ke `?v=202609202100`).
3. Hard refresh, buka tab Pelanggan dengan akun `finance_admin`/`super_admin`/akun lain yang punya `customers.manage`, klik salah satu pelanggan, coba buat kartu.

## Scope & catatan
- **Sengaja dibatasi ke "create/update kartu" saja**, sesuai permintaan — belum termasuk: perhitungan poin otomatis dari transaksi, redeem poin, manfaat/diskon otomatis per tier, atau tampilan kartu membership di sisi pelanggan (customer-facing). Itu semua bisa jadi batch lanjutan kalau dibutuhkan.
- Tidak ada tombol nonaktifkan/cabut kartu di UI (tabel & RPC sudah punya kolom `status` untuk itu, tinggal ditambahkan kalau diperlukan).
- Belum diuji ke database live — mohon dites dulu sebelum dipakai di produksi.

---

# Perbaikan Bug — Dialog Macet (20 Sep 2026)

## Masalah
Tombol "Buat Kartu Membership" (dan berpotensi tombol lain yang pakai dialog kustom seperti "Tambah Pengeluaran") bisa **tidak merespons sama sekali** saat diklik, tanpa pesan error apapun.

## Penyebab
Sistem dialog kustom di `app.js` (`aocPrompt`/`aocConfirm`) memakai satu variabel `aocDialogPromise` sebagai "kunci" supaya tidak ada dua dialog terbuka bersamaan. Masalahnya: kalau ada dialog SEBELUMNYA yang tidak sempat ter-resolve dengan benar (misalnya tab browser sempat pindah, atau ada gangguan lain), kunci itu **tersangkut aktif selamanya** untuk sisa sesi browser tersebut — akibatnya SEMUA dialog berikutnya (termasuk fitur baru yang memakai `aocPrompt`) langsung gagal diam-diam tanpa tampil sama sekali.

## Perbaikan
`openAocDialog()` di `app.js` sekarang otomatis membersihkan dialog macet sebelumnya (kalau ada) sebelum membuka dialog baru, jadi kunci itu tidak akan tersangkut lagi.

## Solusi cepat untuk kamu sekarang
Sebelum sempat upload perbaikan ini pun, masalah ini biasanya hilang dengan **reload/refresh penuh halaman admin** (bukan cuma klik ulang) — karena kuncinya tersimpan di memori browser, bukan di database.

## Cara pasang perbaikan permanen
1. Upload ulang `src` (file yang berubah: `app.js`, `admin.js`, `admin.html`, versi cache `app.js` naik ke `?v=202609202130`).
2. **Hard refresh** (Ctrl+Shift+R / Cmd+Shift+R) halaman admin.
3. Coba lagi tombol Buat Kartu Membership.

Catatan: `auth.js`, `catalog.js`, `profile.js` (halaman customer: cart, item, orders, payment, shop) meng-import `app.js` **tanpa** versi cache sama sekali — jadi kalau ke depan ada perubahan di `app.js` lagi, halaman-halaman itu juga perlu di-hard-refresh manual atau ditambahkan cache-busting serupa.

---

# Perbaikan Bug #2 — `resolve is not a function` (20 Sep 2026)

## Masalah
Setelah perbaikan dialog macet di atas dipasang, tombol OK/konfirmasi pada dialog (`aocPrompt`/`aocConfirm`) malah memicu error di console: `TypeError: resolve is not a function`.

## Penyebab
Ini bug lama yang **sudah ada sejak awal**, tapi selama ini "tersembunyi" karena ketiban bug pertama (dialog macet) — dialog nyaris tidak pernah benar-benar sempat diklik OK sampai selesai, jadi kode yang salah ini jarang ketimpa. Di fungsi `finish()`, variabel `resolve` diambil dari `aocDialogPromise` (yang isinya adalah objek Promise itu sendiri, bukan fungsi resolve-nya) — seharusnya diambil dari `wrap._resolve` (fungsi resolve yang benar, disimpan saat Promise dibuat).

## Perbaikan
`finish()` di `app.js` sekarang mengambil `wrap._resolve` yang benar. Sudah divalidasi sintaksnya (`node --check`).

## Cara pasang
Sama seperti perbaikan sebelumnya: upload ulang `src`, versi cache `app.js`/`admin.js` naik ke `?v=202609202230`, lalu hard refresh halaman admin.

---

# Fitur Baru — Batch 3: Kartu Membership Fisik/Digital + QR Code (20 Sep 2026)

## Yang ditambahkan
1. **Kartu membership visual di beranda (`index.html`)** — muncul otomatis untuk pelanggan yang sudah login DAN sudah punya kartu (dari Batch 2). Desain kartu bergaya kartu fisik, warna gradasi beda per tier (Bronze/Silver/Gold/Platinum), menampilkan nama, nomor kartu, dan tier.
2. **QR Code yang bisa di-scan** di kartu tersebut — encode nomor kartu (`card_number`), dibuat pakai library ringan `qrcodejs` (CDN, tanpa biaya). Pelanggan tinggal tunjukkan QR ini ke kasir/admin toko.
3. **Fungsi baru `mountMembershipCard()` di `app.js`** — bisa dipanggil di halaman lain juga (mis. `profile.html`) kalau nanti mau ditambahkan di sana juga, cukup pastikan ada elemen dengan struktur ID yang sama (`membershipCardSection`, dst — lihat `index.html` sebagai contoh) dan library `qrcodejs` ikut dimuat di halaman itu.
4. **Kotak pencarian "🔍 Cari nomor kartu membership"** di tab Pelanggan admin — supaya QR yang di-scan (atau nomor kartu yang diketik manual) bisa langsung dipakai mencari pelanggannya. Cocok dipakai kalau kasir punya alat scan QR yang otomatis mengisi/mengetik hasil scan-nya di kotak ini.

## Cara pasang
1. Jalankan `PATCH-MEMBERSHIP-CARD.sql` kalau belum (dari Batch 2) — tidak ada perubahan skema baru di batch ini.
2. Upload ulang `src` (yang berubah: `index.html`, `app.js`, `admin.js`, `admin.html`, `styles.css`; versi cache naik ke `?v=202609202300`).
3. Hard refresh.
4. Tes: login sebagai pelanggan yang sudah dibuatkan kartu membership → buka beranda → kartu & QR harus muncul di bagian atas.
5. Tes admin: buka tab Pelanggan → ketik/scan nomor kartu di kotak pencarian → pelanggan yang cocok harus otomatis kebuka detailnya.

## Catatan & keterbatasan
- QR code di-generate murni di sisi browser (tidak ada data terkirim ke server pihak ketiga) — library dimuat dari CDN cdnjs.
- Kartu **tidak muncul** kalau: belum login, atau belum pernah dibuatkan kartu membership dari admin (bukan bug — memang disengaja).
- Belum ada endpoint/QR-scanner khusus di sisi admin (scan lewat kamera HP) — kotak pencarian di atas mengasumsikan alat scan eksternal yang mengetik hasil scan secara otomatis (seperti scanner barcode USB/Bluetooth pada umumnya), atau nomor kartu diketik manual.
- Belum ada versi cetak/download PDF kartu fisik — ini murni tampilan digital di web. Kasih tahu kalau versi cetak/PDF juga dibutuhkan.
- Belum diuji ke live site — mohon dites dulu.
