import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";
import { CONFIG } from "./config.js";

export const supabase = createClient(
  CONFIG.SUPABASE_URL,
  CONFIG.SUPABASE_ANON_KEY,
);
export const DEFAULT_SITE_SETTINGS = Object.freeze({
  site_name: CONFIG.SITE_NAME || "AbidzarOutdoorcamp",
  whatsapp_number: CONFIG.WHATSAPP_NUMBER || "6289509349428",
  whatsapp_message:
    "Halo CS AbidzarOutdoorcamp, saya ingin bertanya mengenai layanan.",
  address: "",
  business_hours: "",
  google_maps_url: "",
  instagram_url: "",
  tiktok_url: "",
  hero_eyebrow: "Outdoor rental & open trip",
  hero_title: "Siapkan petualangan.",
  hero_subtitle: "Pesan semuanya di satu tempat.",
  hero_description:
    "Cari perlengkapan di katalog Sewa Item atau pilih perjalanan di katalog Open Trip. Keduanya tetap dapat digabungkan dalam satu keranjang dan satu checkout.",
  seo_title: "AbidzarOutdoorcamp — Sewa Outdoor & Open Trip",
  seo_description:
    "Katalog sewa perlengkapan outdoor dan open trip AbidzarOutdoorcamp.",
  rental_min_days: 1,
  rental_max_days: 30,
  payment_enabled: false,
  payment_method: "qrisorkut",
  payment_timeout_minutes: 15,
  late_fee_text: "",
  guarantee_policy: "",
  cancellation_policy: "",
  refund_policy: "",
  maintenance_mode: false,
  maintenance_message:
    "Website sedang dalam perawatan. Silakan hubungi kami melalui WhatsApp.",
});

let cachedSiteSettings = null;

export async function loadSiteSettings(force = false) {
  if (cachedSiteSettings && !force) return cachedSiteSettings;

  const { data, error } = await supabase
    .from("site_settings")
    .select("settings")
    .eq("id", "main")
    .maybeSingle();

  // Tabel pengaturan bersifat opsional agar website lama tetap berjalan
  // sebelum site-settings.sql dipasang.
  cachedSiteSettings = {
    ...DEFAULT_SITE_SETTINGS,
    ...(!error && data?.settings && typeof data.settings === "object"
      ? data.settings
      : {}),
  };

  return cachedSiteSettings;
}

export function applySiteSettings(settings) {
  const value = { ...DEFAULT_SITE_SETTINGS, ...(settings || {}) };
  const siteName = String(
    value.site_name || DEFAULT_SITE_SETTINGS.site_name,
  ).trim();
  const whatsapp = String(value.whatsapp_number || "").replace(/\D/g, "");
  const whatsappText = String(value.whatsapp_message || "").trim();

  document.querySelectorAll(".brand").forEach((element) => {
    const splitAt = siteName.toLowerCase().indexOf("outdoor");
    if (splitAt > 0) {
      element.replaceChildren(
        document.createTextNode(siteName.slice(0, splitAt)),
        Object.assign(document.createElement("span"), {
          textContent: siteName.slice(splitAt),
        }),
      );
    } else {
      element.textContent = siteName;
    }
  });

  if (document.title.includes("AbidzarOutdoorcamp")) {
    document.title = document.title.replace("AbidzarOutdoorcamp", siteName);
  }

  const isHomepage =
    /(?:^|\/)index\.html$/.test(location.pathname) ||
    location.pathname.endsWith("/");

  if (isHomepage) {
    if (value.seo_title) document.title = value.seo_title;
    const meta = document.querySelector('meta[name="description"]');
    if (meta && value.seo_description) meta.content = value.seo_description;
  }

  const content = {
    "site-hero-eyebrow": value.hero_eyebrow,
    "site-hero-title": value.hero_title,
    "site-hero-subtitle": value.hero_subtitle,
    "site-hero-description": value.hero_description,
  };

  Object.entries(content).forEach(([id, text]) => {
    const element = document.getElementById(id);
    if (element && text) element.textContent = text;
  });

  document.querySelectorAll(".customer-service-float").forEach((link) => {
    if (!whatsapp) {
      link.classList.add("hidden");
      return;
    }

    link.href = `https://wa.me/${whatsapp}?text=${encodeURIComponent(whatsappText)}`;
    link.title = `Hubungi CS: +${whatsapp}`;
    link.setAttribute("aria-label", `Hubungi CS ${siteName} melalui WhatsApp`);
  });

  document.documentElement.dataset.maintenance = String(
    Boolean(value.maintenance_mode),
  );
  window.dispatchEvent(
    new CustomEvent("site-settings-ready", { detail: value }),
  );
}
const CART_KEY = "tripkita_cart";
const LEGACY_CART_KEYS = [
  "tripkita_cart_v3",
  "tripkita_cart_v2",
  "tripkita_cart_v1",
];

