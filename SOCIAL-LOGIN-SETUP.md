# Auth AOC — Google + Email/Password

Auth AOC menggunakan 2 jalur login:
- Email + Password
- Google

UI login sosial terhubung ke Supabase Auth menggunakan `signInWithOAuth()`.

## 1. Redirect URL Supabase

Di Supabase Dashboard → Authentication → URL Configuration, tambahkan URL website AOC.

Contoh produksi:

`https://domain-website-kamu/login.html`

Untuk pengembangan lokal, tambahkan origin/URL localhost yang dipakai AOC.

## 2. Google

Supabase Dashboard → Authentication → Sign In / Providers → Google → Enable.

Buat OAuth Client ID Web di Google Cloud, lalu masukkan Client ID + Client Secret ke Supabase.

Callback Supabase berbentuk:

`https://PROJECT-REF.supabase.co/auth/v1/callback`

## 3. Email + Password

Supabase Dashboard → Authentication → Sign In / Providers → Email.

Pastikan Email provider aktif. Alur registrasi dan login email/password AOC tetap menggunakan sistem Auth yang sudah ada, termasuk kode keamanan 6 digit.

## Catatan

- Facebook dan X/Twitter tidak lagi digunakan oleh UI Auth AOC.
- Client Secret hanya dimasukkan di dashboard/provider configuration, jangan ditaruh di JavaScript frontend.
- Setelah OAuth Google kembali ke `login.html`, sistem keamanan kode 6 digit AOC yang sudah ada tetap dijalankan oleh `auth.js`.
