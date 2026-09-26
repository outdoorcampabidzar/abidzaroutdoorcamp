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

function safeNextPage() {
  const rawNext = new URLSearchParams(location.search).get("next") || "index.html";
  try {
    const resolved = new URL(rawNext, location.href);
    if (resolved.origin !== location.origin) return "index.html";
    const filename = resolved.pathname.split("/").pop() || "index.html";
    return `${filename}${resolved.search}${resolved.hash}`;
  } catch {
    return "index.html";
  }
}

const nextPage = safeNextPage();

function clearMessage() {
  if (!messageBox) return;
  messageBox.textContent = "";
  messageBox.className = "notice hidden";
}

function showMessage(text, type = "warning") {
  if (typeof message === "function") {
    message(messageBox, text, type);
  } else if (messageBox) {
    messageBox.textContent = text;
    messageBox.className = `notice ${type}`;
  }
}

function normalizePhone(value) {
  const compact = String(value || "").replace(/[^\d+]/g, "");
  if (compact.startsWith("+62")) return `0${compact.slice(3)}`;
  if (compact.startsWith("62")) return `0${compact.slice(2)}`;
  return compact;
}

function validatePhone(value) {
  return /^08\d{8,12}$/.test(normalizePhone(value).replace(/\D/g, ""));
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
  if (!strengthBox || !strengthText || !passwordInput) return;
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
  document.querySelectorAll("[data-register-required]").forEach((field) => {
    field.required = enabled;
  });
  if (passwordInput) passwordInput.autocomplete = enabled ? "new-password" : "current-password";
}

function toggleOptionalField(field, hidden) {
  if (!field) return;
  field.classList.toggle("hidden", hidden);
  field.setAttribute("aria-hidden", String(hidden));
}

function setMode(nextMode) {
  mode = nextMode === "register" ? "register" : "login";
  const isRegister = mode === "register";

  page?.classList.toggle("is-register", isRegister);
  toggleOptionalField(registerFields, !isRegister);
  toggleOptionalField(confirmPasswordField, !isRegister);
  toggleOptionalField(termsField, !isRegister);
  toggleOptionalField(strengthBox, !isRegister);
  toggleOptionalField(transactionPinField, !isRegister);
  toggleOptionalField(confirmTransactionPinField, !isRegister);
  setRegisterRequired(isRegister);
  clearMessage();

  if (title) title.textContent = isRegister ? "Daftar Akun" : "Masuk ke Akun";
  if (badge) badge.textContent = isRegister ? "Buat Profil Baru" : "Selamat Datang";
  if (subtitle) {
    subtitle.textContent = isRegister
      ? "Lengkapi profil agar proses checkout berikutnya lebih cepat."
      : "Gunakan email dan password yang sudah terdaftar.";
  }
  if (submitButton) submitButton.textContent = isRegister ? "Buat Akun" : "Login";
  if (toggleButton) {
    toggleButton.textContent = isRegister ? "Sudah punya akun? Login" : "Belum punya akun? Daftar";
  }

  if (!isRegister) {
    if (confirmPasswordInput) confirmPasswordInput.value = "";
    if (transactionPinInput) transactionPinInput.value = "";
    if (confirmTransactionPinInput) confirmTransactionPinInput.value = "";
    const terms = form?.elements?.terms;
    if (terms) terms.checked = false;
  }

  requestAnimationFrame(() => {
    const target = isRegister ? form?.elements?.full_name : form?.elements?.email;
    target?.focus?.();
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

  if (fullName.length < 3) return "Nama lengkap minimal 3 karakter.";
  if (!validatePhone(phone)) return "Nomor WhatsApp tidak valid. Gunakan format 08xxxxxxxxxx.";
  if (city.length < 2) return "Kota atau kabupaten wajib diisi.";
  if (address.length < 8) return "Alamat domisili terlalu singkat.";
  if (password.length < 8) return "Password minimal 8 karakter.";
  if (passwordScore(password) < 2) return "Password terlalu lemah. Tambahkan kombinasi huruf dan angka.";
  if (password !== confirmation) return "Konfirmasi password tidak sama.";
  if (!/^\d{6}$/.test(transactionPin)) return "PIN transaksi harus tepat 6 digit.";
  if (transactionPin !== confirmTransactionPin) return "Konfirmasi PIN transaksi tidak sama.";
  if (new Set(transactionPin.split("")).size === 1) return "Jangan gunakan PIN yang semua angkanya sama.";

  const terms = form?.elements?.terms;
  if (terms && !terms.checked) return "Setujui penggunaan data profil untuk melanjutkan.";
  return "";
}

async function saveImmediateProfile(userId, profile) {
  if (!userId) return;
  const { error } = await supabase.rpc("complete_my_profile", { p_profile: profile });
  if (error) console.warn("Profil akan disinkronkan oleh trigger:", error.message);
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
    options: { data: profile }
  });

  if (error) throw error;

  if (data.session && data.user) {
    await saveImmediateProfile(data.user.id, profile);
    const { error: pinError } = await supabase.rpc("set_transaction_pin", { p_pin: transactionPin });
    if (pinError) {
      console.warn("PIN transaksi belum tersimpan:", pinError.message);
      showMessage("Akun berhasil dibuat, tetapi PIN transaksi belum tersimpan. Login tetap dapat digunakan.", "warning");
    } else {
      showMessage("Akun berhasil dibuat. Silakan lanjut.", "success");
    }
    setTimeout(() => { location.href = nextPage; }, 450);
    return;
  }

  // Supabase dapat mewajibkan konfirmasi email. Jangan menganggap pendaftaran gagal.
  showMessage("Akun berhasil dibuat. Silakan cek email untuk konfirmasi, lalu login.", "success");
  setMode("login");
  if (form?.elements?.email) form.elements.email.value = String(values.email || "").trim().toLowerCase();
  if (passwordInput) passwordInput.value = "";
}

