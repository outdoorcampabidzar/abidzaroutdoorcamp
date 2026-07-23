import { supabase, message } from "./app.js";

const form = document.getElementById("profileForm");
const saveButton = document.getElementById("profileSave");
const resetButton = document.getElementById("passwordReset");
const messageBox = document.getElementById("profileMessage");

let currentUser = null;
let currentAvatarUrl = "";

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

  const avatar = document.querySelector("[data-profile-avatar]");
  const avatarUrl = String(profile?.avatar_url || currentAvatarUrl || "").trim();
  avatar.innerHTML = "";
  if (avatarUrl) {
    const image = document.createElement("img");
    image.src = avatarUrl;
    image.alt = `Foto profil ${name}`;
    avatar.appendChild(image);
  } else {
    avatar.textContent = initial(name);
  }
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
    .select("full_name,phone,address,city,postal_code,role,avatar_url")
    .eq("id", user.id)
    .single();

  if (error && error.code !== "PGRST116") {
    message(messageBox, error.message, "error");
    return;
  }

  const profile = data || {};
  currentAvatarUrl = profile.avatar_url || "";

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
  const avatarFile = document.getElementById("profileAvatarFile").files?.[0];
  if (avatarFile) {
    if (avatarFile.size > 3 * 1024 * 1024) {
      message(messageBox, "Foto profil maksimal 3 MB.", "error");
      return;
    }
    if (!["image/jpeg", "image/png", "image/webp"].includes(avatarFile.type)) {
      message(messageBox, "Gunakan foto JPG, PNG, atau WEBP.", "error");
      return;
    }
  }
  const payload = {
    full_name: String(values.full_name || "").trim(),
    phone: normalizePhone(values.phone),
    city: String(values.city || "").trim(),
    address: String(values.address || "").trim(),
    postal_code: String(values.postal_code || "").trim() || null,
    avatar_url: currentAvatarUrl || null
  };

  saveButton.disabled = true;
  saveButton.textContent = "Menyimpan...";

  if (avatarFile) {
    const extension = avatarFile.name.split(".").pop()?.toLowerCase() || "jpg";
    const path = `${currentUser.id}/avatar.${extension}`;
    const { error: uploadError } = await supabase.storage
      .from("avatars")
      .upload(path, avatarFile, { upsert: true, cacheControl: "3600" });
    if (uploadError) {
      saveButton.disabled = false;
      saveButton.textContent = "Simpan Profil";
      message(messageBox, `Upload foto gagal: ${uploadError.message}`, "error");
      return;
    }
    currentAvatarUrl =
      `${supabase.storage.from("avatars").getPublicUrl(path).data.publicUrl}?v=${Date.now()}`;
    payload.avatar_url = currentAvatarUrl;
  }

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

  document.getElementById("profileAvatarFile").value = "";
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
