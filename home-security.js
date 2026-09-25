// Beranda Security Challenge
// Meminta kode 6 digit baru setiap kali halaman Beranda dibuka.
// Ini adalah challenge UX, bukan pengganti RLS/auth/PIN transaksi server-side.
const KEY = "aoc_home_security_verified";

function randomSixDigits() {
  const a = new Uint32Array(1);
  crypto.getRandomValues(a);
  return String(a[0] % 1000000).padStart(6, "0");
}

function styles() {
  if (document.getElementById("aocHomeSecurityStyles")) return;
  const s = document.createElement("style");
  s.id = "aocHomeSecurityStyles";
  s.textContent = `
    .aoc-home-security-backdrop{position:fixed;inset:0;background:rgba(0,0,0,.78);backdrop-filter:blur(10px);z-index:99999;display:grid;place-items:center;padding:18px}
    .aoc-home-security-card{width:min(420px,100%);background:#0d1218;border:1px solid #26313d;border-radius:20px;padding:24px;box-shadow:0 24px 80px rgba(0,0,0,.5);color:#f5f7fa;font-family:inherit}
    .aoc-home-security-card h2{margin:0 0 8px;font-size:22px}.aoc-home-security-card p{color:#aeb8c4;margin:0 0 18px;line-height:1.5}
    .aoc-home-security-code{letter-spacing:9px;font-size:30px;font-weight:800;text-align:center;background:#151c24;border:1px solid #2d3947;border-radius:14px;padding:16px;margin:12px 0 18px;user-select:none}
    .aoc-home-security-input{width:100%;box-sizing:border-box;background:#080c11;color:#fff;border:1px solid #344150;border-radius:12px;padding:14px;font-size:20px;text-align:center;letter-spacing:7px;outline:none}
    .aoc-home-security-input:focus{border-color:#59d99a;box-shadow:0 0 0 3px rgba(89,217,154,.12)}
    .aoc-home-security-btn{width:100%;margin-top:14px;border:0;border-radius:12px;padding:14px;font-weight:800;cursor:pointer;background:#59d99a;color:#06110b}
    .aoc-home-security-error{min-height:22px;color:#ff8e8e;text-align:center;margin-top:10px;font-size:13px}
    .aoc-home-security-note{font-size:12px!important;text-align:center;margin-top:12px!important;color:#7f8a96!important}
  `;
  document.head.appendChild(s);
}

export function requireHomeSecurity() {
  if (sessionStorage.getItem(KEY) === "1") return;
  styles();
  const code = randomSixDigits();
  const wrap = document.createElement("div");
  wrap.className = "aoc-home-security-backdrop";
  wrap.innerHTML = `
    <div class="aoc-home-security-card" role="dialog" aria-modal="true" aria-labelledby="aocHomeSecurityTitle">
      <h2 id="aocHomeSecurityTitle">🔐 Verifikasi Beranda</h2>
      <p>Masukkan kode keamanan 6 digit yang tampil di bawah untuk membuka Beranda.</p>
      <div class="aoc-home-security-code" aria-label="Kode keamanan">${code}</div>
      <input class="aoc-home-security-input" id="aocHomeSecurityInput" inputmode="numeric" autocomplete="off" maxlength="6" placeholder="••••••" aria-label="Masukkan kode keamanan">
      <button class="aoc-home-security-btn" id="aocHomeSecurityBtn" type="button">Buka Beranda</button>
      <div class="aoc-home-security-error" id="aocHomeSecurityError"></div>
      <p class="aoc-home-security-note">Kode dibuat baru setiap kali Beranda dibuka.</p>
    </div>`;
  document.body.appendChild(wrap);
  const input = wrap.querySelector("#aocHomeSecurityInput");
  const btn = wrap.querySelector("#aocHomeSecurityBtn");
  const error = wrap.querySelector("#aocHomeSecurityError");
  const verify = () => {
    const value = input.value.replace(/\D/g, "").slice(0, 6);
    input.value = value;
    if (value !== code) {
      error.textContent = "Kode keamanan salah. Masukkan 6 digit yang tampil di atas.";
      input.value = "";
      input.focus();
      return;
    }
    sessionStorage.setItem(KEY, "1");
    wrap.remove();
  };
  input.addEventListener("input", () => {
    input.value = input.value.replace(/\D/g, "").slice(0, 6);
    error.textContent = "";
    if (input.value.length === 6) verify();
  });
  btn.addEventListener("click", verify);
  input.addEventListener("keydown", (e) => { if (e.key === "Enter") verify(); });
  setTimeout(() => input.focus(), 0);
}

// Saat meninggalkan Beranda, token verifikasi dibuang agar kunjungan berikutnya
// meminta challenge baru. Back/forward juga akan memicu verifikasi baru.
window.addEventListener("pagehide", () => sessionStorage.removeItem(KEY));
