# Home Security Gate V8

- Beranda dikunci sejak pertama dibuka.
- Pengunjung wajib memasukkan tepat 6 digit angka sebelum isi Beranda dapat digunakan.
- Kode tidak ditampilkan di Beranda.
- Setelah berhasil, status unlock disimpan hanya untuk tab/sesi browser tersebut.
- PIN checkout 2 langkah tetap terpisah.
- File utama: `index.html`, `home-security-code.js`, `styles.css`.

Catatan keamanan: V8 memvalidasi format 6 digit di browser. Jika kode harus diverifikasi terhadap kode yang diterbitkan server/admin, sambungkan `onVerify` ke RPC/backend agar validasi tidak dapat dilewati dari browser.


## V10 fix
- Beranda selalu dikunci saat dibuka.
- Tidak memakai sessionStorage/localStorage untuk menyimpan status terbuka.
- Saat kembali ke Beranda melalui Back/Forward cache, kode 6 digit diminta lagi.
- Input harus tepat 6 digit sebelum proses verifikasi dijalankan.