export const rupiah = (n) =>
  new Intl.NumberFormat("id-ID", {
    style: "currency",
    currency: "IDR",
    maximumFractionDigits: 0,
  }).format(Number(n || 0));

export const esc = (value) =>
  String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");

export function message(el, text, type = "") {
  el.textContent = text;
  el.className = `notice ${type}`.trim();
  el.classList.remove("hidden");
}

export function getCart() {
  // Bila key utama sudah pernah dibuat, termasuk ketika nilainya [],
  // jangan membaca ulang key lama karena dapat menghidupkan kembali item terhapus.
  const currentValue = localStorage.getItem(CART_KEY);

  if (currentValue !== null) {
    try {
      const parsed = JSON.parse(currentValue);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      localStorage.setItem(CART_KEY, "[]");
      return [];
    }
  }

  // Migrasi keranjang lama hanya satu kali.
  for (const key of LEGACY_CART_KEYS) {
    try {
      const parsed = JSON.parse(localStorage.getItem(key) || "[]");

      if (Array.isArray(parsed) && parsed.length > 0) {
        localStorage.setItem(CART_KEY, JSON.stringify(parsed));
        LEGACY_CART_KEYS.forEach((oldKey) => localStorage.removeItem(oldKey));
        return parsed;
      }
    } catch {
      localStorage.removeItem(key);
    }
  }

  localStorage.setItem(CART_KEY, "[]");
  LEGACY_CART_KEYS.forEach((key) => localStorage.removeItem(key));
  return [];
}

export function saveCart(cart) {
  const safeCart = Array.isArray(cart) ? cart : [];
  localStorage.setItem(CART_KEY, JSON.stringify(safeCart));

  // Bersihkan semua penyimpanan versi lama agar item terhapus tidak muncul kembali.
  LEGACY_CART_KEYS.forEach((key) => localStorage.removeItem(key));
  updateCartBadge();
}

export function addCart(item, qty = 1, replace = false, selectedVariant = null) {
  const variant = selectedVariant?.id ? selectedVariant : null;
  const max = Math.max(
    1,
    Number(item.type === "trip" ? item.quota : variant ? variant.stock : item.stock) || 0,
  );
  const cartKey = `${item.id}:${variant?.id || "default"}`;
  const entry = {
    cart_key: cartKey,
    item_id: item.id,
    title: item.title,
    price: Number(item.price) + Number(variant?.price_adjustment || 0),
    image_url: item.image_url,
    type: item.type,
    trip_date: item.trip_date,
    location: item.location,
    quantity: Math.min(max, Math.max(1, Number(qty))),
    max_quantity: max,
    variant_id: variant?.id || null,
    variant_name: variant
      ? [variant.name, variant.capacity].filter(Boolean).join(" · ")
      : "",
    variant_price_adjustment: Number(variant?.price_adjustment || 0),
    requires_guarantee: Boolean(item.requires_guarantee),
    guarantee_note: item.guarantee_note || "",
    deposit: Number(item.deposit || 0),
    variants: item.item_variants || [],
    price_tiers: item.item_price_tiers || [],
  };
  if (replace) return saveCart([entry]);
  const cart = getCart();
  const old = cart.find(
    (x) => (x.cart_key || `${x.item_id}:default`) === cartKey,
  );
  if (old) old.quantity = Math.min(max, Number(old.quantity) + entry.quantity);
  else cart.push(entry);
  saveCart(cart);
}

export function updateCartBadge() {
  const count = getCart().reduce((s, x) => s + Number(x.quantity || 0), 0);
  document.querySelectorAll("[data-cart-count]").forEach((el) => {
    el.textContent = count;
    el.classList.toggle("hidden", count === 0);
  });
}

