import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";
import { CONFIG } from "./config.js";

export const supabase = createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY);
const CART_KEY = "tripkita_cart";
const LEGACY_CART_KEYS = [
  "tripkita_cart_v3",
  "tripkita_cart_v2",
  "tripkita_cart_v1"
];

export const rupiah = n => new Intl.NumberFormat("id-ID", {
  style: "currency", currency: "IDR", maximumFractionDigits: 0
}).format(Number(n || 0));

export const esc = value => String(value ?? "")
  .replaceAll("&", "&amp;").replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;").replaceAll('"', "&quot;")
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
        LEGACY_CART_KEYS.forEach(oldKey => localStorage.removeItem(oldKey));
        return parsed;
      }
    } catch {
      localStorage.removeItem(key);
    }
  }

  localStorage.setItem(CART_KEY, "[]");
  LEGACY_CART_KEYS.forEach(key => localStorage.removeItem(key));
  return [];
}

export function saveCart(cart) {
  const safeCart = Array.isArray(cart) ? cart : [];
  localStorage.setItem(CART_KEY, JSON.stringify(safeCart));

  // Bersihkan semua penyimpanan versi lama agar item terhapus tidak muncul kembali.
  LEGACY_CART_KEYS.forEach(key => localStorage.removeItem(key));
  updateCartBadge();
}

export function addCart(item, qty = 1, replace = false) {
  const max = Math.max(1, Number(item.type === "trip" ? item.quota : item.stock) || 99);
  const entry = {
    item_id: item.id, title: item.title, price: Number(item.price),
    image_url: item.image_url, type: item.type, trip_date: item.trip_date,
    location: item.location, quantity: Math.min(max, Math.max(1, Number(qty))),
    max_quantity: max, requires_guarantee: Boolean(item.requires_guarantee),
    guarantee_note: item.guarantee_note || ""
  };
  if (replace) return saveCart([entry]);
  const cart = getCart();
  const old = cart.find(x => x.item_id === item.id);
  if (old) old.quantity = Math.min(max, Number(old.quantity) + entry.quantity);
  else cart.push(entry);
  saveCart(cart);
}

export function updateCartBadge() {
  const count = getCart().reduce((s, x) => s + Number(x.quantity || 0), 0);
  document.querySelectorAll("[data-cart-count]").forEach(el => {
    el.textContent = count;
    el.classList.toggle("hidden", count === 0);
  });
}

export async function setupNav() {
  updateCartBadge();

  const { data: { user } } = await supabase.auth.getUser();

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

  loginElements.forEach(element =>
    element.classList.toggle("hidden", Boolean(user))
  );

  logoutElements.forEach(element =>
    element.classList.toggle("hidden", !user)
  );

  accountMenus.forEach(element =>
    element.classList.toggle("hidden", !user)
  );

  notificationElements.forEach(element =>
    element.classList.toggle("hidden", !user)
  );

  let hasAdminAccess = false;

  if (user) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("role,full_name")
      .eq("id", user.id)
      .single();

    const displayName =
      profile?.full_name?.trim() ||
      user.email?.split("@")[0] ||
      "Pengguna";

    const compactName =
      displayName.split(/\s+/).filter(Boolean)[0] || "Pengguna";

    const initial =
      compactName.slice(0, 1).toUpperCase() || "U";

    const normalizedRole =
      String(profile?.role || "").trim().toLowerCase();

    hasAdminAccess = normalizedRole === "admin";

    if (!hasAdminAccess) {
      const { data: rpcAdmin } = await supabase.rpc("is_admin");
      hasAdminAccess = rpcAdmin === true;
    }

    userNames.forEach(element => {
      element.textContent = `Halo, ${compactName}`;
      element.title = `Login sebagai ${displayName}`;
    });

    userFullNames.forEach(element => {
      element.textContent = displayName;
    });

    userEmails.forEach(element => {
      element.textContent = user.email || "-";
    });

    userRoles.forEach(element => {
      element.textContent = hasAdminAccess ? "Administrator" : "Pengguna";
    });

    userAvatars.forEach(element => {
      element.textContent = initial;
    });
  }

  adminElements.forEach(element => {
    element.classList.toggle("hidden", !hasAdminAccess);
    element.setAttribute("aria-hidden", String(!hasAdminAccess));
  });

  logoutElements.forEach(button => {
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

    accountToggle.addEventListener("click", event => {
      event.stopPropagation();

      if (accountDropdown.classList.contains("is-open")) {
        closeAccountMenu();
      } else {
        openAccountMenu();
      }
    });

    accountDropdown.addEventListener("click", event => {
      event.stopPropagation();

      if (event.target.closest("a, [data-logout]")) {
        closeAccountMenu();
      }
    });

    document.addEventListener("click", event => {
      if (
        !accountDropdown.contains(event.target) &&
        !accountToggle.contains(event.target)
      ) {
        closeAccountMenu();
      }
    });

    document.addEventListener("keydown", event => {
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

    navToggle.addEventListener("click", event => {
      event.stopPropagation();

      if (navMenu.classList.contains("is-open")) closeMenu();
      else openMenu();
    });

    navMenu.querySelectorAll("a, button").forEach(element => {
      element.addEventListener("click", () => {
        if (
          window.innerWidth <= 1080 &&
          !element.matches("[data-user-menu-toggle]")
        ) {
          closeMenu();
        }
      });
    });

    document.addEventListener("click", event => {
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

document.addEventListener("DOMContentLoaded", setupNav);
