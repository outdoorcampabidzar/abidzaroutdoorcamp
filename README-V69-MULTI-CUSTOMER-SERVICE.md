# AOC V69 — Multi Customer Service

Fitur Customer Service sekarang mendukung 2 nomor atau lebih dan dapat dikelola dari Admin Panel.

## Admin Panel
Pengaturan Website → Customer Service → Nomor WhatsApp CS

Setiap CS dapat diatur:
- Nama / label
- Nomor WhatsApp
- Bagian / layanan
- Pesan awal WhatsApp
- Aktif / nonaktif

Klik `＋ Tambah CS` untuk menambah nomor sebanyak yang dibutuhkan.

## Customer
Tombol `Hubungi CS` akan:
- langsung membuka WhatsApp jika hanya ada 1 CS aktif;
- membuka daftar pilihan CS jika ada 2 CS atau lebih.

Data multi-CS disimpan di `site_settings.settings.customer_services`, jadi tidak memerlukan tabel database baru.

Nomor WhatsApp lama (`whatsapp_number` dan admin_1/2/3) tetap dipertahankan sebagai fallback agar kompatibel dengan data lama.