export async function setupNav() {
  updateCartBadge();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const loginElements = document.querySelectorAll("[data-login]");
  const logoutElements = document.querySelectorAll("[data-logout]");
  const adminElements = document.querySelectorAll("[data-admin]");
  const accountMenus = document.querySelectorAll("[data-account-menu]");
  const notificationElements = document.querySelectorAll("[data-notification]");
  const userNames = document.querySelectorAll("[data-user-name]");
  const userFullNames = document.querySelectorAll("[data-user-full-name]");
  const userEmails = document.querySelectorAll("[data-user-email]");
  const userRoles = document.querySelectorAll("[data-user-role]");
  const userAvatars = document.querySelectorAll("[data-user-avatar]");

  loginElements.forEach((element) =>
    element.classList.toggle("hidden", Boolean(user)),
  );

  logoutElements.forEach((element) =>
    element.classList.toggle("hidden", !user),
  );

  accountMenus.forEach((element) => element.classList.toggle("hidden", !user));

  notificationElements.forEach((element) =>
    element.classList.toggle("hidden", !user),
  );

  let hasAdminAccess = false;

  if (user) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("role,full_name")
      .eq("id", user.id)
      .single();

    const displayName =
      profile?.full_name?.trim() || user.email?.split("@")[0] || "Pengguna";

    const compactName =
      displayName.split(/\s+/).filter(Boolean)[0] || "Pengguna";

    const initial = compactName.slice(0, 1).toUpperCase() || "U";

    const normalizedRole = String(profile?.role || "")
      .trim()
      .toLowerCase();

    hasAdminAccess = normalizedRole === "admin";

    if (!hasAdminAccess) {
      const { data: rpcAdmin } = await supabase.rpc("is_admin");
      hasAdminAccess = rpcAdmin === true;
    }

    userNames.forEach((element) => {
      element.textContent = `Halo, ${compactName}`;
      element.title = `Login sebagai ${displayName}`;
    });

    userFullNames.forEach((element) => {
      element.textContent = displayName;
    });

    userEmails.forEach((element) => {
      element.textContent = user.email || "-";
    });

    userRoles.forEach((element) => {
      element.textContent = hasAdminAccess ? "Administrator" : "Pengguna";
    });

    userAvatars.forEach((element) => {
      element.textContent = initial;
    });
  }

  adminElements.forEach((element) => {
    element.classList.toggle("hidden", !hasAdminAccess);
    element.setAttribute("aria-hidden", String(!hasAdminAccess));
  });

  logoutElements.forEach((button) => {
    button.onclick = async () => {
      await supabase.auth.signOut();
      location.href = "index.html";
    };
  });

  const accountToggle = document.querySelector("[data-user-menu-toggle]");
  const accountDropdown = document.querySelector("[data-user-dropdown]");

  const closeAccountMenu = () => {
    if (!accountToggle || !accountDropdown) return;

    accountDropdown.classList.remove("is-open");
    accountDropdown.setAttribute("aria-hidden", "true");
    accountToggle.setAttribute("aria-expanded", "false");
  };

  const openAccountMenu = () => {
    if (!accountToggle || !accountDropdown) return;

    accountDropdown.classList.add("is-open");
    accountDropdown.setAttribute("aria-hidden", "false");
    accountToggle.setAttribute("aria-expanded", "true");
  };

  if (
    accountToggle &&
    accountDropdown &&
    accountToggle.dataset.bound !== "true"
  ) {
    accountToggle.dataset.bound = "true";

    accountToggle.addEventListener("click", (event) => {
      event.stopPropagation();

      if (accountDropdown.classList.contains("is-open")) {
        closeAccountMenu();
      } else {
        openAccountMenu();
      }
    });

    accountDropdown.addEventListener("click", (event) => {
      event.stopPropagation();

      if (event.target.closest("a, [data-logout]")) {
        closeAccountMenu();
      }
    });

    document.addEventListener("click", (event) => {
      if (
        !accountDropdown.contains(event.target) &&
        !accountToggle.contains(event.target)
      ) {
        closeAccountMenu();
      }
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        closeAccountMenu();
        accountToggle.focus();
      }
    });
  }

  const navToggle = document.querySelector("[data-nav-toggle]");
  const navMenu = document.querySelector("[data-nav-menu]");

  if (navToggle && navMenu && navToggle.dataset.bound !== "true") {
    navToggle.dataset.bound = "true";

    const closeMenu = () => {
      navMenu.classList.remove("is-open");
      navToggle.setAttribute("aria-expanded", "false");
      navToggle.innerHTML = '<span aria-hidden="true">☰</span>';
      closeAccountMenu();
    };

    const openMenu = () => {
      navMenu.classList.add("is-open");
      navToggle.setAttribute("aria-expanded", "true");
      navToggle.innerHTML = '<span aria-hidden="true">✕</span>';
    };

    navToggle.addEventListener("click", (event) => {
      event.stopPropagation();

      if (navMenu.classList.contains("is-open")) closeMenu();
      else openMenu();
    });

    navMenu.querySelectorAll("a, button").forEach((element) => {
      element.addEventListener("click", () => {
        if (
          window.innerWidth <= 1080 &&
          !element.matches("[data-user-menu-toggle]")
        ) {
          closeMenu();
        }
      });
    });

    document.addEventListener("click", (event) => {
      if (
        window.innerWidth <= 1080 &&
        navMenu.classList.contains("is-open") &&
        !navMenu.contains(event.target) &&
        !navToggle.contains(event.target)
      ) {
        closeMenu();
      }
    });

    window.addEventListener("resize", () => {
      if (window.innerWidth > 1080) {
        closeMenu();
      }
    });
  }
}

document.addEventListener("DOMContentLoaded", () => {
  setupNav();
  loadSiteSettings()
    .then(applySiteSettings)
    .catch(() => {
      applySiteSettings(DEFAULT_SITE_SETTINGS);
    });
});
