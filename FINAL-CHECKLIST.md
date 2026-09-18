# AOC Final Verification Checklist

## 2 Mode
- [ ] Item `sale_enabled=true` dan `sale_price>0` menampilkan tombol Jual.
- [ ] Klik Sewa/Jual pada detail item mengubah badge, label harga, subtotal, tombol, dan gateway.
- [ ] Harga checkout dihitung ulang oleh database.
- [ ] Order Sale + Rental ditolak server-side.

## Multi Toko
- [ ] Toko 1 dan Toko 2 mempunyai stok masing-masing.
- [ ] Ganti toko mengubah stok yang ditampilkan.
- [ ] Checkout menyimpan `orders.location_id` sesuai toko yang dipilih.
- [ ] Rental availability memakai stok toko yang dipilih.
- [ ] Sale availability memakai stok toko yang dipilih.

## Stock lifecycle
- [ ] Rental `paid` tidak mengurangi stok fisik.
- [ ] Sale `paid` mengurangi stok lokasi satu kali.
- [ ] Sale `paid -> cancelled` mengembalikan stok ke lokasi asal satu kali.
- [ ] Return rental tidak menambah stok fisik dua kali.
- [ ] Pembayaran bersamaan tidak dapat menjual stok yang sama.

## Admin
- [ ] Admin permission/RLS berjalan.
- [ ] Stok per toko dapat diubah dari panel.
- [ ] Pengembalian checklist dapat diselesaikan.
- [ ] Status rental mengikuti Pending → Confirmed → Paid → Returned → Completed.

## Setelah deploy
1. Jalankan SQL sesuai README-FINAL-V4.md.
2. Refresh schema Supabase.
3. Logout/login ulang.
4. Hard refresh browser.
5. Tes satu item Sewa + Jual pada dua toko.
