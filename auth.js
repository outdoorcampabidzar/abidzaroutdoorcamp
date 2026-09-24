import { supabase, message } from "./app.js";

const page = document.getElementById("authPage");
const form = document.getElementById("authForm");
const registerFields = document.getElementById("registerFields");
const confirmPasswordField = document.getElementById("confirmPasswordField");
const termsField = document.getElementById("termsField");
const strengthBox = document.getElementById("passwordStrength");
const strengthText = document.getElementById("passwordStrengthText");
const title = document.getElementById("authTitle");
const subtitle = document.getElementById("authSubtitle");
const badge = document.getElementById("authBadge");
const submitButton = document.getElementById("authSubmit");
const toggleButton = document.getElementById("authToggle");
const socialButtons = [...document.querySelectorAll("[data-oauth-provider]")];
const messageBox = document.getElementById("authMessage");
const passwordInput = document.getElementById("authPassword");
const confirmPasswordInput = document.getElementById("confirmPassword");
const transactionPinField = document.getElementById("transactionPinField");
const confirmTransactionPinField = document.getElementById("confirmTransactionPinField");
const transactionPinInput = document.getElementById("transactionPin");
const confirmTransactionPinInput = document.getElementById("confirmTransactionPin");

let mode = "login";
let isSubmitting = false;
let pendingCodeType = null;
let pendingCode = null;

const authCodePanel = document.getElementById("authCodePanel");
const authCodeTitle = document.getElementById("authCodeTitle");
const authCodeHint = document.getElementById("authCodeHint");
const authCodeDisplay = document.getElementById("authCodeDisplay");
const authCodeInput = document.getElementById("authCodeInput");
const authCodeVerify = document.getElementById("authCodeVerify");
const authCodeNew = document.getElementById("authCodeNew");
const authLockOverlay = document.getElementById("authLockOverlay");
const authLockPanelHost = document.getElementById("authLockPanelHost");
const authCodePanelPlaceholder = document.getElementById("authCodePanelPlaceholder");

function setAuthLock(locked) {
  document.body.classList.toggle("auth-locked", locked);
  if (authLockOverlay) {
    authLockOverlay.classList.toggle("hidden", !locked);
    authLockOverlay.setAttribute("aria-hidden", String(!locked));
  }
  if (page) page.inert = locked;
  document.querySelectorAll("body > nav, body > .customer-service-float").forEach(el => {
    if (locked) el.setAttribute("inert", "");
    else el.removeAttribute("inert");
  });
}

function hideCodePanel() {
  setAuthLock(false);
  authCodePanel.classList.add("hidden");
  if (authCodePanelPlaceholder?.parentNode) {
    authCodePanelPlaceholder.parentNode.insertBefore(authCodePanel, authCodePanelPlaceholder.nextSibling);
  }
  authCodeDisplay.textContent = "------";
  authCodeInput.value = "";
  pendingCodeType = null;
  pendingCode = null;
}

function showCodePanel(type, code) {
  pendingCodeType = type;
  pendingCode = String(code || "");
  authCodeTitle.textContent = type === "login" ? "Kode Login" : "Kode Aktivasi";
  authCodeHint.textContent = type === "login"
    ? "Setiap login menghasilkan kode 6 digit acak. Masukkan kode yang tampil untuk melanjutkan."
    : "Akun dibuat. Masukkan kode 6 digit yang tampil untuk mengaktifkan akun.";
  authCodeDisplay.textContent = pendingCode || "------";
  if (authLockPanelHost) authLockPanelHost.appendChild(authCodePanel);
  authCodePanel.classList.remove("hidden");
  setAuthLock(true);
  authCodeInput.value = "";
  requestAnimationFrame(() => authCodeInput.focus());
}

async function issueCode(type) {
  const fn = type === "login" ? "issue_login_code" : "issue_account_activation_code";
  const { data, error } = await supabase.rpc(fn);
  if (error) throw error;
  const code = data?.code ?? data;
  if (!/^\d{6}$/.test(String(code || ""))) {
    throw new Error("Supabase tidak mengembalikan kode 6 digit.");
  }
  showCodePanel(type, String(code));
  message(messageBox, type === "login" ? "Kode login baru berhasil dibuat." : "Kode aktivasi berhasil dibuat.", "success");
}

