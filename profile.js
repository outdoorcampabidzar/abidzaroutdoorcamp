import { supabase, message } from "./app.js";

const form = document.getElementById("profileForm");
const saveButton = document.getElementById("profileSave");
const resetButton = document.getElementById("passwordReset");
const messageBox = document.getElementById("profileMessage");

let currentUser = null;

function initial(value) {
  return String(value || "U").trim().slice(0, 1).toUpperCase() || "U";
}

function normalizePhone(value) {
  const compact = String(value || "").replace(/[^\d+]/g, "");

  if (compact.startsWith("+62")) return `0${compact.slice(3)}`;
  if (compact.startsWith("62")) return `0${compact.slice(2)}`;

  return compact;
}

function updateSummary(profile) {
  const name = profile?.full_name?.trim() || currentUser?.email?.split("@")[0] || "Pengguna";
  const role = String(profile?.role || "user").toLowerCase() === "admin"
    ? "Administrator"
    : "Pengguna";

  document.querySelector("[data-profile-avatar]").textContent = initial(name);
  document.querySelector("[data-profile-name]").textContent = name;
  document.querySelector("[data-profile-email]").textContent = currentUser?.email || "-";
  document.querySelector("[data-profile-role]").textContent = role;
}

async function loadProfile() {
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    location.href = "login.html?next=profile.html";
    return;
  }

  currentUser = user;

  const { data, error } = await supabase
    .from("profiles")
    .select("full_name,phone,address,city,postal_code,role")
    .eq("id", user.id)
    .single();

  if (error && error.code !== "PGRST116") {
    message(messageBox, error.message, "error");
    return;
  }

  const profile = data || {};

  form.elements.full_name.value = profile.full_name || "";
  form.elements.email.value = user.email || "";
  form.elements.phone.value = profile.phone || "";
  form.elements.city.value = profile.city || "";
  form.elements.address.value = profile.address || "";
  form.elements.postal_code.value = profile.postal_code || "";

  updateSummary(profile);
}

form.addEventListener("submit", async event => {
  event.preventDefault();

  if (!form.reportValidity()) return;

  const values = Object.fromEntries(new FormData(form));
  const payload = {
    full_name: String(values.full_name || "").trim(),
    phone: normalizePhone(values.phone),
    city: String(values.city || "").trim(),
    address: String(values.address || "").trim(),
    postal_code: String(values.postal_code || "").trim() || null
  };

  saveButton.disabled = true;
  saveButton.textContent = "Menyimpan...";

  const { error } = await supabase
    .from("profiles")
    .update(payload)
    .eq("id", currentUser.id);

  saveButton.disabled = false;
  saveButton.textContent = "Simpan Profil";

  if (error) {
    message(messageBox, error.message, "error");
    return;
  }

  updateSummary({ ...payload, role: document.querySelector("[data-profile-role]").textContent === "Administrator" ? "admin" : "user" });
  message(messageBox, "Profil berhasil diperbarui.", "success");
});

resetButton.addEventListener("click", async () => {
  if (!currentUser?.email) return;

  resetButton.disabled = true;
  resetButton.textContent = "Mengirim...";

  const redirectTo = new URL("login.html", location.href).href;
  const { error } = await supabase.auth.resetPasswordForEmail(
    currentUser.email,
    { redirectTo }
  );

  resetButton.disabled = false;
  resetButton.textContent = "Kirim Email Ganti Password";

  if (error) {
    message(messageBox, error.message, "error");
    return;
  }

  message(
    messageBox,
    "Email untuk mengganti password sudah dikirim.",
    "success"
  );
});

loadProfile();
