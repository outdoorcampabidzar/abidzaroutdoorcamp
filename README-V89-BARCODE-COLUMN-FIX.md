# AOC V89 — BARCODE COLUMN FIX

Memperbaiki crop barcode yang terjadi karena kolom kode lebih kecil daripada lebar barcode.

Perubahan:
- Kolom kanan kartu depan diperbesar agar menampung QR + barcode.
- Kolom kanan kartu belakang diperbesar agar barcode tidak keluar grid.
- Barcode container menggunakan 100% dari kolomnya, bukan 24cqw yang melebihi kolom.
- JsBarcode dibuat sedikit lebih ramping agar seluruh CODE128 dan teks kode tetap terlihat.
- Tidak mengubah desain/background/data ID Card lainnya.