async function verifyCode() {
  if (!pendingCodeType) return;
  const code = String(authCodeInput.value || "").replace(/\D/g, "");
  if (!/^\d{6}$/.test(code)) {
    message(messageBox, "Masukkan tepat 6 digit kode.", "error");
    return;
  }

  authCodeVerify.disabled = true;
  try {
    const fn = pendingCodeType === "login" ? "verify_login_code" : "verify_account_activation_code";
    const { data, error } = await supabase.rpc(fn, { p_code: code });
    if (error) throw error;
    if (data === false || data?.success === false) throw new Error("Kode salah atau sudah kedaluwarsa.");

    const verifiedType = pendingCodeType;
    hideCodePanel();
    message(messageBox, verifiedType === "login" ? "Login berhasil." : "Akun berhasil diaktifkan.", "success");
    setTimeout(() => { location.href = nextPage; }, 400);
  } catch (error) {
    message(messageBox, error.message || "Kode tidak valid.", "error");
  } finally {
    authCodeVerify.disabled = false;
  }
}

function safeNextPage() {
  const rawNext =
    new URLSearchParams(location.search).get("next") || "index.html";

  try {
    const resolved = new URL(rawNext, location.href);

    if (resolved.origin !== location.origin) return "index.html";

    return `${resolved.pathname.split("/").pop() || "index.html"}${resolved.search}${resolved.hash}`;
  } catch {
    return "index.html";
  }
}

const nextPage = safeNextPage();

function clearMessage() {
  messageBox.textContent = "";
  messageBox.className = "notice hidden";
}

function normalizePhone(value) {
  const compact = String(value || "").replace(/[^\d+]/g, "");

  if (compact.startsWith("+62")) return `0${compact.slice(3)}`;
  if (compact.startsWith("62")) return `0${compact.slice(2)}`;

  return compact;
}

function validatePhone(value) {
  const digits = normalizePhone(value).replace(/\D/g, "");
  return /^08\d{8,12}$/.test(digits);
}

function passwordScore(value) {
  const password = String(value || "");
  let score = 0;

  if (password.length >= 8) score += 1;
  if (/[a-z]/.test(password) && /[A-Z]/.test(password)) score += 1;
  if (/\d/.test(password)) score += 1;
  if (/[^A-Za-z0-9]/.test(password) || password.length >= 12) score += 1;

  return score;
}

function updatePasswordStrength() {
  const score = passwordScore(passwordInput.value);
  const bars = strengthBox.querySelectorAll(".password-strength-bars span");
  const labels = [
    "Password terlalu lemah.",
    "Password masih lemah.",
    "Password cukup.",
    "Password kuat.",
    "Password sangat kuat."
  ];

  bars.forEach((bar, index) => {
    bar.classList.toggle("active", index < score);
    bar.dataset.level = String(score);
  });

  strengthText.textContent = labels[score];
}

function setRegisterRequired(enabled) {
  document.querySelectorAll("[data-register-required]").forEach(field => {
    field.required = enabled;
  });

  passwordInput.autocomplete = enabled
    ? "new-password"
    : "current-password";
}

function setMode(nextMode) {
  hideCodePanel();
  mode = nextMode;
  const isRegister = mode === "register";

  page.classList.toggle("is-register", isRegister);
  registerFields.classList.toggle("hidden", !isRegister);
  confirmPasswordField.classList.toggle("hidden", !isRegister);
  termsField.classList.toggle("hidden", !isRegister);
  strengthBox.classList.toggle("hidden", !isRegister);
  transactionPinField.classList.toggle("hidden", !isRegister);
  confirmTransactionPinField.classList.toggle("hidden", !isRegister);
  transactionPinField.setAttribute("aria-hidden", String(!isRegister));
  confirmTransactionPinField.setAttribute("aria-hidden", String(!isRegister));

  registerFields.setAttribute("aria-hidden", String(!isRegister));
  confirmPasswordField.setAttribute("aria-hidden", String(!isRegister));
  termsField.setAttribute("aria-hidden", String(!isRegister));

  setRegisterRequired(isRegister);
  clearMessage();

  title.textContent = isRegister ? "Daftar Akun" : "Masuk ke Akun";
  badge.textContent = isRegister ? "Buat Profil Baru" : "Selamat Datang";

  subtitle.textContent = isRegister
    ? "Lengkapi profil agar proses checkout berikutnya lebih cepat."
    : "Gunakan email dan password yang sudah terdaftar.";

  submitButton.textContent = isRegister ? "Buat Akun" : "Login";

  toggleButton.textContent = isRegister
    ? "Sudah punya akun? Login"
    : "Belum punya akun? Daftar";

  if (!isRegister) {
    confirmPasswordInput.value = "";
    transactionPinInput.value = "";
    confirmTransactionPinInput.value = "";
    form.elements.terms.checked = false;
  }

  requestAnimationFrame(() => {
    (isRegister
      ? form.elements.full_name
      : form.elements.email
    )?.focus();
  });
}