async function login(values) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email: String(values.email || "").trim().toLowerCase(),
    password: String(values.password || "")
  });
  if (error) throw error;
  if (!data?.session) throw new Error("Login belum menghasilkan sesi. Silakan coba lagi.");
  showMessage("Login berhasil.", "success");
  setTimeout(() => { location.href = nextPage; }, 250);
}

function oauthRedirectUrl() {
  const url = new URL("login.html", window.location.href);
  if (nextPage && nextPage !== "index.html") url.searchParams.set("next", nextPage);
  return url.toString();
}

async function signInWithSocial(provider, button) {
  socialButtons.forEach((item) => { item.disabled = true; });
  const original = button.innerHTML;
  button.classList.add("is-loading");
  button.querySelector("small")?.replaceChildren(document.createTextNode("Membuka login..."));

  try {
    const { error } = await supabase.auth.signInWithOAuth({
      provider,
      options: {
        redirectTo: oauthRedirectUrl(),
        ...(provider === "google" ? { queryParams: { access_type: "offline", prompt: "select_account" } } : {})
      }
    });
    if (error) throw error;
  } catch (error) {
    showMessage(error?.message || `Login ${provider} gagal.`, "error");
    button.innerHTML = original;
    button.classList.remove("is-loading");
    socialButtons.forEach((item) => { item.disabled = false; });
  }
}

socialButtons.forEach((button) => {
  button.addEventListener("click", () => {
    if (mode !== "login") setMode("login");
    signInWithSocial(button.dataset.oauthProvider, button);
  });
});

form?.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (isSubmitting || !form) return;
  clearMessage();
  if (!form.reportValidity()) return;

  const values = Object.fromEntries(new FormData(form));
  if (mode === "register") {
    const validationError = validateRegistration(values);
    if (validationError) {
      showMessage(validationError, "error");
      return;
    }
  }

  isSubmitting = true;
  if (submitButton) {
    submitButton.disabled = true;
    submitButton.textContent = mode === "register" ? "Membuat Akun..." : "Memeriksa Akun...";
  }
  showMessage("Memproses data akun...", "warning");

  try {
    if (mode === "register") await register(values);
    else await login(values);
  } catch (error) {
    showMessage(error?.message || "Proses akun gagal.", "error");
  } finally {
    isSubmitting = false;
    if (submitButton) {
      submitButton.disabled = false;
      submitButton.textContent = mode === "register" ? "Buat Akun" : "Login";
    }
  }
});

toggleButton?.addEventListener("click", () => setMode(mode === "login" ? "register" : "login"));
passwordInput?.addEventListener("input", updatePasswordStrength);

[transactionPinInput, confirmTransactionPinInput].forEach((input) => {
  input?.addEventListener("input", () => {
    input.value = input.value.replace(/\D/g, "").slice(0, 6);
  });
});

document.querySelectorAll("[data-password-toggle]").forEach((button) => {
  button.addEventListener("click", () => {
    const input = document.getElementById(button.dataset.passwordToggle);
    if (!input) return;
    const willShow = input.type === "password";
    input.type = willShow ? "text" : "password";
    button.textContent = willShow ? "Sembunyi" : "Lihat";
    button.setAttribute("aria-label", willShow ? "Sembunyikan password" : "Tampilkan password");
  });
});

async function initAuth() {
  setMode("login");
  try {
    const { data, error } = await supabase.auth.getUser();
    if (error) {
      console.warn("Auth session check:", error.message);
      return;
    }
    if (data?.user) {
      setTimeout(() => { location.href = nextPage; }, 150);
    }
  } catch (error) {
    console.warn("Auth initialization failed:", error);
    showMessage("Layanan autentikasi belum siap. Periksa koneksi internet dan konfigurasi Supabase.", "error");
  }
}

initAuth();
