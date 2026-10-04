# AOC V88 — Barcode No Crop Fix

Memperbaiki barcode ID Card yang masih terpotong:
- CODE128 diperkecil secara proporsional agar seluruh batang barcode masuk.
- SVG memakai preserveAspectRatio xMidYMid meet.
- Tinggi SVG otomatis, tidak dipaksa sehingga tidak memotong isi barcode.
- Overflow SVG dibuat visible.
- Ukuran teks barcode diperkecil agar tidak memotong kode.
- Front dan belakang memakai perbaikan yang sama.