function validateRegistration(values) {
  const fullName = String(values.full_name || "").trim();
  const phone = normalizePhone(values.phone);
  const city = String(values.city || "").trim();
  const address = String(values.address || "").trim();
  const password = String(values.password || "");
  const confirmation = String(values.confirm_password || "");
  const transactionPin = String(values.transaction_pin || "").replace(/\D/g, "");
  const confirmTransactionPin = String(values.confirm_transaction_pin || "").replace(/\D/g, "");

  if (fullName.length < 3) {
    return "Nama lengkap minimal 3 karakter.";
  }

  if (!validatePhone(phone)) {
    return "Nomor WhatsApp tidak valid. Gunakan format 08xxxxxxxxxx.";
  }

  if (city.length < 2) {
    return "Kota atau kabupaten wajib diisi.";
  }

  if (address.length < 8) {
    return "Alamat domisili terlalu singkat.";
  }

  if (password.length < 8) {
    return "Password minimal 8 karakter.";
  }

  if (passwordScore(password) < 2) {
    return "Password terlalu lemah. Tambahkan kombinasi huruf dan angka.";
  }

  if (password !== confirmation) {
    return "Konfirmasi password tidak sama.";
  }

  if (!/^\d{6}$/.test(transactionPin)) {
    return "PIN transaksi harus tepat 6 digit.";
  }

  if (transactionPin !== confirmTransactionPin) {
    return "Konfirmasi PIN transaksi tidak sama.";
  }

  if (new Set(transactionPin.split("")).size === 1) {
    return "Jangan gunakan PIN yang semua angkanya sama.";
  }

  if (!form.elements.terms.checked) {
    return "Setujui penggunaan data profil untuk melanjutkan.";
  }

  return "";
}

async function saveImmediateProfile(userId, profile) {
  const { error } = await supabase.rpc("complete_my_profile", {
    p_profile: profile
  });

  // Trigger database tetap menjadi mekanisme utama saat konfirmasi email aktif.
  if (error) {
    console.warn("Profil akan disinkronkan oleh trigger:", error.message);
  }
}

async function register(values) {
  const profile = {
    full_name: String(values.full_name || "").trim(),
    phone: normalizePhone(values.phone),
    city: String(values.city || "").trim(),
    address: String(values.address || "").trim(),
    postal_code: String(values.postal_code || "").trim() || null
  };
  const transactionPin = String(values.transaction_pin || "").replace(/\D/g, "");

  const { data, error } = await supabase.auth.signUp({
    email: String(values.email || "").trim().toLowerCase(),
    password: String(values.password || ""),
    options: {
      data: profile
    }
  });

  if (error) throw error;

  if (data.session && data.user) {
    await saveImmediateProfile(data.user.id, profile);
    const { error: pinError } = await supabase.rpc("set_transaction_pin", { p_pin: transactionPin });
    if (pinError) throw pinError;
    await issueCode("register");
    message(messageBox, "Akun berhasil dibuat. Masukkan kode aktivasi 6 digit.", "success");
    return;
  }

  throw new Error("Akun dibuat tetapi sesi belum tersedia. Matikan Confirm email di Supabase → Authentication → Sign In / Providers → Email, lalu daftar lagi.");
}

async function login(values) {
  const { error } = await supabase.auth.signInWithPassword({
    email: String(values.email || "").trim().toLowerCase(),
    password: String(values.password || "")
  });

  if (error) throw error;

  await issueCode("login");
  message(messageBox, "Password benar. Masukkan kode login 6 digit untuk melanjutkan.", "success");
}

