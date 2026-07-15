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
const messageBox = document.getElementById("authMessage");
const passwordInput = document.getElementById("authPassword");
const confirmPasswordInput = document.getElementById("confirmPassword");

let mode = "login";
let isSubmitting = false;

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
  mode = nextMode;
  const isRegister = mode === "register";

  page.classList.toggle("is-register", isRegister);
  registerFields.classList.toggle("hidden", !isRegister);
  confirmPasswordField.classList.toggle("hidden", !isRegister);
  termsField.classList.toggle("hidden", !isRegister);
  strengthBox.classList.toggle("hidden", !isRegister);

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

    message(
      messageBox,
      "Akun berhasil dibuat. Mengarahkan ke halaman berikutnya...",
      "success"
    );

    setTimeout(() => {
      location.href = nextPage;
    }, 700);

    return;
  }

  message(
    messageBox,
    "Pendaftaran berhasil. Periksa email untuk konfirmasi akun, lalu login.",
    "success"
  );

  form.reset();
  setMode("login");
  form.elements.email.value =
    String(values.email || "").trim().toLowerCase();
}

async function login(values) {
  const { error } = await supabase.auth.signInWithPassword({
    email: String(values.email || "").trim().toLowerCase(),
    password: String(values.password || "")
  });

  if (error) throw error;

  location.href = nextPage;
}

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

const { data: { user } } = await supabase.auth.getUser();

if (user) {
  location.href = nextPage;
} else {
  setMode("login");
}
