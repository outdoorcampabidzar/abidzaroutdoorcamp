// AOC — homepage 6-digit security gate (V10).
// The Beranda is ALWAYS blocked on a fresh open and when returning via browser
// back/forward cache. The visitor must enter exactly 6 numeric digits before
// the page can be used. No code is displayed on the Beranda.
export function mountHomeSecurityCode({ onVerify } = {}) {
  const gate = document.getElementById('homeSecurityGate');
  const form = document.getElementById('homeSecurityForm');
  const input = document.getElementById('homeSecurityInput');
  const status = document.getElementById('homeSecurityStatus');
  const button = document.getElementById('homeSecuritySubmit');
  if (!gate || !form || !input || !status || !button) return;

  const lock = () => {
    gate.classList.remove('hidden', 'is-closing');
    gate.setAttribute('aria-hidden', 'false');
    document.documentElement.classList.add('home-security-locked');
    document.body.classList.add('home-security-locked');
    input.disabled = false;
    button.disabled = false;
    input.value = '';
    status.textContent = 'Masukkan tepat 6 digit kode keamanan.';
    requestAnimationFrame(() => input.focus());
  };

  const unlock = () => {
    gate.classList.add('hidden');
    gate.setAttribute('aria-hidden', 'true');
    document.documentElement.classList.remove('home-security-locked');
    document.body.classList.remove('home-security-locked');
  };

  // IMPORTANT: do not use sessionStorage/localStorage. Every time Beranda
  // is opened, the code must be entered again.
  lock();

  input.addEventListener('input', () => {
    input.value = input.value.replace(/\D/g, '').slice(0, 6);
    status.textContent = input.value.length === 6
      ? 'Kode 6 digit siap diverifikasi.'
      : 'Masukkan tepat 6 digit kode keamanan.';
  });

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const code = input.value.trim();
    if (!/^\d{6}$/.test(code)) {
      status.textContent = 'Kode harus tepat 6 digit angka.';
      input.focus();
      return;
    }

    button.disabled = true;
    input.disabled = true;
    status.textContent = 'Memverifikasi kode...';
    try {
      const ok = typeof onVerify === 'function' ? await onVerify(code) : true;
      if (!ok) throw new Error('Kode keamanan tidak valid.');
      unlock();
    } catch (error) {
      status.textContent = error?.message || 'Kode keamanan tidak valid.';
      input.disabled = false;
      button.disabled = false;
      input.select();
    }
  });

  // Returning to Beranda with browser Back/Forward must lock it again.
  window.addEventListener('pageshow', (event) => {
    if (event.persisted) lock();
  });
}