function oauthRedirectUrl() {
  // OAuth Google harus kembali langsung ke halaman utama AOC.
  // Menggunakan URL relatif menjaga path /src/ saat AOC dipasang di GitHub Pages.
  return new URL("index.html", window.location.href).toString();
}

async function signInWithSocial(provider, button) {
  socialButtons.forEach(item => { item.disabled = true; });
  const original = button.innerHTML;
  button.classList.add("is-loading");
  button.querySelector("small")?.replaceChildren(document.createTextNode("Membuka login..."));

  try {
    const { error } = await supabase.auth.signInWithOAuth({
      provider,
      options: {
        redirectTo: oauthRedirectUrl(),
        queryParams: provider === "google" ? { access_type: "offline", prompt: "select_account" } : undefined
      }
    });
    if (error) throw error;
  } catch (error) {
    message(messageBox, error.message || `Login ${provider} gagal.`, "error");
    button.innerHTML = original;
    button.classList.remove("is-loading");
    socialButtons.forEach(item => { item.disabled = false; });
  }
}

socialButtons.forEach(button => {
  button.addEventListener("click", () => {
    if (mode !== "login") setMode("login");
    signInWithSocial(button.dataset.oauthProvider, button);
  });
});

form.addEventListener("submit", async event => {
  event.preventDefault();

  if (isSubmitting) return;

  clearMessage();

  if (!form.reportValidity()) return;

  const values = Object.fromEntries(new FormData(form));

  if (mode === "register") {
    const validationError = validateRegistration(values);

    if (validationError) {
      message(messageBox, validationError, "error");
      return;
    }
  }

  isSubmitting = true;
  submitButton.disabled = true;
  submitButton.textContent =
    mode === "register" ? "Membuat Akun..." : "Memeriksa Akun...";

  message(messageBox, "Memproses data akun...", "warning");

  try {
    if (mode === "register") await register(values);
    else await login(values);
  } catch (error) {
    message(messageBox, error.message || "Proses akun gagal.", "error");
  } finally {
    isSubmitting = false;
    submitButton.disabled = false;
    submitButton.textContent =
      mode === "register" ? "Buat Akun" : "Login";
  }
});

toggleButton.addEventListener("click", () => {
  setMode(mode === "login" ? "register" : "login");
});

passwordInput.addEventListener("input", updatePasswordStrength);

authCodeInput.addEventListener("input", () => {
  authCodeInput.value = authCodeInput.value.replace(/\D/g, "").slice(0, 6);
});

[transactionPinInput, confirmTransactionPinInput].forEach((input) => {
  input?.addEventListener("input", () => {
    input.value = input.value.replace(/\D/g, "").slice(0, 6);
  });
});
authCodeVerify.addEventListener("click", verifyCode);
authCodeNew.addEventListener("click", async () => {
  if (!pendingCodeType) return;
  authCodeNew.disabled = true;
  try { await issueCode(pendingCodeType); }
  catch (error) { message(messageBox, error.message || "Gagal membuat kode baru.", "error"); }
  finally { authCodeNew.disabled = false; }
});

document.querySelectorAll("[data-password-toggle]").forEach(button => {
  button.addEventListener("click", () => {
    const input = document.getElementById(button.dataset.passwordToggle);
    const willShow = input.type === "password";

    input.type = willShow ? "text" : "password";
    button.textContent = willShow ? "Sembunyi" : "Lihat";
    button.setAttribute(
      "aria-label",
      willShow ? "Sembunyikan password" : "Tampilkan password"
    );
  });
});

document.addEventListener("keydown", event => {
  if (authLockOverlay && !authLockOverlay.classList.contains("hidden") && event.key === "Escape") {
    event.preventDefault();
    authCodeInput.focus();
  }
});

window.addEventListener("beforeunload", () => {
  // Do not persist a successful verification flag in localStorage/sessionStorage.
});

const { data: { user } } = await supabase.auth.getUser();

if (user) {
  setMode("login");
  try {
    await issueCode("login");
  } catch (error) {
    console.warn("Kode login otomatis gagal:", error.message);
    message(messageBox, "Sesi ditemukan. Silakan login ulang untuk mendapatkan kode 6 digit.", "warning");
  }
} else {
  setMode("login");
}
